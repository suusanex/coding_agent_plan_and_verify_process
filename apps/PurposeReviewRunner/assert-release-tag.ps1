[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RunnerPath,

    [Parameter(Mandatory)]
    [string]$Tag
)

$ErrorActionPreference = 'Stop'
$resolvedRunner = (Resolve-Path -LiteralPath $RunnerPath -ErrorAction Stop).Path
$output = @(& $resolvedRunner version)
if ($LASTEXITCODE -ne 0) {
    throw "purpose-review-runner version failed with exit code $LASTEXITCODE."
}

$lines = @($output | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($lines.Count -ne 1) {
    throw "purpose-review-runner version must write exactly one JSON object to stdout."
}

try {
    $version = $lines[0] | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "purpose-review-runner version returned invalid JSON: $($_.Exception.Message)"
}

if ($version.protocolVersion -ne 3 -or [string]::IsNullOrWhiteSpace([string]$version.runnerVersion)) {
    throw 'purpose-review-runner version returned an incompatible protocol response.'
}

$expectedTag = "purpose-review-runner-v$($version.runnerVersion)"
if ($Tag -cne $expectedTag) {
    throw "Release tag '$Tag' does not match Runner version '$($version.runnerVersion)'. Expected '$expectedTag'."
}

Write-Output "Release tag matches Runner version: $Tag"
