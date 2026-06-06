param(
    [string]$RepoPath = (Get-Location).Path,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs = @("status")
)

$ErrorActionPreference = "Stop"

$packageRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$profileHome = Resolve-Path (Join-Path $packageRoot "profiles\codex-first")

$env:CODEX_HOME = $profileHome.Path

Push-Location $RepoPath
try {
    & codex @CodexArgs
}
finally {
    Pop-Location
}
