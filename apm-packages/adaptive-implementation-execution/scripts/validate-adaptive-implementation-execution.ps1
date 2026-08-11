[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Get-Location).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Read-RepoText([string] $RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Missing file: $RelativePath")
        return ''
    }
    return Get-Content -LiteralPath $path -Raw
}

function Require-File([string] $RelativePath) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $RelativePath) -PathType Leaf)) {
        $failures.Add("Missing file: $RelativePath")
    }
}

function Require-Text([string] $RelativePath, [string] $Pattern, [string] $Description) {
    $text = Read-RepoText $RelativePath
    if ($text -and $text -notmatch $Pattern) {
        $failures.Add("Missing $Description in $RelativePath")
    }
}

function Forbid-Text([string] $RelativePath, [string] $Pattern, [string] $Description) {
    $text = Read-RepoText $RelativePath
    if ($text -and $text -match $Pattern) {
        $failures.Add("Found obsolete $Description in $RelativePath")
    }
}

$required = @(
    'apm-packages/adaptive-implementation-execution/.apm/agents/high-implementation-starter.agent.md',
    'apm-packages/adaptive-implementation-execution/.apm/agents/standard-implementation-completer.agent.md',
    'apm-packages/adaptive-implementation-execution/apm.yml',
    'apm-packages/adaptive-implementation-execution/codex-profile-overlays.json',
    'apm-packages/codex-profile-finalizer/apm.yml',
    'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs',
    'apm-packages/codex-profile-finalizer/tests/validate-finalizer.ps1',
    'apm-packages/codex-profile-finalizer/tests/validate-apm-install.ps1',
    'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-apm-smoke.ps1',
    'apm-packages/adaptive-implementation-execution/tests/routing-scenarios.json',
    'apm-packages/adaptive-implementation-execution/tests/validate-routing-scenarios.ps1'
)
foreach ($path in $required) { Require-File $path }

$integratedManifests = @(
    @{ Path = 'apm-packages/plan-coverage-residual-flow/apm.yml'; Version = '0\.13\.0' }
)
foreach ($integratedManifest in $integratedManifests) {
    Require-Text $integratedManifest.Path ("(?m)^version:\s*" + $integratedManifest.Version + '\s*$') "integrated package version $($integratedManifest.Version -replace '\\', '')"
}

$overlayPath = Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution/codex-profile-overlays.json'
if (Test-Path -LiteralPath $overlayPath) {
    try {
        $overlay = Get-Content -LiteralPath $overlayPath -Raw | ConvertFrom-Json
        if ($overlay.schemaVersion -ne 1 -or $overlay.package -ne 'adaptive-implementation-execution') {
            $failures.Add('Adaptive profile overlay schema or package ownership is invalid')
        }
        $allowedFields = @('agent', 'model', 'model_reasoning_effort', 'sandbox_mode')
        foreach ($entry in $overlay.profiles) {
            $unknownFields = @($entry.PSObject.Properties.Name | Where-Object { $_ -notin $allowedFields })
            if ($unknownFields.Count -gt 0) {
                $failures.Add("Adaptive overlay has unsupported fields: $($unknownFields -join ', ')")
            }
            $agent = Join-Path $repoRoot ("apm-packages/adaptive-implementation-execution/.apm/agents/{0}.agent.md" -f $entry.agent)
            if (-not (Test-Path -LiteralPath $agent -PathType Leaf)) {
                $failures.Add("Adaptive overlay agent is not package-owned: $($entry.agent)")
            }
            foreach ($field in @('model', 'model_reasoning_effort', 'sandbox_mode')) {
                if ([string]::IsNullOrWhiteSpace([string]$entry.$field)) {
                    $failures.Add("Adaptive overlay field is missing: $($entry.agent).$field")
                }
            }
        }
    }
    catch {
        $failures.Add("Adaptive overlay JSON is invalid: $($_.Exception.Message)")
    }
}

Require-Text 'apm-packages/adaptive-implementation-execution/apm.yml' 'path:\s*apm-packages/codex-profile-finalizer' 'finalizer dependency'
Require-Text 'apm-packages/codex-profile-finalizer/apm.yml' 'name:\s*codex-profile-finalizer' 'finalizer package name'
Require-Text 'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs' 'codex-profile-overlays\.json' 'overlay discovery'
Require-Text 'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs' '--dry-run|--check|--force' 'finalizer options'
Forbid-Text 'README.md' 'provision-work-repo-agents|install-adaptive-implementation-local|sync-pr-review-remediation-local' 'legacy installer reference'
Forbid-Text 'apm-packages/adaptive-implementation-execution/README.md' 'codex-agents/.*\.toml|install-adaptive-implementation-local' 'legacy Adaptive profile source'

try {
    & (Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution/tests/validate-routing-scenarios.ps1') -FixturePath (Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution/tests/routing-scenarios.json') | Write-Output
}
catch {
    $failures.Add("Adaptive routing scenario validation failed: $($_.Exception.Message)")
}

try {
    & (Join-Path $repoRoot 'apm-packages/codex-profile-finalizer/tests/validate-finalizer.ps1') | Write-Output
}
catch {
    $failures.Add("Codex profile finalizer validation failed: $($_.Exception.Message)")
}

try {
    & (Join-Path $repoRoot 'apm-packages/codex-profile-finalizer/tests/validate-apm-install.ps1') | Write-Output
}
catch {
    $failures.Add("Codex profile finalizer local APM smoke failed: $($_.Exception.Message)")
}

if ($failures.Count -gt 0) {
    $message = "Adaptive Implementation validation failed:" + [Environment]::NewLine + "- " + ($failures -join ([Environment]::NewLine + "- "))
    Write-Error $message
    exit 1
}

Write-Output 'Adaptive Implementation validation: PASS'
