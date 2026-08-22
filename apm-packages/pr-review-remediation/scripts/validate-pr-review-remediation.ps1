[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packageRoot = Join-Path $repoRoot 'apm-packages/pr-review-remediation'
$scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ('pr-review-remediation-validation-' + [guid]::NewGuid().ToString('N'))
$safeToDelete = $false

function Assert-File([string]$RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
}

function Assert-Contains([string]$RelativePath, [string]$Pattern, [string]$Description) {
    Assert-File $RelativePath
    if ((Get-Content -Raw -LiteralPath (Join-Path $repoRoot $RelativePath)) -notmatch $Pattern) {
        throw "$RelativePath does not contain $Description"
    }
}

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE" }
}

try {
    $null = New-Item -ItemType Directory -Path $scratchRoot
    $resolvedScratch = (Resolve-Path -LiteralPath $scratchRoot).Path
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedScratch.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe scratch path: $resolvedScratch"
    }
    $safeToDelete = $true

    foreach ($path in @(
        'apm-packages/pr-review-remediation/apm.yml',
        'apm-packages/pr-review-remediation/README.md',
        'apm-packages/pr-review-remediation/codex-profile-overlays.json',
        'apm-packages/pr-review-remediation/.apm/agents/local-reviewer.agent.md',
        'apm-packages/pr-review-remediation/.apm/agents/review-planner.agent.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs',
        'tests/pr-review-remediation/PRR-001/run.schema.json',
        'tests/pr-review-remediation/PRR-001/run.json',
        'tests/pr-review-remediation/PRR-001/local-review-findings.md',
        'tests/pr-review-remediation/PRR-001/review-plan.md'
    )) { Assert-File $path }

    $agentNames = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot '.apm/agents') -Filter '*.agent.md' -File | Sort-Object Name | ForEach-Object Name)
    if (($agentNames -join '|') -ne 'local-reviewer.agent.md|review-planner.agent.md') { throw "Unexpected baseline agents: $($agentNames -join ', ')" }
    $skillNames = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot '.apm/skills') -Directory | Sort-Object Name | ForEach-Object Name)
    if (($skillNames -join '|') -ne 'pr-review-remediation') { throw "Unexpected baseline Skills: $($skillNames -join ', ')" }
    $scriptNames = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'scripts') -File | Sort-Object Name | ForEach-Object Name)
    $expectedScripts = 'run-pr-review-remediation-agent-smoke.ps1|validate-pr-review-remediation-agent-smoke.ps1|validate-pr-review-remediation-apm-smoke.ps1|validate-pr-review-remediation.ps1'
    if (($scriptNames -join '|') -ne $expectedScripts) { throw "Unexpected baseline scripts: $($scriptNames -join ', ')" }
    $fixtureNames = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests/pr-review-remediation') -Directory | Sort-Object Name | ForEach-Object Name)
    if (($fixtureNames -join '|') -ne 'PRR-001') { throw "Unexpected baseline fixtures: $($fixtureNames -join ', ')" }

    Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?m)^version:\s*0\.6\.0\s*$' 'baseline-only package version'
    Assert-Contains 'apm-packages/pr-review-remediation/README.md' '\$persistent-purpose-review' 'successor purpose review route'
    Assert-Contains 'apm-packages/pr-review-remediation/README.md' '(?m)^\$moduleRoot\s*=\s*"\.\\apm_modules\\suusanex\\coding_agent_plan_and_verify_process"\s*$' 'installed module root assignment'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'Production code changed: No' 'Phase 1 non-mutation contract'

    $profiles = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'codex-profile-overlays.json') | ConvertFrom-Json
    $profileNames = @($profiles.profiles.agent)
    if (($profileNames -join '|') -ne 'local-reviewer|review-planner') {
        throw "Unexpected profile set: $($profileNames -join ', ')"
    }

    $collector = Join-Path $packageRoot '.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs'
    $publishRoot = Join-Path $resolvedScratch 'collector'
    Invoke-Native 'dotnet' @('publish', $collector, '--output', $publishRoot, '--disable-build-servers') 'collector publish'
    $collectorExecutable = Join-Path $publishRoot ($(if ($IsWindows) { 'collect-pr-review-context.exe' } else { 'collect-pr-review-context' }))
    Invoke-Native $collectorExecutable @('--help') 'collector help'

    Invoke-Native 'pwsh' @('-NoProfile', '-File', (Join-Path $packageRoot 'scripts/validate-pr-review-remediation-agent-smoke.ps1'), '-RepositoryRoot', $repoRoot) 'PRR-001 evidence validation'
    Assert-Contains 'apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1' '\[switch\]\$DescribePayload' 'external-model payload inspection gate'

    Write-Output 'PR Review Remediation baseline validation: PASS'
}
finally {
    if ($safeToDelete -and (Test-Path -LiteralPath $scratchRoot)) {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force
    }
}
