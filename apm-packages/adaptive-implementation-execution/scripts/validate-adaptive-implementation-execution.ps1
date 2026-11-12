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

Assert-Contains $manifest '(?m)^version:\s*0\.7\.0\s*$' 'package version 0.7.0'
Assert-Contains $skill 'AWAITING_STRUCTURE_REVIEW.*persist, present, END TURN' 'mandatory turn stop'
Assert-Contains $skill '承認とhandoff readinessを別々に検証' 'separate approval and readiness'
Assert-Contains $skill 'Deferred to child' 'deferred child design'
Assert-Contains $skill 'same_unresolved_cause_rehanded_off: false' 'reentry resolution'
Assert-Contains $skill 'acceptanceとWork Package mappingが双方向に一致する' 'acceptance mapping'
Assert-Contains $skill 'Allowed edit surfaceが全Authorized surfaceを包含する' 'edit authorization'
Assert-Contains $skill 'Finalization status: Validated' 'Design Pair finalization'
Assert-Contains $skill 'actual diffの実装後照合結果' 'child comparison reconciliation'
Assert-NotContains $skill '最初のownerによる完了は例外ではなく|implementation feedback loop|CONTINUE_DECISION_SURFACE_IMPLEMENTATION|bounded-residual-work-only' 'old ownership rules'
Assert-NotContains $decisionOwner '(?m)^\s*model:|^handoffs:' 'parent model or automatic handoff'
Assert-Contains $decisionOwner '現在のトップレベル親' 'parent ownership'
Assert-Contains $decisionOwner 'そのターンを終了' 'real turn boundary'
Assert-Contains $decisionOwner '日本語XMLコメント.*入力.*保証・検査' 'boundary contracts'
Assert-Contains $decisionOwner 'NotImplementedException' 'explicit unfinished leaves'
Assert-Contains $decisionOwner '変更対象production projectと契約変更の影響を受けるproduction project' 'production build scope'
Assert-Contains $decisionOwner '同じデータの更新箇所.*同じinterfaceの実装.*兄弟機能' 'existing-path discovery'
Assert-Contains $decisionOwner '実際に読んだfile / symbolと呼び出し関係' 'reference evidence'
Assert-Contains $decisionOwner 'API呼び出し / 拡張点利用 / 構造追従 / 別方式' 'reuse choices'
Assert-Contains $decisionOwner 'test architecture / seam / harness.*Deferred to child' 'child test design freedom'
Assert-Contains $decisionOwner 'Implementation Self-Map Delta' 'traceability'
Assert-Contains $decisionOwner '親単独のIMPLEMENTATION_COMPLETED経路はありません' 'no parent completion'
Assert-Contains $decisionOwner 'Target Map IDは一意.*相互排他かつ完全被覆' 'Design Pair set integrity'
Assert-Contains $decisionOwner '旧confirmationを流用できません' 'stale Design Pair rejection'
Assert-Contains $decisionOwner 'waiting state.*空集合PASS.*架空・重複・未分類ID.*BLOCKED' 'invalid Design Pair rejection'
Assert-Contains $residualOwner '(?m)^model:\s*GPT-6 Luna \(copilot\)' 'child model'
Assert-NotContains $residualOwner '(?m)^handoffs:|^\s+agent:\s*decision-surface' 'separate upper reentry'
Assert-Contains $residualOwner 'Structure reviewがAPPROVED' 'child checks approval'
Assert-Contains $residualOwner 'UNPERSISTED_PARENT_PAYLOAD' 'Living Record adapter'
Assert-Contains $residualOwner 'NEEDS_DECISION_SURFACE_REENTRY' 'structural return'
Assert-Contains $residualOwner 'actual diff' 'post-implementation comparison'
Assert-Contains $handoff 'Schema: adaptive-structure-0.7' 'new state version'
Assert-Contains $handoff 'Ownership transfer basis: human-approved-structure' 'new transfer basis'
Assert-Contains $handoff 'User response quote: Pending' 'actual response evidence'
Assert-Contains $handoff 'Approved structure version: Pending' 'approval binding'
Assert-Contains $handoff 'untrackedを含む対象fileごとのSHA256' 'snapshot includes new files'
Assert-Contains $handoff '元snapshotと承認履歴を上書きせず' 'review history'
Assert-Contains $handoff 'Deferred to child' 'readiness excludes details'
Assert-NotContains $handoff '## Decision surface assessment|bounded-residual-work-only' 'old all-resolved gate'
$overlayDocument = Get-Content -Raw -LiteralPath (Get-RepoPath $overlay) | ConvertFrom-Json
if (@($overlayDocument.profiles).Count -ne 1 -or $overlayDocument.profiles[0].agent -cne 'bounded-residual-implementation-owner') {
    Add-Failure 'Only the child may have a Codex model overlay.'
}
Assert-Contains $routingFixture '"schema_version": 5' 'routing schema v5'
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
