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

function Get-NormalizedTextSha256([string]$Path) {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes((Get-NormalizedText $Path))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-RequiredOutputTemplate([string]$ContractText, [string]$AnchorPattern, [string]$ContractName) {
    $anchor = [regex]::Match($ContractText, $AnchorPattern, [Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $anchor.Success) {
        throw "$ContractName required-output anchor is missing."
    }
    $tail = $ContractText.Substring($anchor.Index + $anchor.Length)
    $fence = [regex]::Match($tail, '(?ms)^```(?:md|markdown)\s*\n(?<template>.*?)^```\s*$')
    if (-not $fence.Success) {
        throw "$ContractName required-output template is missing after its anchor."
    }
    return $fence.Groups['template'].Value
}

function Get-ContractSection([string]$ContractText, [string]$StartPattern, [string]$EndPattern, [string]$ContractName) {
    $match = [regex]::Match($ContractText, "(?ms)$StartPattern(?<section>.*?)$EndPattern")
    if (-not $match.Success) {
        throw "$ContractName contract section could not be extracted."
    }
    return $match.Groups['section'].Value
}

function Get-NormalizedTableHeader([string]$Line) {
    return (($Line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() }) -join '|')
}

function Add-ContractShapeErrors(
    [System.Collections.Generic.List[string]]$Errors,
    [string]$ArtifactText,
    [string]$TemplateText,
    [string]$ArtifactName,
    [bool]$RequireHandoffFields = $true
) {
    $templateLines = $TemplateText -split "`n"
    $artifactLines = $ArtifactText -split "`n"

    foreach ($heading in @($templateLines | Where-Object { $_ -cmatch '^#{1,4}\s+\S' } | Select-Object -Unique)) {
        $staticPrefix = ($heading -split '<', 2)[0].TrimEnd()
        if (-not (@($artifactLines | Where-Object { $_.StartsWith($staticPrefix, [StringComparison]::Ordinal) }).Count -gt 0)) {
            $Errors.Add("$ArtifactName is missing current contract heading: $heading")
        }
    }

    for ($index = 0; $index -lt ($templateLines.Count - 1); $index++) {
        if ($templateLines[$index] -cmatch '^\|.*\|\s*$' -and $templateLines[$index + 1] -cmatch '^\|(?:\s*:?-+:?\s*\|)+\s*$') {
            $requiredHeader = Get-NormalizedTableHeader $templateLines[$index]
            $found = @($artifactLines | Where-Object {
                $_ -cmatch '^\|.*\|\s*$' -and (Get-NormalizedTableHeader $_) -ceq $requiredHeader
            }).Count -gt 0
            if (-not $found) {
                $Errors.Add("$ArtifactName is missing current contract table header: $requiredHeader")
            }
        }
    }

    if ($RequireHandoffFields) {
        foreach ($match in [regex]::Matches($TemplateText, '(?m)^- (?<label>[A-Za-z][A-Za-z0-9 _/-]*):')) {
            $label = $match.Groups['label'].Value.Trim()
            if ($ArtifactText -cnotmatch "(?m)^- $([regex]::Escape($label)):") {
                $Errors.Add("$ArtifactName is missing current contract handoff field: $label")
            }
        }
    }
}

function Add-CanonicalLedgerShapeErrors(
    [System.Collections.Generic.List[string]]$Errors,
    [string]$LedgerText,
    [string]$ReferenceText
) {
    Add-ContractShapeErrors $Errors $LedgerText $ReferenceText 'canonical Coverage Ledger' $false
    foreach ($sectionName in @('Source of truth', 'Close readiness summary')) {
        $section = [regex]::Match($ReferenceText, "(?ms)^## $([regex]::Escape($sectionName))\s*\n(?<body>.*?)(?=^## |\z)")
        if (-not $section.Success) {
            $Errors.Add("coverage-ledger reference is missing section $sectionName")
            continue
        }
        $lines = $section.Groups['body'].Value -split "`n"
        foreach ($line in $lines) {
            if ($line -cmatch '^\| (?<label>[^|]+?) \|' -and $line -cnotmatch '^\|\s*(?:Field|Check|---)') {
                $label = $Matches['label'].Trim()
                if ($LedgerText -cnotmatch "(?m)^\| $([regex]::Escape($label)) \|") {
                    $Errors.Add("canonical Coverage Ledger is missing current $sectionName row: $label")
                }
            }
        }
    }
}

function Add-AgentVersionErrors(
    [System.Collections.Generic.List[string]]$Errors,
    [string]$ArtifactText,
    [string]$AgentPath,
    [string]$SkillPath,
    [string]$ArtifactName
) {
    $agentHash = Get-NormalizedTextSha256 $AgentPath
    $skillHash = Get-NormalizedTextSha256 $SkillPath
    if ($ArtifactText -cnotmatch "(?m)^\| Agent file SHA \| ``$agentHash`` \|$") {
        $Errors.Add("$ArtifactName Agent file SHA does not match current contract authority.")
    }
    if ($ArtifactText -cnotmatch "(?m)^\| Skill file SHA \| ``$skillHash`` \|$") {
        $Errors.Add("$ArtifactName Skill file SHA does not match current Plan Coverage Skill.")
    }
}

function Add-AdaptiveFinalOutputErrors(
    [System.Collections.Generic.List[string]]$Errors,
    [string]$ArtifactText,
    [string]$AdaptiveSkillText,
    [string]$ArtifactName
) {
    $section = [regex]::Match($AdaptiveSkillText, '(?ms)^## Final output\s*\n(?<body>.*?)(?=^## |\z)')
    if (-not $section.Success) {
        $Errors.Add('Adaptive Skill is missing its Final output contract.')
        return
    }
    foreach ($line in $section.Groups['body'].Value -split "`n") {
        if ($line -cnotmatch '^- (?<item>.+)$') {
            continue
        }
        $label = $Matches['item']
        $label = ($label -split '、|, if any|（|または', 2)[0].Trim().Trim('`')
        if (-not [string]::IsNullOrWhiteSpace($label) -and $ArtifactText -notmatch [regex]::Escape($label)) {
            $Errors.Add("$ArtifactName is missing current Adaptive final-output item: $label")
        }
    }
}

function Find-OneFile([string]$Root, [string]$Leaf, [string]$Purpose) {
    $matches = @(Get-ChildItem -LiteralPath $Root -Force -Recurse -File -Filter $Leaf)
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

function Get-FixtureErrors([string]$Root, [System.Collections.IDictionary]$Authority) {
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

    $planContract = Get-NormalizedText $Authority['plan-kernel.agent.md']
    $triageContract = Get-NormalizedText $Authority['change-risk-triage.agent.md']
    $readinessContract = Get-NormalizedText $Authority['architecture-slice-readiness.agent.md']
    $decompositionContract = Get-NormalizedText $Authority['plan-slice-decomposition.agent.md']
    $runtimeContract = Get-NormalizedText $Authority['runtime-contract-kernel.agent.md']
    $testDesignContract = Get-NormalizedText $Authority['test-design-kernel.agent.md']
    $handoffContract = Get-NormalizedText $Authority['implementation-handoff-review.agent.md']
    $verificationContract = Get-NormalizedText $Authority['verification-kernel.agent.md']
    $crossContract = Get-NormalizedText $Authority['cross-slice-verification-kernel.agent.md']
    $residualContract = Get-NormalizedText $Authority['residual-decision-gate.agent.md']
    $adaptiveSkill = Get-NormalizedText $Authority['AdaptiveSkill']
    $coverageLedgerReference = Get-NormalizedText $Authority['CoverageLedger']

    $planTemplate = @(
        Get-RequiredOutputTemplate $planContract '^### Step 9\. Write the Plan Kernel artifact\s*$' 'Plan Kernel'
        Get-RequiredOutputTemplate $planContract '^### Black-box behavior coverage の記述\s*$' 'Plan Kernel behavior coverage'
        Get-RequiredOutputTemplate $planContract '^### Handoff Packet の記述\s*$' 'Plan Kernel handoff'
    ) -join "`n"
    $triageTemplate = Get-RequiredOutputTemplate $triageContract '^## Required output structure\s*$' 'Change Risk Triage'
    $readinessTemplate = Get-ContractSection $readinessContract '^## Output\s*$' '^## Must not do\s*$' 'Architecture Slice Readiness'
    $decompositionTemplate = Get-RequiredOutputTemplate $decompositionContract '^### Step 9\. Write output\s*$' 'Plan Slice Decomposition'
    $runtimeTemplate = Get-RequiredOutputTemplate $runtimeContract '^## Required output structure\s*$' 'Runtime Contract Kernel'
    $testDesignTemplate = Get-RequiredOutputTemplate $testDesignContract '^## Required output structure\s*$' 'Test Design Kernel'
    $handoffTemplate = Get-RequiredOutputTemplate $handoffContract '^### Step 4\. Write the review output\s*$' 'Implementation Handoff Review'
    $verificationTemplate = Get-RequiredOutputTemplate $verificationContract '^## Required output structure\s*$' 'Verification Kernel'
    $crossTemplate = Get-RequiredOutputTemplate $crossContract '^## Required output structure\s*$' 'Cross-Slice Verification Kernel'
    $residualTemplate = Get-RequiredOutputTemplate $residualContract '^## Required output structure\s*$' 'Residual Decision Gate'

    Add-ContractShapeErrors $errors $parentPlan $planTemplate 'parent Plan'
    Add-ContractShapeErrors $errors (Get-NormalizedText (Join-Path $Root 'plans/pcf-001-change-risk-triage.md')) $triageTemplate 'change-risk-triage'
    Add-ContractShapeErrors $errors $readiness $readinessTemplate 'architecture-slice-readiness'
    Add-ContractShapeErrors $errors $decomposition $decompositionTemplate 'plan-slice-decomposition'
    foreach ($slice in @($expected.slices)) {
        $slicePlan = Get-NormalizedText (Join-Path $Root ([string]$slice.plan))
        $sliceRuntime = Get-NormalizedText (Join-Path $Root ([string]$slice.runtime_contract))
        $sliceTestDesign = Get-NormalizedText (Join-Path $Root ([string]$slice.test_design))
        $sliceHandoff = Get-NormalizedText (Join-Path $Root ([string]$slice.handoff))
        $sliceImplementation = Get-NormalizedText (Join-Path $Root ([string]$slice.implementation))
        $sliceVerification = Get-NormalizedText (Join-Path $Root ([string]$slice.verification))
        Add-ContractShapeErrors $errors $slicePlan $planTemplate "$($slice.id) bounded Plan"
        Add-ContractShapeErrors $errors $sliceRuntime $runtimeTemplate "$($slice.id) runtime contract"
        Add-ContractShapeErrors $errors $sliceTestDesign $testDesignTemplate "$($slice.id) test design"
        Add-ContractShapeErrors $errors $sliceHandoff $handoffTemplate "$($slice.id) implementation handoff"
        Add-AdaptiveFinalOutputErrors $errors $sliceImplementation $adaptiveSkill "$($slice.id) Adaptive evidence"
        Add-ContractShapeErrors $errors $sliceVerification $verificationTemplate "$($slice.id) verification"
        Add-AgentVersionErrors $errors $sliceHandoff $Authority['implementation-handoff-review.agent.md'] $Authority['PlanCoverageSkill'] "$($slice.id) implementation handoff"
        Add-AgentVersionErrors $errors $sliceVerification $Authority['verification-kernel.agent.md'] $Authority['PlanCoverageSkill'] "$($slice.id) verification"
    }
    Add-CanonicalLedgerShapeErrors $errors $ledger $coverageLedgerReference
    Add-ContractShapeErrors $errors $cross $crossTemplate 'cross-slice verification'
    Add-AgentVersionErrors $errors $cross $Authority['cross-slice-verification-kernel.agent.md'] $Authority['PlanCoverageSkill'] 'cross-slice verification'
    Add-ContractShapeErrors $errors $residual $residualTemplate 'residual decision'
    Add-AgentVersionErrors $errors $residual $Authority['residual-decision-gate.agent.md'] $Authority['PlanCoverageSkill'] 'residual decision'

    $triage = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-change-risk-triage.md')
    if ($parentPlan -cnotmatch '(?m)^- Plan readiness: ReadyForRiskTriage$') { $errors.Add('Parent Plan must be ReadyForRiskTriage.') }
    if ($triage -cnotmatch '(?ms)^## 推奨プロファイル\s*\n\s*`full-coverage`\s*(?=\n## )') { $errors.Add('Risk triage must select full-coverage.') }
    if ($readiness -cnotmatch '(?m)^- Verdict: ReadyForSliceDecomposition$') { $errors.Add('Readiness must authorize slice decomposition.') }
    if ($readiness -cnotmatch '(?m)^- Architecture Elaboration: N/A for this happy path$' -or $readiness -cnotmatch '(?m)^- Architecture baseline authority: Slice Architecture artifact$') { $errors.Add('The happy path must use the current Slice Architecture without Architecture Elaboration.') }
    if ($decomposition -cnotmatch '(?m)^\| `SL-002` \|.*\| `SL-001` verified \| No \|$') { $errors.Add('Decomposition must preserve the two-slice dependency order.') }

    foreach ($trackedSource in @(
        @{ Path = 'plans/pcf-001.md'; RevisionType = 'content_sha256' },
        @{ Path = 'plans/pcf-001-black-box-behavior-spec.md'; RevisionType = 'content_sha256' },
        @{ Path = 'plans/pcf-001-change-risk-triage.md'; RevisionType = 'content_sha256' },
        @{ Path = 'plans/pcf-001-slice-architecture.md'; RevisionType = 'external_content_sha256' }
    )) {
        $hash = Get-NormalizedTextSha256 (Join-Path $Root $trackedSource.Path)
        $expectedRevision = "- { role: .* path: `"$([regex]::Escape($trackedSource.Path))`", revision_type: $($trackedSource.RevisionType), revision: `"$hash`" }"
        if ($readiness -cnotmatch $expectedRevision) {
            $errors.Add("Readiness tracked source hash is stale or missing: $($trackedSource.Path)")
        }
    }

    $allIds = @($expected.requirement_ids) + @($expected.acceptance_ids) + @($expected.case_ids) + @($expected.cross_cutting_ids)
    foreach ($id in $allIds) {
        $quotedId = ('`{0}`' -f $id)
        $ledgerPrefix = ('| `{0}` |' -f $id)
        if ($parentPlan -cnotmatch [regex]::Escape($quotedId)) { $errors.Add("Parent Plan does not define $id.") }
        if ($ledger -cnotmatch [regex]::Escape($quotedId)) { $errors.Add("Coverage Ledger does not classify $id.") }
        if ($cross -cnotmatch [regex]::Escape($quotedId)) { $errors.Add("Cross-slice verification does not trace $id.") }
    }

    foreach ($slice in @($expected.slices)) {
        $handoff = Get-NormalizedText (Join-Path $Root ([string]$slice.handoff))
        $implementation = Get-NormalizedText (Join-Path $Root ([string]$slice.implementation))
        $verification = Get-NormalizedText (Join-Path $Root ([string]$slice.verification))
        if ($handoff -cnotmatch '(?m)^\| Actual verdict \| `READY_FOR_BOUNDED_PARENT_PLAN_PASS` \|$' -or $handoff -cnotmatch '(?m)^\| Architecture compatibility \| Match \|$' -or $handoff -cnotmatch "(?m)^\| ``$($slice.id)`` \|.*\| Match \| proceed to Adaptive Implementation \|$") {
            $errors.Add("$($slice.id) must emit the formal handoff verdict and current architecture Match.")
        }
        if ($handoff -cmatch '(?m)^\| Architecture compatibility \| (?:Drift|Unclear) \|$' -or $handoff -cmatch "(?m)^\| ``$($slice.id)`` \|.*\| (?:Drift|Unclear) \|") {
            $errors.Add("$($slice.id) architecture Drift or Unclear must fail closed.")
        }
        if ($implementation -cnotmatch 'implementation_route=adaptive.*implementation_route_source=default' -or $implementation -cnotmatch 'Handoff architecture verdict consumed: `Match`') {
            $errors.Add("$($slice.id) must consume Match through Adaptive Implementation.")
        }
        if ($verification -cnotmatch '(?m)^\| Actual verdict \| `PARENT_PLAN_VERIFIED` \|$' -or $verification -cnotmatch '(?ms)^## 判定結果\s*\n\s*`PARENT_PLAN_VERIFIED`') {
            $errors.Add("$($slice.id) independent Verification Kernel verdict is missing.")
        }
    }

    if ($cross -cnotmatch 'src/StartupFlow\.ps1' -or $cross -cnotmatch '(?ms)^## Verdict\s*\n\s*`CROSS_SLICE_VERIFIED`') {
        $errors.Add('Cross-slice verification must exercise the production entrypoint and emit CROSS_SLICE_VERIFIED.')
    }
    if ($residual -cnotmatch '`CROSS_SLICE_VERIFIED`' -or $residual -cnotmatch '(?ms)^## Verdict\s*\n\s*`READY_TO_CLOSE_WITH_NO_RESIDUALS`') {
        $errors.Add('Residual Decision must consume CROSS_SLICE_VERIFIED before closing with no residuals.')
    }
    if ($ledger -cnotmatch '(?m)^\| No fake-only completion \| PASS \|' -or $ledger -cnotmatch '(?m)^\| No unclassified delta remains \| PASS \|' -or $ledger -cnotmatch '(?m)^\| Residual decisions explicit \| PASS \|') {
        $errors.Add('Coverage Ledger must leave no fake-only evidence, unclassified items, or blocking residuals.')
    }
    foreach ($id in @($expected.requirement_ids) + @($expected.acceptance_ids)) {
        $ledgerPrefix = ('| `{0}` |' -f $id)
        $ledgerLine = @($ledger -split "`n" | Where-Object { $_ -cmatch [regex]::Escape($ledgerPrefix) })
        if ($ledgerLine.Count -ne 1 -or $ledgerLine[0] -cnotmatch '\| Implemented \| Verified \|') {
            $errors.Add("Coverage Ledger must mark parent item $id implemented and verified exactly once.")
        }
    }
    foreach ($id in @($expected.case_ids)) {
        $ledgerPrefix = ('| `{0}` |' -f $id)
        $ledgerLine = @($ledger -split "`n" | Where-Object { $_ -cmatch [regex]::Escape($ledgerPrefix) })
        if ($ledgerLine.Count -ne 1 -or $ledgerLine[0] -cnotmatch '\| Verified \|') {
            $errors.Add("Coverage Ledger must mark Behavior Case $id verified exactly once.")
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

function Assert-FixtureValid([string]$Root, [string]$Context, [System.Collections.IDictionary]$Authority) {
    $errors = @(Get-FixtureErrors $Root $Authority)
    if ($errors.Count -gt 0) {
        throw "$Context failed fixture validation:`n- $($errors -join "`n- ")"
    }
}

function Assert-NegativeMutationFails([string]$Name, [scriptblock]$Mutate, [System.Collections.IDictionary]$Authority) {
    $caseRoot = Join-Path $tempRoot "negative-$Name"
    Copy-Item -LiteralPath $fixtureRoot -Destination $caseRoot -Recurse
    & $Mutate $caseRoot
    $errors = @(Get-FixtureErrors $caseRoot $Authority)
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

    Assert-FixtureValid $fixtureRoot 'PCF-001' $authority

    Assert-NegativeMutationFails 'missing-sl-002-verification' {
        param($root)
        Remove-Item -LiteralPath (Join-Path $root 'plans/pcf-001-slice-SL-002-verification-kernel.md') -Force
    } $authority
    foreach ($verdict in @('Drift', 'Unclear')) {
        Assert-NegativeMutationFails "architecture-$($verdict.ToLowerInvariant())" {
            param($root)
            $path = Join-Path $root 'plans/pcf-001-slice-SL-002-implementation-handoff-review.md'
            [System.IO.File]::WriteAllText($path, ([System.IO.File]::ReadAllText($path)).Replace('| Architecture compatibility | Match |', "| Architecture compatibility | $verdict |"), [System.Text.UTF8Encoding]::new($false))
        }.GetNewClosure() $authority
    }
    Assert-NegativeMutationFails 'missing-production-binding' {
        param($root)
        $path = Join-Path $root 'expected.json'
        [System.IO.File]::WriteAllText($path, ([System.IO.File]::ReadAllText($path)).Replace('src/StartupFlow.ps1', 'src/MissingStartupFlow.ps1'), [System.Text.UTF8Encoding]::new($false))
    } $authority
    Assert-NegativeMutationFails 'missing-cross-slice-verdict' {
        param($root)
        $path = Join-Path $root 'plans/pcf-001-cross-slice-verification-kernel.md'
        [System.IO.File]::WriteAllText($path, ([System.IO.File]::ReadAllText($path)).Replace('`CROSS_SLICE_VERIFIED`', '`CROSS_SLICE_PENDING`'), [System.Text.UTF8Encoding]::new($false))
    } $authority
    Assert-NegativeMutationFails 'residual-before-cross-slice' {
        param($root)
        $path = Join-Path $root 'expected.json'
        $text = [System.IO.File]::ReadAllText($path)
        $text = $text -replace '"CROSS_SLICE_VERIFIED",\s*"READY_TO_CLOSE_WITH_NO_RESIDUALS"', "`"READY_TO_CLOSE_WITH_NO_RESIDUALS`",`n    `"CROSS_SLICE_VERIFIED`""
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    } $authority
    Assert-NegativeMutationFails 'removed-dependency-reference' {
        param($root)
        $path = Join-Path $root 'README.md'
        [System.IO.File]::AppendAllText($path, "`nRemoved dependency regression token: token-aware-full-coverage-3layer`n", [System.Text.UTF8Encoding]::new($false))
    } $authority
    Assert-NegativeMutationFails 'missing-current-handoff-section' {
        param($root)
        $path = Join-Path $root 'plans/pcf-001-slice-SL-001-implementation-handoff-review.md'
        [System.IO.File]::WriteAllText($path, ([System.IO.File]::ReadAllText($path)).Replace('## Readiness scope', '## Omitted current readiness scope'), [System.Text.UTF8Encoding]::new($false))
    } $authority
    Assert-NegativeMutationFails 'missing-canonical-ledger-section' {
        param($root)
        $path = Join-Path $root 'plans/pcf-001-coverage-ledger.md'
        [System.IO.File]::WriteAllText($path, ([System.IO.File]::ReadAllText($path)).Replace('## Residual Decision Ledger', '## Omitted residual ledger'), [System.Text.UTF8Encoding]::new($false))
    } $authority

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
    if ($slice1Evidence.slice -cne 'SL-001' -or $slice1Evidence.verdict -cne 'PARENT_PLAN_VERIFIED' -or $slice1Evidence.snapshot_state -cne 'Active' -or $slice1Evidence.correlation_id -cne 'pcf-001') {
        throw 'SL-001 runtime evidence does not match the expected postcondition.'
    }

    $slice2 = $expected.slices[1]
    Copy-Item -Path (Join-Path $fixtureRoot "$($slice2.payload)/*") -Destination $consumerRoot -Recurse -Force
    $slice2Evidence = Invoke-FixtureVerifier $consumerRoot ([string]$slice2.verifier)
    if ($slice2Evidence.slice -cne 'SL-002' -or $slice2Evidence.verdict -cne 'PARENT_PLAN_VERIFIED' -or $slice2Evidence.consumer_state -cne 'Accepting' -or $slice2Evidence.postcondition -cne 'Accepted' -or -not $slice2Evidence.reject_observed) {
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
