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
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Missing file: $RelativePath")
        return
    }
    if ((Get-Content -LiteralPath $path -Raw) -notmatch $Pattern) {
        $failures.Add("Missing $Description in $RelativePath")
    }
}

$required = @(
    'apm-packages/pr-review-remediation/.apm/agents/local-reviewer.agent.md',
    'apm-packages/pr-review-remediation/.apm/agents/purpose-reviewer.agent.md',
    'apm-packages/pr-review-remediation/.apm/agents/review-planner.agent.md',
    'apm-packages/pr-review-remediation/apm.yml',
    'apm-packages/pr-review-remediation/codex-profile-overlays.json',
    'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs',
    'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1'
)
foreach ($path in $required) { Require-File $path }

$overlayPath = Join-Path $repoRoot 'apm-packages/pr-review-remediation/codex-profile-overlays.json'
if (Test-Path -LiteralPath $overlayPath) {
    try {
        $overlay = Get-Content -LiteralPath $overlayPath -Raw | ConvertFrom-Json
        if ($overlay.schemaVersion -ne 1 -or $overlay.package -ne 'pr-review-remediation' -or $overlay.profiles.Count -ne 3) {
            $failures.Add('PR Review profile overlay schema, ownership, or profile count is invalid')
        }
        $allowedFields = @('agent', 'model', 'model_reasoning_effort', 'sandbox_mode')
        foreach ($entry in $overlay.profiles) {
            $unknownFields = @($entry.PSObject.Properties.Name | Where-Object { $_ -notin $allowedFields })
            if ($unknownFields.Count -gt 0) {
                $failures.Add("PR Review overlay has unsupported fields: $($unknownFields -join ', ')")
            }
            $agent = Join-Path $repoRoot ("apm-packages/pr-review-remediation/.apm/agents/{0}.agent.md" -f $entry.agent)
            if (-not (Test-Path -LiteralPath $agent -PathType Leaf)) {
                $failures.Add("PR Review overlay agent is not package-owned: $($entry.agent)")
            }
            foreach ($field in @('model', 'model_reasoning_effort', 'sandbox_mode')) {
                if ([string]::IsNullOrWhiteSpace([string]$entry.$field)) {
                    $failures.Add("PR Review overlay field is missing: $($entry.agent).$field")
                }
            }
        }
    }
    catch {
        $failures.Add("PR Review overlay JSON is invalid: $($_.Exception.Message)")
    }
}

Require-Text 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*apm-packages/codex-profile-finalizer' 'finalizer dependency'
Require-Text 'apm-packages/pr-review-remediation/README.md' 'finalize-codex-agent-profiles\.cs' 'shared finalizer usage'
Require-Text 'apm-packages/pr-review-remediation/README.md' 'codex-profile-overlays\.json' 'overlay documentation'
Require-Text 'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs' '--dry-run|--check|--force' 'finalizer options'

if (Test-Path -LiteralPath (Join-Path $repoRoot 'apm-packages/pr-review-remediation/codex-agents')) {
    $failures.Add('Obsolete PR Review codex-agents directory remains')
}

if ($failures.Count -gt 0) {
    $message = "PR Review Remediation validation failed:" + [Environment]::NewLine + "- " + ($failures -join ([Environment]::NewLine + "- "))
    Write-Error $message
    exit 1
}

Write-Output 'PR Review Remediation validation: PASS'
