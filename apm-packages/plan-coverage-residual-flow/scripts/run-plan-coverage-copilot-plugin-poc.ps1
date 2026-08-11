[CmdletBinding()]
param(
    [string]$Model,
    [string]$CopilotCommand = 'copilot',
    [string]$ResultsDir,
    [string[]]$ScenarioIds,
    [int]$TimeoutSeconds = 1800,
    [string]$BundleRoot,
    [switch]$SkipBuild,
    [switch]$SkipValidate,
    [switch]$KeepWorktree,
    [switch]$DescribePayload,
    [switch]$ConfirmExternalModelPayload,
    [switch]$SkipFullCoverage,
    [switch]$SkipStdSlice,
    [switch]$DiscoveryOnly
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'PlanCoverageAgentPlugin.Common.ps1')

$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Get-ApRepoRootFromPackage $packageRoot
$pocRoot = Join-Path $packageRoot 'tests/agent-plugin-poc'
$rqRoot = Join-Path $packageRoot 'tests/runtime-qualification'
$authScenarioPath = Join-Path $packageRoot 'tests/invocation-authorization-scenarios.json'
$stdFixtureRoot = Join-Path $rqRoot 'copilot-cli/standard-slice'
$fullFixtureRoot = Join-Path $rqRoot 'copilot-cli/full-coverage'
$baselinePath = Join-Path $rqRoot 'results/2026-08-10-copilot-cli.json'
$apmYmlPath = Join-Path $packageRoot 'apm.yml'
$canonicalRoot = Join-Path $packageRoot '.apm'
$buildScript = Join-Path $PSScriptRoot 'build-plan-coverage-agent-plugin.ps1'
$validateScript = Join-Path $PSScriptRoot 'validate-plan-coverage-agent-plugin.ps1'

if ([string]::IsNullOrWhiteSpace($ResultsDir)) {
    $ResultsDir = Join-Path $pocRoot 'results'
}
$ResultsDir = [System.IO.Path]::GetFullPath($ResultsDir)

# Shared scenario lib expects these names (same as #106 runner).
$planCoverageOwnedAgents = @($script:PlanCoverageOwnedAgentNames)
$adaptiveAgents = @('high-implementation-starter', 'standard-implementation-completer')
$allTrackedAgents = @($planCoverageOwnedAgents + $adaptiveAgents + @('design-pair-implementation-execution'))
# $Repository/$Ref used by Install-PlanCoverageInto in lib — keep empty so local staging path is used if ever called.
$Repository = $null
$Ref = $null

. (Join-Path $PSScriptRoot 'plan-coverage-copilot-scenario-lib.ps1')

function Assert-NoProjectShadowing([string]$Worktree) {
    $shadows = @(
        '.agents/skills/plan-coverage-residual-flow',
        '.github/agents/plan-kernel.agent.md',
        '.github/instructions/plan-coverage-shared.instructions.md',
        '.codex/agents/plan-kernel.toml'
    )
    foreach ($rel in $shadows) {
        if (Test-Path -LiteralPath (Join-Path $Worktree $rel)) {
            throw "Fixture worktree must not contain project-level Plan Coverage shadow path: $rel"
        }
    }
}

function New-PluginPocWorktree {
    param(
        [string]$ScenarioDir,
        [object]$AuthScenario,
        [string]$SeedRoot,
        [string]$OracleVerifyPath,
        [string[]]$ExtraOraclePaths,
        [string]$RequestPath
    )
    $worktree = Join-Path $ScenarioDir 'repo'
    New-Item -ItemType Directory -Path $worktree -Force | Out-Null
    # Direct plugin path: NO apm install of Plan Coverage. Empty git repo (+ optional E2E seed only).
    if ($SeedRoot -and (Test-Path -LiteralPath $SeedRoot)) {
        Copy-DirectoryContents $SeedRoot $worktree
    }
    if ($RequestPath -and (Test-Path -LiteralPath $RequestPath)) {
        Copy-Item -LiteralPath $RequestPath -Destination (Join-Path $worktree 'REQUEST.md') -Force
    }
    $testsDir = Join-Path $worktree 'tests'
    if ($OracleVerifyPath -and (Test-Path -LiteralPath $OracleVerifyPath)) {
        New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
        $destName = if ((Split-Path -Leaf $OracleVerifyPath) -ceq 'verify.ps1') {
            if ($ScenarioDir -match 'FULL') { 'verify-full-001.ps1' } else { 'verify-std-001.ps1' }
        }
        else {
            Split-Path -Leaf $OracleVerifyPath
        }
        Copy-Item -LiteralPath $OracleVerifyPath -Destination (Join-Path $testsDir $destName) -Force
    }
    foreach ($extra in @($ExtraOraclePaths)) {
        if ($extra -and (Test-Path -LiteralPath $extra)) {
            New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
            $leaf = Split-Path -Leaf $extra
            Copy-Item -LiteralPath $extra -Destination (Join-Path $testsDir $leaf) -Force
        }
    }

    if ($AuthScenario) {
        if ($AuthScenario.context.existing_plan -or $AuthScenario.context.existing_plan_coverage_artifacts) {
            New-Item -ItemType Directory -Path (Join-Path $worktree 'plans') -Force | Out-Null
            Write-Utf8File (Join-Path $worktree 'plans/existing-placeholder.md') "# Existing plan placeholder`n"
            Write-Utf8File (Join-Path $worktree 'plans/existing-placeholder-coverage-ledger.md') "# Existing coverage ledger placeholder`n"
        }
        if ($AuthScenario.context.large -or $AuthScenario.context.high_risk -or $AuthScenario.context.architecture_change) {
            Write-Utf8File (Join-Path $worktree 'TASK_CONTEXT.md') @"
# Task context (fixture metadata only; not authorization)

- large: $($AuthScenario.context.large)
- high_risk: $($AuthScenario.context.high_risk)
- architecture_change: $($AuthScenario.context.architecture_change)
"@
        }
    }

    Assert-NoProjectShadowing $worktree
    Initialize-GitFixture $worktree 'plugin-poc fixture'
    return $worktree
}

function Invoke-CopilotPluginScenario {
    param(
        [string]$Worktree,
        [string]$Prompt,
        [string]$ScenarioId,
        [string]$EvidenceDir,
        [string]$CopilotExe,
        [string]$ModelName,
        [int]$TimeoutSec,
        [string]$PluginBundleRoot,
        [string]$PluginLoadMode
    )

    # Caller already provides a per-scenario evidence directory.
    $scenarioDir = $EvidenceDir
    New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
    $hookLog = Join-Path $scenarioDir 'hooks.jsonl'
    $stdoutPath = Join-Path $scenarioDir 'stdout.txt'
    $stderrPath = Join-Path $scenarioDir 'stderr.txt'
    $sharePath = Join-Path $scenarioDir 'session.md'
    $copilotHome = Join-Path $scenarioDir 'copilot-home'
    Initialize-CopilotHome -CopilotHome $copilotHome -HookLogPath $hookLog

    $before = @(Get-GitSnapshot $Worktree)
    $beforeSet = @{}
    foreach ($b in $before) {
        if (-not [string]::IsNullOrWhiteSpace($b)) { $beforeSet[[string]$b] = $true }
    }

    $promptPath = Join-Path $Worktree 'QUALIFICATION_PROMPT.md'
    Write-Utf8File $promptPath $Prompt
    $shortPrompt = @'
Read QUALIFICATION_PROMPT.md in this repository root and execute it completely without asking clarifying questions. If REQUEST.md also exists, treat QUALIFICATION_PROMPT.md as authoritative and REQUEST.md as supporting source requirement detail. Do not stop for human product decisions that the fixture already closed.
'@.Trim()

    $args = @()
    if ($PluginLoadMode -ceq 'plugin-dir') {
        $args += @('--plugin-dir', $PluginBundleRoot)
    }
    $args += @(
        '--no-ask-user',
        '-p', $shortPrompt,
        '-C', $Worktree,
        '--allow-all',
        '--disable-builtin-mcps',
        '--no-custom-instructions',
        '--share', $sharePath,
        '--output-format', 'text'
    )
    if (-not [string]::IsNullOrWhiteSpace($ModelName)) {
        $args = @('--model', $ModelName) + $args
    }

    $stdout = ''
    $stderr = ''
    $exitCode = -1
    $previousCopilotHome = $env:COPILOT_HOME
    $previousHookLog = $env:RQ_HOOK_LOG
    $previousAllowAll = $env:COPILOT_ALLOW_ALL
    $previousCi = $env:CI
    try {
        $env:COPILOT_HOME = $copilotHome
        $env:RQ_HOOK_LOG = $hookLog
        $env:COPILOT_ALLOW_ALL = 'true'
        $env:CI = 'true'

        if ($PluginLoadMode -ceq 'plugin-install') {
            $installOut = & $CopilotExe @('plugin', 'install', $PluginBundleRoot) 2>&1
            $installExit = $LASTEXITCODE
            Write-Utf8File (Join-Path $scenarioDir 'plugin-install.txt') (($installOut | ForEach-Object { [string]$_ }) -join "`n")
            if ($installExit -ne 0) {
                throw "copilot plugin install failed with exit code $installExit"
            }
        }

        Push-Location $Worktree
        try {
            $outputLines = & $CopilotExe @args 2>&1
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) { $exitCode = 0 }
            $stdout = ($outputLines | ForEach-Object { [string]$_ }) -join "`n"
            $stderr = ''
        }
        catch {
            $exitCode = -1
            $stderr = "$_"
            $stdout = ''
        }
        finally {
            Pop-Location
        }
        Write-Utf8File $stdoutPath $(if ($null -eq $stdout) { '' } else { $stdout })
        Write-Utf8File $stderrPath $(if ($null -eq $stderr) { '' } else { $stderr })
    }
    finally {
        if ($null -ne $previousCopilotHome) { $env:COPILOT_HOME = $previousCopilotHome } else { Remove-Item Env:COPILOT_HOME -ErrorAction SilentlyContinue }
        if ($null -ne $previousHookLog) { $env:RQ_HOOK_LOG = $previousHookLog } else { Remove-Item Env:RQ_HOOK_LOG -ErrorAction SilentlyContinue }
        if ($null -ne $previousAllowAll) { $env:COPILOT_ALLOW_ALL = $previousAllowAll } else { Remove-Item Env:COPILOT_ALLOW_ALL -ErrorAction SilentlyContinue }
        if ($null -ne $previousCi) { $env:CI = $previousCi } else { Remove-Item Env:CI -ErrorAction SilentlyContinue }
    }

    $after = Get-GitSnapshot $Worktree
    $created = @()
    $changed = @()
    foreach ($path in $after) {
        if ($beforeSet.ContainsKey($path)) { $changed += $path } else { $created += $path }
    }
    foreach ($d in @(& git -C $Worktree diff --name-only 2>$null)) {
        $n = $d.Replace('\', '/')
        if ($changed -notcontains $n -and $created -notcontains $n) { $changed += $n }
    }

    $agents = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @(Get-AgentsFromHookLog $hookLog)) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    foreach ($a in @(Get-AgentsFromSessionEvents $copilotHome)) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    $combinedText = @"
$stdout

$stderr

$(if (Test-Path -LiteralPath $sharePath) { Get-Content -LiteralPath $sharePath -Raw -ErrorAction SilentlyContinue })
"@
    $modelObserved = 'client-selected-or-unobserved'
    if ($combinedText -cmatch '(?i)\bmodel(?:\s+is|\s*[:=])\s*([a-z0-9._-]+)') {
        $modelObserved = $Matches[1]
    }
    $exitInt = 0
    try { $exitInt = [int]$exitCode } catch { $exitInt = -1 }

    return [pscustomobject]@{
        ExitCode = $exitInt
        Stdout = $stdout
        Stderr = $stderr
        SharePath = $sharePath
        HookLog = $hookLog
        Agents = @($agents)
        Created = $created
        Changed = $changed
        CombinedText = $combinedText
        ModelObserved = $modelObserved
        TranscriptSha = if (Test-Path -LiteralPath $sharePath) { Get-Sha256File $sharePath } else { Get-Sha256Text $stdout }
        HookSha = Get-Sha256File $hookLog
        PluginLoadMode = $PluginLoadMode
    }
}

function Test-CodexDirectPluginSupport {
    $evidence = [System.Collections.Generic.List[object]]::new()
    $status = 'UNCONFIRMED_NO_LOCAL_DIRECT_LOAD_OBSERVED'
    try {
        $ver = ((& codex --version 2>&1 | Out-String).Trim())
        $evidence.Add([ordered]@{ kind = 'client_version'; value = $ver }) | Out-Null
        $help = ((& codex plugin --help 2>&1 | Out-String).Trim())
        $evidence.Add([ordered]@{ kind = 'plugin_help'; value = ($help -replace '\s+', ' ').Substring(0, [Math]::Min(500, ($help.Length))) }) | Out-Null
        $addHelp = ((& codex plugin add --help 2>&1 | Out-String).Trim())
        $evidence.Add([ordered]@{ kind = 'plugin_add_help'; value = ($addHelp -replace '\s+', ' ').Substring(0, [Math]::Min(500, ($addHelp.Length))) }) | Out-Null

        # Probe actual CLI rejection of a local path (no hand-unpack into .codex/**).
        $probeDir = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-plugin-probe-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $probeDir -Force | Out-Null
        Write-ApUtf8File (Join-Path $probeDir 'plugin.json') "{`"name`":`"probe`",`"version`":`"0.0.0`"}`n"
        try {
            $probeOut = & codex @('plugin', 'add', $probeDir) 2>&1
            $probeText = (($probeOut | ForEach-Object { [string]$_ }) -join "`n")
            $probeExit = $LASTEXITCODE
            $evidence.Add([ordered]@{
                    kind  = 'local_path_probe'
                    value = "exit=$probeExit text=$(($probeText -replace '\s+', ' ').Substring(0, [Math]::Min(400, $probeText.Length)))"
                }) | Out-Null
            if ($probeExit -ne 0) {
                $status = 'UNCONFIRMED_NO_LOCAL_DIRECT_LOAD_OBSERVED'
                $evidence.Add([ordered]@{
                        kind  = 'conclusion'
                        value = 'codex plugin add rejected local path probe; marketplace-oriented help only. No confirmed local Agent Plugins bundle direct-load path.'
                    }) | Out-Null
            }
            else {
                $status = 'UNCONFIRMED'
                $evidence.Add([ordered]@{ kind = 'conclusion'; value = 'local path probe unexpectedly succeeded; needs manual review' }) | Out-Null
            }
        }
        finally {
            Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        $status = 'UNCONFIRMED_NO_LOCAL_DIRECT_LOAD_OBSERVED'
        $evidence.Add([ordered]@{ kind = 'error'; value = "$_" }) | Out-Null
    }
    return [ordered]@{
        status   = $status
        evidence = @($evidence)
    }
}

function Get-BoundaryInventory {
    # Post-#111 ownership: Adaptive agents live only under package-owned .apm/agents (no root projection fallback).
    return @(
        [ordered]@{ item = 'Plan Coverage SKILL.md'; classification = 'agent-plugins-portable'; canonical_owner = '.apm/skills'; bundle_representation = 'skills/...'; runtime_representation = 'plugin skills discovery'; direct_plugin = 'yes'; apm_path = 'yes'; reason = '1:1 pack' }
        [ordered]@{ item = 'Skill references'; classification = 'agent-plugins-portable'; canonical_owner = '.apm/skills/references'; bundle_representation = 'skills/.../references'; runtime_representation = 'plugin skill refs'; direct_plugin = 'yes'; apm_path = 'yes'; reason = 'packed with Skill' }
        [ordered]@{ item = 'Plan Coverage custom agents'; classification = 'copilot-plugin-extension'; canonical_owner = '.apm/agents'; bundle_representation = 'agents/*.agent.md'; runtime_representation = 'Copilot plugin agents/ or APM .github/agents'; direct_plugin = 'yes-on-copilot'; apm_path = 'yes'; reason = 'not AP v1 portable core' }
        [ordered]@{ item = 'Plan Coverage shared instruction'; classification = 'apm-projection-materialization'; canonical_owner = '.apm/instructions'; bundle_representation = 'instructions/'; runtime_representation = '.github/instructions via APM'; direct_plugin = 'path-gap'; apm_path = 'yes'; reason = '.github/instructions not seeded under direct plugin' }
        [ordered]@{ item = 'Adaptive Implementation Skill'; classification = 'transitive-portable-dependency'; canonical_owner = 'adaptive package'; bundle_representation = 'absent-from-PC-bundle; standalone-pack-ok'; runtime_representation = 'APM transitive install'; direct_plugin = 'separate-bundle'; apm_path = 'yes'; reason = 'attested in install lock; not inlined by PC pack' }
        [ordered]@{ item = 'Adaptive HIGH agent'; classification = 'copilot-plugin-extension'; canonical_owner = 'adaptive .apm/agents'; bundle_representation = 'absent-from-PC-bundle'; runtime_representation = 'APM .github/agents from Adaptive package'; direct_plugin = 'no-in-PC-bundle'; apm_path = 'yes'; reason = 'package-owned canonical post-#111; separate Adaptive plugin or APM materialization' }
        [ordered]@{ item = 'Adaptive STANDARD agent'; classification = 'copilot-plugin-extension'; canonical_owner = 'adaptive .apm/agents'; bundle_representation = 'absent-from-PC-bundle'; runtime_representation = 'APM .github/agents from Adaptive package'; direct_plugin = 'no-in-PC-bundle'; apm_path = 'yes'; reason = 'package-owned canonical post-#111; separate Adaptive plugin or APM materialization' }
        [ordered]@{ item = 'concrete model selection'; classification = 'codex-runtime-adapter'; canonical_owner = 'owning package overlay + finalizer'; bundle_representation = 'absent'; runtime_representation = 'Codex TOML overlays'; direct_plugin = 'n/a'; apm_path = 'yes'; reason = 'runtime-specific compatibility finalization' }
        [ordered]@{ item = 'explicit invocation authorization'; classification = 'agent-plugins-portable'; canonical_owner = 'SKILL.md'; bundle_representation = 'Skill text'; runtime_representation = 'Skill behavior'; direct_plugin = 'yes'; apm_path = 'yes'; reason = 'canonical Skill contract' }
        [ordered]@{ item = 'handoff state'; classification = 'currently-unqualified'; canonical_owner = 'process artifacts'; bundle_representation = 'n/a'; runtime_representation = 'plans/* durable artifacts'; direct_plugin = 'process'; apm_path = 'yes'; reason = 'artifact contract' }
        [ordered]@{ item = 'APM lock/provenance'; classification = 'apm-distribution-provenance'; canonical_owner = 'apm pack/install'; bundle_representation = 'apm.lock.yaml + attestation lock'; runtime_representation = 'install integrity'; direct_plugin = 'embedded'; apm_path = 'yes'; reason = 'pack lock + adaptive attestation lock' }
        [ordered]@{ item = 'Codex TOML projection'; classification = 'codex-runtime-adapter'; canonical_owner = 'APM codex target'; bundle_representation = 'absent'; runtime_representation = '.codex/agents/*.toml'; direct_plugin = 'no'; apm_path = 'yes'; reason = 'not AP portable' }
        [ordered]@{ item = 'Copilot runtime custom agents'; classification = 'copilot-runtime-adapter'; canonical_owner = 'plugin agents/ / APM copilot'; bundle_representation = 'agents/'; runtime_representation = '.github/agents or plugin agents'; direct_plugin = 'yes'; apm_path = 'yes'; reason = 'Copilot extension surface' }
    )
}

function Get-AdaptivePackagingFromBuild($BuildResult, [string]$BundlePath) {
    $adaptiveInBundle = Test-Path -LiteralPath (Join-Path $BundlePath 'skills/adaptive-implementation-execution/SKILL.md') -PathType Leaf
    $highInBundle = Test-Path -LiteralPath (Join-Path $BundlePath 'agents/high-implementation-starter.agent.md') -PathType Leaf
    $stdInBundle = Test-Path -LiteralPath (Join-Path $BundlePath 'agents/standard-implementation-completer.agent.md') -PathType Leaf
    $att = $null
    if ($BuildResult -and $BuildResult.adaptive_attestation) {
        $att = $BuildResult.adaptive_attestation
    }
    return [ordered]@{
        attestation                    = $att
        install_lock_attests_skill_high_standard = $(if ($att) { [string]$att.status -ceq 'PASS' } else { $null })
        path_dep_pack_refused          = $(if ($att) { [bool]$att.path_dep_pack_refused } else { $null })
        plan_coverage_bundle_includes_adaptive = ($adaptiveInBundle -or $highInBundle -or $stdInBundle)
        adaptive_standalone_pack_ok    = $(if ($att -and $att.standalone_adaptive_bundle_root) {
                Test-Path -LiteralPath (Join-Path $att.standalone_adaptive_bundle_root 'skills/adaptive-implementation-execution/SKILL.md')
            } else { $null })
        present_in_plan_coverage_bundle = [ordered]@{
            skill    = $adaptiveInBundle
            high     = $highInBundle
            standard = $stdInBundle
        }
    }
}

$packageMeta = Get-ApYamlScalarMap $apmYmlPath
$canonicalFingerprint = Get-CanonicalFingerprint $canonicalRoot
$apmYmlSha = Get-Sha256File $apmYmlPath
$packageVersion = Get-PackageVersion $apmYmlPath
# Qualifying external-model evidence requires a clean full SHA (no -dirty).
$candidateCommit = Get-ApGitCandidateCommit -RepoRoot $repoRoot
if ($candidateCommit -notmatch '^[a-f0-9]{40}$') {
    throw "candidate_commit must be a clean 40-char SHA for PoC evidence (got: $candidateCommit)"
}

$payload = @"
Plan Coverage GitHub Copilot CLI Agent Plugins direct-load PoC (#107)
- package: plan-coverage-residual-flow $packageVersion
- candidate: $candidateCommit
- canonical_fingerprint: $canonicalFingerprint
- path: canonical .apm -> apm pack plugin bundle -> copilot plugin install|--plugin-dir (NO apm install of Plan Coverage into fixture)
- scenarios: A-H (+ optional STD-001/FULL-001)
- external model: yes when -ConfirmExternalModelPayload
"@

if ($DescribePayload) {
    Write-Host $payload
    exit 0
}

$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$runRoot = Join-Path $tempParent ('plan-coverage-plugin-poc-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot, $ResultsDir -Force | Out-Null
$ownedBuildOut = $null
$buildResult = $null

try {
    # Build bundle
    if ([string]::IsNullOrWhiteSpace($BundleRoot)) {
        if ($SkipBuild) { throw 'BundleRoot required with -SkipBuild' }
        $ownedBuildOut = Join-Path $runRoot 'bundle-out'
        Write-Host 'Building plugin bundle...'
        $buildResult = & $buildScript -OutputDir $ownedBuildOut -Force
        if (-not $buildResult -or -not $buildResult.bundle_root) {
            throw 'build-plan-coverage-agent-plugin.ps1 did not return bundle_root'
        }
        $BundleRoot = [string]$buildResult.bundle_root
    }
    else {
        # Prefer sibling build-manifest.json when reusing an external bundle.
        $maybeManifest = Join-Path (Split-Path -Parent $BundleRoot) 'build-manifest.json'
        if (Test-Path -LiteralPath $maybeManifest -PathType Leaf) {
            $buildResult = Get-Content -Raw -LiteralPath $maybeManifest | ConvertFrom-Json
        }
    }
    $BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
    if (-not (Test-Path -LiteralPath $BundleRoot -PathType Container)) {
        throw "BundleRoot not found: $BundleRoot"
    }

    $pluginManifestSha = Get-Sha256File (Join-Path $BundleRoot 'plugin.json')
    $bundleLockSha = Get-Sha256File (Join-Path $BundleRoot 'apm.lock.yaml')
    $apmVersion = ((& apm --version 2>&1 | Out-String).Trim())
    $adaptivePackaging = Get-AdaptivePackagingFromBuild -BuildResult $buildResult -BundlePath $BundleRoot
    $adaptiveAttestationLockSha = $null
    if ($adaptivePackaging.attestation -and $adaptivePackaging.attestation.lock_sha256) {
        $adaptiveAttestationLockSha = [string]$adaptivePackaging.attestation.lock_sha256
    }
    elseif ($buildResult -and $buildResult.adaptive_attestation -and $buildResult.adaptive_attestation.lock_sha256) {
        $adaptiveAttestationLockSha = [string]$buildResult.adaptive_attestation.lock_sha256
    }

    $bundleStatus = 'PASS'
    if (-not $SkipValidate) {
        Write-Host 'Validating plugin bundle...'
        & $validateScript -BundleRoot $BundleRoot -SkipBuild -SkipNegativeTests
        if ($LASTEXITCODE -ne 0) {
            $bundleStatus = 'FAIL'
            throw "validate-plan-coverage-agent-plugin failed with exit code $LASTEXITCODE"
        }
    }

    $codexInfo = Test-CodexDirectPluginSupport
    $baseline = $null
    $baselineFp = $null
    if (Test-Path -LiteralPath $baselinePath -PathType Leaf) {
        $baseline = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json
        $baselineFp = [string]$baseline.canonical_fingerprint
    }
    $fingerprintMatch = ($baselineFp -and ($baselineFp -ceq $canonicalFingerprint))

    $capabilityGaps = [System.Collections.Generic.List[string]]::new()
    $copilotDirect = [ordered]@{
        status             = 'NOT_RUN'
        plugin_discovery   = 'NOT_RUN'
        plugin_install     = 'NOT_RUN'
        plugin_load_mode   = $null
        authorization      = 'NOT_RUN'
        standard_slice     = 'NOT_RUN'
        full_coverage      = 'NOT_RUN'
        adaptive_connection = 'NOT_RUN'
        shared_instruction = 'NOT_PROBED'
        capability_gaps    = @()
    }

    $scenarioResults = [System.Collections.Generic.List[object]]::new()
    $runStamp = Get-Date -Format 'yyyy-MM-dd'
    $modelObservedGlobal = $(if ($Model) { $Model } else { 'client-selected-or-unobserved' })
    $clientVersion = 'UNOBSERVABLE'

    if (-not $ConfirmExternalModelPayload -and -not $DiscoveryOnly) {
        $copilotDirect.status = 'NOT_RUN'
        $capabilityGaps.Add('external-model-not-confirmed: pass -ConfirmExternalModelPayload to run live scenarios') | Out-Null
        Write-Host 'External model not confirmed. Writing NOT_RUN evidence skeleton. Use -DiscoveryOnly for install/list without model, or -ConfirmExternalModelPayload for full PoC.'
    }

    if ($DiscoveryOnly -or $ConfirmExternalModelPayload) {
        $copilotExe = Resolve-CopilotExecutable $CopilotCommand
        Ensure-CopilotAuthEnv
        $clientVersion = ((& $copilotExe --version 2>&1 | Out-String).Trim() -replace '[\r\n].*', '').Trim()
        if ([string]::IsNullOrWhiteSpace($clientVersion)) { $clientVersion = 'UNOBSERVABLE' }

        # Discovery / install probe in isolated COPILOT_HOME (no model prompt).
        $discDir = Join-Path $runRoot 'discovery'
        New-Item -ItemType Directory -Path $discDir -Force | Out-Null
        $discHome = Join-Path $discDir 'copilot-home'
        Initialize-CopilotHome -CopilotHome $discHome -HookLogPath (Join-Path $discDir 'hooks.jsonl')
        $prevHome = $env:COPILOT_HOME
        try {
            $env:COPILOT_HOME = $discHome
            $listDir = & $copilotExe @('--plugin-dir', $BundleRoot, 'plugin', 'list') 2>&1
            $listDirText = ($listDir | ForEach-Object { [string]$_ }) -join "`n"
            Write-Utf8File (Join-Path $discDir 'plugin-list-plugin-dir.txt') $listDirText
            if ($listDirText -match 'plan-coverage-residual-flow') {
                $copilotDirect.plugin_discovery = 'PASS'
                $copilotDirect.plugin_load_mode = 'plugin-dir'
            }
            else {
                $copilotDirect.plugin_discovery = 'FAIL'
                $capabilityGaps.Add('plugin-dir list did not show plan-coverage-residual-flow') | Out-Null
            }

            $installOut = & $copilotExe @('plugin', 'install', $BundleRoot) 2>&1
            $installText = ($installOut | ForEach-Object { [string]$_ }) -join "`n"
            Write-Utf8File (Join-Path $discDir 'plugin-install.txt') $installText
            $installExit = $LASTEXITCODE
            if ($installExit -eq 0 -and ($installText -match 'installed' -or $installText -match 'plan-coverage')) {
                $copilotDirect.plugin_install = 'PASS'
            }
            else {
                $copilotDirect.plugin_install = 'FAIL'
                $capabilityGaps.Add("copilot plugin install exit=$installExit") | Out-Null
            }
            $listAfter = & $copilotExe @('plugin', 'list') 2>&1
            Write-Utf8File (Join-Path $discDir 'plugin-list-after-install.txt') (($listAfter | ForEach-Object { [string]$_ }) -join "`n")
        }
        finally {
            if ($null -ne $prevHome) { $env:COPILOT_HOME = $prevHome } else { Remove-Item Env:COPILOT_HOME -ErrorAction SilentlyContinue }
        }

        if ($DiscoveryOnly -and -not $ConfirmExternalModelPayload) {
            if ($copilotDirect.plugin_discovery -ceq 'PASS' -or $copilotDirect.plugin_install -ceq 'PASS') {
                $copilotDirect.status = 'PARTIAL'
            }
            elseif ($copilotDirect.plugin_discovery -ceq 'FAIL' -and $copilotDirect.plugin_install -ceq 'FAIL') {
                $copilotDirect.status = 'BLOCKED'
            }
            else {
                $copilotDirect.status = 'PARTIAL'
            }
            $capabilityGaps.Add('DiscoveryOnly: authorization/STD/FULL not executed (no -ConfirmExternalModelPayload)') | Out-Null
        }
    }

    if ($ConfirmExternalModelPayload) {
        Write-Host $payload
        $copilotExe = Resolve-CopilotExecutable $CopilotCommand
        Ensure-CopilotAuthEnv
        $evidenceRoot = Join-Path $runRoot 'evidence'
        New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
        $pluginLoadMode = if ($copilotDirect.plugin_discovery -ceq 'PASS') { 'plugin-dir' } else { 'plugin-install' }
        $copilotDirect.plugin_load_mode = $pluginLoadMode

        $authScenarios = Get-Content -Raw -LiteralPath $authScenarioPath | ConvertFrom-Json
        $selectedFilter = $null
        if ($ScenarioIds -and @($ScenarioIds).Count -gt 0) {
            $selectedFilter = @{}
            foreach ($raw in @($ScenarioIds)) {
                foreach ($part in ([string]$raw -split '[,;\s]+')) {
                    if (-not [string]::IsNullOrWhiteSpace($part)) {
                        $selectedFilter[$part.Trim().ToUpperInvariant()] = $true
                    }
                }
            }
        }

        foreach ($scenario in $authScenarios) {
            $sid = [string]$scenario.id
            if ($selectedFilter -and -not $selectedFilter.ContainsKey($sid.ToUpperInvariant())) { continue }
            Write-Host "=== Plugin PoC authorization $sid ==="
            $scenarioDir = Join-Path $evidenceRoot "auth-$sid"
            New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
            $worktree = New-PluginPocWorktree -ScenarioDir $scenarioDir -AuthScenario $scenario
            $prompt = Build-PromptFromAuthScenario $scenario
            Write-Utf8File (Join-Path $scenarioDir 'prompt.md') $prompt
            $run = Invoke-CopilotPluginScenario -Worktree $worktree -Prompt $prompt -ScenarioId $sid -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec $TimeoutSeconds -PluginBundleRoot $BundleRoot -PluginLoadMode $pluginLoadMode
            if ($run.ModelObserved -and $run.ModelObserved -cne 'client-selected-or-unobserved') {
                $modelObservedGlobal = $run.ModelObserved
            }
            $evaluated = Evaluate-AuthScenario $scenario $run
            $scenarioResults.Add($evaluated)
            Write-Host "Scenario $sid => $($evaluated.status)"
        }

        if (-not $SkipStdSlice -and (-not $selectedFilter -or $selectedFilter.ContainsKey('STD-001'))) {
            Write-Host '=== Plugin PoC STD-001 ==='
            $scenarioDir = Join-Path $evidenceRoot 'STD-001'
            New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
            $worktree = New-PluginPocWorktree -ScenarioDir $scenarioDir -SeedRoot (Join-Path $stdFixtureRoot 'seed') -OracleVerifyPath (Join-Path $stdFixtureRoot 'verify.ps1') -RequestPath (Join-Path $stdFixtureRoot 'request.md')
            # Hash oracle like #106 New-E2EWorktree
            $oracleMeta = Join-Path $scenarioDir 'oracle-hashes.json'
            $oracleMap = [ordered]@{}
            $stdTests = Join-Path $worktree 'tests'
            if (Test-Path -LiteralPath $stdTests) {
                Get-ChildItem -LiteralPath $stdTests -Filter 'verify*.ps1' -File | ForEach-Object {
                    $oracleMap[$_.Name] = Get-Sha256File $_.FullName
                }
            }
            Write-Utf8File $oracleMeta (ConvertTo-JsonCompat $oracleMap)
            $prompt = Get-NormalizedText (Join-Path $worktree 'REQUEST.md')
            $run = Invoke-CopilotPluginScenario -Worktree $worktree -Prompt $prompt -ScenarioId 'STD-001' -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec $TimeoutSeconds -PluginBundleRoot $BundleRoot -PluginLoadMode $pluginLoadMode
            $evaluated = Evaluate-StdScenario $run $worktree $oracleMeta
            $scenarioResults.Add($evaluated)
            Write-Host "STD-001 => $($evaluated.status)"
            if ($evaluated.adaptive_connection) {
                $copilotDirect.adaptive_connection = if ($evaluated.adaptive_connection.connection_satisfied) { 'PASS' } else { 'FAIL' }
            }
        }

        if (-not $SkipFullCoverage -and (-not $selectedFilter -or $selectedFilter.ContainsKey('FULL-001'))) {
            Write-Host '=== Plugin PoC FULL-001 ==='
            $scenarioDir = Join-Path $evidenceRoot 'FULL-001'
            New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
            $extra = @(
                (Join-Path $fullFixtureRoot 'seed/tests/verify-sl-001.ps1'),
                (Join-Path $fullFixtureRoot 'seed/tests/verify-sl-002.ps1')
            )
            $worktree = New-PluginPocWorktree -ScenarioDir $scenarioDir -SeedRoot (Join-Path $fullFixtureRoot 'seed') -OracleVerifyPath (Join-Path $fullFixtureRoot 'verify.ps1') -ExtraOraclePaths $extra -RequestPath (Join-Path $fullFixtureRoot 'request.md')
            $oracleMeta = Join-Path $scenarioDir 'oracle-hashes.json'
            $oracleMap = [ordered]@{}
            $fullTests = Join-Path $worktree 'tests'
            if (Test-Path -LiteralPath $fullTests) {
                Get-ChildItem -LiteralPath $fullTests -Filter 'verify*.ps1' -File | ForEach-Object {
                    $oracleMap[$_.Name] = Get-Sha256File $_.FullName
                }
            }
            Write-Utf8File $oracleMeta (ConvertTo-JsonCompat $oracleMap)
            $prompt = Get-NormalizedText (Join-Path $worktree 'REQUEST.md')
            $run = Invoke-CopilotPluginScenario -Worktree $worktree -Prompt $prompt -ScenarioId 'FULL-001' -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec ([Math]::Max($TimeoutSeconds, 3600)) -PluginBundleRoot $BundleRoot -PluginLoadMode $pluginLoadMode
            $evaluated = Evaluate-FullScenario $run $worktree $oracleMeta
            $scenarioResults.Add($evaluated)
            Write-Host "FULL-001 => $($evaluated.status)"
            if ($evaluated.adaptive_connection -and $evaluated.adaptive_connection.connection_satisfied) {
                $copilotDirect.adaptive_connection = 'PASS'
            }
            elseif ($copilotDirect.adaptive_connection -cne 'PASS') {
                $copilotDirect.adaptive_connection = $(if ($evaluated.status -ceq 'FAIL') { 'FAIL' } else { $copilotDirect.adaptive_connection })
            }
        }

        # Summarize auth/std/full
        $byId = @{}
        foreach ($s in $scenarioResults) { $byId[[string]$s.id] = $s }
        $authIds = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H')
        $authPass = $true
        $authRan = $false
        foreach ($id in $authIds) {
            if ($byId.ContainsKey($id)) {
                $authRan = $true
                if ($byId[$id].status -cne 'PASS') { $authPass = $false }
            }
        }
        if ($authRan) {
            $copilotDirect.authorization = if ($authPass) { 'PASS' } else { 'FAIL' }
        }
        if ($byId.ContainsKey('STD-001')) {
            $copilotDirect.standard_slice = [string]$byId['STD-001'].status
        }
        elseif ($SkipStdSlice) {
            $copilotDirect.standard_slice = 'NOT_RUN'
        }
        if ($byId.ContainsKey('FULL-001')) {
            $copilotDirect.full_coverage = [string]$byId['FULL-001'].status
        }
        elseif ($SkipFullCoverage) {
            $copilotDirect.full_coverage = 'NOT_RUN'
            $capabilityGaps.Add('FULL-001 skipped by flag') | Out-Null
        }

        # Shared instruction gap probe: agents reference .github/instructions path; fixture must not seed it.
        $sharedInFixture = $false
        foreach ($s in $scenarioResults) {
            $repoPath = Join-Path $evidenceRoot $(if ($s.id -match 'STD|FULL') { $s.id } else { "auth-$($s.id)" })
            $repoPath = Join-Path $repoPath 'repo/.github/instructions/plan-coverage-shared.instructions.md'
            if (Test-Path -LiteralPath $repoPath) { $sharedInFixture = $true }
        }
        if ($sharedInFixture) {
            $capabilityGaps.Add('shared-instruction unexpectedly present in fixture (forbidden seed)') | Out-Null
            $copilotDirect.shared_instruction = 'INVALID_FIXTURE'
        }
        else {
            $copilotDirect.shared_instruction = 'NOT_MATERIALIZED_IN_FIXTURE'
            # If agents failed to run while skill may have loaded, record gap.
            $anyAgent = @($scenarioResults | Where-Object { @($_.agents_observed).Count -gt 0 }).Count -gt 0
            if (-not $anyAgent -and $copilotDirect.authorization -ceq 'PASS') {
                $capabilityGaps.Add('no Plan Coverage agents observed on authorized scenarios — possible shared-instruction / agent discovery gap under direct plugin') | Out-Null
            }
            if (-not $anyAgent) {
                $capabilityGaps.Add('APM materialization or Copilot plugin adapter may be required for .github/instructions/plan-coverage-shared.instructions.md and full agent orchestration') | Out-Null
            }
        }

        # Adaptive gap if routes need it — prefer packaging attestation language from build.
        if ($copilotDirect.adaptive_connection -cne 'PASS') {
            if ($adaptivePackaging.install_lock_attests_skill_high_standard -eq $true -and -not $adaptivePackaging.plan_coverage_bundle_includes_adaptive) {
                $capabilityGaps.Add('Adaptive Skill/HIGH/STANDARD attested in source-install lock deployed_files/hashes but not inlined by apm pack of Plan Coverage (path-dep pack refused; Adaptive packs standalone)') | Out-Null
            }
            elseif (-not (Test-Path -LiteralPath (Join-Path $BundleRoot 'skills/adaptive-implementation-execution'))) {
                $capabilityGaps.Add('Adaptive Implementation not present in plugin bundle (transitive package / APM projection)') | Out-Null
            }
        }

        # Overall copilot_direct_load status
        if ($copilotDirect.plugin_discovery -cne 'PASS' -and $copilotDirect.plugin_install -cne 'PASS') {
            $copilotDirect.status = 'BLOCKED'
        }
        elseif ($copilotDirect.authorization -ceq 'FAIL') {
            $copilotDirect.status = 'FAIL'
        }
        elseif ($copilotDirect.authorization -ceq 'PASS' -and $copilotDirect.standard_slice -ceq 'PASS' -and $copilotDirect.full_coverage -ceq 'PASS' -and $copilotDirect.adaptive_connection -ceq 'PASS') {
            $copilotDirect.status = 'PASS'
        }
        elseif ($copilotDirect.authorization -ceq 'PASS') {
            $copilotDirect.status = 'PARTIAL'
        }
        else {
            $copilotDirect.status = 'PARTIAL'
        }
    }

    $copilotDirect.capability_gaps = @($capabilityGaps)

    # Decision
    $verdict = 'HOLD'
    $rationale = [System.Collections.Generic.List[string]]::new()
    $next = [System.Collections.Generic.List[string]]::new()
    if ($bundleStatus -cne 'PASS') {
        $verdict = 'NO_GO'
        $rationale.Add('Bundle conformance failed') | Out-Null
    }
    else {
        $rationale.Add('Strict Agent Plugins v1 bundle synthesized at pack stage (no checked-in package-root plugin.json); APM local-source install semantics preserved') | Out-Null
        if ($adaptivePackaging.install_lock_attests_skill_high_standard -eq $true) {
            $rationale.Add('Adaptive Skill/HIGH/STANDARD attested in source-install lock deployed_files/hashes; apm pack refuses path deps; Plan Coverage pack does not inline Adaptive; Adaptive standalone pack succeeds') | Out-Null
        }
    }
    if ($copilotDirect.status -ceq 'NOT_RUN') {
        $verdict = 'HOLD'
        $rationale.Add('Live Copilot direct-load scenarios not executed (external model not confirmed or discovery-only)') | Out-Null
        $next.Add('Run run-plan-coverage-copilot-plugin-poc.ps1 -ConfirmExternalModelPayload on an authenticated Copilot CLI host') | Out-Null
    }
    elseif ($copilotDirect.status -ceq 'PASS' -and $fingerprintMatch) {
        $verdict = 'GO'
        $rationale.Add('Direct plugin path achieved authorization + STD + FULL parity-capable run with matching canonical fingerprint') | Out-Null
    }
    elseif ($copilotDirect.status -ceq 'PARTIAL' -or $copilotDirect.status -ceq 'BLOCKED') {
        $verdict = 'HOLD'
        $rationale.Add("Copilot direct-load status=$($copilotDirect.status); portable Skill/bundle OK but runtime adapter gaps remain") | Out-Null
        foreach ($g in $capabilityGaps) { $rationale.Add("gap: $g") | Out-Null }
        $next.Add('Design Copilot plugin adapter / APM materialization for shared instructions and Adaptive transitive deps') | Out-Null
    }
    elseif ($copilotDirect.status -ceq 'FAIL' -and $copilotDirect.authorization -ceq 'FAIL') {
        $verdict = 'NO_GO'
        $rationale.Add('Explicit invocation safety failed under direct plugin load') | Out-Null
    }
    else {
        $verdict = 'HOLD'
        $rationale.Add("Copilot direct-load status=$($copilotDirect.status)") | Out-Null
    }
    if (-not $fingerprintMatch) {
        if ($verdict -ceq 'GO') { $verdict = 'HOLD' }
        $rationale.Add('Baseline #106 fingerprint mismatch or missing — semantic parity not claimed') | Out-Null
    }
    if ($codexInfo.status -ceq 'UNCONFIRMED_NO_LOCAL_DIRECT_LOAD_OBSERVED' -or $codexInfo.status -ceq 'UNSUPPORTED_CURRENT_CLIENT' -or $codexInfo.status -ceq 'UNCONFIRMED') {
        $rationale.Add("Codex direct plugin: $($codexInfo.status)") | Out-Null
    }
    else {
        $next.Add('Codex direct-load follow-up if client gains local bundle support') | Out-Null
    }
    $next.Add('Keep APM as multi-target projection + dependency materialization') | Out-Null
    $next.Add('Treat Agent Plugins as portable Skill packaging contract (+ Copilot agents/ extension)') | Out-Null
    $next.Add('No package version bump for PoC-only packaging') | Out-Null

    $comparison = [ordered]@{
        baseline_result                = 'tests/runtime-qualification/results/2026-08-10-copilot-cli.json'
        baseline_canonical_fingerprint = $baselineFp
        current_canonical_fingerprint  = $canonicalFingerprint
        fingerprint_match              = [bool]$fingerprintMatch
        semantic_parity_claimed        = [bool]($fingerprintMatch -and $copilotDirect.status -ceq 'PASS' -and $copilotDirect.standard_slice -ceq 'PASS' -and $copilotDirect.full_coverage -ceq 'PASS' -and $copilotDirect.adaptive_connection -ceq 'PASS')
        install_discovery_method       = [ordered]@{
            baseline = 'apm install -> projections'
            poc      = 'apm pack (synthesized plugin.json) -> copilot plugin install|--plugin-dir; no PC apm install into fixture'
        }
        shared_instruction             = [ordered]@{
            baseline = 'APM materializes .github/instructions'
            poc      = [string]$copilotDirect.shared_instruction
        }
        authorization                  = [ordered]@{
            baseline = 'A-H PASS'
            poc      = [string]$copilotDirect.authorization
        }
        standard_slice                 = [ordered]@{
            baseline = 'STD-001 PASS'
            poc      = [string]$copilotDirect.standard_slice
        }
        full_coverage                  = [ordered]@{
            baseline = 'FULL-001 PASS'
            poc      = [string]$copilotDirect.full_coverage
        }
        adaptive_connection            = [ordered]@{
            baseline = 'PASS'
            poc      = [string]$copilotDirect.adaptive_connection
        }
        adaptive_packaging             = [ordered]@{
            install_lock_attests_skill_high_standard = $adaptivePackaging.install_lock_attests_skill_high_standard
            path_dep_pack_refused                    = $adaptivePackaging.path_dep_pack_refused
            plan_coverage_bundle_includes_adaptive   = $adaptivePackaging.plan_coverage_bundle_includes_adaptive
            adaptive_standalone_pack_ok              = $adaptivePackaging.adaptive_standalone_pack_ok
        }
    }

    $result = [ordered]@{
        schema_version = 1
        issue          = 107
        date           = $runStamp
        spec           = [ordered]@{
            agent_plugins_version = '1.0.0'
            agent_plugins_schema  = $script:AgentPluginsV1SchemaId
        }
        source_run     = [ordered]@{
            candidate_commit                   = $candidateCommit
            canonical_fingerprint              = $canonicalFingerprint
            package_version                    = $packageVersion
            apm_yml_sha256                     = $apmYmlSha
            plugin_manifest_sha256             = $pluginManifestSha
            bundle_lock_sha256                 = $bundleLockSha
            bundle_root_recorded               = $(if ($KeepWorktree) { $BundleRoot } else { '(ephemeral)' })
            source_run_id                      = (Split-Path -Leaf $runRoot)
            adaptive_attestation_lock_sha256   = $adaptiveAttestationLockSha
            evidence_note                      = 'Generated by run-plan-coverage-copilot-plugin-poc.ps1 (includes pack-stage plugin.json synthesis + Adaptive packaging attestation fields).'
        }
        environment    = [ordered]@{
            apm_version         = $apmVersion
            copilot_cli_version = $clientVersion
            platform            = $(if ($PSVersionTable.Platform) { [string]$PSVersionTable.Platform } else { 'win32' })
            model_requested     = $(if ($Model) { $Model } else { $null })
            model_observed      = $modelObservedGlobal
        }
        bundle         = [ordered]@{
            status                        = $bundleStatus
            manifest_conformance          = $bundleStatus
            canonical_skill_match         = ($bundleStatus -ceq 'PASS')
            canonical_agent_match         = ($bundleStatus -ceq 'PASS')
            lock_embedded                 = (Test-Path -LiteralPath (Join-Path $BundleRoot 'apm.lock.yaml'))
            adaptive_in_bundle            = [bool]$adaptivePackaging.plan_coverage_bundle_includes_adaptive
            plugin_json_synthesis         = 'pack-stage-from-apm.yml'
            source_plugin_json_checked_in = $false
        }
        copilot_direct_load = $copilotDirect
        codex_direct_load   = $codexInfo
        boundary_inventory  = @(Get-BoundaryInventory)
        comparison_to_apm   = $comparison
        scenarios           = @($scenarioResults)
        decision            = [ordered]@{
            verdict    = $verdict
            rationale  = @($rationale)
            next_steps = @($next)
        }
    }

    $jsonPath = Join-Path $ResultsDir "$runStamp-copilot-plugin-poc.json"
    $mdPath = Join-Path $ResultsDir "$runStamp-copilot-plugin-poc.md"
    Write-Utf8File $jsonPath (ConvertTo-JsonCompat $result)

    $md = @"
# Plan Coverage Agent Plugins direct-load PoC (#107)

- date: $runStamp
- decision.verdict: $verdict
- package_version: $packageVersion
- canonical_fingerprint: $canonicalFingerprint
- baseline_fingerprint: $baselineFp
- fingerprint_match: $fingerprintMatch
- bundle.status: $bundleStatus
- copilot_direct_load.status: $($copilotDirect.status)
- plugin_discovery: $($copilotDirect.plugin_discovery)
- plugin_install: $($copilotDirect.plugin_install)
- authorization: $($copilotDirect.authorization)
- standard_slice: $($copilotDirect.standard_slice)
- full_coverage: $($copilotDirect.full_coverage)
- adaptive_connection: $($copilotDirect.adaptive_connection)
- codex_direct_load: $($codexInfo.status)
- copilot_cli_version: $clientVersion
- apm_version: $apmVersion
- candidate_commit: $candidateCommit
- temporary_run_root: $runRoot

## Capability gaps

$(($capabilityGaps | ForEach-Object { "- $_" }) -join "`n")

## Scenarios

| id | kind | status | agents_observed | stop_reason |
| --- | --- | --- | --- | --- |
$(($scenarioResults | ForEach-Object { "| $($_.id) | $($_.kind) | $($_.status) | $((@($_.agents_observed) -join ', ')) | $($_.stop_reason) |" }) -join "`n")

## Decision rationale

$(($rationale | ForEach-Object { "- $_" }) -join "`n")

## Next steps

$(($next | ForEach-Object { "- $_" }) -join "`n")

## Notes

- #106 APM baseline evidence was not modified.
- Fixture repos did not receive ``apm install`` of Plan Coverage.
- Shared instruction was not hand-copied into fixtures.
- Agent Plugins portable core is Skill (+ references) + closed ``plugin.json`` (pack-stage synthesis only); agents/ are Copilot plugin extension surfaces.
- Adaptive packaging attestation fields come from ``build-plan-coverage-agent-plugin.ps1`` (install lock + path-dep refusal + standalone pack).
"@
    Write-Utf8File $mdPath ($md.Replace("`r`n", "`n"))
    Write-Host "Wrote $jsonPath"
    Write-Host "Wrote $mdPath"
    Write-Host "decision.verdict=$verdict copilot_direct_load=$($copilotDirect.status)"

    if ($bundleStatus -cne 'PASS') { exit 1 }
    exit 0
}
finally {
    if (-not $KeepWorktree) {
        $resolved = [System.IO.Path]::GetFullPath($runRoot)
        if ($resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('plan-coverage-plugin-poc-', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "Kept worktree: $runRoot"
    }
}
