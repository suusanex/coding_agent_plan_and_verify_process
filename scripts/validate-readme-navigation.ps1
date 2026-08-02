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

$documentationFiles = @(
    'README.md',
    'docs/installation-and-maintenance.md',
    'apps/CodexLocalInbox/README.md',
    'scripts/codex-notification-runtime/README.md',
    'apm-packages/completion-notification-decorator/.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/README.md',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/codex-first-ai-development-process/README.md',
    'apm-packages/completion-notification-decorator/README.md',
    'apm-packages/copilot-fallback-ai-development-process/README.md',
    'apm-packages/design-pair-implementation-execution/README.md',
    'apm-packages/full-autonomous-plan-first-flow/README.md',
    'apm-packages/goal-context-authoring/README.md',
    'apm-packages/plan-coverage-residual-flow/README.md',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/token-aware-full-coverage-3layer/README.md'
)

$rootReadme = Read-Text 'README.md'
foreach ($heading in @(
    '## 開発プロセスを選ぶ',
    '## 補助機能を使う',
    '## ローカルツールを使う',
    '## 導入・保守を行う'
)) {
    if (-not $rootReadme.Contains($heading, [StringComparison]::Ordinal)) {
        Add-Failure "Root README is missing navigation heading: $heading"
    }
}

foreach ($target in @(
    'apm-packages/plan-coverage-residual-flow/README.md',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/design-pair-implementation-execution/README.md',
    'apm-packages/codex-first-ai-development-process/README.md',
    'apm-packages/copilot-fallback-ai-development-process/README.md',
    'apm-packages/full-autonomous-plan-first-flow/README.md',
    'apm-packages/token-aware-full-coverage-3layer/README.md',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/goal-context-authoring/README.md',
    'apm-packages/completion-notification-decorator/README.md',
    'scripts/codex-notification-runtime/README.md',
    'apps/CodexLocalInbox/README.md',
    'docs/installation-and-maintenance.md'
)) {
    if (-not $rootReadme.Contains("($target)", [StringComparison]::Ordinal)) {
        Add-Failure "Root README is missing navigation target: $target"
    }
}

foreach ($classification in @('APM process', 'helper APM package', 'non-APM runtime tool', 'non-APM WinUI application')) {
    if (-not $rootReadme.Contains($classification, [StringComparison]::Ordinal)) {
        Add-Failure "Root README is missing classification: $classification"
    }
}

if (($rootReadme -split "`n").Count -gt 120) {
    Add-Failure 'Root README must remain a concise navigation page of at most 120 lines.'
}

if ($rootReadme -match '(?im)^[ \t]*```[ \t]*(?:powershell|pwsh|ps1)[ \t]*$') {
    Add-Failure 'Root README must not contain detailed PowerShell, pwsh, or ps1 procedures.'
}

$codexFirstReadme = Read-Text 'apm-packages/codex-first-ai-development-process/README.md'
if (-not $codexFirstReadme.Contains('.\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs', [StringComparison]::Ordinal)) {
    Add-Failure 'Codex-first README must provide a repository-root-relative installer path.'
}

$fallbackReadme = Read-Text 'apm-packages/copilot-fallback-ai-development-process/README.md'
if (-not $fallbackReadme.Contains('.\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs', [StringComparison]::Ordinal)) {
    Add-Failure 'Copilot fallback README must provide a repository-root-relative installer path.'
}
foreach ($limitation in @('lite / standard documentation level', 'core / audit artifact分離', 'profile TOML互換更新', '未移植')) {
    if (-not $fallbackReadme.Contains($limitation, [StringComparison]::Ordinal)) {
        Add-Failure "Copilot fallback README is missing compatibility limitation: $limitation"
    }
}

$fullAutonomousReadme = Read-Text 'apm-packages/full-autonomous-plan-first-flow/README.md'
foreach ($heading in @('## Use when', '## Install', '## Start', '## Documentation and validation')) {
    if (-not $fullAutonomousReadme.Contains($heading, [StringComparison]::Ordinal)) {
        Add-Failure "Full Autonomous README is missing entrypoint section: $heading"
    }
}

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
