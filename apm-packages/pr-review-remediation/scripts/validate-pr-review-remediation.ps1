[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$packageRoot = Join-Path $repoRoot 'apm-packages/pr-review-remediation'
$scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ('pr-review-remediation-validation-' + [guid]::NewGuid().ToString('N'))
$safeToDelete = $false

function Assert-Contains([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $RelativePath)
    if ($text -notmatch $Pattern) { throw "Missing ${Description}: $RelativePath" }
}

function Assert-NotContains([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $RelativePath)
    if ($text -match $Pattern) { throw "Forbidden ${Description}: $RelativePath" }
}

try {
    foreach ($relative in @(
        'apm-packages/pr-review-remediation/apm.yml',
        'apm-packages/pr-review-remediation/README.md',
        'apm-packages/pr-review-remediation/codex-profile-overlays.json',
        'apm-packages/pr-review-remediation/.apm/agents/review-planner.agent.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md',
        'apm-packages/pr-review-remediation/tests/fixtures/remote-review-scenarios.json',
        'apm-packages/pr-review-remediation/tests/fixtures/expected-review-plan.md',
        'apm-packages/pr-review-remediation/tests/fixtures/expected-review-complete.md'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) { throw "Missing package file: $relative" }
    }

    $agents = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot '.apm/agents') -Filter '*.agent.md' -File | ForEach-Object Name)
    if (($agents -join '|') -ne 'review-planner.agent.md') { throw "Unexpected baseline agents: $($agents -join ', ')" }
    $scripts = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'scripts') -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object Name)
    if (($scripts -join '|') -ne 'validate-pr-review-remediation-apm-smoke.ps1|validate-pr-review-remediation.ps1') {
        throw "Unexpected package scripts: $($scripts -join ', ')"
    }

    Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?ms)^version:\s*0\.7\.0\s*$.*^\s*- copilot\s*$.*^\s*- codex\s*$.*^\s*- agent-skills\s*$' '0.7.0 multi-target manifest'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'Production code changed: No' 'Phase 1 non-mutation contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' '別の明示turn' 'separate Adaptive turn boundary'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/agents/review-planner.agent.md' 'Apply \| Hold \| Reject' 'remote finding decision contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/agents/review-planner.agent.md' 'waitStatus: timeout' 'timeout fail-closed contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/agents/review-planner.agent.md' 'REVIEW_COMPLETE' 'no-remediation terminal contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md' 'Source Coverage' 'remote source coverage contract'
    Assert-Contains 'apm-packages/pr-review-remediation/tests/fixtures/expected-review-complete.md' 'Verdict: REVIEW_COMPLETE' 'no-remediation expected verdict'
    Assert-NotContains 'apm-packages/pr-review-remediation/tests/fixtures/expected-review-complete.md' 'implementation_intent|adaptive-implementation-execution|Ordered Remediation Plan' 'no-remediation implementation handoff'

    foreach ($relative in @(
        'apm-packages/pr-review-remediation/README.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
        'apm-packages/pr-review-remediation/.apm/agents/review-planner.agent.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md'
    )) {
        Assert-NotContains $relative 'local-review-findings|Local Codex|Goal Context multi-round|purpose-review-findings' 'retired local/purpose planner input'
    }

    $profiles = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'codex-profile-overlays.json') | ConvertFrom-Json
    $profileNames = @($profiles.profiles | ForEach-Object agent)
    if (($profileNames -join '|') -ne 'review-planner') { throw "Unexpected Codex profiles: $($profileNames -join ', ')" }
    if ([string]$profiles.profiles[0].sandbox_mode -cne 'read-only') { throw 'review-planner profile must be read-only.' }

    $catalog = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'tests/fixtures/remote-review-scenarios.json') | ConvertFrom-Json
    $expected = @{
        'REMOTE-001' = 'READY_FOR_ADAPTIVE_IMPLEMENTATION'
        'REMOTE-002' = 'REVIEW_COMPLETE'
        'REMOTE-003' = 'HUMAN_DECISION_REQUIRED'
        'REMOTE-004' = 'BLOCKED'
        'REMOTE-005' = 'BLOCKED'
        'REMOTE-006' = 'HUMAN_DECISION_REQUIRED'
        'REMOTE-007' = 'READY_FOR_ADAPTIVE_IMPLEMENTATION'
    }
    if (@($catalog.scenarios).Count -ne $expected.Count) { throw 'Unexpected remote scenario count.' }
    foreach ($scenario in @($catalog.scenarios)) {
        if (-not $expected.ContainsKey([string]$scenario.id)) { throw "Unknown remote scenario: $($scenario.id)" }
        if ([string]$scenario.expectedVerdict -cne $expected[[string]$scenario.id]) { throw "Wrong verdict for $($scenario.id)" }
    }

    $collector = Join-Path $packageRoot '.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs'
    $null = New-Item -ItemType Directory -Path $scratchRoot -Force
    $resolvedScratch = (Resolve-Path -LiteralPath $scratchRoot).Path
    if (-not $resolvedScratch.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe scratch path: $resolvedScratch" }
    $safeToDelete = $true
    & dotnet publish $collector --output (Join-Path $resolvedScratch 'collector')
    if ($LASTEXITCODE -ne 0) { throw 'Collector publish failed.' }
    & dotnet run --file $collector -- --help
    if ($LASTEXITCODE -ne 0) { throw 'Collector help failed.' }

    Write-Output 'PR Review Remediation remote-only validation: PASS'
}
finally {
    if ($safeToDelete -and (Test-Path -LiteralPath $scratchRoot)) {
        $resolved = [IO.Path]::GetFullPath($scratchRoot)
        if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove unsafe scratch path: $resolved" }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
