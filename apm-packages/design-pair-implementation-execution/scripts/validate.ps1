[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Get-Location).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Require-File([string] $RelativePath) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $RelativePath) -PathType Leaf)) {
        $failures.Add("Missing file: $RelativePath")
    }
}

function Require-Text([string] $RelativePath, [string] $Pattern, [string] $Description) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Content -LiteralPath $path -Raw) -notmatch $Pattern) {
        $failures.Add("Missing $Description in $RelativePath")
    }
}

foreach ($path in @(
    'apm-packages/design-pair-implementation-execution/apm.yml',
    'apm-packages/design-pair-implementation-execution/README.md',
    'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/SKILL.md',
    'apm-packages/adaptive-implementation-execution/codex-profile-overlays.json',
    'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs'
)) { Require-File $path }

Require-Text 'apm-packages/design-pair-implementation-execution/apm.yml' 'path:\s*apm-packages/adaptive-implementation-execution' 'Adaptive dependency'
Require-Text 'apm-packages/plan-coverage-residual-flow/apm.yml' '(?m)^version:\s*0\.13\.0\s*$' 'Plan Coverage package version 0.13.0'
Require-Text 'apm-packages/design-pair-implementation-execution/README.md' 'finalize-codex-agent-profiles\.cs' 'shared finalizer usage'
Require-Text 'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs' 'codex-profile-overlays\.json' 'overlay discovery'

foreach ($path in @(
    'apm-packages/design-pair-implementation-execution/README.md',
    'apm-packages/design-pair-implementation-execution/docs/usage-guide.md',
    'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md'
)) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $path) -PathType Leaf) {
        if ((Get-Content -LiteralPath (Join-Path $repoRoot $path) -Raw) -match 'install-adaptive-implementation-local|provision-work-repo-agents') {
            $failures.Add("Obsolete helper reference in $path")
        }
    }
}

if ($failures.Count -gt 0) {
    $message = "Design Pair validation failed:" + [Environment]::NewLine + "- " + ($failures -join ([Environment]::NewLine + "- "))
    Write-Error $message
    exit 1
}

Write-Output 'Design Pair validation: PASS'
