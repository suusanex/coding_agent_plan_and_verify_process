[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[^/]+/[^/]+$')][string]$Repository,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Ref,
    [string]$ApmExecutable = 'apm'
)

$ErrorActionPreference = 'Stop'
$tempRoot = [System.IO.Path]::GetTempPath()
$env:DOTNET_CLI_HOME = Join-Path $tempRoot 'apm-global-smoke-dotnet-home'
$env:NUGET_PACKAGES = Join-Path $tempRoot 'apm-global-smoke-nuget-packages'
$env:NUGET_HTTP_CACHE_PATH = Join-Path $tempRoot 'apm-global-smoke-nuget-http-cache'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$smoke = Join-Path $repoRoot 'scripts/validate-apm-global-package-smoke.cs'
& dotnet run --file $smoke -- --package adaptive-implementation-execution --repository $Repository --ref $Ref --apm $ApmExecutable
if ($LASTEXITCODE -ne 0) {
    throw "Adaptive global APM smoke failed with exit code $LASTEXITCODE."
}
