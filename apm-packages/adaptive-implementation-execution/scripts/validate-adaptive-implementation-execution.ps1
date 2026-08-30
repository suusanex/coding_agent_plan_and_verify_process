[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string] $Message) {
    $failures.Add($Message)
}

function Get-RepoPath([string] $RelativePath) {
    Join-Path $repoRoot $RelativePath
}

function Assert-FileExists([string] $RelativePath) {
    if (-not (Test-Path -LiteralPath (Get-RepoPath $RelativePath) -PathType Leaf)) {
        Add-Failure "Missing file: $RelativePath"
    }
}

function Assert-FileNotExists([string] $RelativePath) {
    if (Test-Path -LiteralPath (Get-RepoPath $RelativePath)) {
        Add-Failure "Obsolete file must not exist: $RelativePath"
    }
}

function Assert-Contains([string] $RelativePath, [string] $Pattern, [string] $Description) {
    $path = Get-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }
    if ((Get-Content -Raw -LiteralPath $path) -notmatch $Pattern) {
        Add-Failure "$RelativePath does not contain $Description"
    }
}

function Assert-NotContains([string] $RelativePath, [string] $Pattern, [string] $Description) {
    $path = Get-RepoPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }
    if ((Get-Content -Raw -LiteralPath $path) -match $Pattern) {
        Add-Failure "$RelativePath contains forbidden $Description"
    }
}

function Get-FrontmatterValue([string] $RelativePath, [string] $Key) {
    $match = Select-String -LiteralPath (Get-RepoPath $RelativePath) -Pattern ("^" + [regex]::Escape($Key) + ':\s*(.+?)\s*$') | Select-Object -First 1
    if ($null -eq $match) { return $null }
    $match.Matches[0].Groups[1].Value
}

$decisionOwner = 'apm-packages/adaptive-implementation-execution/.apm/agents/decision-surface-implementation-owner.agent.md'
$residualOwner = 'apm-packages/adaptive-implementation-execution/.apm/agents/bounded-residual-implementation-owner.agent.md'
$skill = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md'
$handoff = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md'
$manifest = 'apm-packages/adaptive-implementation-execution/apm.yml'
$overlay = 'apm-packages/adaptive-implementation-execution/codex-profile-overlays.json'
$routingFixture = 'apm-packages/adaptive-implementation-execution/tests/routing-scenarios.json'
$routingValidator = 'apm-packages/adaptive-implementation-execution/tests/validate-routing-scenarios.ps1'

$requiredFiles = @(
    $decisionOwner,
    $residualOwner,
    $skill,
    $handoff,
    $manifest,
    $overlay,
    $routingFixture,
    $routingValidator,
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/intent.md',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/adaptive-implementation-execution/docs/install-guide.md',
    'apm-packages/adaptive-implementation-execution/docs/usage-guide.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/copilot-manual-smoke.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/copilot-cli-real-model-e2e-2026-07-31.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/copilot-cli-real-model-e2e-2026-08-09.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/copilot-cli-real-model-e2e-2026-08-30.md',
    'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-apm-smoke.ps1',
    'apm-packages/adaptive-implementation-execution/tests/agent-plugin/contract.json',
    'apm-packages/adaptive-implementation-execution/tests/agent-plugin/qualification.json'
)
foreach ($file in $requiredFiles) { Assert-FileExists $file }

foreach ($obsolete in @(
    'apm-packages/adaptive-implementation-execution/.apm/agents/high-implementation-starter.agent.md',
    'apm-packages/adaptive-implementation-execution/.apm/agents/standard-implementation-completer.agent.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/legacy-adaptive-handoff.md'
)) {
    Assert-FileNotExists $obsolete
}

Assert-Contains $manifest '(?m)^version:\s*0\.6\.0\s*$' 'package version 0.6.0'
Assert-Contains $manifest 'remaining decision surfaces.*bounded residual completion' 'decision-surface package description'
Assert-NotContains $manifest 'decision closure|standard-model implementation ownership' 'removed fixed ownership description'

Assert-Contains $skill '## Semantic roles' 'semantic role definition'
Assert-Contains $skill 'Decision-Surface Implementation Owner.*implementation feedback loop' 'decision-surface implementation ownership'
Assert-Contains $skill 'Bounded-Residual Implementation Owner.*bounded residual work' 'bounded residual ownership'
Assert-Contains $skill 'runtime topology.*independent|runtime topology.*独立' 'topology and semantics separation'
Assert-Contains $skill 'READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION' 'bounded residual transfer verdict'
Assert-Contains $skill 'CONTINUE_DECISION_SURFACE_IMPLEMENTATION' 'decision-surface continuation verdict'
Assert-Contains $skill 'NEEDS_DECISION_SURFACE_REENTRY' 'decision-surface re-entry verdict'
Assert-Contains $skill 'IMPLEMENTATION_COMPLETED' 'common completion verdict'
Assert-Contains $skill 'code editを避けることも、一定量のeditを行うことも目的にしません' 'no code quota rule'
Assert-Contains $skill '最初のownerによる完了は例外ではなく' 'natural first-owner completion'
Assert-Contains $skill 'top-level parent自身へ`Decision-Surface Implementation Owner`を割り当て.*同じruntime instanceが兼ねる構成は許容します' 'parent topology can host the decision-surface semantic owner'
Assert-Contains $skill 'parentというruntime位置だけを理由にimplementation ownershipを付与または禁止してはいけません' 'parent topology does not determine semantic ownership'
Assert-Contains $skill 'reentry_progress_evidence' 're-entry progress evidence'
Assert-Contains $skill 'same_unresolved_cause_rehanded_off: false' 're-entry unresolved-cause guard'
Assert-Contains $skill '初回transferは`reentry_count: 0`' 'initial re-entry history'
Assert-Contains $skill 'reentry_count.*直前に受理したBounded Residual Implementation Handoffの値に1を加えた値' 're-entry count provenance'
Assert-Contains $skill 'triggerまたはcountが不正ならfail closedで停止し、次ownerを起動しません' 'invalid re-entry provenance stops routing'
Assert-NotContains $skill 'transfer_surface_reduced|厳密に縮小' 'removed strict-reduction retransfer gate'
Assert-Contains $skill '旧0\.5 handoff.*互換normalizationせず' 'breaking old handoff rejection'
Assert-NotContains $skill 'READY_FOR_STANDARD_COMPLETION|CONTINUE_HIGH_IMPLEMENTATION|COMPLETED_BY_HIGH_MODEL|NEEDS_HIGH_MODEL_REENTRY|Direct completion reason|HIGH_MODEL code changes|Legacy Adaptive handoff normalization' 'removed 0.5 contract vocabulary'

Assert-Contains $decisionOwner '(?m)^name:\s*decision-surface-implementation-owner\s*$' 'decision-surface agent name'
Assert-Contains $decisionOwner 'agent:\s*bounded-residual-implementation-owner' 'bounded residual handoff target'
Assert-Contains $decisionOwner 'implement enough production code / tests' 'implementation feedback loop'
Assert-Contains $decisionOwner 'zero-code transfer.*default、目標、quotaではありません|code editなし.*default、目標、quotaではありません' 'zero-code non-default rule'
Assert-Contains $decisionOwner 'Decision surface assessment' 'decision surface assessment'
Assert-Contains $decisionOwner 'Ownership transfer basis: `bounded-residual-work-only`' 'bounded residual transfer basis'
Assert-Contains $decisionOwner 'reentry_progress_evidence' 'decision-surface re-entry progress evidence'
Assert-Contains $decisionOwner 'same_unresolved_cause_rehanded_off: false' 'decision-surface unresolved-cause guard'
Assert-Contains $decisionOwner 'transfer例外理由は要求しません' 'normal first-owner completion'
Assert-Contains $decisionOwner 'Implementation Self-Map Delta' 'Plan Coverage traceability'
Assert-NotContains $decisionOwner 'high-implementation-starter|standard-implementation-completer|READY_FOR_STANDARD_COMPLETION|COMPLETED_BY_HIGH_MODEL|Direct completion reason|HIGH_MODEL code changes|transfer_surface_reduced|厳密に縮小' 'removed decision-closer vocabulary'

Assert-Contains $residualOwner '(?m)^name:\s*bounded-residual-implementation-owner\s*$' 'bounded residual agent name'
Assert-Contains $residualOwner 'agent:\s*decision-surface-implementation-owner' 'decision-surface re-entry target'
Assert-Contains $residualOwner '作業種別による固定分業ではありません' 'no work-type ownership rule'
Assert-Contains $residualOwner 'NEEDS_DECISION_SURFACE_REENTRY' 'new decision surface re-entry'
Assert-Contains $residualOwner 'same_unresolved_cause_rehanded_off: false' 'bounded residual unresolved-cause guard'
Assert-Contains $residualOwner 'edit type.*ではre-entryしません|edit、新規file.*だけではre-entryしません' 'edit-type-only rejection'
Assert-Contains $residualOwner 'UNPERSISTED_PARENT_PAYLOAD' 'Plan Coverage parent persistence adapter'
Assert-NotContains $residualOwner 'high-implementation-starter|standard-implementation-completer|NEEDS_HIGH_MODEL_REENTRY|通常のimplementation owner' 'removed standard-owner vocabulary'

Assert-Contains $handoff '(?m)^# Bounded Residual Implementation Handoff\s*$' 'new handoff title'
Assert-Contains $handoff 'Ownership transfer basis: bounded-residual-work-only' 'handoff transfer basis'
Assert-Contains $handoff '## Decision surface assessment' 'handoff assessment'
Assert-Contains $handoff '## Implementation and verification evidence' 'handoff implementation evidence'
Assert-Contains $handoff 'Resolved / N/A' 'resolved status vocabulary'
Assert-Contains $handoff 'Decision-Surface Implementation Owner' 'semantic decision origin'
Assert-Contains $handoff 'reentry_progress_evidence' 'handoff re-entry progress evidence'
Assert-Contains $handoff 'same_unresolved_cause_rehanded_off: N/A' 'structured re-entry progress evidence'
Assert-NotContains $handoff 'Decision closure|HIGH_MODEL code changes|non-local-decisions-closed|Legacy Adaptive handoff normalization|transfer_surface_reduced|厳密に縮小' 'removed handoff vocabulary'

Assert-Contains $overlay '"agent": "decision-surface-implementation-owner"' 'decision-surface Codex profile'
Assert-Contains $overlay '"agent": "bounded-residual-implementation-owner"' 'bounded residual Codex profile'
$overlayDocument = Get-Content -Raw -LiteralPath (Get-RepoPath $overlay) | ConvertFrom-Json -Depth 10
if (@($overlayDocument.profiles).Count -ne 2) {
    Add-Failure 'Adaptive Codex overlay must define exactly two semantic owners.'
}
elseif ($overlayDocument.profiles[0].model -ceq $overlayDocument.profiles[1].model) {
    Add-Failure 'Adaptive semantic owners must use distinct default model mappings.'
}

if ((Get-FrontmatterValue $decisionOwner 'model') -cne 'GPT-5.6 Terra (copilot)') {
    Add-Failure 'Decision-surface Copilot model mapping is invalid.'
}
if ((Get-FrontmatterValue $residualOwner 'model') -cne 'GPT-5.6 Luna (copilot)') {
    Add-Failure 'Bounded-residual Copilot model mapping is invalid.'
}

Assert-Contains $routingFixture '"schema_version": 4' 'routing schema v4'
Assert-Contains $routingFixture 'implementation-evidence-before-transfer' 'implementation feedback scenario'
Assert-Contains $routingFixture 'inspection-only-transfer-is-allowed-not-required' 'inspection-only scenario'
Assert-Contains $routingFixture 'decision-surface-owner-completes-naturally' 'natural completion scenario'
Assert-Contains $routingFixture 'edit-type-only-reentry-is-rejected' 'edit-type-only negative scenario'
Assert-NotContains $routingFixture 'HIGH_MODEL code changes|Direct completion reason|COMPLETED_BY_HIGH_MODEL' 'removed routing metrics'

$maxWindowsPackagePathLength = 110
$packageFiles = @(& git -C $repoRoot ls-files --cached --others --exclude-standard -- 'apm-packages/adaptive-implementation-execution')
if ($LASTEXITCODE -ne 0) {
    Add-Failure 'Cannot enumerate Adaptive package payload.'
}
foreach ($relativePath in $packageFiles) {
    if ($relativePath.Length -gt $maxWindowsPackagePathLength) {
        Add-Failure "Package path exceeds Windows path budget: $relativePath"
    }
}

$routingOutput = & pwsh -NoProfile -File (Get-RepoPath $routingValidator) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Add-Failure "Routing scenario validator failed: $routingOutput"
}

if ($failures.Count -gt 0) {
    Write-Error ("Adaptive Implementation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

$global:LASTEXITCODE = 0
Write-Output 'Adaptive Implementation validation: PASS'
