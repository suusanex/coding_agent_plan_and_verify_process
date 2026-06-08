param(
    [string]$RepoPath = (Get-Location).Path,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs = @("status")
)

$ErrorActionPreference = "Stop"

$packageRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$profileHome = Resolve-Path (Join-Path $packageRoot "profiles\codex-first")
$runtimeHome = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-first-profile-runtime-" + [guid]::NewGuid().ToString("N"))
$previousCodexHome = $env:CODEX_HOME
$locationPushed = $false

try {
    New-Item -ItemType Directory -Force $runtimeHome | Out-Null
    Copy-Item -Recurse -Force (Join-Path $profileHome.Path "*") $runtimeHome

    $runtimeSkill = Join-Path $runtimeHome "skills\codex-first-cost-router"
    New-Item -ItemType Directory -Force $runtimeSkill | Out-Null
    Copy-Item -Recurse -Force (Join-Path $packageRoot ".apm\skills\codex-first-cost-router\*") $runtimeSkill

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
