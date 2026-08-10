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

function Find-OneFile([string]$Root, [string]$Leaf, [string]$Purpose) {
    $matches = @(Get-ChildItem -LiteralPath $Root -Force -Recurse -File -Filter $Leaf)
    if ($matches.Count -ne 1) {
        throw "$Purpose must resolve to exactly one '$Leaf' file under $Root; found $($matches.Count)."
    }
    return $matches[0].FullName
}

function Get-MarkdownTemplate([string]$Text, [string]$HeadingPattern, [string]$Name) {
    $pattern = '(?ms)^```md[ \t]*\n(?<template>' + $HeadingPattern + '.*?)(?:\n^```[ \t]*$)'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        throw "$Name markdown template is missing."
    }
    return $match.Groups['template'].Value
}

function Get-NormalizedTableHeader([string]$Line) {
    return (($Line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() }) -join '|')
}

function Add-TemplateShapeErrors(
    [System.Collections.Generic.List[string]]$Errors,
    [string]$Artifact,
    [string]$Template,
    [string]$Name
) {
    $templateLines = $Template -split "`n"
    $artifactLines = $Artifact -split "`n"
    foreach ($heading in @($templateLines | Where-Object { $_ -cmatch '^#{1,4}\s+\S' } | Select-Object -Unique)) {
        $prefix = ($heading -split '<', 2)[0].TrimEnd()
        $prefixPattern = '^' + ([regex]::Escape($prefix) -replace 'xxx', '\d{3}')
        if (-not (@($artifactLines | Where-Object { $_ -cmatch $prefixPattern }).Count -gt 0)) {
            $Errors.Add("$Name is missing required heading: $heading")
        }
    }
    foreach ($field in @($templateLines | Where-Object { $_ -cmatch '^- [^:]+:' } | ForEach-Object {
        [regex]::Match($_, '^- (?<label>[^:]+):').Groups['label'].Value
    } | Select-Object -Unique)) {
        $fieldPattern = '^- ' + [regex]::Escape($field) + ':'
        if (-not (@($artifactLines | Where-Object { $_ -cmatch $fieldPattern }).Count -gt 0)) {
            $Errors.Add("$Name is missing required field: $field")
        }
    }
    for ($index = 0; $index -lt ($templateLines.Count - 1); $index++) {
        if ($templateLines[$index] -cmatch '^\|.*\|\s*$' -and $templateLines[$index + 1] -cmatch '^\|(?:\s*:?-+:?\s*\|)+\s*$') {
            $required = Get-NormalizedTableHeader $templateLines[$index]
            $found = @($artifactLines | Where-Object {
                $_ -cmatch '^\|.*\|\s*$' -and (Get-NormalizedTableHeader $_) -ceq $required
            }).Count -gt 0
            if (-not $found) {
                $Errors.Add("$Name is missing required table header: $required")
            }
        }
    }
}

function Resolve-ContractAuthority {
    $agentLeaves = @(
        'change-risk-triage.agent.md',
        'plan-slice-decomposition.agent.md',
        'implementation-contract-kernel.agent.md',
        'runtime-contract-kernel.agent.md',
        'test-design-kernel.agent.md',
        'implementation-handoff-review.agent.md',
        'verification-kernel.agent.md',
        'cross-slice-verification-kernel.agent.md',
        'residual-decision-gate.agent.md',
        'coverage-gap-triage.agent.md',
        'coverage-gap-resolution-slice.agent.md',
        'implementation-contract-review-kernel.agent.md'
    )
    if ([string]::IsNullOrWhiteSpace($InstalledRoot)) {
        $files = [ordered]@{
            PlanCoverageSkill = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/SKILL.md'
            SliceLivingRecord = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/references/full-coverage-slice-living-record.md'
            FullCoverageClose = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/references/full-coverage-close.md'
            CoverageLedger = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md'
        }
        foreach ($leaf in $agentLeaves) {
            $files[$leaf] = Join-Path $packageRoot ".apm/agents/$leaf"
        }
    }
    else {
        $resolvedInstalledRoot = (Resolve-Path -LiteralPath $InstalledRoot).Path
        $files = [ordered]@{
            PlanCoverageSkill = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/SKILL.md'
            SliceLivingRecord = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/references/full-coverage-slice-living-record.md'
            FullCoverageClose = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/references/full-coverage-close.md'
            CoverageLedger = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/references/coverage-ledger.md'
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
    try {
        $expected = Get-Content -Raw -LiteralPath $expectedPath | ConvertFrom-Json
    }
    catch {
        $errors.Add("expected.json is missing or invalid: $($_.Exception.Message)")
        return $errors
    }

    $requiredOrder = 'ReadyForRiskTriage,full-coverage,ReadyForSliceDecomposition,SL-001,SL-002,CROSS_SLICE_PARTIAL_WITH_FIX_CANDIDATES,GAP_TRIAGED,RESOLVED_FOR_SELECTED_SCOPE,SL-002_REVERIFIED,CROSS_SLICE_VERIFIED,READY_TO_CLOSE_WITH_NO_RESIDUALS'
    if ((@($expected.stage_order) -join ',') -cne $requiredOrder) {
        $errors.Add('Stage order must keep cross-slice verification before residual decision.')
    }
    if ($expected.artifact_mode -cne 'slice-living-record') {
        $errors.Add('New full-coverage fixture must use artifact_mode slice-living-record.')
    }
    if (@($expected.slices).Count -ne 2 -or $expected.slices[0].id -cne 'SL-001' -or $expected.slices[1].id -cne 'SL-002') {
        $errors.Add('The fixture must define exactly SL-001 followed by SL-002.')
    }
    elseif (@($expected.slices[0].depends_on).Count -ne 0 -or (@($expected.slices[1].depends_on) -join ',') -cne 'SL-001') {
        $errors.Add('SL-002 must depend on independently verified SL-001.')
    }

    $basePaths = @(
        'plans/pcf-001.md',
        'plans/pcf-001-change-risk-triage.md',
        'plans/pcf-001-architecture-slice-readiness.md',
        'plans/pcf-001-slice-decomposition.md',
        [string]$expected.coverage_ledger
    ) + @($expected.slices | ForEach-Object { [string]$_.living_record }) + @([string]$expected.full_coverage_close)
    $baseExpected = [int]$expected.base_parent_artifacts + @($expected.slices).Count + 1
    if ($baseExpected -ne 8 -or $baseExpected -gt (6 + @($expected.slices).Count) -or @($basePaths | Select-Object -Unique).Count -ne $baseExpected) {
        $errors.Add('The two-slice base durable artifact budget must be 8 and no greater than 6 + executable slices.')
    }

    $allowedExceptionReasons = @('cross-thread-handoff', 'parallel-write-isolation', 'human-approval-wait', 'external-audit-evidence', 'record-size-limit')
    foreach ($conditional in @($expected.conditional_artifacts)) {
        if ([string]::IsNullOrWhiteSpace([string]$conditional.path) -or [string]::IsNullOrWhiteSpace([string]$conditional.condition)) {
            $errors.Add('Every conditional artifact needs path and condition.')
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$conditional.reason_code)) {
            if ($allowedExceptionReasons -cnotcontains [string]$conditional.reason_code) {
                $errors.Add("Conditional artifact has an invalid exception reason: $($conditional.path)")
            }
            $targetSlice = @($expected.slices | Where-Object { $_.id -ceq [string]$conditional.slice_id })
            if ($targetSlice.Count -ne 1) {
                $errors.Add("Exception artifact must identify one target slice: $($conditional.path)")
            }
            else {
                $targetRecordPath = Join-Path $Root ([string]$targetSlice[0].living_record)
                if (Test-Path -LiteralPath $targetRecordPath -PathType Leaf) {
                    $targetRecord = Get-NormalizedText $targetRecordPath
                    $exceptionPattern = '(?m)^\|\s*' + [regex]::Escape("``$($conditional.path)``") +
                        '\s*\|\s*' + [regex]::Escape("``$($conditional.reason_code)``") +
                        '\s*\|.*\|\s*' + [regex]::Escape([string]$conditional.owner) +
                        '\s*\|\s*' + [regex]::Escape([string]$conditional.classification) +
                        '\s*\|\s*' + [regex]::Escape([string]$conditional.lifecycle) + '\s*\|$'
                    if ($targetRecord -cnotmatch $exceptionPattern) {
                        $errors.Add("Artifact exception row is missing or not pre-applied: $($conditional.path)")
                    }
                }
            }
        }
    }
    $declaredPaths = @('README.md') + $basePaths + @($expected.conditional_artifacts | ForEach-Object { [string]$_.path })
    foreach ($path in @($declaredPaths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $path) -PathType Leaf)) {
            $errors.Add("Declared fixture file is missing: $path")
        }
    }
    foreach ($slice in @($expected.slices)) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root ([string]$slice.payload)) -PathType Container)) {
            $errors.Add("Payload is missing for $($slice.id).")
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Root "seed/$($slice.verifier)") -PathType Leaf)) {
            $errors.Add("Independent runtime verifier is missing for $($slice.id).")
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Root "seed/$($expected.cross_slice_verifier)") -PathType Leaf)) {
        $errors.Add('Cross-slice runtime verifier is missing.')
    }
    $productionBinding = @($expected.slices | Where-Object {
        Test-Path -LiteralPath (Join-Path $Root "$($_.payload)/$($expected.production_entrypoint)") -PathType Leaf
    }).Count -gt 0
    if (-not $productionBinding) {
        $errors.Add('Production entrypoint is not supplied by any slice payload.')
    }

    $plansRoot = Join-Path $Root 'plans'
    $separatePattern = '^pcf-001-slice-SL-\d{3}-(?:change-risk-triage|implementation-contract-kernel|runtime-contract-kernel|test-design-kernel|implementation-handoff-review|implementation-completion-handoff|high-model-reentry-handoff|implementation-execution|verification-kernel|coverage-gap-triage|coverage-gap-resolution-slice)\.md$'
    foreach ($file in @(Get-ChildItem -LiteralPath $plansRoot -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -cmatch $separatePattern) {
            $relativePath = "plans/$($file.Name)"
            $declaredException = @($expected.conditional_artifacts | Where-Object {
                $_.path -ceq $relativePath -and -not [string]::IsNullOrWhiteSpace([string]$_.reason_code)
            })
            if ($declaredException.Count -ne 1) {
                $errors.Add("Separate per-slice artifact bypassed Artifact Creation Gate: $($file.Name)")
            }
        }
    }
    if (@(Get-ChildItem -LiteralPath $plansRoot -Filter '*.md' -File).Count -ne ($baseExpected + @($expected.conditional_artifacts).Count)) {
        $errors.Add('Artifact count exceeds the declared base plus conditional budget.')
    }
    if ($errors.Count -gt 0) { return $errors }

    $livingTemplate = Get-MarkdownTemplate (Get-NormalizedText $Authority['SliceLivingRecord']) '# SL-xxx: <slice name>' 'Slice Living Record'
    $closeTemplate = Get-MarkdownTemplate (Get-NormalizedText $Authority['FullCoverageClose']) '# Full-Coverage Close Record' 'Full-Coverage Close Record'
    $ledgerTemplate = Get-NormalizedText $Authority['CoverageLedger']
    $decomposition = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-slice-decomposition.md')
    $ledger = Get-NormalizedText (Join-Path $Root ([string]$expected.coverage_ledger))
    $close = Get-NormalizedText (Join-Path $Root ([string]$expected.full_coverage_close))
    Add-TemplateShapeErrors $errors $close $closeTemplate 'Full-Coverage Close Record'
    Add-TemplateShapeErrors $errors $ledger $ledgerTemplate 'Coverage Ledger'

    if ($decomposition -cnotmatch '(?m)^- artifact_mode: slice-living-record$' -or $decomposition -cnotmatch '(?m)^- Base expected total: 8$') {
        $errors.Add('Decomposition must record Living Record mode and the base artifact budget.')
    }
    if ($decomposition -cnotmatch '(?m)^- Living Record writer: Plan Coverage parent/router only$' -or $decomposition -cnotmatch '(?m)^- Canonical Coverage Ledger writer: Plan Coverage parent/router only$') {
        $errors.Add('Decomposition must preserve parent-only write ownership.')
    }

    $allIds = @($expected.requirement_ids) + @($expected.acceptance_ids) + @($expected.case_ids) + @($expected.cross_cutting_ids)
    foreach ($slice in @($expected.slices)) {
        $record = Get-NormalizedText (Join-Path $Root ([string]$slice.living_record))
        Add-TemplateShapeErrors $errors $record $livingTemplate "$($slice.id) Living Record"
        if ($record -cnotmatch '(?m)^- artifact_mode: slice-living-record$' -or $record -cnotmatch '(?m)^- documentation_level: standard$') {
            $errors.Add("$($slice.id) does not use the canonical artifact/documentation metadata.")
        }
        if ($record -cnotmatch '(?m)^- Formal implementation-handoff-review verdict: `READY_FOR_BOUNDED_PARENT_PLAN_PASS`$' -or $record -cnotmatch '(?m)^- Architecture compatibility: Match$' -or $record -cnotmatch '(?m)^- Implementation allowed: Yes$') {
            $errors.Add("$($slice.id) must have the formal ready verdict and architecture Match.")
        }
        if ($record -cmatch '(?m)^- Architecture compatibility: (?:Drift|Unclear)$') {
            $errors.Add("$($slice.id) architecture Drift or Unclear must fail closed.")
        }
        if ($record -cnotmatch '(?m)^- Implementation route: adaptive / default$' -or $record -cnotmatch '`(?:COMPLETED_BY_HIGH_MODEL|COMPLETED)`' -or $record -cnotmatch '(?m)^### Implementation Self-Map$') {
            $errors.Add("$($slice.id) must aggregate Adaptive evidence and the Implementation Self-Map.")
        }
        if ($record -cnotmatch '(?m)^- Formal verification-kernel verdict: `PARENT_PLAN_VERIFIED`$' -or $record -cnotmatch '(?m)^- Fake / stub / mock assessment: no substitute used\.$') {
            $errors.Add("$($slice.id) independent production verification is incomplete or fake-only.")
        }
        if ($record -cmatch '(?m)^\| `SL-[^|]+\|.*\| No \|$') {
            $errors.Add("$($slice.id) has a pending Coverage Ledger Delta.")
        }
        if ($record -cmatch '(?m)^- Unauthorized section write attempted:' -or $record -cmatch '(?m)^- artifact_mode: (?!slice-living-record)') {
            $errors.Add("$($slice.id) contains an owner violation or mixed artifact mode.")
        }
        foreach ($id in @($slice.requirement_ids) + @($slice.acceptance_ids) + @($slice.case_ids) + @($slice.xc_ids)) {
            if ($record -cnotmatch [regex]::Escape("``$id``")) {
                $errors.Add("$($slice.id) lost required FR / AC / CASE / XC mapping for $id.")
            }
        }
    }

    foreach ($id in $allIds) {
        if ($ledger -cnotmatch [regex]::Escape("``$id``")) { $errors.Add("Canonical ledger does not classify $id.") }
        if ($close -cnotmatch [regex]::Escape("``$id``")) { $errors.Add("Close record does not trace $id.") }
    }
    if ($close -cnotmatch '(?m)^- Pending Coverage Ledger Delta count: 0$' -or $close -cnotmatch '(?m)^- Canonical ledger consistency: PASS$') {
        $errors.Add('Close record has a pending or contradictory canonical ledger state.')
    }
    if ($close -cnotmatch '(?m)^- Formal cross-slice-verification-kernel verdict: `CROSS_SLICE_VERIFIED`$' -or $close -cnotmatch 'src/StartupFlow\.ps1') {
        $errors.Add('Cross-slice verification must use production wiring and its formal verdict.')
    }
    if ($close -cnotmatch '(?m)^\| `CROSS-PARTIAL-001` \| Cross-Slice Verification .*\| FixNowSelected \|.*\| Yes \|$') {
        $errors.Add('The partial cross-slice verdict delta must be applied before the repair loop.')
    }
    $repairRecord = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-slice-SL-002.md')
    if ($close -cnotmatch '(?m)^- Trigger verdict: `CROSS_SLICE_PARTIAL_WITH_FIX_CANDIDATES`$' -or
        $close -cnotmatch '(?m)^- Selected gap selectors: `GAP-001`$' -or
        $close -cnotmatch '(?m)^- Target Slice Living Records: `plans/pcf-001-slice-SL-002\.md`$' -or
        $close -cnotmatch '(?m)^- Repair verdicts: `GAP-001=RESOLVED_FOR_SELECTED_SCOPE`$' -or
        $close -cnotmatch '(?m)^- Slice re-verification verdicts: `SL-002=PARENT_PLAN_VERIFIED`$' -or
        $close -cnotmatch '(?m)^- Cross-slice rerun verdict: `CROSS_SLICE_VERIFIED`$') {
        $errors.Add('Full-Coverage Close Record does not preserve the FixNow repair and re-verification loop.')
    }
    if ($repairRecord -cnotmatch '(?m)^## Gap Repair Evidence$' -or
        $repairRecord -cnotmatch '(?m)^- Selected selectors: `GAP-001`$' -or
        $repairRecord -cnotmatch '(?m)^- Repair verdict: `RESOLVED_FOR_SELECTED_SCOPE`$' -or
        $repairRecord -cnotmatch '(?m)^- Re-verification required: Yes; completed with `PARENT_PLAN_VERIFIED`$' -or
        $repairRecord -cnotmatch '(?m)^\| `SL-002-REPAIR-001` \| Gap Repair .*\| Yes \|$' -or
        $repairRecord -cnotmatch '(?m)^\| `SL-002-REVERIFY-001` \| Verification Rerun .*\| Yes \|$') {
        $errors.Add('SL-002 Living Record does not contain applied repair and re-verification evidence.')
    }
    $reentryPath = Join-Path $Root 'plans/pcf-001-slice-SL-002-high-model-reentry-handoff.md'
    $reentry = if (Test-Path -LiteralPath $reentryPath -PathType Leaf) { Get-NormalizedText $reentryPath } else { '' }
    if ($repairRecord -cnotmatch '(?m)^- Model / owner sequence: HIGH_MODEL -> `READY_FOR_STANDARD_COMPLETION` -> STANDARD_MODEL -> `NEEDS_HIGH_MODEL_REENTRY` payload -> Plan Coverage parent Artifact Creation Gate -> HIGH_MODEL -> `COMPLETED_BY_HIGH_MODEL`$' -or
        $repairRecord -cnotmatch '(?m)^- Re-entry persistence sequence: STANDARD_MODEL returned an unpersisted payload -> Plan Coverage parent applied the exact-path Artifact Exceptions row -> parent persisted the tracked handoff -> HIGH_MODEL resumed\.$' -or
        $reentry -cnotmatch '(?m)^- Verdict: `NEEDS_HIGH_MODEL_REENTRY`$' -or
        $reentry -cnotmatch '(?m)^- Persistence state: persisted by Plan Coverage parent after Artifact Creation Gate$' -or
        $reentry -cnotmatch '(?m)^- Artifact gate sequence: STANDARD_MODEL returned this content as `UNPERSISTED_PARENT_PAYLOAD`; Plan Coverage parent applied the exact-path Artifact Exceptions row; parent persisted this file; HIGH_MODEL resumed\.$') {
        $errors.Add('SL-002 does not prove delayed parent registration and persistence of the tracked re-entry handoff.')
    }
    if ($close -cnotmatch '(?m)^- Required slices independently verified: `SL-001=PARENT_PLAN_VERIFIED`, `SL-002=PARENT_PLAN_VERIFIED`$') {
        $errors.Add('Every required slice must be independently verified before cross-slice verification.')
    }
    if ($close -cnotmatch '(?m)^- Formal residual-decision-gate verdict: `READY_TO_CLOSE_WITH_NO_RESIDUALS`$' -or $close -cnotmatch '(?m)^- Cross-slice verdict consumed: `CROSS_SLICE_VERIFIED`$') {
        $errors.Add('Residual Decision must consume the formal cross-slice verdict before close.')
    }
    if ($close.IndexOf('## Cross-Slice Verification', [StringComparison]::Ordinal) -gt $close.IndexOf('## Residual Decision', [StringComparison]::Ordinal)) {
        $errors.Add('Residual Decision appears before Cross-Slice Verification.')
    }
    if ($close.IndexOf('## FixNow Repair Loop', [StringComparison]::Ordinal) -gt $close.IndexOf('## Residual Decision', [StringComparison]::Ordinal)) {
        $errors.Add('Residual Decision appears before the conditional FixNow repair loop is consumed.')
    }
    if ($close -cmatch '(?m)^\| `(?:CROSS-VERIFY|RESIDUAL)-[^|]+\|.*\| No \|$') {
        $errors.Add('Close record contains a pending Coverage Ledger Delta.')
    }
    if ($ledger -cnotmatch '(?m)^\| No fake-only completion \| PASS \|' -or $ledger -cnotmatch '(?m)^\| No unclassified delta remains \| PASS \|') {
        $errors.Add('Canonical ledger is not close-ready.')
    }

    $triage = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-change-risk-triage.md')
    foreach ($positiveFullCoverageEvidence in @(
        'SEQ-PUBLISH',
        'SEQ-REPLAY',
        'Cross-process durable-state observation',
        'durable identity is `correlation_id` plus `generation`',
        'producer is the only state authority',
        'consumer startup accepts a stale or partially published generation',
        'Escalation gate result: Satisfied'
    )) {
        if (-not $triage.Contains($positiveFullCoverageEvidence, [StringComparison]::Ordinal)) {
            $errors.Add("Positive full-coverage triage evidence is missing: $positiveFullCoverageEvidence")
        }
    }

    $readiness = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-architecture-slice-readiness.md')
    if ($readiness -cnotmatch '(?m)^- Reassessment result: KeepFullCoverage$' -or $readiness -cnotmatch '(?m)^- Escalation gate result: `Satisfied`$') {
        $errors.Add('Architecture readiness must confirm the positive full-coverage escalation evidence.')
    }
    foreach ($tracked in @(
        @{ Path = 'plans/pcf-001.md'; RevisionType = 'content_sha256' },
        @{ Path = 'plans/pcf-001-black-box-behavior-spec.md'; RevisionType = 'content_sha256' },
        @{ Path = 'plans/pcf-001-change-risk-triage.md'; RevisionType = 'content_sha256' },
        @{ Path = 'plans/pcf-001-slice-architecture.md'; RevisionType = 'external_content_sha256' }
    )) {
        $hash = Get-NormalizedTextSha256 (Join-Path $Root $tracked.Path)
        $pattern = "- { role: .* path: `"$([regex]::Escape($tracked.Path))`", revision_type: $($tracked.RevisionType), revision: `"$hash`" }"
        if ($readiness -cnotmatch $pattern) { $errors.Add("Readiness tracked source hash is stale: $($tracked.Path)") }
    }

    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File) {
        $text = Get-NormalizedText $file.FullName
        if ($text -cmatch '(?m)^artifact_mode:\s*compact-slice-record-v2\s*$' -or $text -cmatch '(?m)^## Parent Authorization\s*$' -or $text -cmatch '(?m)^## Parent Orchestration State\s*$' -or $text -cmatch 'slice-prep\.agent\.md') {
            $errors.Add("Removed three-layer active semantics are present in $($file.FullName.Substring($Root.Length + 1)).")
        }
        if ($text -cmatch 'forced migration|auto-migrated legacy') {
            $errors.Add("Legacy resume was silently migrated in $($file.FullName.Substring($Root.Length + 1)).")
        }
    }
    return $errors
}

function Assert-FixtureValid([string]$Root, [string]$Context, [System.Collections.IDictionary]$Authority) {
    $errors = @(Get-FixtureErrors $Root $Authority)
    if ($errors.Count -gt 0) { throw "$Context failed fixture validation:`n- $($errors -join "`n- ")" }
}

$script:ReplaceText = {
    param([string]$Path, [string]$Old, [string]$New)
    [System.IO.File]::WriteAllText($Path, ([System.IO.File]::ReadAllText($Path)).Replace($Old, $New), [System.Text.UTF8Encoding]::new($false))
}

function Assert-NegativeMutationFails([string]$Name, [scriptblock]$Mutate, [System.Collections.IDictionary]$Authority) {
    $caseRoot = Join-Path $tempRoot "negative-$Name"
    Copy-Item -LiteralPath $fixtureRoot -Destination $caseRoot -Recurse
    & $Mutate $caseRoot
    if (@(Get-FixtureErrors $caseRoot $Authority).Count -eq 0) {
        throw "Negative fixture '$Name' did not fail closed."
    }
}

function Invoke-FixtureVerifier([string]$ConsumerRoot, [string]$RelativePath) {
    $output = @(& pwsh -NoProfile -File (Join-Path $ConsumerRoot $RelativePath))
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { throw "Fixture verifier '$RelativePath' failed or returned no evidence." }
    return ($output[-1] | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $authority = Resolve-ContractAuthority
    $authorityText = @($authority.Values | ForEach-Object { Get-NormalizedText $_ }) -join "`n"
    foreach ($pattern in @(
        'artifact_mode: slice-living-record', 'output_contract: section-delta',
        'Plan Coverage parent/router', 'Artifact Creation Gate', 'needs-further-decomposition',
        'Only a current-baseline `Match` may proceed', 'references/full-coverage-close.md',
        'legacy/separate', 'pending Coverage Ledger Delta', 'unpersisted parent payload',
        'high-model-reentry-handoff.md'
    )) {
        if ($authorityText -cnotmatch [regex]::Escape($pattern)) { throw "Contract authority is missing: $pattern" }
    }
    Assert-FixtureValid $fixtureRoot 'PCF-001' $authority

    $record1 = 'plans/pcf-001-slice-SL-001.md'
    $record2 = 'plans/pcf-001-slice-SL-002.md'
    $closePath = 'plans/pcf-001-full-coverage-close.md'
    Assert-NegativeMutationFails 'missing-required-section' { param($r) & $script:ReplaceText (Join-Path $r $record1) '## Runtime Contract' '## Omitted Runtime Contract' } $authority
    Assert-NegativeMutationFails 'missing-required-field' { param($r) & $script:ReplaceText (Join-Path $r $closePath) '- Production wiring verified: PASS via `src/StartupFlow.ps1`' '- Removed production wiring field' } $authority
    Assert-NegativeMutationFails 'coverage-ledger-schema-missing' { param($r) & $script:ReplaceText (Join-Path $r 'plans/pcf-001-coverage-ledger.md') '## Residual Decision Ledger' '## Omitted Residual Decision Ledger' } $authority
    Assert-NegativeMutationFails 'owner-outside-section' { param($r) Add-Content -LiteralPath (Join-Path $r $record1) '- Unauthorized section write attempted: Runtime Contract by verification-kernel' } $authority
    foreach ($verdict in @('Drift', 'Unclear')) {
        Assert-NegativeMutationFails "architecture-$($verdict.ToLowerInvariant())" { param($r) & $script:ReplaceText (Join-Path $r $record2) '- Architecture compatibility: Match' "- Architecture compatibility: $verdict" }.GetNewClosure() $authority
    }
    Assert-NegativeMutationFails 'missing-independent-verification' { param($r) & $script:ReplaceText (Join-Path $r $record2) '- Formal verification-kernel verdict: `PARENT_PLAN_VERIFIED`' '- Formal verification-kernel verdict: pending' } $authority
    Assert-NegativeMutationFails 'missing-production-binding' { param($r) & $script:ReplaceText (Join-Path $r 'expected.json') 'src/StartupFlow.ps1' 'src/MissingStartupFlow.ps1' } $authority
    Assert-NegativeMutationFails 'fake-only-evidence' { param($r) & $script:ReplaceText (Join-Path $r $record1) '- Fake / stub / mock assessment: no substitute used.' '- Fake / stub / mock assessment: fake-only evidence.' } $authority
    Assert-NegativeMutationFails 'xc-field-continuity-missing' { param($r) & $script:ReplaceText (Join-Path $r $record1) 'XC-001' 'XC-MISSING' } $authority
    Assert-NegativeMutationFails 'mapping-missing' { param($r) & $script:ReplaceText (Join-Path $r $record1) 'CASE-001' 'CASE-MISSING' } $authority
    Assert-NegativeMutationFails 'pending-before-verification' { param($r) & $script:ReplaceText (Join-Path $r $record1) '| Yes |' '| No |' } $authority
    Assert-NegativeMutationFails 'pending-before-close' { param($r) & $script:ReplaceText (Join-Path $r $closePath) '- Pending Coverage Ledger Delta count: 0' '- Pending Coverage Ledger Delta count: 1' } $authority
    Assert-NegativeMutationFails 'ledger-contradiction' { param($r) & $script:ReplaceText (Join-Path $r $closePath) '- Canonical ledger consistency: PASS' '- Canonical ledger consistency: FAIL' } $authority
    Assert-NegativeMutationFails 'repair-loop-skipped' { param($r) & $script:ReplaceText (Join-Path $r $closePath) '- Cross-slice rerun verdict: `CROSS_SLICE_VERIFIED`' '- Cross-slice rerun verdict: skipped' } $authority
    Assert-NegativeMutationFails 'tracked-handoff-without-exception' { param($r) & $script:ReplaceText (Join-Path $r $record2) '| `plans/pcf-001-slice-SL-002-implementation-completion-handoff.md` | `cross-thread-handoff` |' '| removed | removed |' } $authority
    Assert-NegativeMutationFails 'tracked-reentry-without-exception' { param($r) & $script:ReplaceText (Join-Path $r $record2) '| `plans/pcf-001-slice-SL-002-high-model-reentry-handoff.md` | `cross-thread-handoff` |' '| removed | removed |' } $authority
    Assert-NegativeMutationFails 'ungated-separate-artifact' { param($r) Copy-Item (Join-Path $r $record1) (Join-Path $r 'plans/pcf-001-slice-SL-001-runtime-contract-kernel.md') } $authority
    Assert-NegativeMutationFails 'artifact-budget-exceeded' { param($r) & $script:ReplaceText (Join-Path $r 'plans/pcf-001-slice-decomposition.md') '- Base expected total: 8' '- Base expected total: 9' } $authority
    Assert-NegativeMutationFails 'required-slice-unverified' { param($r) & $script:ReplaceText (Join-Path $r $closePath) '`SL-002=PARENT_PLAN_VERIFIED`' '`SL-002=PENDING`' } $authority
    Assert-NegativeMutationFails 'residual-before-cross' {
        param($r)
        $path = Join-Path $r 'expected.json'
        $text = [System.IO.File]::ReadAllText($path)
        $text = $text -replace '"CROSS_SLICE_VERIFIED",\s*"READY_TO_CLOSE_WITH_NO_RESIDUALS"', '"READY_TO_CLOSE_WITH_NO_RESIDUALS", "CROSS_SLICE_VERIFIED"'
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    } $authority
    Assert-NegativeMutationFails 'forced-legacy-migration' { param($r) Add-Content -LiteralPath (Join-Path $r 'README.md') 'Compatibility normalization: forced migration' } $authority
    Assert-NegativeMutationFails 'mixed-artifact-mode' { param($r) & $script:ReplaceText (Join-Path $r $record2) '- artifact_mode: slice-living-record' '- artifact_mode: legacy-separate' } $authority
    Assert-NegativeMutationFails 'removed-three-layer-semantics' { param($r) Add-Content -LiteralPath (Join-Path $r $record1) '## Parent Authorization' } $authority

    $expected = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'expected.json') | ConvertFrom-Json
    $consumerRoot = Join-Path $tempRoot 'consumer'
    New-Item -ItemType Directory -Path $consumerRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $fixtureRoot 'seed/*') -Destination $consumerRoot -Recurse -Force
    $slice1 = $expected.slices[0]
    Copy-Item -Path (Join-Path $fixtureRoot "$($slice1.payload)/*") -Destination $consumerRoot -Recurse -Force
    $evidence1 = Invoke-FixtureVerifier $consumerRoot ([string]$slice1.verifier)
    if ($evidence1.slice -cne 'SL-001' -or $evidence1.verdict -cne 'PARENT_PLAN_VERIFIED' -or $evidence1.snapshot_state -cne 'Active' -or $evidence1.correlation_id -cne 'pcf-001' -or $evidence1.generation -ne 7 -or -not $evidence1.atomic_publish) { throw 'SL-001 runtime evidence mismatch.' }
    $slice2 = $expected.slices[1]
    Copy-Item -Path (Join-Path $fixtureRoot "$($slice2.payload)/*") -Destination $consumerRoot -Recurse -Force
    $evidence2 = Invoke-FixtureVerifier $consumerRoot ([string]$slice2.verifier)
    if ($evidence2.slice -cne 'SL-002' -or $evidence2.verdict -cne 'PARENT_PLAN_VERIFIED' -or $evidence2.postcondition -cne 'Accepted' -or -not $evidence2.reject_observed -or -not $evidence2.stale_generation_rejected -or -not $evidence2.replay_idempotent) { throw 'SL-002 runtime evidence mismatch.' }
    $cross = Invoke-FixtureVerifier $consumerRoot ([string]$expected.cross_slice_verifier)
    if ($cross.verdict -cne 'CROSS_SLICE_VERIFIED' -or $cross.production_entrypoint -cne 'src/StartupFlow.ps1' -or $cross.postcondition -cne 'Accepted' -or $cross.generation -ne 7 -or -not $cross.reject_observed -or -not $cross.stale_generation_rejected -or -not $cross.replay_idempotent) { throw 'Cross-slice runtime evidence mismatch.' }

    $mode = if ([string]::IsNullOrWhiteSpace($InstalledRoot)) { 'source' } else { 'installed' }
    Write-Host "Plan Coverage standalone full-coverage E2E ($mode): PASS"
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('plan-coverage-full-coverage-e2e-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
