[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[^/]+/[^/]+$')][string]$Repository,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Ref,
    [string]$UpdateRef,
    [string]$ApmExecutable = 'apm'
)

$ErrorActionPreference = 'Stop'
$tempRoot = [System.IO.Path]::GetTempPath()
$env:DOTNET_CLI_HOME = Join-Path $tempRoot 'apm-global-smoke-dotnet-home'
$env:NUGET_PACKAGES = Join-Path $tempRoot 'apm-global-smoke-nuget-packages'
$env:NUGET_HTTP_CACHE_PATH = Join-Path $tempRoot 'apm-global-smoke-nuget-http-cache'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$smoke = Join-Path $repoRoot 'scripts/validate-apm-global-package-smoke.cs'
$smokeArguments = @('--package', 'persistent-purpose-review', '--repository', $Repository, '--ref', $Ref)
if (-not [string]::IsNullOrWhiteSpace($UpdateRef)) { $smokeArguments += @('--update-ref', $UpdateRef) }
$smokeArguments += @('--apm', $ApmExecutable)
& dotnet run --file $smoke -- @smokeArguments
if ($LASTEXITCODE -ne 0) {
    throw "Persistent Purpose Review global APM smoke failed with exit code $LASTEXITCODE."
}
