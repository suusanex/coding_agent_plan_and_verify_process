[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Read-Text([string]$RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing documentation file: $RelativePath"
        return ''
    }

    return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Assert-Contains([string]$Text, [string]$Expected, [string]$FailureMessage) {
    if (-not $Text.Contains($Expected, [StringComparison]::Ordinal)) {
        Add-Failure $FailureMessage
    }
}

$documentationFiles = @(
    'README.md',
    'docs/installation-and-maintenance.md',
    'apps/CodexLocalInbox/README.md',
    'scripts/codex-notification-runtime/README.md',
    'apm-packages/completion-notification-decorator/.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/README.md',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/completion-notification-decorator/README.md',
    'apm-packages/design-pair-implementation-execution/README.md',
    'apm-packages/goal-context-authoring/README.md',
    'apm-packages/plan-coverage-residual-flow/README.md',
    'apm-packages/pr-review-remediation/README.md'
)

$rootReadme = Read-Text 'README.md'
foreach ($heading in @(
    '## このrepositoryでできること',
    '## Quickstart: 目的から選ぶ',
    '## Processの関係',
    '## 通常使うprocessを一通り入れる',
    '## 開発支援ツール',
    '## 詳細ドキュメントとmaintenance'
)) {
    Assert-Contains $rootReadme $heading "Root README is missing Quickstart/navigation heading: $heading"
}

foreach ($purposeHeading in @(
    '### 実装を改善したい',
    '### 実装前に内部設計も対話して決めたい',
    '### PRレビューと修正を改善したい',
    '### Planから実装・検証・残件判断まで抜けを防ぎたい'
)) {
    Assert-Contains $rootReadme $purposeHeading "Root README is missing purpose-oriented Quickstart: $purposeHeading"
}

foreach ($target in @(
    'apm-packages/plan-coverage-residual-flow/README.md',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/design-pair-implementation-execution/README.md',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/goal-context-authoring/README.md',
    'apm-packages/completion-notification-decorator/README.md',
    'scripts/codex-notification-runtime/README.md',
    'apps/CodexLocalInbox/README.md',
    'docs/installation-and-maintenance.md'
)) {
    Assert-Contains $rootReadme "($target)" "Root README is missing navigation target: $target"
}

foreach ($role in @(
    'Adaptive Implementation',
    'Design Pair',
    'PR Review Remediation',
    'Plan Coverage Residual Flow',
    'Goal Context Authoring',
    'Completion Notification Decorator',
    'Codex Notification Runtime',
    'Codex Local Inbox'
)) {
    Assert-Contains $rootReadme $role "Root README is missing process/tool role: $role"
}

foreach ($command in @(
    'apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills',
    'apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target copilot,codex,agent-skills',
    'apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills',
    'sync-pr-review-remediation-local.cs',
    'provision-work-repo-agents.cs -- C:\path\to\target --dry-run',
    'apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target codex,agent-skills',
    'apm install "$sourceRoot\apm-packages\completion-notification-decorator" --target codex,agent-skills',
    'dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --dry-run',
    'dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- install',
    'dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --check',
    'dotnet run --project .\apps\CodexLocalInbox\CodexLocalInbox.csproj'
)) {
    Assert-Contains $rootReadme $command "Root README is missing required Quickstart command: $command"
}

foreach ($scopePhrase in @(
    '利用するwork repositoryごと',
    'PCのuser-levelでOS userごとに一度setup',
    'local Windows application',
    'generic `TURN_ENDED`'
)) {
    Assert-Contains $rootReadme $scopePhrase "Root README is missing installation scope or notification boundary: $scopePhrase"
}

if ($rootReadme.Contains('machine-level', [StringComparison]::OrdinalIgnoreCase)) {
    Add-Failure 'Root README must not describe the current-user notification runtime as machine-level.'
}

$allInHeading = '## 通常使うprocessを一通り入れる'
$supportHeading = '## 開発支援ツール'
$allInStart = $rootReadme.IndexOf($allInHeading, [StringComparison]::Ordinal)
$allInEnd = $rootReadme.IndexOf($supportHeading, [StringComparison]::Ordinal)
if ($allInStart -ge 0 -and $allInEnd -gt $allInStart) {
    $allInQuickstart = $rootReadme.Substring($allInStart, $allInEnd - $allInStart)
    $designPairInstall = 'apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target copilot,codex,agent-skills'
    $adaptiveApply = 'install-adaptive-implementation-local.cs" -- .'
    $adaptiveCheck = 'install-adaptive-implementation-local.cs" -- . --check'
    $designPairIndex = $allInQuickstart.IndexOf($designPairInstall, [StringComparison]::Ordinal)
    $adaptiveApplyIndex = $allInQuickstart.IndexOf($adaptiveApply, [StringComparison]::Ordinal)
    $adaptiveCheckIndex = $allInQuickstart.IndexOf($adaptiveCheck, [StringComparison]::Ordinal)
    if ($designPairIndex -lt 0 -or $adaptiveApplyIndex -le $designPairIndex -or $adaptiveCheckIndex -le $adaptiveApplyIndex) {
        Add-Failure 'The all-in Quickstart must complete and check Adaptive profiles after the Design Pair install.'
    }
}

$rootLines = ($rootReadme -split "`n").Count
if ($rootLines -gt 220) {
    Add-Failure "Root README must remain a concise Quickstart/navigation page of at most 220 lines; actual: $rootLines."
}
if ($rootReadme.Length -gt 24000) {
    Add-Failure "Root README must not duplicate package reference detail beyond 24000 characters; actual: $($rootReadme.Length)."
}
if (-not ($rootReadme -match '(?im)^[ \t]*```[ \t]*powershell[ \t]*$')) {
    Add-Failure 'Root README must contain executable PowerShell Quickstart blocks.'
}

$planCoverageReadme = Read-Text 'apm-packages/plan-coverage-residual-flow/README.md'
Assert-Contains $planCoverageReadme '## Install' 'Plan Coverage README is missing an Install section.'
Assert-Contains $planCoverageReadme '[`scripts/provision-work-repo-agents.cs`](../../scripts/provision-work-repo-agents.cs)' 'Plan Coverage README must link directly to the provisioning helper.'
foreach ($mode in @('--dry-run', '--check')) {
    Assert-Contains $planCoverageReadme "provision-work-repo-agents.cs -- C:\path\to\target $mode" "Plan Coverage README is missing provisioning mode: $mode"
}
if (-not ($planCoverageReadme -match '(?m)^dotnet run --file \.\\scripts\\provision-work-repo-agents\.cs -- C:\\path\\to\\target$')) {
    Add-Failure 'Plan Coverage README is missing the provisioning apply command.'
}
Assert-Contains $planCoverageReadme 'Adaptive Implementation Skill' 'Plan Coverage README must explain its Adaptive Implementation dependency.'
Assert-Contains $planCoverageReadme '[Design Pair Implementation Execution](../design-pair-implementation-execution/README.md)' 'Plan Coverage README must explain the optional Design Pair add-on.'

$linkPattern = [regex]'(?<!!)\[[^\]]+\]\((?<target>[^)]+)\)'
foreach ($relativePath in $documentationFiles) {
    $text = Read-Text $relativePath
    if ([string]::IsNullOrEmpty($text)) {
        continue
    }

    $sourceDirectory = Split-Path -Parent (Join-Path $repoRoot $relativePath)
    foreach ($match in $linkPattern.Matches($text)) {
        $target = $match.Groups['target'].Value.Trim()
        if ($target.StartsWith('<') -and $target.EndsWith('>')) {
            $target = $target.Substring(1, $target.Length - 2)
        }

        if ($target -match '^(?:https?://|mailto:|#)') {
            continue
        }

        $pathPart = ($target -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($pathPart)) {
            continue
        }

        $decodedPath = [Uri]::UnescapeDataString($pathPart).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $resolvedTarget = [IO.Path]::GetFullPath((Join-Path $sourceDirectory $decodedPath))
        if (-not $resolvedTarget.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            Add-Failure "$relativePath links outside the repository: $target"
            continue
        }

        if (-not (Test-Path -LiteralPath $resolvedTarget)) {
            Add-Failure "$relativePath has a broken relative link: $target"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("README navigation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Host 'README navigation validation: PASS'
