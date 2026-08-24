[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [string]$OutputDirectory,
    [string]$ApmExecutable = 'apm',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentPlugin.Common.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$packageRoot = Join-Path $repoRoot "apm-packages/$Package"
if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) { throw "Unknown package: $Package" }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('agent-plugin-output-' + [guid]::NewGuid().ToString('N'))
}

$result = Invoke-AgentPluginBuild -PackageRoot $packageRoot -OutputDirectory $OutputDirectory -ApmExecutable $ApmExecutable
if ($Json) { $result | ConvertTo-Json -Depth 100 }
else {
    Write-Output "package=$($result.package)"
    Write-Output "version=$($result.version)"
    Write-Output "bundle_root=$($result.bundleRoot)"
    Write-Output "canonical_fingerprint=$($result.canonicalFingerprint)"
    Write-Output "file_count=$(@($result.bundleFiles.Keys).Count)"
}
