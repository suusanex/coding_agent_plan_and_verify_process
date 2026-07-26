[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repository,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Ref,

    [string]$ApmExecutable = 'apm'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Assert-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing ${Description}: $Path"
    }
}

function Assert-Contains([string]$Path, [string]$Pattern, [string]$Description) {
    Assert-File $Path $Description
    if ((Get-Content -Raw -LiteralPath $Path) -notmatch $Pattern) {
        throw "$Description does not contain the required contract: $Path"
    }
}

function Assert-ApmCanonicalAgent([string]$ModulesRoot, [string]$FileName) {
    $matches = @(Get-ChildItem -LiteralPath $ModulesRoot -Recurse -Force -File -Filter $FileName | Where-Object {
        $_.Directory.Name -eq 'agents' -and $_.Directory.Parent.Name -eq '.apm'
    })
    if ($matches.Count -eq 0) {
        throw "Missing canonical agent in APM modules: $FileName"
    }
}

$apmVersion = & $ApmExecutable --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "APM executable failed: $ApmExecutable"
}
if ($apmVersion -notmatch '\b0\.26\.0\b') {
    throw "APM 0.26.0 is required for the reproducible smoke. Observed: $($apmVersion.Trim())"
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$scratch = Join-Path $tempRoot ("pr-review-remediation-apm-smoke-" + [guid]::NewGuid().ToString('N'))
$scratch = [System.IO.Path]::GetFullPath($scratch)
if (-not $scratch.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe scratch path: $scratch"
}

$previousPythonUtf8 = $env:PYTHONUTF8
$previousPythonIoEncoding = $env:PYTHONIOENCODING
New-Item -ItemType Directory -Path (Join-Path $scratch '.codex') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $scratch 'AGENTS.md') -Value 'sentinel-agents'
Set-Content -LiteralPath (Join-Path $scratch '.codex/config.toml') -Value 'sentinel-config'
$agentsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch 'AGENTS.md')).Hash
$configHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch '.codex/config.toml')).Hash

try {
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    $packageSpec = "$Repository/apm-packages/pr-review-remediation#$Ref"

    Push-Location $scratch
    try {
        Invoke-Native $ApmExecutable @('install', $packageSpec, '--target', 'codex,agent-skills', '--https') 'remote APM install'
    }
    finally {
        Pop-Location
    }

    $deployedReviewSkill = Join-Path $scratch '.agents/skills/pr-review-remediation'
    $deployedGoalReviewSkill = Join-Path $scratch '.agents/skills/goal-context-pr-review'
    $deployedAdaptiveSkill = Join-Path $scratch '.agents/skills/adaptive-implementation-execution'
    foreach ($relative in @(
        'SKILL.md',
        'scripts/collect-pr-review-context.cs',
        'templates/local-review-findings.md',
        'templates/review-plan.md',
        'references/usage.md',
        'references/migration.md',
        'references/troubleshooting.md'
    )) {
        Assert-File (Join-Path $deployedReviewSkill $relative) "deployed review Skill asset $relative"
    }
    foreach ($relative in @(
        'SKILL.md',
        'scripts/select-goal-context.cs',
        'templates/purpose-review-findings.md',
        'references/design.md',
        'references/usage.md',
        'references/troubleshooting.md'
    )) {
        Assert-File (Join-Path $deployedGoalReviewSkill $relative) "deployed Goal Context review Skill asset $relative"
    }
    foreach ($relative in @('SKILL.md', 'refs/intent.md', 'refs/handoff.md')) {
        Assert-File (Join-Path $deployedAdaptiveSkill $relative) "deployed Adaptive Skill asset $relative"
    }

    $parts = $Repository.Split('/')
    $repositoryModule = Join-Path $scratch ("apm_modules/{0}/{1}" -f $parts[0], $parts[1])
    foreach ($agent in @(
        'local-reviewer.agent.md',
        'purpose-reviewer.agent.md',
        'review-planner.agent.md',
        'high-implementation-starter.agent.md',
        'standard-implementation-completer.agent.md'
    )) {
        Assert-ApmCanonicalAgent (Join-Path $scratch 'apm_modules') $agent
    }
    $installedReviewHelper = Join-Path $repositoryModule 'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs'
    $reviewHelper = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'sync-pr-review-remediation-local.cs'))
    $adaptiveHelper = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs'))
    Assert-File $installedReviewHelper 'installed review profile helper'
    Assert-File $reviewHelper 'canonical review profile helper from the source checkout'
    Assert-File $adaptiveHelper 'canonical Adaptive profile helper from the source checkout'

    Invoke-Native 'dotnet' @('run', '--file', $reviewHelper, '--', $scratch) 'review profile synchronization'
    Invoke-Native 'dotnet' @('run', '--file', $adaptiveHelper, '--', $scratch) 'Adaptive profile synchronization'
    Invoke-Native 'dotnet' @('run', '--file', $adaptiveHelper, '--', $scratch, '--check') 'Adaptive profile check'
    Invoke-Native 'dotnet' @('run', '--file', $reviewHelper, '--', $scratch, '--check') 'review profile check'
    Invoke-Native 'dotnet' @('run', '--file', (Join-Path $deployedReviewSkill 'scripts/collect-pr-review-context.cs'), '--', '--help') 'deployed relative collector help'
    Invoke-Native 'dotnet' @('run', '--file', (Join-Path $deployedGoalReviewSkill 'scripts/select-goal-context.cs'), '--', '--help') 'deployed Goal Context selector help'

    $profileRoot = Join-Path $scratch '.codex/agents'
    foreach ($profile in @('local-reviewer.toml', 'purpose-reviewer.toml', 'review-planner.toml')) {
        $path = Join-Path $profileRoot $profile
        Assert-Contains $path '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$' "review profile $profile model"
        Assert-Contains $path '(?m)^model_reasoning_effort\s*=\s*"high"\s*$' "review profile $profile reasoning"
        Assert-Contains $path '(?m)^sandbox_mode\s*=\s*"read-only"\s*$' "review profile $profile sandbox"
    }
    Assert-Contains (Join-Path $profileRoot 'local-reviewer.toml') 'developer_instructions\s*=\s*"# Local Reviewer\\n' 'local reviewer full APM contract'
    Assert-Contains (Join-Path $profileRoot 'purpose-reviewer.toml') 'developer_instructions\s*=\s*"# Purpose Reviewer\\n' 'purpose reviewer full APM contract'
    Assert-Contains (Join-Path $profileRoot 'review-planner.toml') 'developer_instructions\s*=\s*"# Review Planner\\n' 'review planner full APM contract'
    foreach ($profile in @('high-implementation-starter.toml', 'standard-implementation-completer.toml')) {
        $path = Join-Path $profileRoot $profile
        Assert-Contains $path '(?m)^model\s*=\s*"[^"\r\n]+"\s*$' "Adaptive profile $profile model"
        Assert-Contains $path '(?m)^sandbox_mode\s*=\s*"workspace-write"\s*$' "Adaptive profile $profile sandbox"
    }

    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch 'AGENTS.md')).Hash -ne $agentsHash) {
        throw 'Remote APM install or profile helpers changed AGENTS.md.'
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch '.codex/config.toml')).Hash -ne $configHash) {
        throw 'Remote APM install or profile helpers changed .codex/config.toml.'
    }

    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'pr-review-remediation' 'APM lock direct package entry'
    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'adaptive-implementation-execution' 'APM lock Adaptive dependency entry'
    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'local-reviewer' 'APM lock local reviewer dependency entry'
    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'purpose-reviewer' 'APM lock purpose reviewer dependency entry'
    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'review-planner' 'APM lock review planner dependency entry'

    Write-Output "PR Review Remediation remote APM smoke: PASS"
    Write-Output "Package: $packageSpec"
    Write-Output "APM: $($apmVersion.Trim())"
}
finally {
    if ($null -eq $previousPythonUtf8) { Remove-Item Env:PYTHONUTF8 -ErrorAction SilentlyContinue } else { $env:PYTHONUTF8 = $previousPythonUtf8 }
    if ($null -eq $previousPythonIoEncoding) { Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue } else { $env:PYTHONIOENCODING = $previousPythonIoEncoding }
    if (Test-Path -LiteralPath $scratch) {
        $resolved = [System.IO.Path]::GetFullPath($scratch)
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe scratch path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
