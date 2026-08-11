[CmdletBinding()]
param(
    [string]$Repository,
    [string]$Ref,
    [string]$Model,
    [string]$CopilotCommand = 'copilot',
    [string]$ResultsDir,
    [string[]]$ScenarioIds,
    [int]$TimeoutSeconds = 1800,
    [switch]$SkipDistributionSmoke,
    [switch]$KeepWorktree,
    [switch]$DescribePayload,
    [switch]$ConfirmExternalModelPayload,
    [string]$ReevaluateFromRunRoot
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($Repository) -xor [string]::IsNullOrWhiteSpace($Ref)) {
    throw 'Repository and Ref must be supplied together.'
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$rqRoot = Join-Path $packageRoot 'tests/runtime-qualification'
$authScenarioPath = Join-Path $packageRoot 'tests/invocation-authorization-scenarios.json'
$schemaPath = Join-Path $rqRoot 'result.schema.json'
$templatePath = Join-Path $rqRoot 'result-template.json'
$stdFixtureRoot = Join-Path $rqRoot 'copilot-cli/standard-slice'
$fullFixtureRoot = Join-Path $rqRoot 'copilot-cli/full-coverage'
$smokeScript = Join-Path $PSScriptRoot 'validate-plan-coverage-residual-flow-apm-smoke.ps1'
$apmYmlPath = Join-Path $packageRoot 'apm.yml'
$canonicalRoot = Join-Path $packageRoot '.apm'

if ([string]::IsNullOrWhiteSpace($ResultsDir)) {
    $ResultsDir = Join-Path $rqRoot 'results'
}
$ResultsDir = [System.IO.Path]::GetFullPath($ResultsDir)

$planCoverageOwnedAgents = @(
    'plan-kernel',
    'black-box-behavior-spec-kernel',
    'change-risk-triage',
    'architecture-slice-readiness',
    'architecture-elaboration',
    'plan-slice-decomposition',
    'implementation-contract-kernel',
    'implementation-contract-review-kernel',
    'runtime-contract-kernel',
    'test-design-kernel',
    'implementation-handoff-review',
    'implementation-execution',
    'code-review-focus-kernel',
    'verification-kernel',
    'cross-slice-verification-kernel',
    'coverage-gap-triage',
    'coverage-gap-resolution-slice',
    'residual-decision-gate'
)
$adaptiveAgents = @(
    'high-implementation-starter',
    'standard-implementation-completer'
)
$allTrackedAgents = @($planCoverageOwnedAgents + $adaptiveAgents + @('design-pair-implementation-execution'))

. (Join-Path $PSScriptRoot 'plan-coverage-copilot-scenario-lib.ps1')

# --- main ---

$canonicalFingerprint = Get-CanonicalFingerprint $canonicalRoot
$apmYmlSha = Get-Sha256File $apmYmlPath
$packageVersion = Get-PackageVersion $apmYmlPath
$candidateCommitRaw = & git -C $repoRoot rev-parse HEAD 2>$null
if ($candidateCommitRaw) { $candidateCommit = ([string]$candidateCommitRaw).Trim() } else { $candidateCommit = 'UNOBSERVABLE' }
$dirty = @(& git -C $repoRoot status --porcelain 2>$null)
if ($dirty.Count -gt 0) {
    $candidateCommit = "$candidateCommit-dirty"
}

$payload = @"
Plan Coverage GitHub Copilot CLI runtime qualification
- package: plan-coverage-residual-flow $packageVersion
- candidate: $candidateCommit
- canonical_fingerprint: $canonicalFingerprint
- model: $(if ($Model) { $Model } else { 'client-selected' })
- scenarios: A-H authorization + STD-001 + FULL-001
- isolation: temporary COPILOT_HOME per scenario (no personal skills/agents/hooks/plugins)
- external model: yes
- secrets on argv: none
"@

if ($DescribePayload) {
    Write-Host $payload
    exit 0
}

function New-RunFromEvidenceDir([string]$ScenarioEvidenceDir, [string]$Worktree, [string]$ScenarioId) {
    $nested = Join-Path $ScenarioEvidenceDir $ScenarioId
    if (-not (Test-Path -LiteralPath $nested -PathType Container)) {
        $nested = $ScenarioEvidenceDir
    }
    $hookLog = Join-Path $nested 'hooks.jsonl'
    $stdoutPath = Join-Path $nested 'stdout.txt'
    $stderrPath = Join-Path $nested 'stderr.txt'
    $sharePath = Join-Path $nested 'session.md'
    $copilotHome = Join-Path $nested 'copilot-home'
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    $share = if (Test-Path -LiteralPath $sharePath) { Get-Content -LiteralPath $sharePath -Raw } else { '' }
    $combined = @"
$stdout

$stderr

$share
"@
    $created = @()
    $changed = @()
    if (Test-Path -LiteralPath $Worktree) {
        $snap = @(Get-GitSnapshot $Worktree)
        foreach ($p in $snap) {
            if ($p -match '^(src/|plans/|config/|QUALIFICATION_PROMPT)') {
                if ((Test-Path -LiteralPath (Join-Path $Worktree $p) -PathType Leaf)) {
                    # Treat all current delta paths as created/changed for re-eval.
                    $created += $p
                }
            }
        }
        # Untracked plans directory expansion already handled by Get-GitSnapshot.
        if ($created.Count -eq 0) {
            Get-ChildItem -LiteralPath (Join-Path $Worktree 'plans') -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $rel = $_.FullName.Substring((Resolve-Path -LiteralPath $Worktree).Path.Length).TrimStart('\', '/').Replace('\', '/')
                $created += $rel
            }
            foreach ($src in @('src/ProducerState.ps1', 'src/ConsumerGate.ps1', 'src/StartupFlow.ps1', 'src/Load-AppConfig.ps1')) {
                $full = Join-Path $Worktree $src
                if (Test-Path -LiteralPath $full -PathType Leaf) {
                    $txt = Get-Content -LiteralPath $full -Raw
                    if ($txt -notmatch 'not implemented') { $changed += $src }
                }
            }
        }
    }
    # agents_observed: hook/session structured only (never artifact inference).
    $agents = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @(Get-AgentsFromHookLog $hookLog)) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    foreach ($a in @(Get-AgentsFromSessionEvents $copilotHome)) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    return [pscustomobject]@{
        ExitCode = 0
        Stdout = $stdout
        Stderr = $stderr
        SharePath = $sharePath
        HookLog = $hookLog
        Agents = @($agents)
        Created = @($created)
        Changed = @($changed)
        CombinedText = $combined
        ModelObserved = 'client-selected-or-unobserved'
        TranscriptSha = if (Test-Path -LiteralPath $sharePath) { Get-Sha256File $sharePath } elseif ($stdout) { Get-Sha256Text $stdout } else { $null }
        HookSha = if (Test-Path -LiteralPath $hookLog) { Get-Sha256File $hookLog } else { $null }
    }
}

function Write-RunMetadataFile([string]$RunRoot, [hashtable]$Meta) {
    $path = Join-Path $RunRoot 'run-metadata.json'
    Write-Utf8File $path (ConvertTo-JsonCompat ([ordered]@{} + $Meta))
    return $path
}

function Read-RunMetadataFile([string]$RunRoot) {
    $path = Join-Path $RunRoot 'run-metadata.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    return (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json)
}

if (-not [string]::IsNullOrWhiteSpace($ReevaluateFromRunRoot)) {
    $reevalRoot = [System.IO.Path]::GetFullPath($ReevaluateFromRunRoot)
    if (-not (Test-Path -LiteralPath $reevalRoot -PathType Container)) {
        throw "ReevaluateFromRunRoot not found: $reevalRoot"
    }
    Write-Host "Re-evaluating kept run without external model: $reevalRoot"
    $meta = Read-RunMetadataFile $reevalRoot
    if (-not $meta) {
        throw "run-metadata.json missing under $reevalRoot. Refuse to re-bind fingerprints from the current checkout."
    }

    $existingResultPath = Join-Path $ResultsDir "$(Get-Date -Format yyyy-MM-dd)-copilot-cli.json"
    if (-not (Test-Path -LiteralPath $existingResultPath)) {
        $hit = @(Get-ChildItem -LiteralPath $ResultsDir -Filter '*-copilot-cli.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1)
        if ($hit.Count -gt 0) { $existingResultPath = $hit[0].FullName }
    }
    if (-not $existingResultPath -or -not (Test-Path -LiteralPath $existingResultPath)) {
        throw 'No existing result JSON to merge authorization scenarios from.'
    }
    $base = Get-Content -Raw -LiteralPath $existingResultPath | ConvertFrom-Json
    $scenarioResults = [System.Collections.Generic.List[object]]::new()
    foreach ($s in @($base.scenarios)) {
        if (@('STD-001', 'FULL-001') -contains [string]$s.id) { continue }
        $scenarioResults.Add($s)
    }

    $stdDir = Join-Path $reevalRoot 'evidence\STD-001'
    $stdRepo = Join-Path $stdDir 'repo'
    if (Test-Path -LiteralPath $stdRepo) {
        $oracleMeta = Join-Path $stdDir 'oracle-hashes.json'
        $run = New-RunFromEvidenceDir $stdDir $stdRepo 'STD-001'
        $scenarioResults.Add((Evaluate-StdScenario $run $stdRepo $oracleMeta))
        Write-Host "STD-001 re-eval => $(( $scenarioResults | Where-Object { $_.id -eq 'STD-001' } | Select-Object -First 1).status)"
    }

    $fullDir = Join-Path $reevalRoot 'evidence\FULL-001'
    $fullRepo = Join-Path $fullDir 'repo'
    if (Test-Path -LiteralPath $fullRepo) {
        $oracleMeta = Join-Path $fullDir 'oracle-hashes.json'
        $run = New-RunFromEvidenceDir $fullDir $fullRepo 'FULL-001'
        $scenarioResults.Add((Evaluate-FullScenario $run $fullRepo $oracleMeta))
        Write-Host "FULL-001 re-eval => $(( $scenarioResults | Where-Object { $_.id -eq 'FULL-001' } | Select-Object -First 1).status)"
    }

    $byId = @{}
    foreach ($s in $scenarioResults) { $byId[[string]$s.id] = $s }
    $requiredIds = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'STD-001', 'FULL-001')
    $scenariosPass = $true
    foreach ($id in $requiredIds) {
        if (-not $byId.ContainsKey($id) -or $byId[$id].status -cne 'PASS') { $scenariosPass = $false }
    }
    $distStatus = if ($meta.distribution_smoke -and $meta.distribution_smoke.status) { $meta.distribution_smoke.status } else { $base.distribution_smoke.status }
    if ($distStatus -cne 'PASS') { $scenariosPass = $false }

    $adaptiveOk = $false
    $handoffOk = $false
    foreach ($id in @('STD-001', 'FULL-001')) {
        if (-not $byId.ContainsKey($id)) { continue }
        $ac = $byId[$id].adaptive_connection
        if ($ac -and $ac.connection_satisfied) { $adaptiveOk = $true }
        if ($ac -and $ac.high_to_standard_handoff_satisfied) { $handoffOk = $true }
    }
    if (-not $adaptiveOk) { $scenariosPass = $false }

    $sourceFp = [string]$meta.canonical_fingerprint
    $fingerprintMatchesCurrent = ($sourceFp -ceq $canonicalFingerprint)
    $packageMatches = ([string]$meta.package_version -ceq $packageVersion)
    $canQualifyCurrent = $scenariosPass -and $fingerprintMatchesCurrent -and $packageMatches
    $overall = if ($canQualifyCurrent) { 'QUALIFIED' } elseif ($scenariosPass -and -not $fingerprintMatchesCurrent) { 'PENDING' } else { 'FAIL' }

    $notes = 'Re-evaluated from kept worktree without new external model calls. source_run identity frozen from run-metadata.json. '
    if (-not $fingerprintMatchesCurrent) {
        $notes += "source fingerprint $sourceFp != current $canonicalFingerprint; cannot promote to current QUALIFIED. "
    }
    if ($adaptiveOk -and -not $handoffOk) {
        $notes += 'Adaptive connection satisfied via HIGH COMPLETED_BY_HIGH_MODEL durable evidence; HIGH->STANDARD handoff was NOT_REQUIRED (no STANDARD remainder). '
    }
    $notes += 'Qualified client surface is GitHub Copilot CLI only.'

    $clientVersion = [string]$meta.client_version
    $result = [ordered]@{
        schema_version = 1
        date = (Get-Date -Format 'yyyy-MM-dd')
        runtime = $base.runtime
        client_version = $clientVersion
        model_requested = $(if ($meta.psobject.Properties.Name -contains 'model_requested') { $meta.model_requested } else { $base.model_requested })
        model_observed = $(if ($meta.model_observed) { $meta.model_observed } else { $base.model_observed })
        apm_version = $(if ($meta.apm_version) { $meta.apm_version } else { $base.apm_version })
        # Frozen to the original live run — never re-bind from current checkout.
        candidate_commit = [string]$meta.candidate_commit
        plan_coverage_package_version = [string]$meta.package_version
        canonical_fingerprint = $sourceFp
        apm_yml_sha256 = [string]$meta.apm_yml_sha256
        install_targets = @($meta.install_targets)
        apm_lock_sha256 = [string]$meta.apm_lock_sha256
        platform = $(if ($meta.platform) { $meta.platform } else { $base.platform })
        distribution_smoke = $(if ($meta.distribution_smoke) { $meta.distribution_smoke } else { $base.distribution_smoke })
        overall_status = $overall
        qualification_matrix_notes = $notes
        source_run = [ordered]@{
            source_run_id = [string]$meta.source_run_id
            candidate_commit = [string]$meta.candidate_commit
            canonical_fingerprint = $sourceFp
            apm_yml_sha256 = [string]$meta.apm_yml_sha256
            package_version = [string]$meta.package_version
            apm_lock_sha256 = [string]$meta.apm_lock_sha256
            install_targets = @($meta.install_targets)
            client_version = $clientVersion
            apm_version = $(if ($meta.apm_version) { [string]$meta.apm_version } else { $null })
            model_requested = $(if ($meta.psobject.Properties.Name -contains 'model_requested') { $meta.model_requested } else { $null })
            model_observed = $(if ($meta.model_observed) { [string]$meta.model_observed } else { $null })
            platform = $(if ($meta.platform) { [string]$meta.platform } else { $null })
            distribution_smoke = $(if ($meta.distribution_smoke) { $meta.distribution_smoke } else { $null })
        }
        scenarios = @($scenarioResults)
    }

    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
    $jsonPath = Join-Path $ResultsDir "$($result.date)-copilot-cli.json"
    $mdPath = Join-Path $ResultsDir "$($result.date)-copilot-cli.md"
    Write-Utf8File $jsonPath (ConvertTo-JsonCompat $result)
    $md = @"
# Plan Coverage GitHub Copilot CLI runtime qualification

- date: $($result.date)
- overall_status: $overall
- reevaluation: kept-worktree-no-new-model-calls
- source_run_id: $($meta.source_run_id)
- source_run_root: $reevalRoot
- client_version: $clientVersion
- model_observed: $($result.model_observed)
- apm_version: $($result.apm_version)
- candidate_commit: $($meta.candidate_commit)
- plan_coverage_package_version: $($meta.package_version)
- canonical_fingerprint: $sourceFp
- current_checkout_fingerprint: $canonicalFingerprint
- fingerprint_matches_current: $fingerprintMatchesCurrent
- distribution_smoke: $distStatus
- adaptive_connection_satisfied: $adaptiveOk
- high_to_standard_handoff_satisfied: $handoffOk

## Scenarios

| id | kind | status | agents_observed | stop_reason |
| --- | --- | --- | --- | --- |
$(($scenarioResults | ForEach-Object { "| $($_.id) | $($_.kind) | $($_.status) | $((@($_.agents_observed) -join ', ')) | $($_.stop_reason) |" }) -join "`n")
"@
    Write-Utf8File $mdPath ($md.Replace("`r`n", "`n"))
    Write-Host "Wrote $jsonPath"
    Write-Host "Wrote $mdPath"
    Write-Host "overall_status=$overall fingerprint_matches_current=$fingerprintMatchesCurrent"
    if ($overall -cne 'QUALIFIED') { exit 1 }
    exit 0
}

if (-not $ConfirmExternalModelPayload) {
    throw 'Refusing to call an external model. Re-run with -DescribePayload, -ConfirmExternalModelPayload, or -ReevaluateFromRunRoot.'
}

$copilotExe = Resolve-CopilotExecutable $CopilotCommand
Ensure-CopilotAuthEnv
$copilotVersion = ((& $copilotExe --version 2>&1 | Out-String).Trim())
if ([string]::IsNullOrWhiteSpace($copilotVersion)) { $copilotVersion = 'UNOBSERVABLE' }
$apmVersion = ((& apm --version 2>&1 | Out-String).Trim())
if ([string]::IsNullOrWhiteSpace($apmVersion)) { $apmVersion = 'UNOBSERVABLE' }

$runStamp = Get-Date -Format 'yyyy-MM-dd'
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$runRoot = Join-Path $tempParent ('plan-coverage-rq-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot, $ResultsDir -Force | Out-Null
$evidenceRoot = Join-Path $runRoot 'evidence'
$installRoot = Join-Path $runRoot 'install-seed'
New-Item -ItemType Directory -Path $evidenceRoot, $installRoot -Force | Out-Null

Write-Host $payload
Write-Host "Run root: $runRoot"

$authScenarios = Get-Content -Raw -LiteralPath $authScenarioPath | ConvertFrom-Json
$selectedFilter = $null
if ($ScenarioIds -and @($ScenarioIds).Count -gt 0) {
    $expandedIds = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in @($ScenarioIds)) {
        foreach ($part in ([string]$raw -split '[,;\s]+')) {
            if (-not [string]::IsNullOrWhiteSpace($part)) {
                $expandedIds.Add($part.Trim())
            }
        }
    }
    $selectedFilter = @{}
    foreach ($id in $expandedIds) {
        $selectedFilter[$id.ToUpperInvariant()] = $true
    }
    Write-Host ("Scenario filter: " + (($selectedFilter.Keys | Sort-Object) -join ', '))
}

$distributionSmoke = [ordered]@{
    status = 'NOT_RUN'
    command = './apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow-apm-smoke.ps1'
    rationale = 'Not executed in this run.'
}

try {
    if (-not $SkipDistributionSmoke) {
        Write-Host 'Running fresh APM distribution smoke...'
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            & $smokeScript
        }
        else {
            & $smokeScript -Repository $Repository -Ref $Ref
        }
        if ($LASTEXITCODE -ne 0) {
            $distributionSmoke.status = 'FAIL'
            $distributionSmoke.rationale = "Smoke failed with exit code $LASTEXITCODE"
            throw $distributionSmoke.rationale
        }
        $distributionSmoke.status = 'PASS'
        $distributionSmoke.rationale = 'Fresh APM install smoke passed (copilot,codex,agent-skills + transitive Adaptive + installed E2E when remote).'
    }

    Write-Host 'Installing Plan Coverage into qualification seed worktree...'
    Install-PlanCoverageInto $installRoot
    $lockPath = Join-Path $installRoot 'apm.lock.yaml'
    $lockSha = if (Test-Path -LiteralPath $lockPath) { Get-Sha256File $lockPath } else { 'MISSING' }

    $runId = Split-Path -Leaf $runRoot
    $runMetadata = [ordered]@{
        source_run_id = $runId
        candidate_commit = $candidateCommit
        canonical_fingerprint = $canonicalFingerprint
        apm_yml_sha256 = $apmYmlSha
        package_version = $packageVersion
        apm_lock_sha256 = $lockSha
        install_targets = @('copilot', 'codex', 'agent-skills')
        client_version = ($copilotVersion -replace '[\r\n].*', '').Trim()
        apm_version = $apmVersion
        model_requested = $(if ($Model) { $Model } else { $null })
        model_observed = $(if ($Model) { $Model } else { 'client-selected-or-unobserved' })
        platform = $(if ($PSVersionTable.Platform) { [string]$PSVersionTable.Platform } else { 'win32' })
        distribution_smoke = $distributionSmoke
    }
    Write-RunMetadataFile $runRoot $runMetadata
    Write-Host "Wrote run-metadata.json for source_run_id=$runId"

    $scenarioResults = [System.Collections.Generic.List[object]]::new()
    $modelObservedGlobal = $(if ($Model) { $Model } else { 'client-selected-or-unobserved' })

    foreach ($scenario in $authScenarios) {
        $sid = [string]$scenario.id
        if ($selectedFilter -and -not $selectedFilter.ContainsKey($sid.ToUpperInvariant())) { continue }
        Write-Host "=== Authorization scenario $sid ==="
        $scenarioDir = Join-Path $evidenceRoot "auth-$sid"
        New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
        $worktree = New-AuthWorktree -BaseInstallRoot $installRoot -Scenario $scenario -ScenarioDir $scenarioDir
        $prompt = Build-PromptFromAuthScenario $scenario
        Write-Utf8File (Join-Path $scenarioDir 'prompt.md') $prompt
        $run = Invoke-CopilotScenario -Worktree $worktree -Prompt $prompt -ScenarioId $sid -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec $TimeoutSeconds
        if ($run.ModelObserved -and $run.ModelObserved -cne 'client-selected-or-unobserved') {
            $modelObservedGlobal = $run.ModelObserved
        }
        $evaluated = Evaluate-AuthScenario $scenario $run
        $scenarioResults.Add($evaluated)
        Write-Host "Scenario $sid => $($evaluated.status)"
    }

    if (-not $selectedFilter -or $selectedFilter.ContainsKey('STD-001')) {
        Write-Host '=== STD-001 standard-slice E2E ==='
        $scenarioDir = Join-Path $evidenceRoot 'STD-001'
        New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
        $worktree = New-E2EWorktree -BaseInstallRoot $installRoot -SeedRoot (Join-Path $stdFixtureRoot 'seed') -OracleVerifyPath (Join-Path $stdFixtureRoot 'verify.ps1') -ExtraOraclePaths @() -ScenarioDir $scenarioDir -RequestPath (Join-Path $stdFixtureRoot 'request.md')
        $prompt = Get-NormalizedText (Join-Path $worktree 'REQUEST.md')
        $run = Invoke-CopilotScenario -Worktree $worktree -Prompt $prompt -ScenarioId 'STD-001' -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec $TimeoutSeconds
        if ($run.ModelObserved -and $run.ModelObserved -cne 'client-selected-or-unobserved') {
            $modelObservedGlobal = $run.ModelObserved
        }
        $oracleMeta = Join-Path $scenarioDir 'oracle-hashes.json'
        $evaluated = Evaluate-StdScenario $run $worktree $oracleMeta
        $scenarioResults.Add($evaluated)
        Write-Host "STD-001 => $($evaluated.status)"
    }

    if (-not $selectedFilter -or $selectedFilter.ContainsKey('FULL-001')) {
        Write-Host '=== FULL-001 full-coverage E2E ==='
        $scenarioDir = Join-Path $evidenceRoot 'FULL-001'
        New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
        $extra = @(
            (Join-Path $fullFixtureRoot 'seed/tests/verify-sl-001.ps1'),
            (Join-Path $fullFixtureRoot 'seed/tests/verify-sl-002.ps1')
        )
        $worktree = New-E2EWorktree -BaseInstallRoot $installRoot -SeedRoot (Join-Path $fullFixtureRoot 'seed') -OracleVerifyPath (Join-Path $fullFixtureRoot 'verify.ps1') -ExtraOraclePaths $extra -ScenarioDir $scenarioDir -RequestPath (Join-Path $fullFixtureRoot 'request.md')
        $prompt = Get-NormalizedText (Join-Path $worktree 'REQUEST.md')
        $run = Invoke-CopilotScenario -Worktree $worktree -Prompt $prompt -ScenarioId 'FULL-001' -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec ([Math]::Max($TimeoutSeconds, 3600))
        if ($run.ModelObserved -and $run.ModelObserved -cne 'client-selected-or-unobserved') {
            $modelObservedGlobal = $run.ModelObserved
        }
        $oracleMeta = Join-Path $scenarioDir 'oracle-hashes.json'
        $evaluated = Evaluate-FullScenario $run $worktree $oracleMeta
        $scenarioResults.Add($evaluated)
        Write-Host "FULL-001 => $($evaluated.status)"
    }

    $requiredIds = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'STD-001', 'FULL-001')
    $byId = @{}
    foreach ($s in $scenarioResults) { $byId[$s.id] = $s }
    $allPass = $true
    foreach ($id in $requiredIds) {
        $idKey = $id.ToUpperInvariant()
        if (-not $selectedFilter -or $selectedFilter.ContainsKey($idKey)) {
            if (-not $byId.ContainsKey($id) -or $byId[$id].status -cne 'PASS') {
                $allPass = $false
            }
        }
    }
    if ($distributionSmoke.status -cne 'PASS' -and -not $SkipDistributionSmoke) {
        $allPass = $false
    }
    $adaptiveOk = $false
    $handoffOk = $false
    foreach ($id in @('STD-001', 'FULL-001')) {
        if (-not $byId.ContainsKey($id)) { continue }
        $ac = $byId[$id].adaptive_connection
        if ($ac -and $ac.connection_satisfied) { $adaptiveOk = $true }
        if ($ac -and $ac.high_to_standard_handoff_satisfied) { $handoffOk = $true }
    }
    if (-not $selectedFilter -and -not $adaptiveOk) { $allPass = $false }

    $overall = if ($allPass -and (-not $selectedFilter)) { 'QUALIFIED' } elseif ($allPass) { 'PENDING' } else { 'FAIL' }

    $runMetadata.model_observed = $modelObservedGlobal
    $runMetadata.distribution_smoke = $distributionSmoke
    Write-RunMetadataFile $runRoot $runMetadata

    $clientVersionClean = ($copilotVersion -replace '[\r\n].*', '').Trim()
    $notes = 'Qualified client surface is GitHub Copilot CLI only. Codex was not re-qualified in this run beyond existing static/historical evidence. VS Code Agent mode was not runtime-qualified. '
    if ($adaptiveOk -and -not $handoffOk) {
        $notes += 'Adaptive connection satisfied via HIGH COMPLETED_BY_HIGH_MODEL durable evidence where STANDARD remainder was not required. '
    }
    $notes += "source_run_id=$runId bound via run-metadata.json."

    $result = [ordered]@{
        schema_version = 1
        date = $runStamp
        runtime = [ordered]@{
            surface = 'github-copilot'
            qualified_client_surface = 'github-copilot-cli'
            other_surfaces = @('vscode-agent-mode: separate-runtime-qualification-not-performed')
        }
        client_version = $clientVersionClean
        model_requested = $(if ($Model) { $Model } else { $null })
        model_observed = $modelObservedGlobal
        apm_version = $apmVersion
        candidate_commit = $candidateCommit
        plan_coverage_package_version = $packageVersion
        canonical_fingerprint = $canonicalFingerprint
        apm_yml_sha256 = $apmYmlSha
        install_targets = @('copilot', 'codex', 'agent-skills')
        apm_lock_sha256 = $lockSha
        platform = $(if ($PSVersionTable.Platform) { [string]$PSVersionTable.Platform } else { 'win32' })
        distribution_smoke = $distributionSmoke
        overall_status = $overall
        qualification_matrix_notes = $notes
        source_run = [ordered]@{
            source_run_id = $runId
            candidate_commit = $candidateCommit
            canonical_fingerprint = $canonicalFingerprint
            apm_yml_sha256 = $apmYmlSha
            package_version = $packageVersion
            apm_lock_sha256 = $lockSha
            install_targets = @('copilot', 'codex', 'agent-skills')
            client_version = $clientVersionClean
            apm_version = $apmVersion
            model_requested = $(if ($Model) { $Model } else { $null })
            model_observed = $modelObservedGlobal
            platform = $(if ($PSVersionTable.Platform) { [string]$PSVersionTable.Platform } else { 'win32' })
            distribution_smoke = $distributionSmoke
        }
        scenarios = @($scenarioResults)
    }

    $jsonPath = Join-Path $ResultsDir "$runStamp-copilot-cli.json"
    $mdPath = Join-Path $ResultsDir "$runStamp-copilot-cli.md"
    Write-Utf8File $jsonPath (ConvertTo-JsonCompat $result)

    $md = @"
# Plan Coverage GitHub Copilot CLI runtime qualification

- date: $runStamp
- overall_status: $overall
- client_version: $copilotVersion
- model_requested: $(if ($Model) { $Model } else { 'null' })
- model_observed: $modelObservedGlobal
- apm_version: $apmVersion
- candidate_commit: $candidateCommit
- plan_coverage_package_version: $packageVersion
- canonical_fingerprint: $canonicalFingerprint
- install_targets: copilot,codex,agent-skills
- distribution_smoke: $($distributionSmoke.status)
- platform: $($result.platform)
- temporary_evidence: $runRoot

## Scenarios

| id | kind | status | agents_observed | stop_reason |
| --- | --- | --- | --- | --- |
$(($scenarioResults | ForEach-Object { "| $($_.id) | $($_.kind) | $($_.status) | $((@($_.agents_observed) -join ', ')) | $($_.stop_reason) |" }) -join "`n")

## Notes

- skill_observation is UNOBSERVABLE unless Copilot CLI emits a dedicated skill-load event.
- Authorization negatives require no Plan Coverage agents, no Plan Coverage artifact writes, and no route recommendation.
- STD-001 / FULL-001 use external oracles hash-checked by the harness.
- Personal COPILOT_HOME customizations were isolated via temporary COPILOT_HOME.
"@
    Write-Utf8File $mdPath $md.Replace("`r`n", "`n")

    Write-Host "Wrote $jsonPath"
    Write-Host "Wrote $mdPath"
    Write-Host "overall_status=$overall"

    if ($overall -cne 'QUALIFIED') {
        exit 1
    }
}
finally {
    if (-not $KeepWorktree) {
        $resolved = [System.IO.Path]::GetFullPath($runRoot)
        if ($resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('plan-coverage-rq-', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "Kept worktree: $runRoot"
    }
}
