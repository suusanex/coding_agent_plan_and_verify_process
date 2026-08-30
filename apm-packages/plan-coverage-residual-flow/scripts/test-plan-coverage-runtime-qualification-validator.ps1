[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$validatorPath = Join-Path $PSScriptRoot 'validate-plan-coverage-runtime-qualification.ps1'
$resultsRoot = Join-Path $packageRoot 'tests/runtime-qualification/results'
$historicalQualifiedPath = Join-Path $resultsRoot '2026-08-10-copilot-cli.json'
$targetedCurrentPath = Join-Path $resultsRoot '2026-08-11-copilot-cli-pending.json'
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempParent ('plan-coverage-rq-validator-test-' + [Guid]::NewGuid().ToString('N'))

. (Join-Path $PSScriptRoot 'PlanCoverageRuntimeQualification.Common.ps1')

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
    $currentQualificationInputFingerprint = [regex]::Match($ordinaryHistorical.Output, '(?m)^current_qualification_input_fingerprint=([a-f0-9]{64})$').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($currentFingerprint) -or [string]::IsNullOrWhiteSpace($currentPackageVersion) -or [string]::IsNullOrWhiteSpace($currentApmYmlSha256) -or [string]::IsNullOrWhiteSpace($currentQualificationInputFingerprint)) {
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

    $pendingFailure = Get-Content -Raw -LiteralPath $targetedCurrentPath | ConvertFrom-Json
    $pendingFailure.scenarios[0].status = 'FAIL'
    $pendingFailurePath = Join-Path $tempRoot 'pending-failure.json'
    Write-JsonFixture $pendingFailurePath $pendingFailure
    $pendingFailureResult = Invoke-Validator @('-ResultPath', $pendingFailurePath)
    Assert-Result $pendingFailureResult 1 'PENDING evidence scenario DO-001 status is FAIL' 'PENDING evidence rejects a failed targeted scenario'

    $pendingDuplicate = Get-Content -Raw -LiteralPath $targetedCurrentPath | ConvertFrom-Json
    $pendingDuplicate.scenarios = @($pendingDuplicate.scenarios) + @($pendingDuplicate.scenarios[0])
    $pendingDuplicatePath = Join-Path $tempRoot 'pending-duplicate.json'
    Write-JsonFixture $pendingDuplicatePath $pendingDuplicate
    $pendingDuplicateResult = Invoke-Validator @('-ResultPath', $pendingDuplicatePath)
    Assert-Result $pendingDuplicateResult 1 'Duplicate scenario DO-001' 'PENDING evidence rejects duplicate scenario ids'

    $distributionMismatch = Get-Content -Raw -LiteralPath $targetedCurrentPath | ConvertFrom-Json
    $distributionMismatch.distribution_smoke.rationale = 'Tampered rationale.'
    $distributionMismatchPath = Join-Path $tempRoot 'distribution-rationale-mismatch.json'
    Write-JsonFixture $distributionMismatchPath $distributionMismatch
    $distributionMismatchResult = Invoke-Validator @('-ResultPath', $distributionMismatchPath)
    Assert-Result $distributionMismatchResult 1 'result.distribution_smoke.rationale must equal source_run.distribution_smoke.rationale' 'distribution smoke rationale mismatch is rejected'

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
    $exactCurrent | Add-Member -NotePropertyName qualification_input_fingerprint -NotePropertyValue $currentQualificationInputFingerprint
    $exactCurrent.source_run | Add-Member -NotePropertyName qualification_input_fingerprint -NotePropertyValue $currentQualificationInputFingerprint
    foreach ($scenario in @($exactCurrent.scenarios | Where-Object { $_.id -in @('STD-001', 'FULL-001') })) {
        $historicalAdaptiveConnection = $scenario.adaptive_connection
        $scenario.adaptive_connection = [pscustomobject][ordered]@{
            decision_surface_execution          = $historicalAdaptiveConnection.high_execution
            bounded_residual_handoff             = $historicalAdaptiveConnection.handoff
            bounded_residual_execution           = $historicalAdaptiveConnection.standard_execution
            connection_satisfied                 = $historicalAdaptiveConnection.connection_satisfied
            bounded_residual_transfer_satisfied  = $historicalAdaptiveConnection.high_to_standard_handoff_satisfied
            design_pair_auto_selected             = $historicalAdaptiveConnection.design_pair_auto_selected
            decision_surface_observed             = $historicalAdaptiveConnection.high_observed
            bounded_residual_observed             = $historicalAdaptiveConnection.standard_observed
            bounded_residual_handoff_observed     = $historicalAdaptiveConnection.handoff_observed
        }
    }
    $targetedCurrent = Get-Content -Raw -LiteralPath $targetedCurrentPath | ConvertFrom-Json
    $decisionOwnershipScenarios = @($targetedCurrent.scenarios | Where-Object { [string]$_.id -like 'DO-*' })
    $exactCurrent.scenarios = @($exactCurrent.scenarios) + $decisionOwnershipScenarios
    $exactCurrentPath = Join-Path $tempRoot 'synthetic-exact-current.json'
    Write-JsonFixture $exactCurrentPath $exactCurrent
    $strictCurrent = Invoke-Validator @('-ResultPath', $exactCurrentPath, '-RequireQualified')
    Assert-Result $strictCurrent 0 'snapshot_relation=CURRENT_SNAPSHOT' 'strict gate accepts exact-current full evidence fixture'

    $legacyAdaptiveField = Get-Content -Raw -LiteralPath $exactCurrentPath | ConvertFrom-Json
    $legacyAdaptiveField.scenarios[8].adaptive_connection | Add-Member -NotePropertyName high_execution -NotePropertyValue $legacyAdaptiveField.scenarios[8].adaptive_connection.decision_surface_execution
    $legacyAdaptiveFieldPath = Join-Path $tempRoot 'legacy-adaptive-field.json'
    Write-JsonFixture $legacyAdaptiveFieldPath $legacyAdaptiveField
    $legacyAdaptiveFieldResult = Invoke-Validator @('-ResultPath', $legacyAdaptiveFieldPath, '-RequireQualified')
    Assert-Result $legacyAdaptiveFieldResult 1 'adaptive_connection contains historical 0.5 field high_execution' 'strict gate rejects historical Adaptive fields on the current snapshot'

    $staleQualificationInput = Get-Content -Raw -LiteralPath $exactCurrentPath | ConvertFrom-Json
    $staleQualificationInput.qualification_input_fingerprint = '1111111111111111111111111111111111111111111111111111111111111111'
    $staleQualificationInput.source_run.qualification_input_fingerprint = $staleQualificationInput.qualification_input_fingerprint
    $staleQualificationInputPath = Join-Path $tempRoot 'stale-qualification-input.json'
    Write-JsonFixture $staleQualificationInputPath $staleQualificationInput
    $staleQualificationInputResult = Invoke-Validator @('-ResultPath', $staleQualificationInputPath, '-RequireQualified')
    Assert-Result $staleQualificationInputResult 1 'No full QUALIFIED evidence matches the current canonical fingerprint' 'strict gate rejects stale runtime dependency identity'

    $inputFixtureRoot = Join-Path $tempRoot 'qualification-input-repository'
    foreach ($relativePath in @(Get-QualificationInputRelativePaths $repoRoot)) {
        $sourcePath = Join-Path $repoRoot $relativePath
        $destinationPath = Join-Path $inputFixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
    $copiedInputFingerprint = Get-PlanCoverageQualificationInputFingerprint $inputFixtureRoot
    if ($copiedInputFingerprint -cne $currentQualificationInputFingerprint) {
        throw 'Copied qualification input fingerprint does not match the repository input fingerprint.'
    }
    [System.IO.File]::WriteAllText((Join-Path $inputFixtureRoot 'README.md'), "Unrelated parent repository change.`n", [System.Text.UTF8Encoding]::new($false))
    if ((Get-PlanCoverageQualificationInputFingerprint $inputFixtureRoot) -cne $copiedInputFingerprint) {
        throw 'Unrelated repository content must not change qualification input fingerprint.'
    }
    $adaptiveSkillPath = Join-Path $inputFixtureRoot 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md'
    $adaptiveSkillText = [System.IO.File]::ReadAllText($adaptiveSkillPath)
    [System.IO.File]::WriteAllText($adaptiveSkillPath, $adaptiveSkillText + "`nqualification-input-test`n", [System.Text.UTF8Encoding]::new($false))
    if ((Get-PlanCoverageQualificationInputFingerprint $inputFixtureRoot) -ceq $copiedInputFingerprint) {
        throw 'Adaptive runtime input change must change qualification input fingerprint.'
    }
    Write-Host 'PASS: qualification input fingerprint tracks runtime dependencies only'

    $reevaluationPathsFirst = Get-ReevaluationOutputPaths $targetedCurrentPath
    $reevaluationPathsSecond = Get-ReevaluationOutputPaths $reevaluationPathsFirst.JsonPath
    if ($reevaluationPathsFirst.JsonPath -cne $reevaluationPathsSecond.JsonPath -or $reevaluationPathsFirst.JsonPath -cne [System.IO.Path]::GetFullPath($targetedCurrentPath)) {
        throw 'Repeated re-evaluation must replace the same source-run result path.'
    }
    Write-Host 'PASS: repeated re-evaluation keeps one canonical result path'

    if (-not (Test-QualificationCommandSucceeded 'PENDING') -or (Test-QualificationCommandSucceeded 'FAIL')) {
        throw 'Targeted all-PASS PENDING must succeed and FAIL must return failure.'
    }
    Write-Host 'PASS: targeted all-PASS PENDING is a successful command result'

    $runnerText = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'run-plan-coverage-copilot-qualification.ps1'))
    foreach ($requiredRunnerContract in @(
            '$outputPaths = Get-ReevaluationOutputPaths $existingResultPath',
            'if (-not (Test-QualificationCommandSucceeded $overall))'
        )) {
        if (-not $runnerText.Contains($requiredRunnerContract, [StringComparison]::Ordinal)) {
            throw "Runner missing tested qualification contract: $requiredRunnerContract"
        }
    }
    Write-Host 'PASS: runner uses canonical re-evaluation path and targeted success contract'

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
