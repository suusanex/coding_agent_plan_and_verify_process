[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
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
Require 'README.md' 'apm-packages/persistent-purpose-review/README\.md' 'Persistent Purpose Review package link'
Require 'README.md' 'apps/PurposeReviewRunner/README\.md' 'Purpose Review Runner link'
Require 'README.md' 'apm-packages/plan-coverage-residual-flow/README\.md' 'Plan Coverage package link'
Require 'README.md' 'finalize-codex-agent-profiles\.cs' 'common finalizer Quickstart'
Require 'docs/installation-and-maintenance.md' 'codex-profile-overlays\.json' 'overlay maintenance contract'
Require 'docs/installation-and-maintenance.md' 'pr-review-remediation-technical-reference\.md' 'PR Review documentation ownership'
Require 'apm-packages/plan-coverage-residual-flow/README.md' 'apm install .*plan-coverage-residual-flow' 'Plan Coverage APM install'
Require 'apm-packages/adaptive-implementation-execution/README.md' 'codex-profile-overlays\.json' 'Adaptive overlay contract'
Require 'apm-packages/pr-review-remediation/README.md' '独立した`review-planner`、Codex agent profile、`codex-profile-finalizer`は必要ありません' 'PR Review standalone install contract'
Require 'apm-packages/pr-review-remediation/README.md' '\$pr-review-remediation を使って、このbranchのReady PRを処理してください。' 'PR Review primary usage instruction'
Require 'apm-packages/pr-review-remediation/README.md' 'docs/pr-review-remediation-technical-reference\.md' 'PR Review technical reference link'
Require 'apm-packages/pr-review-remediation/README.md' '(?s)## 前提条件.*## 5分Quickstart.*## Adaptive Implementationを使う場合.*## 結果の見え方.*## 更新.*## 削除.*## Troubleshootingと関連文書' 'PR Review user-first section order'
Forbid 'apm-packages/pr-review-remediation/README.md' 'dotnet run --file .*finalize-codex-agent-profiles\.cs' 'PR Review finalizer command'
Forbid 'apm-packages/pr-review-remediation/README.md' 'review-context\.json|REMEDIATION_REQUIRED|headRepository\.nameWithOwner|build-agent-plugin\.ps1' 'PR Review internal contract detail'
Require 'docs/pr-review-remediation-technical-reference.md' 'review-context\.json' 'PR Review artifact contract'
Require 'docs/pr-review-remediation-technical-reference.md' 'REMEDIATION_REQUIRED' 'PR Review internal state contract'
Require 'docs/pr-review-remediation-technical-reference.md' 'Untrusted remote content boundary' 'PR Review trust boundary contract'
Require 'docs/pr-review-remediation-technical-reference.md' 'validate-agent-plugin-package\.ps1' 'PR Review maintainer validation'
Require 'apm-packages/persistent-purpose-review/README.md' 'purpose-review-runner version' 'Persistent Purpose Review Runner preflight'
Require 'apm-packages/persistent-purpose-review/README.md' '--target agent-skills --global' 'Persistent Purpose Review global APM install'
Require 'apm-packages/persistent-purpose-review/README.md' '実装完了後は \$persistent-purpose-review' 'Persistent Purpose Review usage instruction'
Require 'apps/PurposeReviewRunner/README.md' 'releases/latest' 'Runner latest release link'
Require 'apps/PurposeReviewRunner/README.md' 'docs/purpose-review-runner-technical-reference\.md' 'Runner technical reference link'
Require 'apps/PurposeReviewRunner/README.md' 'docs/purpose-review-runner-maintenance\.md' 'Runner maintainer reference link'
Require 'apps/PurposeReviewRunner/README.md' 'docs/purpose-review-runner-compatibility\.md' 'Runner compatibility link'
Require 'docs/purpose-review-runner-technical-reference.md' 'protocolVersion' 'Runner protocol reference'
Require 'docs/purpose-review-runner-maintenance.md' 'purpose-review-runner-v' 'Runner release tag contract'
Require 'docs/purpose-review-runner-compatibility.md' '0\.3\.0' 'Runner compatibility version gate'

foreach ($path in @(
    'README.md',
    'docs/installation-and-maintenance.md',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/persistent-purpose-review/README.md',
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
