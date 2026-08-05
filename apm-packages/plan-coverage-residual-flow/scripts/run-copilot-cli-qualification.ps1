[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('plan-coverage-residual-flow', 'token-aware-full-coverage-3layer')]
    [string]$PackageName,

    [string]$Repository,

    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$Ref,

    [string]$LocalSkillPath,

    [string]$OutputRoot,

    [switch]$RunModel,

    [string]$Prompt,

    [string]$ModelScenarioId = 'explicit-lite',

    [string]$ScenarioResultsPath,

    [switch]$AllowIncomplete,

    [switch]$KeepWorkspace
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Repository) -xor [string]::IsNullOrWhiteSpace($Ref)) {
    throw 'Repository and Ref must be supplied together.'
}

if ($RunModel -and [string]::IsNullOrWhiteSpace($Prompt)) {
    throw 'Prompt is required when -RunModel is specified.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' '..')))).Path
$packageRelative = Join-Path 'apm-packages' $PackageName
$packageRoot = Join-Path $repoRoot $packageRelative
$scenarioPath = Join-Path $packageRoot (Join-Path 'tests' (Join-Path 'copilot-cli' 'qualification-scenarios.json'))
$defaultOutputRoot = Join-Path $packageRoot (Join-Path 'tests' (Join-Path 'copilot-cli' 'runs'))
$localSkillCandidate = $null

if (-not [string]::IsNullOrWhiteSpace($LocalSkillPath)) {
    $localSkillCandidate = if ([System.IO.Path]::IsPathRooted($LocalSkillPath)) {
        $LocalSkillPath
    }
    else {
        Join-Path $repoRoot $LocalSkillPath
    }
}

if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
    throw "Package directory does not exist: $packageRelative"
}
if (-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf)) {
    throw "Qualification fixture does not exist: $scenarioPath"
}

$rawOutputRoot = if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $defaultOutputRoot } else { $OutputRoot }
$resolvedOutputRoot = [System.IO.Path]::GetFullPath($rawOutputRoot)
New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
$runName = "$PackageName-$(Get-Date -Format yyyyMMdd-HHmmss)-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$runRoot = Join-Path $resolvedOutputRoot $runName
$workspace = Join-Path $runRoot 'workspace'
$logRoot = Join-Path $runRoot 'copilot-logs'
New-Item -ItemType Directory -Path $workspace, $logRoot -Force | Out-Null

function Write-Utf8File([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllLines($Path, $Lines, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Captured([string]$FilePath, [string[]]$Arguments, [string]$OutputPath) {
    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    Write-Utf8File $OutputPath @($output | ForEach-Object { [string]$_ })
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

function Get-CommandVersion([string]$FilePath, [string[]]$Arguments) {
    $result = Invoke-Captured $FilePath $Arguments (Join-Path $runRoot ("$([System.IO.Path]::GetFileNameWithoutExtension($FilePath))-version.txt"))
    if ($result.ExitCode -ne 0) {
        throw "$FilePath version command failed with exit code $($result.ExitCode)."
    }
    return (($result.Output -join "`n").Trim())
}

function Get-GitState() {
    $head = (& git -C $repoRoot rev-parse HEAD 2>$null).Trim()
    $status = @(& git -C $repoRoot status --short 2>$null)
    if ($status.Count -gt 0) {
        return "$head-dirty"
    }
    return $head
}

function Get-InstalledPackageVersion([string]$LockPath, [string]$Name) {
    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
        return 'UNOBSERVABLE'
    }

    $lines = Get-Content -LiteralPath $LockPath
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^\s+name:\s+$([regex]::Escape($Name))\s*$") {
            for ($lookAhead = $index + 1; $lookAhead -lt [Math]::Min($index + 12, $lines.Count); $lookAhead++) {
                if ($lines[$lookAhead] -match '^\s+version:\s*(\S+)\s*$') {
                    return $Matches[1]
                }
            }
        }
    }
    return 'UNOBSERVABLE'
}

function Get-ScenarioEvidence([object]$Scenario) {
    if ($null -ne $Scenario.evidence -and -not [string]::IsNullOrWhiteSpace([string]$Scenario.evidence)) {
        return [string]$Scenario.evidence
    }
    if ($Scenario.status -eq 'BLOCKED') {
        return [string]$Scenario.blocker
    }
    return 'No real CLI evidence was supplied for this scenario.'
}

function Validate-ResumeResult([object]$Result, [string]$ScenarioId) {
    $status = ([string]$Result.status).ToUpperInvariant()
    $declaration = $Result.evidence_declaration
    if ($null -eq $declaration) {
        throw "Resume scenario $ScenarioId requires evidence_declaration; static fixture or Skill discovery evidence is insufficient."
    }

    if ($status -eq 'PASS') {
        if ([string]$declaration.evidence_source -cne 'real-cli') {
            throw "Resume scenario $ScenarioId PASS requires evidence_source real-cli."
        }
        if ([string]$declaration.artifact_authoritative_resume -cne 'PROVEN') {
            throw "Resume scenario $ScenarioId PASS requires explicit artifact-authoritative evidence."
        }
        if ([string]::IsNullOrWhiteSpace([string]$declaration.evidence_bundle_path) -or
            [string]$declaration.evidence_bundle_path -ceq 'N/A') {
            throw "Resume scenario $ScenarioId PASS requires an evidence bundle path."
        }
        if ([string]$declaration.evidence_bundle_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Resume scenario $ScenarioId PASS requires a SHA-256 evidence bundle hash."
        }
        foreach ($referenceField in @('prompt_reference', 'command_reference', 'output_reference')) {
            if ([string]::IsNullOrWhiteSpace([string]$declaration.$referenceField) -or
                [string]$declaration.$referenceField -ceq 'N/A') {
                throw "Resume scenario $ScenarioId PASS requires $referenceField."
            }
        }
        if (@($declaration.artifact_references).Count -eq 0) {
            throw "Resume scenario $ScenarioId PASS requires artifact references."
        }
        foreach ($artifact in @($declaration.artifact_references)) {
            if ([string]::IsNullOrWhiteSpace([string]$artifact.path) -or
                [string]$artifact.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
                throw "Resume scenario $ScenarioId PASS requires artifact paths with SHA-256."
            }
        }
        if (@($declaration.changed_files).Count -eq 0 -or
            @($declaration.verdict_sequence).Count -eq 0) {
            throw "Resume scenario $ScenarioId PASS requires changed_files and verdict_sequence evidence."
        }
    }
    elseif ($status -eq 'UNOBSERVABLE') {
        if ([string]$declaration.artifact_authoritative_resume -cne 'NOT_PROVEN') {
            throw "Resume scenario $ScenarioId UNOBSERVABLE must declare artifact-authoritative resume NOT_PROVEN."
        }
        if ($ScenarioId -eq 'new-session-resume' -and
            [string]$Result.evidence -notmatch '(?i)conversation\s+resume') {
            throw "Plan Coverage new-session-resume must identify conversation resume as observation only."
        }
        if ([string]$Result.evidence -notmatch '(?i)artifact-authoritative.*not proven') {
            throw "Resume scenario $ScenarioId must state that artifact-authoritative resume was not proven."
        }
    }
}

function Import-ScenarioResults([string]$Path, [object[]]$FixtureScenarios) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @{}
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Scenario result file does not exist: $Path"
    }

    $document = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    if ([string]$document.package -cne $PackageName) {
        throw "Scenario result package does not match $PackageName."
    }
    if ([string]$document.execution_kind -cne 'real-cli') {
        throw 'Scenario result must identify execution_kind real-cli; static fixture or Skill discovery evidence is insufficient.'
    }

    $fixtureIds = @($FixtureScenarios | ForEach-Object { [string]$_.id })
    $resumeScenarioId = if ($PackageName -eq 'plan-coverage-residual-flow') {
        'new-session-resume'
    }
    else {
        'new-session-parent-state-resume'
    }
    $resultMap = @{}
    foreach ($result in @($document.scenarios)) {
        $id = [string]$result.id
        if ($fixtureIds -notcontains $id) {
            throw "Scenario result contains an unknown scenario: $id"
        }
        if ($resultMap.ContainsKey($id)) {
            throw "Scenario result contains a duplicate scenario: $id"
        }

        $status = ([string]$result.status).ToUpperInvariant()
        if ($status -notin @('PASS', 'FAIL', 'NOT RUN', 'UNOBSERVABLE', 'BLOCKED')) {
            throw "Scenario $id has an unsupported status: $status"
        }
        $fixtureScenario = $FixtureScenarios | Where-Object { [string]$_.id -ceq $id }
        if ([string]$fixtureScenario.kind -ceq 'blocked' -and $status -ne 'BLOCKED') {
            throw "Blocked scenario $id must remain BLOCKED."
        }
        if ([string]$fixtureScenario.kind -ne 'blocked' -and $status -eq 'BLOCKED') {
            throw "Non-blocked scenario $id cannot be BLOCKED."
        }
        if ($id -eq $resumeScenarioId) {
            Validate-ResumeResult $result $resumeScenarioId
        }

        $resultMap[$id] = [pscustomobject]@{
            Status = $status
            Evidence = Get-ScenarioEvidence $result
            Validation = if ($null -eq $result.validation) { 'not supplied' } else { [string]$result.validation }
            RequestedModel = if ($null -eq $result.requested_model) { 'not supplied' } else { [string]$result.requested_model }
            ObservedModel = if ($null -eq $result.observed_model) { 'not supplied' } else { [string]$result.observed_model }
            EvidenceDeclaration = $result.evidence_declaration
        }
    }
    return $resultMap
}

function Get-RequiredAssets([string]$Package, [string]$Workspace) {
    $skillRelative = Join-Path '.agents' (Join-Path 'skills' (Join-Path $Package 'SKILL.md'))
    $sharedInstructionRelative = Join-Path '.github' (Join-Path 'instructions' 'plan-coverage-shared.instructions.md')
    $skillPath = Join-Path $Workspace $skillRelative
    $sharedInstructionPath = Join-Path $Workspace $sharedInstructionRelative
    $agentPath = Join-Path $Workspace (Join-Path '.github' 'agents')
    $instructionPath = if ($Package -eq 'token-aware-full-coverage-3layer') {
        Join-Path $Workspace (Join-Path '.github' (Join-Path 'instructions' 'token-aware-full-coverage-3layer.instructions.md'))
    }
    else {
        $null
    }

    $assets = [ordered]@{
        Skill = $skillPath
        SharedInstruction = $sharedInstructionPath
        PackageInstruction = $instructionPath
        Agents = $agentPath
    }
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $assets.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            continue
        }
        $pathType = if ($entry.Key -eq 'Agents') { 'Container' } else { 'Leaf' }
        if (-not (Test-Path -LiteralPath $entry.Value -PathType $pathType)) {
            [void]$missing.Add($entry.Key)
        }
    }
    if ((Test-Path -LiteralPath $agentPath -PathType Container) -and
        @(Get-ChildItem -LiteralPath $agentPath -Filter '*.agent.md' -File).Count -eq 0) {
        [void]$missing.Add('Agents/*.agent.md')
    }

    return [pscustomobject]@{
        Paths = $assets
        Missing = @($missing)
        Complete = $missing.Count -eq 0
    }
}

$scenarioData = Get-Content -Raw -LiteralPath $scenarioPath | ConvertFrom-Json
$fixtureScenarios = @($scenarioData.real_cli_scenarios)
$scenarioResults = Import-ScenarioResults $ScenarioResultsPath $fixtureScenarios
$copilotVersion = 'UNOBSERVABLE'
$apmVersion = 'UNOBSERVABLE'
$sourceRevision = 'UNOBSERVABLE'
$startupFailure = $null
try {
    $copilotVersion = Get-CommandVersion 'copilot' @('--version')
    $apmVersion = Get-CommandVersion 'apm' @('--version')
    $sourceRevision = Get-GitState
}
catch {
    $startupFailure = $_.Exception.Message
}
$installMode = 'remote-package'
$installResult = $null
$localSkillResolved = $null
$skillList = $null
$modelResult = $null
$modelStatus = 'NOT RUN'
$modelExit = 'N/A'
$installBoundaryStatus = 'NOT RUN'
$skillDiscoveryStatus = 'NOT RUN'
$localOnlyStatus = 'NOT APPLICABLE'
$realScenarioStatus = 'INCOMPLETE'
$qualificationStatus = 'INSTALL_BOUNDARY_FAILURE'
$requiredAssets = $null
$lockPackageVersion = 'UNOBSERVABLE'
$skillHash = 'UNOBSERVABLE'
$failureReason = $null

try {
    if (-not [string]::IsNullOrWhiteSpace($startupFailure)) {
        throw $startupFailure
    }
    Push-Location $workspace
    try {
        if (-not [string]::IsNullOrWhiteSpace($Repository)) {
            $packageSpec = "$Repository/apm-packages/$PackageName#$Ref"
            $installResult = Invoke-Captured 'apm' @('install', $packageSpec, '--target', 'copilot,agent-skills', '--https', '--no-audit') (Join-Path $runRoot 'apm-install.txt')
        }
        else {
            if ([string]::IsNullOrWhiteSpace($LocalSkillPath)) {
                throw 'Supply Repository and Ref for a full package install, or LocalSkillPath for a local Skill-only probe.'
            }
            $localSkillResolved = (Resolve-Path -LiteralPath $localSkillCandidate).Path
            $installMode = 'local-skill-only'
            $installResult = Invoke-Captured 'apm' @('install', $localSkillResolved, '--target', 'agent-skills', '--no-audit') (Join-Path $runRoot 'apm-install.txt')
        }

        if ($installResult.ExitCode -ne 0) {
            $failureReason = "APM install failed with exit code $($installResult.ExitCode)."
        }
        else {
            $requiredAssets = Get-RequiredAssets $PackageName $workspace
            $skillPath = [string]$requiredAssets.Paths.Skill
            if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
                $skillHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant()
            }

            $skillList = Invoke-Captured 'copilot' @('skill', 'list') (Join-Path $runRoot 'copilot-skill-list.txt')
            $skillListText = ($skillList.Output -join "`n")
            $skillDiscovered = $skillList.ExitCode -eq 0 -and $skillListText -match [regex]::Escape($PackageName)
            $skillDiscoveryStatus = if ($skillDiscovered) { 'PASS' } elseif ($skillList.ExitCode -ne 0) { 'FAIL' } else { 'UNOBSERVABLE' }

            $lockPath = Join-Path $workspace 'apm.lock.yaml'
            if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
                Copy-Item -LiteralPath $lockPath -Destination (Join-Path $runRoot 'apm.lock.yaml') -Force
            }
            $lockPackageVersion = Get-InstalledPackageVersion $lockPath $PackageName

            if ($installMode -eq 'local-skill-only') {
                $localOnlyStatus = 'LOCAL_SKILL_ONLY_NON_QUALIFYING'
                $installBoundaryStatus = 'LOCAL_SKILL_ONLY'
            }
            elseif (-not $requiredAssets.Complete -or -not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
                $installBoundaryStatus = 'FAIL'
                $failureReason = "Required full-package assets or lockfile are missing: $($requiredAssets.Missing -join ', ')."
            }
            else {
                $installBoundaryStatus = 'PASS'
            }

            if ($RunModel) {
                $modelResult = Invoke-Captured 'copilot' @(
                    '--no-auto-update',
                    '-p',
                    $Prompt,
                    '--allow-all-tools',
                    '--allow-all-paths',
                    '--no-ask-user',
                    '--output-format',
                    'json',
                    '--silent',
                    '--log-level',
                    'debug',
                    '--log-dir',
                    $logRoot
                ) (Join-Path $runRoot 'copilot-model-output.jsonl')
                $modelExit = [string]$modelResult.ExitCode
                $modelStatus = if ($modelResult.ExitCode -eq 0) { 'UNOBSERVABLE' } else { 'FAIL' }
                $scenarioResults[$ModelScenarioId] = [pscustomobject]@{
                    Status = $modelStatus
                    Evidence = "Harness executed the prompt; exit code $modelExit. Route, agent, and phase evidence require inspection of copilot-model-output.jsonl and debug logs."
                    Validation = "exit code $modelExit"
                    RequestedModel = 'CLI default'
                    ObservedModel = 'not extracted by harness'
                }
            }
        }
    }
    finally {
        Pop-Location
    }
}
catch {
    $failureReason = $_.Exception.Message
}
finally {
    $requiredScenarioIds = @($fixtureScenarios | Where-Object { [string]$_.kind -ne 'blocked' } | ForEach-Object { [string]$_.id })
    $missingScenarioIds = @($requiredScenarioIds | Where-Object { -not $scenarioResults.ContainsKey($_) })
    $unresolvedScenarioIds = @($requiredScenarioIds | Where-Object {
            -not $scenarioResults.ContainsKey($_) -or
            $scenarioResults[$_].Status -in @('NOT RUN', 'UNOBSERVABLE', 'FAIL')
        })

    if ($missingScenarioIds.Count -gt 0 -or $unresolvedScenarioIds.Count -gt 0) {
        $realScenarioStatus = 'INCOMPLETE'
    }
    else {
        $realScenarioStatus = 'PASS'
    }

    if ($installMode -eq 'local-skill-only') {
        $qualificationStatus = 'LOCAL_SKILL_ONLY'
    }
    elseif ($installBoundaryStatus -ne 'PASS') {
        $qualificationStatus = 'INSTALL_BOUNDARY_FAILURE'
    }
    elseif ($skillDiscoveryStatus -ne 'PASS') {
        $qualificationStatus = 'SKILL_DISCOVERY_FAILURE'
    }
    elseif ($realScenarioStatus -ne 'PASS') {
        $qualificationStatus = 'REAL_SCENARIO_INCOMPLETE'
    }
    else {
        $qualificationStatus = 'QUALIFICATION_PASS'
    }

    $recordLines = [System.Collections.Generic.List[string]]::new()
    [void]$recordLines.Add("# GitHub Copilot CLI qualification result")
    [void]$recordLines.Add('')
    [void]$recordLines.Add("- Date: $(Get-Date -Format o)")
    [void]$recordLines.Add("- Operator: automated repository-local harness")
    [void]$recordLines.Add("- Copilot CLI version: $copilotVersion")
    [void]$recordLines.Add("- APM version: $apmVersion")
    [void]$recordLines.Add("- Package: $PackageName")
    [void]$recordLines.Add("- Package version in lock: $lockPackageVersion")
    [void]$recordLines.Add("- Package source and full commit: $(if ($Repository) { "$Repository#$Ref" } else { $localSkillResolved })")
    [void]$recordLines.Add("- Source repository revision: $sourceRevision")
    [void]$recordLines.Add("- Install mode: $installMode")
    [void]$recordLines.Add("- Working repository: $workspace")
    [void]$recordLines.Add("- Installed Skill path: $([string]$requiredAssets.Paths.Skill)")
    [void]$recordLines.Add("- Installed Skill SHA-256: $skillHash")
    [void]$recordLines.Add("- Required full-package assets: $(if ($null -eq $requiredAssets) { 'not observed' } elseif ($requiredAssets.Complete) { 'PASS' } else { "MISSING: $($requiredAssets.Missing -join ', ')" })")
    [void]$recordLines.Add("- Install boundary status: $installBoundaryStatus")
    [void]$recordLines.Add("- Skill discovery status: $skillDiscoveryStatus")
    [void]$recordLines.Add("- Local-only status: $localOnlyStatus")
    [void]$recordLines.Add("- Real-scenario status: $realScenarioStatus")
    [void]$recordLines.Add("- Qualification status: $qualificationStatus")
    [void]$recordLines.Add("- Model capability observation: requested and observed model values require separate evidence; this harness does not infer per-agent model locking.")
    if (-not [string]::IsNullOrWhiteSpace($failureReason)) {
        [void]$recordLines.Add("- Failure or limitation: $failureReason")
    }
    [void]$recordLines.Add('')
    [void]$recordLines.Add('| Scenario | Status | Observable evidence | Validation | Requested model | Observed model |')
    [void]$recordLines.Add('| --- | --- | --- | --- | --- | --- |')

    foreach ($scenario in $fixtureScenarios) {
        $id = [string]$scenario.id
        if ($scenarioResults.ContainsKey($id)) {
            $result = $scenarioResults[$id]
            $status = $result.Status
            $evidence = $result.Evidence
            $validation = $result.Validation
            $requestedModel = $result.RequestedModel
            $observedModel = $result.ObservedModel
        }
        else {
            $status = if ([string]$scenario.kind -eq 'blocked') { 'BLOCKED' } else { 'NOT RUN' }
            $evidence = if ($status -eq 'BLOCKED') { [string]$scenario.blocker } else { 'No result was supplied.' }
            $validation = 'required scenario result missing'
            $requestedModel = 'not run'
            $observedModel = 'not observed'
        }
        [void]$recordLines.Add("| $id | $status | $($evidence -replace '\|', '\|') | $validation | $requestedModel | $observedModel |")
    }

    [void]$recordLines.Add('')
    [void]$recordLines.Add('## Notes and limitations')
    [void]$recordLines.Add('')
    [void]$recordLines.Add("- `local-skill-only` proves CLI Skill discovery for the working-tree Skill but is never qualification evidence.")
    [void]$recordLines.Add("- Static validators and Skill discovery do not prove real model routing, production mutation, durable process completion, or per-agent model locking.")
    [void]$recordLines.Add("- A qualification pass requires every non-blocked fixture scenario to be PASS and every required full-package asset and lock identity to be observed.")
    [void]$recordLines.Add("- Design Pair E2E remains blocked by Issue #69.")

    $resultPath = Join-Path $runRoot 'result.md'
    Write-Utf8File $resultPath $recordLines
    Write-Host "INSTALL_BOUNDARY: $installBoundaryStatus"
    Write-Host "SKILL_DISCOVERY: $skillDiscoveryStatus"
    Write-Host "LOCAL_SKILL_ONLY: $localOnlyStatus"
    Write-Host "REAL_SCENARIOS: $realScenarioStatus"
    if ($qualificationStatus -eq 'QUALIFICATION_PASS') {
        Write-Host 'QUALIFICATION_PASS'
    }
    else {
        Write-Host "QUALIFICATION_STATUS: $qualificationStatus"
    }
    Write-Host "Result: $resultPath"

    $shouldFail = $false
    $failureMessage = $null
    if ($qualificationStatus -eq 'REAL_SCENARIO_INCOMPLETE' -and -not $AllowIncomplete) {
        $shouldFail = $true
        $failureMessage = "Qualification is incomplete; required scenarios are missing, NOT RUN, UNOBSERVABLE, or FAIL: $($unresolvedScenarioIds -join ', ')."
    }
    if ($qualificationStatus -in @('INSTALL_BOUNDARY_FAILURE', 'SKILL_DISCOVERY_FAILURE')) {
        $shouldFail = $true
        $failureMessage = "Qualification boundary failed: $qualificationStatus. $failureReason"
    }

    if (-not $KeepWorkspace -and (Test-Path -LiteralPath $workspace)) {
        Remove-Item -LiteralPath $workspace -Recurse -Force
    }
    if ($shouldFail) {
        throw $failureMessage
    }
}
