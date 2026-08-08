[CmdletBinding()]
param(
    [string]$InstalledRoot
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$fixtureRoot = Join-Path $packageRoot 'tests/full-coverage-standalone/PCF-001'
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempParent ('plan-coverage-full-coverage-e2e-' + [Guid]::NewGuid().ToString('N'))

function Get-NormalizedText([string]$Path) {
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Find-OneFile([string]$Root, [string]$Leaf, [string]$Purpose) {
    $matches = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Leaf)
    if ($matches.Count -ne 1) {
        throw "$Purpose must resolve to exactly one '$Leaf' file under $Root; found $($matches.Count)."
    }
    return $matches[0].FullName
}

function Resolve-ContractAuthority {
    $agentLeaves = @(
        'plan-kernel.agent.md',
        'black-box-behavior-spec-kernel.agent.md',
        'change-risk-triage.agent.md',
        'architecture-slice-readiness.agent.md',
        'architecture-elaboration.agent.md',
        'plan-slice-decomposition.agent.md',
        'runtime-contract-kernel.agent.md',
        'test-design-kernel.agent.md',
        'implementation-handoff-review.agent.md',
        'verification-kernel.agent.md',
        'cross-slice-verification-kernel.agent.md',
        'coverage-gap-triage.agent.md',
        'residual-decision-gate.agent.md',
        'coverage-gap-resolution-slice.agent.md',
        'implementation-contract-kernel.agent.md',
        'implementation-contract-review-kernel.agent.md',
        'code-review-focus-kernel.agent.md',
        'implementation-execution.agent.md',
        'high-implementation-starter.agent.md',
        'standard-implementation-completer.agent.md'
    )

    if ([string]::IsNullOrWhiteSpace($InstalledRoot)) {
        $files = [ordered]@{
            PlanCoverageSkill = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/SKILL.md'
            CoverageLedger = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md'
            PlanCoverageLite = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/references/plan-coverage-lite.md'
            SliceArchitecture = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/references/slice-architecture.md'
            SharedInstructions = Join-Path $repoRoot '.github/instructions/plan-coverage-shared.instructions.md'
            AdaptiveSkill = Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md'
        }
        foreach ($leaf in $agentLeaves) {
            $files[$leaf] = Join-Path $repoRoot ".github/agents/$leaf"
        }
    }
    else {
        $resolvedInstalledRoot = (Resolve-Path -LiteralPath $InstalledRoot).Path
        $files = [ordered]@{
            PlanCoverageSkill = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/SKILL.md'
            CoverageLedger = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/references/coverage-ledger.md'
            PlanCoverageLite = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/references/plan-coverage-lite.md'
            SliceArchitecture = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/references/slice-architecture.md'
            SharedInstructions = Find-OneFile $resolvedInstalledRoot 'plan-coverage-shared.instructions.md' 'installed shared instructions'
            AdaptiveSkill = Join-Path $resolvedInstalledRoot '.agents/skills/adaptive-implementation-execution/SKILL.md'
        }
        foreach ($leaf in $agentLeaves) {
            $files[$leaf] = Find-OneFile $resolvedInstalledRoot $leaf "installed agent $leaf"
        }
    }

    foreach ($entry in $files.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
            throw "Contract authority '$($entry.Key)' is missing: $($entry.Value)"
        }
    }
    return $files
}

function Get-FixtureErrors([string]$Root) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $expectedPath = Join-Path $Root 'expected.json'
    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
        $errors.Add('expected.json is missing.')
        return $errors
    }

    try {
        $expected = Get-Content -Raw -LiteralPath $expectedPath | ConvertFrom-Json
    }
    catch {
        $errors.Add("expected.json is invalid: $($_.Exception.Message)")
        return $errors
    }

    $expectedStages = 'ReadyForRiskTriage,full-coverage,ReadyForSliceDecomposition,SL-001,SL-002,CROSS_SLICE_VERIFIED,READY_TO_CLOSE_WITH_NO_RESIDUALS'
    if ((@($expected.stage_order) -join ',') -cne $expectedStages) {
        $errors.Add('Stage order must run readiness, full-coverage, decomposition, both slices, cross-slice verification, and residual decision in order.')
    }
    if (@($expected.slices).Count -ne 2 -or $expected.slices[0].id -cne 'SL-001' -or $expected.slices[1].id -cne 'SL-002') {
        $errors.Add('The fixture must define exactly SL-001 followed by SL-002.')
    }
    elseif (@($expected.slices[0].depends_on).Count -ne 0 -or (@($expected.slices[1].depends_on) -join ',') -cne 'SL-001') {
        $errors.Add('SL-002 must depend on SL-001, and SL-001 must have no slice dependency.')
    }

    $declaredPaths = @(
        'README.md',
        'plans/pcf-001.md',
        'plans/pcf-001-black-box-behavior-spec.md',
        'plans/pcf-001-change-risk-triage.md',
        'plans/pcf-001-architecture-slice-readiness.md',
        'plans/pcf-001-slice-architecture.md',
        'plans/pcf-001-slice-decomposition.md',
        [string]$expected.cross_slice_artifact,
        [string]$expected.residual_artifact,
        [string]$expected.coverage_ledger
    )
    foreach ($slice in @($expected.slices)) {
        $declaredPaths += @(
            [string]$slice.plan,
            [string]$slice.runtime_contract,
            [string]$slice.test_design,
            [string]$slice.handoff,
            [string]$slice.implementation,
            [string]$slice.verification
        )
        if (-not (Test-Path -LiteralPath (Join-Path $Root ([string]$slice.payload)) -PathType Container)) {
            $errors.Add("Payload is missing for $($slice.id): $($slice.payload)")
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Root "seed/$($slice.verifier)") -PathType Leaf)) {
            $errors.Add("Runtime verifier is missing for $($slice.id): $($slice.verifier)")
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Root "seed/$($expected.cross_slice_verifier)") -PathType Leaf)) {
        $errors.Add("Cross-slice runtime verifier is missing: $($expected.cross_slice_verifier)")
    }
    $productionBindingExists = @($expected.slices | Where-Object {
        Test-Path -LiteralPath (Join-Path $Root "$($_.payload)/$($expected.production_entrypoint)") -PathType Leaf
    }).Count -gt 0
    if (-not $productionBindingExists) {
        $errors.Add("Production entrypoint is not supplied by any slice payload: $($expected.production_entrypoint)")
    }

    foreach ($relativePath in $declaredPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
            $errors.Add("Declared fixture file is missing: $relativePath")
        }
    }
    if ($errors.Count -gt 0) {
        return $errors
    }

    $parentPlan = Get-NormalizedText (Join-Path $Root 'plans/pcf-001.md')
    $readiness = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-architecture-slice-readiness.md')
    $decomposition = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-slice-decomposition.md')
    $ledger = Get-NormalizedText (Join-Path $Root ([string]$expected.coverage_ledger))
    $cross = Get-NormalizedText (Join-Path $Root ([string]$expected.cross_slice_artifact))
    $residual = Get-NormalizedText (Join-Path $Root ([string]$expected.residual_artifact))

    if ($parentPlan -cnotmatch '`ReadyForRiskTriage`') { $errors.Add('Parent Plan must be ReadyForRiskTriage.') }
    if ((Get-NormalizedText (Join-Path $Root 'plans/pcf-001-change-risk-triage.md')) -cnotmatch 'Selected route: `full-coverage`') { $errors.Add('Risk triage must select full-coverage.') }
    if ($readiness -cnotmatch 'Readiness verdict: `ReadyForSliceDecomposition`') { $errors.Add('Readiness must authorize slice decomposition.') }
    if ($readiness -cnotmatch 'Architecture Elaboration: `N/A`' -or $readiness -cnotmatch 'Baseline authority: current Slice Architecture') { $errors.Add('The happy path must use the current Slice Architecture without Architecture Elaboration.') }
    if ($decomposition -cnotmatch '\| 2 \| `SL-002` \| `SL-001` \|') { $errors.Add('Decomposition must preserve the two-slice dependency order.') }

    $allIds = @($expected.requirement_ids) + @($expected.acceptance_ids) + @($expected.case_ids) + @($expected.cross_cutting_ids)
    foreach ($id in $allIds) {
        $quotedId = ('`{0}`' -f $id)
        $ledgerPrefix = ('| `{0}` |' -f $id)
        if ($parentPlan -cnotmatch [regex]::Escape($quotedId)) { $errors.Add("Parent Plan does not define $id.") }
        if ($ledger -cnotmatch [regex]::Escape($ledgerPrefix)) { $errors.Add("Coverage Ledger does not classify $id.") }
        if ($cross -cnotmatch [regex]::Escape($quotedId)) { $errors.Add("Cross-slice verification does not trace $id.") }
    }

    foreach ($slice in @($expected.slices)) {
        $handoff = Get-NormalizedText (Join-Path $Root ([string]$slice.handoff))
        $implementation = Get-NormalizedText (Join-Path $Root ([string]$slice.implementation))
        $verification = Get-NormalizedText (Join-Path $Root ([string]$slice.verification))
        if ($handoff -cnotmatch 'Standard pre-implementation gates: complete' -or $handoff -cnotmatch 'Architecture baseline compatibility: `Match`') {
            $errors.Add("$($slice.id) must complete pre-implementation gates and record architecture Match.")
        }
        if ($handoff -cmatch 'Architecture baseline compatibility: `(?:Drift|Unclear)`') {
            $errors.Add("$($slice.id) architecture Drift or Unclear must fail closed.")
        }
        if ($implementation -cnotmatch 'default Adaptive Implementation' -or $implementation -cnotmatch 'Handoff architecture verdict consumed: `Match`') {
            $errors.Add("$($slice.id) must consume Match through Adaptive Implementation.")
        }
        if ($verification -cnotmatch 'Slice verdict: `SLICE_VERIFIED`') {
            $errors.Add("$($slice.id) independent verification verdict is missing.")
        }
    }

    if ($cross -cnotmatch 'Production entrypoint: `src/StartupFlow\.ps1`' -or $cross -cnotmatch 'Final verdict: `CROSS_SLICE_VERIFIED`') {
        $errors.Add('Cross-slice verification must exercise the production entrypoint and emit CROSS_SLICE_VERIFIED.')
    }
    if ($residual -cnotmatch 'Cross-slice source verdict: `CROSS_SLICE_VERIFIED`' -or $residual -cnotmatch 'Final verdict: `READY_TO_CLOSE_WITH_NO_RESIDUALS`') {
        $errors.Add('Residual Decision must consume CROSS_SLICE_VERIFIED before closing with no residuals.')
    }
    if ($ledger -cnotmatch 'Fake-only evidence: none' -or $ledger -cnotmatch 'Unclassified items: none' -or $ledger -cnotmatch 'Blocking residuals: none') {
        $errors.Add('Coverage Ledger must leave no fake-only evidence, unclassified items, or blocking residuals.')
    }
    foreach ($id in $allIds) {
        $ledgerPrefix = ('| `{0}` |' -f $id)
        $ledgerLine = @($ledger -split "`n" | Where-Object { $_ -cmatch [regex]::Escape($ledgerPrefix) })
        if ($ledgerLine.Count -ne 1 -or $ledgerLine[0] -cnotmatch 'implemented-and-verified') {
            $errors.Add("Coverage Ledger must mark $id implemented-and-verified exactly once.")
        }
    }

    $forbiddenPatterns = @(
        'token-aware-full-coverage-3layer',
        'compact-slice-record-v2',
        'Parent Orchestration State',
        'Parent Authorization',
        'full-coverage-parent-orchestration-state',
        'full-coverage-slice-record',
        'slice-prep\.agent\.md',
        'slice-impl'
    )
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File) {
        $text = Get-NormalizedText $file.FullName
        foreach ($pattern in $forbiddenPatterns) {
            if ($text -cmatch $pattern) {
                $errors.Add("Removed full-coverage dependency '$pattern' is present in $($file.FullName.Substring($Root.Length + 1)).")
            }
        }
    }

    return $errors
}

function Assert-FixtureValid([string]$Root, [string]$Context) {
    $errors = @(Get-FixtureErrors $Root)
    if ($errors.Count -gt 0) {
        throw "$Context failed fixture validation:`n- $($errors -join "`n- ")"
    }
}

function Assert-NegativeMutationFails([string]$Name, [scriptblock]$Mutate) {
    $caseRoot = Join-Path $tempRoot "negative-$Name"
    Copy-Item -LiteralPath $fixtureRoot -Destination $caseRoot -Recurse
    & $Mutate $caseRoot
    $errors = @(Get-FixtureErrors $caseRoot)
    if ($errors.Count -eq 0) {
        throw "Negative fixture '$Name' did not fail closed."
    }
}

function Invoke-FixtureVerifier([string]$ConsumerRoot, [string]$RelativePath) {
    $output = @(& pwsh -NoProfile -File (Join-Path $ConsumerRoot $RelativePath))
    if ($LASTEXITCODE -ne 0) {
        throw "Fixture verifier '$RelativePath' failed with exit code $LASTEXITCODE."
    }
    if ($output.Count -eq 0) {
        throw "Fixture verifier '$RelativePath' returned no evidence."
    }
    return ($output[-1] | ConvertFrom-Json)
}

try {
    if (-not (Test-Path -LiteralPath $fixtureRoot -PathType Container)) {
        throw "PCF-001 fixture is missing: $fixtureRoot"
    }
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $authority = Resolve-ContractAuthority
    $authorityText = @($authority.Values | ForEach-Object { Get-NormalizedText $_ }) -join "`n"
    $requiredContractPatterns = @(
        'ReadyForSliceDecomposition',
        'Architecture baseline compatibility',
        'Only a current-baseline `Match` may proceed',
        'plan-slice-decomposition',
        'cross-slice-verification-kernel',
        'residual-decision-gate',
        'Adaptive Implementation'
    )
    foreach ($pattern in $requiredContractPatterns) {
        if ($authorityText -cnotmatch [regex]::Escape($pattern)) {
            throw "Contract authority does not contain required full-coverage expression: $pattern"
        }
    }
    foreach ($pattern in @('token-aware-full-coverage-3layer', 'compact-slice-record-v2', 'Parent Orchestration State', 'Parent Authorization', 'full-coverage-parent-orchestration-state', 'full-coverage-slice-record', 'slice-prep\.agent\.md', 'slice-impl')) {
        if ($authorityText -cmatch $pattern) {
            throw "Contract authority contains removed full-coverage dependency: $pattern"
        }
    }

    Assert-FixtureValid $fixtureRoot 'PCF-001'

    Assert-NegativeMutationFails 'missing-sl-002-verification' {
        param($root)
        Remove-Item -LiteralPath (Join-Path $root 'plans/pcf-001-slice-SL-002-verification-kernel.md') -Force
    }
    foreach ($verdict in @('Drift', 'Unclear')) {
        Assert-NegativeMutationFails "architecture-$($verdict.ToLowerInvariant())" {
            param($root)
            $path = Join-Path $root 'plans/pcf-001-slice-SL-002-implementation-handoff-review.md'
            [System.IO.File]::WriteAllText($path, (Get-NormalizedText $path).Replace('Architecture baseline compatibility: `Match`', "Architecture baseline compatibility: ``$verdict``"), [System.Text.UTF8Encoding]::new($false))
        }.GetNewClosure()
    }
    Assert-NegativeMutationFails 'missing-production-binding' {
        param($root)
        $path = Join-Path $root 'expected.json'
        [System.IO.File]::WriteAllText($path, (Get-NormalizedText $path).Replace('src/StartupFlow.ps1', 'src/MissingStartupFlow.ps1'), [System.Text.UTF8Encoding]::new($false))
    }
    Assert-NegativeMutationFails 'missing-cross-slice-verdict' {
        param($root)
        $path = Join-Path $root 'plans/pcf-001-cross-slice-verification-kernel.md'
        [System.IO.File]::WriteAllText($path, (Get-NormalizedText $path).Replace('`CROSS_SLICE_VERIFIED`', '`CROSS_SLICE_PENDING`'), [System.Text.UTF8Encoding]::new($false))
    }
    Assert-NegativeMutationFails 'residual-before-cross-slice' {
        param($root)
        $path = Join-Path $root 'expected.json'
        $text = Get-NormalizedText $path
        $text = $text -replace '"CROSS_SLICE_VERIFIED",\s*"READY_TO_CLOSE_WITH_NO_RESIDUALS"', "`"READY_TO_CLOSE_WITH_NO_RESIDUALS`",`n    `"CROSS_SLICE_VERIFIED`""
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    }
    Assert-NegativeMutationFails 'removed-dependency-reference' {
        param($root)
        $path = Join-Path $root 'README.md'
        [System.IO.File]::AppendAllText($path, "`nRemoved dependency regression token: token-aware-full-coverage-3layer`n", [System.Text.UTF8Encoding]::new($false))
    }

    $expected = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'expected.json') | ConvertFrom-Json
    $consumerRoot = Join-Path $tempRoot 'consumer'
    New-Item -ItemType Directory -Path $consumerRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $fixtureRoot 'seed/*') -Destination $consumerRoot -Recurse -Force

    $slice1 = $expected.slices[0]
    Copy-Item -Path (Join-Path $fixtureRoot "$($slice1.payload)/*") -Destination $consumerRoot -Recurse -Force
    if (Test-Path -LiteralPath (Join-Path $consumerRoot 'src/StartupFlow.ps1')) {
        throw 'SL-002 production binding appeared before SL-001 verification.'
    }
    $slice1Evidence = Invoke-FixtureVerifier $consumerRoot ([string]$slice1.verifier)
    if ($slice1Evidence.slice -cne 'SL-001' -or $slice1Evidence.verdict -cne 'SLICE_VERIFIED' -or $slice1Evidence.snapshot_state -cne 'Active' -or $slice1Evidence.correlation_id -cne 'pcf-001') {
        throw 'SL-001 runtime evidence does not match the expected postcondition.'
    }

    $slice2 = $expected.slices[1]
    Copy-Item -Path (Join-Path $fixtureRoot "$($slice2.payload)/*") -Destination $consumerRoot -Recurse -Force
    $slice2Evidence = Invoke-FixtureVerifier $consumerRoot ([string]$slice2.verifier)
    if ($slice2Evidence.slice -cne 'SL-002' -or $slice2Evidence.verdict -cne 'SLICE_VERIFIED' -or $slice2Evidence.consumer_state -cne 'Accepting' -or $slice2Evidence.postcondition -cne 'Accepted' -or -not $slice2Evidence.reject_observed) {
        throw 'SL-002 runtime evidence does not match the expected accepting and rejecting postconditions.'
    }

    $crossEvidence = Invoke-FixtureVerifier $consumerRoot ([string]$expected.cross_slice_verifier)
    if ($crossEvidence.verdict -cne 'CROSS_SLICE_VERIFIED' -or $crossEvidence.production_entrypoint -cne 'src/StartupFlow.ps1' -or $crossEvidence.postcondition -cne 'Accepted' -or $crossEvidence.correlation_id -cne 'pcf-001' -or -not $crossEvidence.reject_observed) {
        throw 'Cross-slice runtime evidence does not match the expected production postconditions.'
    }

    $mode = if ([string]::IsNullOrWhiteSpace($InstalledRoot)) { 'source' } else { 'installed' }
    Write-Host "Plan Coverage standalone full-coverage E2E ($mode): PASS"
}
finally {
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolvedTempRoot.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTempRoot).StartsWith('plan-coverage-full-coverage-e2e-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
