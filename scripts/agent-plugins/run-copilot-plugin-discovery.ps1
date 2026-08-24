[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [string]$CopilotExecutable = 'copilot',
    [string]$ApmExecutable = 'apm'
)

$ErrorActionPreference = 'Stop'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$output = Join-Path $tempRoot ('copilot-plugin-discovery-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $tempRoot ('copilot-plugin-fixture-' + [guid]::NewGuid().ToString('N'))
$safeOutput = $false
$safeFixture = $false
try {
    $null = New-Item -ItemType Directory -Path $output -Force
    $null = New-Item -ItemType Directory -Path $fixture -Force
    $resolvedOutput = (Resolve-Path -LiteralPath $output).Path
    $resolvedFixture = (Resolve-Path -LiteralPath $fixture).Path
    if (-not $resolvedOutput.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe discovery fixture path.' }
    $safeOutput = $true
    $safeFixture = $true
    $json = & (Join-Path $PSScriptRoot 'build-agent-plugin.ps1') -Package $Package -OutputDirectory $resolvedOutput -ApmExecutable $ApmExecutable -Json | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Plugin build failed: $Package" }
    $build = $json | ConvertFrom-Json
    Push-Location -LiteralPath $resolvedFixture
    try {
        $copilotArgs = @('--plugin-dir', [string]$build.bundleRoot, 'plugin', 'list')
        $result = & $CopilotExecutable @copilotArgs 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Copilot plugin discovery failed for $Package`n$(($result | ForEach-Object { [string]$_ }) -join "`n")" }
        $text = ($result | ForEach-Object { [string]$_ }) -join "`n"
        if ($text -notmatch [regex]::Escape($Package)) { throw "Copilot plugin list did not report $Package" }
    }
    finally { Pop-Location }
    Write-Output "Copilot plugin discovery: PASS ($Package)"
}
finally {
    if ($safeOutput -and (Test-Path -LiteralPath $output)) { Remove-Item -LiteralPath $output -Recurse -Force }
    if ($safeFixture -and (Test-Path -LiteralPath $fixture)) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
