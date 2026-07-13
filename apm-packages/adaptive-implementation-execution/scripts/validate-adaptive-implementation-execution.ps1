[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Assert-FileExists {
    param([string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing file: $RelativePath"
    }
}

function Assert-Contains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }

    $content = Get-Content -Raw -LiteralPath $path
    if ($content -notmatch $Pattern) {
        Add-Failure "$RelativePath does not contain $Description"
    }
}

function Assert-NotContains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }

    $content = Get-Content -Raw -LiteralPath $path
    if ($content -match $Pattern) {
        Add-Failure "$RelativePath contains forbidden $Description"
    }
}

function Get-TomlString {
    param(
        [string]$RelativePath,
        [string]$Key
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    $match = Select-String -LiteralPath $path -Pattern ("^\s*" + [regex]::Escape($Key) + '\s*=\s*"([^"]+)"\s*$') | Select-Object -First 1
    if ($null -eq $match) {
        return $null
    }

    return $match.Matches[0].Groups[1].Value
}

$requiredFiles = @(
    '.github/agents/high-implementation-starter.agent.md',
    '.github/agents/standard-implementation-completer.agent.md',
    '.github/workflows/validate-adaptive-implementation-execution.yml',
    'apm-packages/adaptive-implementation-execution/apm.yml',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/references/implementation-intent.md',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/references/implementation-completion-handoff.md',
    'apm-packages/adaptive-implementation-execution/profiles/adaptive-implementation/AGENTS.md',
    'apm-packages/adaptive-implementation-execution/profiles/adaptive-implementation/agents/high-implementation-starter.toml',
    'apm-packages/adaptive-implementation-execution/profiles/adaptive-implementation/agents/standard-implementation-completer.toml',
    'apm-packages/adaptive-implementation-execution/docs/install-guide.md',
    'apm-packages/adaptive-implementation-execution/docs/usage-guide.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md',
    'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs',
    'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1'
)

foreach ($file in $requiredFiles) {
    Assert-FileExists $file
}

$manifest = 'apm-packages/adaptive-implementation-execution/apm.yml'
Assert-Contains $manifest '(?m)^name:\s*adaptive-implementation-execution\s*$' 'package name'
Assert-Contains $manifest '(?m)^\s*-\s+codex\s*$' 'codex target'
Assert-Contains $manifest '(?m)^\s*-\s+agent-skills\s*$' 'agent-skills target'
Assert-NotContains $manifest '(?m)^\s*-\s+copilot\s*$' 'unverified Copilot target'
Assert-NotContains $manifest 'token-aware|codex-first|plan-coverage' 'Plan Coverage or Codex-first dependency'
Assert-NotContains $manifest 'path:\s+.*(?:implementation-intent|implementation-completion-handoff)\.md' 'standalone template dependency'

$manifestPath = Join-Path $repoRoot $manifest
if (Test-Path -LiteralPath $manifestPath) {
    $dependencyPaths = Select-String -LiteralPath $manifestPath -Pattern '^\s*path:\s*(.+?)\s*$' | ForEach-Object {
        $_.Matches[0].Groups[1].Value.Trim()
    }
    foreach ($dependencyPath in $dependencyPaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $dependencyPath))) {
            Add-Failure "Manifest dependency does not exist: $dependencyPath"
        }
    }
}

$skill = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md'
Assert-Contains $skill 'high-implementation-starter' 'HIGH_MODEL start route'
Assert-Contains $skill 'standard-implementation-completer' 'STANDARD_MODEL completion route'
Assert-Contains $skill 'READY_FOR_STANDARD_COMPLETION' 'standard delegation gate'
Assert-Contains $skill 'NEEDS_HIGH_MODEL_REENTRY' 'HIGH_MODEL re-entry route'
Assert-Contains $skill 'write-heavy agent を並列に起動しません' 'write-heavy serial execution rule'
Assert-Contains $skill 'Plan Coverage artifacts が存在しないことは blocker ではありません' 'Plan Coverage independence'
Assert-Contains $skill 'Final review status' 'final review boundary'
Assert-Contains $skill 'Validation expectation: inferred from repository' 'validation inference reporting'
Assert-Contains $skill 'acceptance status table' 'acceptance evidence output'
Assert-Contains $skill 'delegation_surface_reduced' 'bounded re-delegation evidence'
Assert-Contains $skill 'N/A.*理由' 'evidence-backed applicability N/A'
Assert-Contains $skill 'incoming value \+ 1' 're-entry count increment rule'
Assert-Contains $skill '双方向に一致' 'bidirectional acceptance mapping gate'
Assert-Contains $skill 'existing code から scope を狭めない' 'safe non-goal inference rule'

$highAgent = '.github/agents/high-implementation-starter.agent.md'
Assert-Contains $highAgent 'edit production code and tests' 'real implementation loop'
Assert-Contains $highAgent 'CONTINUE_HIGH_IMPLEMENTATION' 'continue-high verdict'
Assert-Contains $highAgent 'COMPLETED_BY_HIGH_MODEL' 'high completion verdict'
Assert-Contains $highAgent 'Allowed edit surface' 'handoff allowed surface'
Assert-Contains $highAgent 'acceptance status table' 'high-model acceptance evidence output'
Assert-Contains $highAgent '一度 re-entry した後' 'high-model re-entry ownership'
Assert-Contains $highAgent 'すべての `Incomplete` acceptance item' 'high-model incomplete acceptance mapping gate'
Assert-Contains $highAgent 're-entry handoff の `reentry_count` を維持' 'high-model re-entry count propagation'

$standardAgent = '.github/agents/standard-implementation-completer.agent.md'
Assert-Contains $standardAgent 'NEEDS_HIGH_MODEL_REENTRY' 're-entry verdict'
Assert-Contains $standardAgent 'Locked decisions' 'locked decision boundary'
Assert-Contains $standardAgent 'Allowed edit surface' 'allowed edit boundary'
Assert-Contains $standardAgent 'Final code review performed|final review status' 'review boundary'
Assert-Contains $standardAgent 'acceptance status table' 'standard-model acceptance evidence output'
Assert-Contains $standardAgent '一度 re-entry した後' 'standard-model re-entry ownership'
Assert-Contains $standardAgent 'incoming Implementation Completion Handoff の値に1を加える' 'standard-model re-entry count increment'
Assert-Contains $standardAgent '双方向に一致' 'standard-model acceptance mapping authorization'

$handoff = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/references/implementation-completion-handoff.md'
foreach ($field in @(
    'Verdict',
    'Handoff persistence',
    'Plan reference',
    'Validation performed',
    'Acceptance status',
    'Applicability evidence',
    'Implemented',
    'Locked decisions',
    'Remaining work',
    'Allowed edit surface',
    'Validation commands',
    'High-model re-entry triggers',
    'reentry_count',
    'previous_reentry_trigger',
    'delegation_surface_reduced',
    'Known assumptions / unresolved observations'
)) {
    Assert-Contains $handoff ([regex]::Escape($field)) "handoff field $field"
}
Assert-Contains $handoff 'Remaining work mapping \(Work ID\)' 'acceptance-to-work mapping column'
Assert-Contains $handoff 'Work ID.*Acceptance item\(s\)' 'work-to-acceptance mapping columns'
Assert-Contains $handoff '`Blocked` を許可しない' 'blocked acceptance rejection'

$highToml = 'apm-packages/adaptive-implementation-execution/profiles/adaptive-implementation/agents/high-implementation-starter.toml'
$standardToml = 'apm-packages/adaptive-implementation-execution/profiles/adaptive-implementation/agents/standard-implementation-completer.toml'
foreach ($toml in @($highToml, $standardToml)) {
    Assert-Contains $toml '(?m)^model\s*=\s*"[^"]+"\s*$' 'top-level model'
    Assert-Contains $toml '(?m)^model_reasoning_effort\s*=\s*"[^"]+"\s*$' 'top-level reasoning effort'
    Assert-Contains $toml '(?m)^sandbox_mode\s*=\s*"workspace-write"\s*$' 'workspace-write sandbox'
}

$highAgentName = Get-TomlString $highToml 'name'
$standardAgentName = Get-TomlString $standardToml 'name'
$highModel = Get-TomlString $highToml 'model'
$standardModel = Get-TomlString $standardToml 'model'
if ($highAgentName -ne 'high-implementation-starter') {
    Add-Failure "$highToml has an unexpected agent name: $highAgentName"
}
if ($standardAgentName -ne 'standard-implementation-completer') {
    Add-Failure "$standardToml has an unexpected agent name: $standardAgentName"
}
if ($highAgentName -eq $standardAgentName) {
    Add-Failure 'HIGH_MODEL and STANDARD_MODEL must reference different custom agents'
}
if ($highModel -eq $standardModel) {
    Add-Failure 'HIGH_MODEL and STANDARD_MODEL must use distinct model mappings'
}

$profile = 'apm-packages/adaptive-implementation-execution/profiles/adaptive-implementation/AGENTS.md'
Assert-Contains $profile 'Plan Coverage artifacts は必須ではない' 'ordinary Plan activation'
Assert-Contains $profile 'parent / router は production code と tests を直接編集しない' 'parent edit prohibition'
Assert-Contains $profile 'write-heavy work を並列実行しない' 'serial agent rule'
Assert-Contains $profile 'final code review' 'final review boundary'
Assert-Contains $profile 'installer の適用は通常の必須手順' 'mandatory profile installer'

$validation = 'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md'
foreach ($id in 1..8) {
    Assert-Contains $validation ("VAL-00$id") "validation scenario VAL-00$id"
}

$installer = 'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs'
Assert-Contains $installer '(?m)^#:property TargetFramework=net10\.0\s*$' 'File-based app target framework'
Assert-Contains $installer '--dry-run' 'dry-run option'
Assert-Contains $installer '--check' 'check option'
Assert-Contains $installer '--remove' 'remove option'
Assert-Contains $installer 'adaptive-implementation-execution:start' 'managed AGENTS marker'
Assert-Contains $installer 'ValidateProfileConfiguration' 'profile configuration validation'
Assert-Contains $installer 'must use distinct model mappings' 'distinct model mapping check'
Assert-Contains $installer 'must reference different custom agents' 'distinct custom agent check'
Assert-Contains $installer 'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local\.cs' 'repo-root usage path'

Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' '通常の必須手順' 'mandatory installer quick start'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' '--check.*次をすべて検証' 'documented installer checks'

$workflow = '.github/workflows/validate-adaptive-implementation-execution.yml'
Assert-Contains $workflow 'validate-adaptive-implementation-execution\.ps1' 'Adaptive Implementation CI validator invocation'

Assert-Contains 'README.md' 'apm-packages/adaptive-implementation-execution' 'root package link'

if ($failures.Count -gt 0) {
    Write-Error ("Adaptive Implementation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'Adaptive Implementation validation: PASS'
