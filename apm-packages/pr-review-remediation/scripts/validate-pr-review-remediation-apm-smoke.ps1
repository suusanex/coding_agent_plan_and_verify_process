[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[^/]+/[^/]+$')][string]$Repository,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Ref,
    [string]$ApmExecutable = 'apm'
)

$ErrorActionPreference = 'Stop'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$scratch = Join-Path $tempRoot ('pr-review-remediation-apm-smoke-' + [guid]::NewGuid().ToString('N'))
$safeToDelete = $false
$locationPushed = $false

function Assert-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing ${Description}: $Path" }
}

try {
    $null = New-Item -ItemType Directory -Path (Join-Path $scratch '.codex') -Force
    $resolvedScratch = (Resolve-Path -LiteralPath $scratch).Path
    if (-not $resolvedScratch.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe scratch path: $resolvedScratch"
    }
    $safeToDelete = $true
    Set-Content -LiteralPath (Join-Path $resolvedScratch 'AGENTS.md') -Value 'sentinel-agents'
    Set-Content -LiteralPath (Join-Path $resolvedScratch '.codex/config.toml') -Value 'sentinel-config'
    $agentsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $resolvedScratch 'AGENTS.md')).Hash
    $configHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $resolvedScratch '.codex/config.toml')).Hash

    $packageSpec = "$Repository/apm-packages/pr-review-remediation#$Ref"
    Push-Location -LiteralPath $resolvedScratch
    $locationPushed = $true
    try {
        & $ApmExecutable install $packageSpec --target 'codex,agent-skills' --https
        if ($LASTEXITCODE -ne 0) { throw "remote APM install failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
        $locationPushed = $false
    }

    $skillRoot = Join-Path $resolvedScratch '.agents/skills/pr-review-remediation'
    foreach ($relative in @(
        'SKILL.md',
        'scripts/collect-pr-review-context.cs',
        'templates/local-review-findings.md',
        'templates/review-plan.md',
        'references/usage.md',
        'references/migration.md',
        'references/troubleshooting.md'
    )) { Assert-File (Join-Path $skillRoot $relative) "baseline Skill asset $relative" }

    $installedSkills = @(Get-ChildItem -LiteralPath (Join-Path $resolvedScratch '.agents/skills') -Directory | Sort-Object Name | ForEach-Object Name)
    if (($installedSkills -join '|') -ne 'pr-review-remediation') { throw "Unexpected installed Skills: $($installedSkills -join ', ')" }
    $parts = $Repository.Split('/')
    $moduleRoot = Join-Path $resolvedScratch ("apm_modules/{0}/{1}" -f $parts[0], $parts[1])
    $finalizer = Join-Path $moduleRoot 'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs'
    Assert-File $finalizer 'Codex profile finalizer'
    & dotnet run --file $finalizer -- $resolvedScratch
    if ($LASTEXITCODE -ne 0) { throw 'Codex profile finalization failed.' }
    & dotnet run --file $finalizer -- $resolvedScratch --check
    if ($LASTEXITCODE -ne 0) { throw 'Codex profile finalizer check failed.' }

    $profileRoot = Join-Path $resolvedScratch '.codex/agents'
    foreach ($profile in @('local-reviewer.toml', 'review-planner.toml')) {
        $path = Join-Path $profileRoot $profile
        Assert-File $path "profile $profile"
        $text = Get-Content -Raw -LiteralPath $path
        if ($text -notmatch '(?m)^sandbox_mode\s*=\s*"read-only"\s*$') { throw "$profile is not read-only." }
    }
    $installedProfiles = @(Get-ChildItem -LiteralPath $profileRoot -Filter '*.toml' -File | Sort-Object Name | ForEach-Object Name)
    if (($installedProfiles -join '|') -ne 'local-reviewer.toml|review-planner.toml') { throw "Unexpected installed profiles: $($installedProfiles -join ', ')" }
    & dotnet run --file (Join-Path $skillRoot 'scripts/collect-pr-review-context.cs') -- --help
    if ($LASTEXITCODE -ne 0) { throw 'Installed collector help failed.' }

    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $resolvedScratch 'AGENTS.md')).Hash -ne $agentsHash) {
        throw 'APM install or finalizer changed AGENTS.md.'
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $resolvedScratch '.codex/config.toml')).Hash -ne $configHash) {
        throw 'APM install or finalizer changed .codex/config.toml.'
    }
    $lockText = Get-Content -Raw -LiteralPath (Join-Path $resolvedScratch 'apm.lock.yaml')
    if ($lockText -notmatch 'pr-review-remediation') {
        throw 'APM lock does not represent the baseline-only dependency set.'
    }

    Write-Output 'PR Review Remediation remote APM smoke: PASS'
}
finally {
    if ($locationPushed) { Pop-Location }
    if ($safeToDelete -and (Test-Path -LiteralPath $scratch)) {
        $resolved = [IO.Path]::GetFullPath($scratch)
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe scratch path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
