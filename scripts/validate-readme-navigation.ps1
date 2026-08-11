[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Get-Location).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Read-Text([string] $RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Missing file: $RelativePath")
        return ''
    }
    return Get-Content -LiteralPath $path -Raw
}

function Require([string] $RelativePath, [string] $Pattern, [string] $Description) {
    $text = Read-Text $RelativePath
    if ($text -and $text -notmatch $Pattern) {
        $failures.Add("Missing $Description in $RelativePath")
    }
}

function Forbid([string] $RelativePath, [string] $Pattern, [string] $Description) {
    $text = Read-Text $RelativePath
    if ($text -and $text -match $Pattern) {
        $failures.Add("Found obsolete $Description in $RelativePath")
    }
}

Require 'README.md' 'apm-packages/adaptive-implementation-execution/README\.md' 'Adaptive package link'
Require 'README.md' 'apm-packages/design-pair-implementation-execution/README\.md' 'Design Pair package link'
Require 'README.md' 'apm-packages/pr-review-remediation/README\.md' 'PR Review package link'
Require 'README.md' 'apm-packages/plan-coverage-residual-flow/README\.md' 'Plan Coverage package link'
Require 'README.md' 'finalize-codex-agent-profiles\.cs' 'common finalizer Quickstart'
Require 'docs/installation-and-maintenance.md' 'codex-profile-overlays\.json' 'overlay maintenance contract'
Require 'apm-packages/plan-coverage-residual-flow/README.md' 'apm install .*plan-coverage-residual-flow' 'Plan Coverage APM install'
Require 'apm-packages/adaptive-implementation-execution/README.md' 'codex-profile-overlays\.json' 'Adaptive overlay contract'
Require 'apm-packages/pr-review-remediation/README.md' 'finalize-codex-agent-profiles\.cs' 'PR Review finalizer command'

foreach ($path in @(
    'README.md',
    'docs/installation-and-maintenance.md',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/plan-coverage-residual-flow/README.md',
    'apm-packages/design-pair-implementation-execution/README.md'
)) {
    Forbid $path 'provision-work-repo-agents|install-adaptive-implementation-local|sync-pr-review-remediation-local' 'legacy helper'
}

if ($failures.Count -gt 0) {
    $message = "README navigation validation failed:" + [Environment]::NewLine + "- " + ($failures -join ([Environment]::NewLine + "- "))
    Write-Error $message
    exit 1
}

Write-Output 'README navigation validation: PASS'
