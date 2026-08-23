[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $PSScriptRoot 'validate-plan-coverage-runtime-qualification.ps1'
$resultsRoot = Join-Path $packageRoot 'tests/runtime-qualification/results'
$historicalQualifiedPath = Join-Path $resultsRoot '2026-08-10-copilot-cli.json'
$targetedCurrentPath = Join-Path $resultsRoot '2026-08-11-copilot-cli-pending.json'
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempParent ('plan-coverage-rq-validator-test-' + [Guid]::NewGuid().ToString('N'))

function Invoke-Validator([string[]]$Arguments) {
    $output = @(& pwsh -NoProfile -File $validatorPath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join "`n")
    }
}

function Assert-Result($Actual, [int]$ExpectedExitCode, [string]$ExpectedText, [string]$CaseName) {
    if ($Actual.ExitCode -ne $ExpectedExitCode) {
        throw "$CaseName exit code $($Actual.ExitCode), expected $ExpectedExitCode.`n$($Actual.Output)"
    }
    if ($Actual.Output -cnotmatch [regex]::Escape($ExpectedText)) {
        throw "$CaseName output did not contain '$ExpectedText'.`n$($Actual.Output)"
    }
    Write-Host "PASS: $CaseName"
}

function Write-JsonFixture([string]$Path, $Value) {
    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $ordinaryHistorical = Invoke-Validator @('-ResultPath', $historicalQualifiedPath)
    Assert-Result $ordinaryHistorical 0 'snapshot_relation=HISTORICAL_BASELINE' 'historical QUALIFIED mismatch is valid in ordinary mode'

    $currentFingerprint = [regex]::Match($ordinaryHistorical.Output, '(?m)^current_canonical_fingerprint=([a-f0-9]{64})$').Groups[1].Value
    $currentPackageVersion = [regex]::Match($ordinaryHistorical.Output, '(?m)^current_package_version=(\S+)$').Groups[1].Value
    $currentApmYmlSha256 = [regex]::Match($ordinaryHistorical.Output, '(?m)^current_apm_yml_sha256=([a-f0-9]{64})$').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($currentFingerprint) -or [string]::IsNullOrWhiteSpace($currentPackageVersion) -or [string]::IsNullOrWhiteSpace($currentApmYmlSha256)) {
        throw 'Unable to read current snapshot identity from validator output.'
    }

    $metadataMismatch = Get-Content -Raw -LiteralPath $historicalQualifiedPath | ConvertFrom-Json
    $metadataMismatch.plan_coverage_package_version = '9.9.9-test-mismatch'
    $metadataMismatchPath = Join-Path $tempRoot 'metadata-mismatch.json'
    Write-JsonFixture $metadataMismatchPath $metadataMismatch
    $metadataMismatchResult = Invoke-Validator @('-ResultPath', $metadataMismatchPath)
    Assert-Result $metadataMismatchResult 1 'result.plan_coverage_package_version must equal source_run.package_version' 'internally inconsistent package metadata is rejected'

    $rebound = Get-Content -Raw -LiteralPath $historicalQualifiedPath | ConvertFrom-Json
    $rebound.canonical_fingerprint = $currentFingerprint
    $reboundPath = Join-Path $tempRoot 'forged-rebound.json'
    Write-JsonFixture $reboundPath $rebound
    $reboundResult = Invoke-Validator @('-ResultPath', $reboundPath)
    Assert-Result $reboundResult 1 'result.canonical_fingerprint must equal source_run.canonical_fingerprint' 'top-level fingerprint re-bind is rejected'

    $strictWithoutFull = Invoke-Validator @('-ResultPath', $targetedCurrentPath, '-RequireQualified')
    Assert-Result $strictWithoutFull 1 'No full QUALIFIED evidence matches the current canonical fingerprint' 'strict gate rejects targeted-only current evidence'

    # strict gateの挙動だけを検証する合成fixtureであり、runtime evidenceとしてはcommitしない。
    $exactCurrent = Get-Content -Raw -LiteralPath $historicalQualifiedPath | ConvertFrom-Json
    $exactCurrent.canonical_fingerprint = $currentFingerprint
    $exactCurrent.source_run.canonical_fingerprint = $currentFingerprint
    $exactCurrent.plan_coverage_package_version = $currentPackageVersion
    $exactCurrent.source_run.package_version = $currentPackageVersion
    $exactCurrent.apm_yml_sha256 = $currentApmYmlSha256
    $exactCurrent.source_run.apm_yml_sha256 = $currentApmYmlSha256
    $targetedCurrent = Get-Content -Raw -LiteralPath $targetedCurrentPath | ConvertFrom-Json
    $decisionOwnershipScenarios = @($targetedCurrent.scenarios | Where-Object { [string]$_.id -like 'DO-*' })
    $exactCurrent.scenarios = @($exactCurrent.scenarios) + $decisionOwnershipScenarios
    $exactCurrentPath = Join-Path $tempRoot 'synthetic-exact-current.json'
    Write-JsonFixture $exactCurrentPath $exactCurrent
    $strictCurrent = Invoke-Validator @('-ResultPath', $exactCurrentPath, '-RequireQualified')
    Assert-Result $strictCurrent 0 'snapshot_relation=CURRENT_SNAPSHOT' 'strict gate accepts exact-current full evidence fixture'

    $allCommitted = Invoke-Validator @()
    Assert-Result $allCommitted 0 'Plan Coverage runtime qualification validator: PASS (ordinary evidence integrity)' 'ordinary CI validates every committed evidence file'

    $global:LASTEXITCODE = 0
    Write-Host 'Plan Coverage runtime qualification validator tests: PASS'
}
finally {
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolvedTempRoot.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTempRoot).StartsWith('plan-coverage-rq-validator-test-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
