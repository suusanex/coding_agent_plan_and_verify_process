param(
    [string]$RepoPath = (Get-Location).Path,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs = @("status")
)

$ErrorActionPreference = "Stop"

$packageRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$repositoryRoot = Resolve-Path (Join-Path $packageRoot "..\..")
$profileHome = Resolve-Path (Join-Path $packageRoot "profiles\codex-first")
$adaptiveSkillSource = Resolve-Path (Join-Path $repositoryRoot "apm-packages\adaptive-implementation-execution\.apm\skills\adaptive-implementation-execution")
$designPairSkillSource = Resolve-Path (Join-Path $repositoryRoot "apm-packages\design-pair-implementation-execution\.apm\skills\design-pair-implementation-execution")
$runtimeHome = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-first-profile-runtime-" + [guid]::NewGuid().ToString("N"))
$previousCodexHome = $env:CODEX_HOME
$locationPushed = $false

try {
    New-Item -ItemType Directory -Force $runtimeHome | Out-Null
    Copy-Item -Recurse -Force (Join-Path $profileHome.Path "*") $runtimeHome

    $runtimeSkill = Join-Path $runtimeHome "skills\codex-first-cost-router"
    New-Item -ItemType Directory -Force $runtimeSkill | Out-Null
    Copy-Item -Recurse -Force (Join-Path $packageRoot ".apm\skills\codex-first-cost-router\*") $runtimeSkill

    $runtimeAdaptiveSkill = Join-Path $runtimeHome "skills\adaptive-implementation-execution"
    New-Item -ItemType Directory -Force $runtimeAdaptiveSkill | Out-Null
    Copy-Item -Recurse -Force (Join-Path $adaptiveSkillSource.Path "*") $runtimeAdaptiveSkill

    $runtimeDesignPairSkill = Join-Path $runtimeHome "skills\design-pair-implementation-execution"
    New-Item -ItemType Directory -Force $runtimeDesignPairSkill | Out-Null
    Copy-Item -Recurse -Force (Join-Path $designPairSkillSource.Path "*") $runtimeDesignPairSkill

    $runtimeTemplates = Join-Path $runtimeHome "templates"
    New-Item -ItemType Directory -Force $runtimeTemplates | Out-Null
    Copy-Item -Recurse -Force (Join-Path $packageRoot "templates\*") $runtimeTemplates

    $env:CODEX_HOME = $runtimeHome

    Push-Location $RepoPath
    $locationPushed = $true
    & codex @CodexArgs
}
finally {
    if ($locationPushed) {
        Pop-Location
    }

    if ($null -eq $previousCodexHome) {
        Remove-Item Env:\CODEX_HOME -ErrorAction SilentlyContinue
    }
    else {
        $env:CODEX_HOME = $previousCodexHome
    }

    if (Test-Path $runtimeHome) {
        try {
            Remove-Item -Recurse -Force $runtimeHome
        }
        catch {
            Write-Warning "Failed to remove temporary Codex-first profile runtime: $runtimeHome"
        }
    }
}
