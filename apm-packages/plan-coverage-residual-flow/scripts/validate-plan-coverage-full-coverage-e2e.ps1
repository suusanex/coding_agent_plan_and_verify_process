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
    $pattern = '(?ms)^```md\s*\n(?<template>' + $HeadingPattern + '.*?)^```\s*$'
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
        'residual-decision-gate.agent.md'
    )
    if ([string]::IsNullOrWhiteSpace($InstalledRoot)) {
        $files = [ordered]@{
            PlanCoverageSkill = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/SKILL.md'
            SliceLivingRecord = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/references/full-coverage-slice-living-record.md'
            FullCoverageClose = Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow/references/full-coverage-close.md'
        }
        foreach ($leaf in $agentLeaves) {
            $files[$leaf] = Join-Path $repoRoot ".github/agents/$leaf"
        }
    }
    else {
        $resolvedInstalledRoot = (Resolve-Path -LiteralPath $InstalledRoot).Path
        $files = [ordered]@{
            PlanCoverageSkill = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/SKILL.md'
            SliceLivingRecord = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/references/full-coverage-slice-living-record.md'
            FullCoverageClose = Join-Path $resolvedInstalledRoot '.agents/skills/plan-coverage-residual-flow/references/full-coverage-close.md'
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

    $requiredOrder = 'ReadyForRiskTriage,full-coverage,ReadyForSliceDecomposition,SL-001,SL-002,CROSS_SLICE_VERIFIED,READY_TO_CLOSE_WITH_NO_RESIDUALS'
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

    foreach ($conditional in @($expected.conditional_artifacts)) {
        if ([string]::IsNullOrWhiteSpace([string]$conditional.path) -or [string]::IsNullOrWhiteSpace([string]$conditional.condition)) {
            $errors.Add('Every conditional artifact needs path and condition.')
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
    $separatePattern = '^pcf-001-slice-SL-\d{3}-(?:change-risk-triage|implementation-contract-kernel|runtime-contract-kernel|test-design-kernel|implementation-handoff-review|implementation-execution|verification-kernel)\.md$'
    foreach ($file in @(Get-ChildItem -LiteralPath $plansRoot -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -cmatch $separatePattern) {
            $errors.Add("Separate per-slice artifact bypassed Artifact Creation Gate: $($file.Name)")
        }
    }
    if (@(Get-ChildItem -LiteralPath $plansRoot -Filter '*.md' -File).Count -ne ($baseExpected + @($expected.conditional_artifacts).Count)) {
        $errors.Add('Artifact count exceeds the declared base plus conditional budget.')
    }
    if ($errors.Count -gt 0) { return $errors }

    $livingTemplate = Get-MarkdownTemplate (Get-NormalizedText $Authority['SliceLivingRecord']) '# SL-xxx: <slice name>' 'Slice Living Record'
    $closeTemplate = Get-MarkdownTemplate (Get-NormalizedText $Authority['FullCoverageClose']) '# Full-Coverage Close Record' 'Full-Coverage Close Record'
    $decomposition = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-slice-decomposition.md')
    $ledger = Get-NormalizedText (Join-Path $Root ([string]$expected.coverage_ledger))
    $close = Get-NormalizedText (Join-Path $Root ([string]$expected.full_coverage_close))
    Add-TemplateShapeErrors $errors $close $closeTemplate 'Full-Coverage Close Record'

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
        if ($record -cnotmatch '(?m)^- Implementation route: adaptive / default$' -or $record -cnotmatch '`COMPLETED_BY_HIGH_MODEL`' -or $record -cnotmatch '(?m)^### Implementation Self-Map$') {
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
    if ($close -cnotmatch '(?m)^- Required slices independently verified: `SL-001=PARENT_PLAN_VERIFIED`, `SL-002=PARENT_PLAN_VERIFIED`$') {
        $errors.Add('Every required slice must be independently verified before cross-slice verification.')
    }
    if ($close -cnotmatch '(?m)^- Formal residual-decision-gate verdict: `READY_TO_CLOSE_WITH_NO_RESIDUALS`$' -or $close -cnotmatch '(?m)^- Cross-slice verdict consumed: `CROSS_SLICE_VERIFIED`$') {
        $errors.Add('Residual Decision must consume the formal cross-slice verdict before close.')
    }
    if ($close.IndexOf('## Cross-Slice Verification', [StringComparison]::Ordinal) -gt $close.IndexOf('## Residual Decision', [StringComparison]::Ordinal)) {
        $errors.Add('Residual Decision appears before Cross-Slice Verification.')
    }
    if ($close -cmatch '(?m)^\| `(?:CROSS-VERIFY|RESIDUAL)-[^|]+\|.*\| No \|$') {
        $errors.Add('Close record contains a pending Coverage Ledger Delta.')
    }
    if ($ledger -cnotmatch '(?m)^\| No fake-only completion \| PASS \|' -or $ledger -cnotmatch '(?m)^\| No unclassified delta remains \| PASS \|') {
        $errors.Add('Canonical ledger is not close-ready.')
    }

    $readiness = Get-NormalizedText (Join-Path $Root 'plans/pcf-001-architecture-slice-readiness.md')
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

function Set-TextReplacement([string]$Path, [string]$Old, [string]$New) {
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
        'legacy/separate', 'pending Coverage Ledger Delta'
    )) {
        if ($authorityText -cnotmatch [regex]::Escape($pattern)) { throw "Contract authority is missing: $pattern" }
    }
    Assert-FixtureValid $fixtureRoot 'PCF-001' $authority

    $record1 = 'plans/pcf-001-slice-SL-001.md'
    $record2 = 'plans/pcf-001-slice-SL-002.md'
    $closePath = 'plans/pcf-001-full-coverage-close.md'
    Assert-NegativeMutationFails 'missing-required-section' { param($r) Set-TextReplacement (Join-Path $r $record1) '## Runtime Contract' '## Omitted Runtime Contract' } $authority
    Assert-NegativeMutationFails 'owner-outside-section' { param($r) Add-Content -LiteralPath (Join-Path $r $record1) '- Unauthorized section write attempted: Runtime Contract by verification-kernel' } $authority
    foreach ($verdict in @('Drift', 'Unclear')) {
        Assert-NegativeMutationFails "architecture-$($verdict.ToLowerInvariant())" { param($r) Set-TextReplacement (Join-Path $r $record2) '- Architecture compatibility: Match' "- Architecture compatibility: $verdict" }.GetNewClosure() $authority
    }
    Assert-NegativeMutationFails 'missing-independent-verification' { param($r) Set-TextReplacement (Join-Path $r $record2) '- Formal verification-kernel verdict: `PARENT_PLAN_VERIFIED`' '- Formal verification-kernel verdict: pending' } $authority
    Assert-NegativeMutationFails 'missing-production-binding' { param($r) Set-TextReplacement (Join-Path $r 'expected.json') 'src/StartupFlow.ps1' 'src/MissingStartupFlow.ps1' } $authority
    Assert-NegativeMutationFails 'fake-only-evidence' { param($r) Set-TextReplacement (Join-Path $r $record1) '- Fake / stub / mock assessment: no substitute used.' '- Fake / stub / mock assessment: fake-only evidence.' } $authority
    Assert-NegativeMutationFails 'xc-field-continuity-missing' { param($r) Set-TextReplacement (Join-Path $r $record1) 'XC-001' 'XC-MISSING' } $authority
    Assert-NegativeMutationFails 'mapping-missing' { param($r) Set-TextReplacement (Join-Path $r $record1) 'CASE-001' 'CASE-MISSING' } $authority
    Assert-NegativeMutationFails 'pending-before-verification' { param($r) Set-TextReplacement (Join-Path $r $record1) '| Yes |' '| No |' } $authority
    Assert-NegativeMutationFails 'pending-before-close' { param($r) Set-TextReplacement (Join-Path $r $closePath) '- Pending Coverage Ledger Delta count: 0' '- Pending Coverage Ledger Delta count: 1' } $authority
    Assert-NegativeMutationFails 'ledger-contradiction' { param($r) Set-TextReplacement (Join-Path $r $closePath) '- Canonical ledger consistency: PASS' '- Canonical ledger consistency: FAIL' } $authority
    Assert-NegativeMutationFails 'ungated-separate-artifact' { param($r) Copy-Item (Join-Path $r $record1) (Join-Path $r 'plans/pcf-001-slice-SL-001-runtime-contract-kernel.md') } $authority
    Assert-NegativeMutationFails 'artifact-budget-exceeded' { param($r) Set-TextReplacement (Join-Path $r 'plans/pcf-001-slice-decomposition.md') '- Base expected total: 8' '- Base expected total: 9' } $authority
    Assert-NegativeMutationFails 'required-slice-unverified' { param($r) Set-TextReplacement (Join-Path $r $closePath) '`SL-002=PARENT_PLAN_VERIFIED`' '`SL-002=PENDING`' } $authority
    Assert-NegativeMutationFails 'residual-before-cross' {
        param($r)
        $path = Join-Path $r 'expected.json'
        $text = [System.IO.File]::ReadAllText($path)
        $text = $text -replace '"CROSS_SLICE_VERIFIED",\s*"READY_TO_CLOSE_WITH_NO_RESIDUALS"', '"READY_TO_CLOSE_WITH_NO_RESIDUALS", "CROSS_SLICE_VERIFIED"'
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    } $authority
    Assert-NegativeMutationFails 'forced-legacy-migration' { param($r) Add-Content -LiteralPath (Join-Path $r 'README.md') 'Compatibility normalization: forced migration' } $authority
    Assert-NegativeMutationFails 'mixed-artifact-mode' { param($r) Set-TextReplacement (Join-Path $r $record2) '- artifact_mode: slice-living-record' '- artifact_mode: legacy-separate' } $authority
    Assert-NegativeMutationFails 'removed-three-layer-semantics' { param($r) Add-Content -LiteralPath (Join-Path $r $record1) '## Parent Authorization' } $authority

    $expected = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'expected.json') | ConvertFrom-Json
    $consumerRoot = Join-Path $tempRoot 'consumer'
    New-Item -ItemType Directory -Path $consumerRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $fixtureRoot 'seed/*') -Destination $consumerRoot -Recurse -Force
    $slice1 = $expected.slices[0]
    Copy-Item -Path (Join-Path $fixtureRoot "$($slice1.payload)/*") -Destination $consumerRoot -Recurse -Force
    $evidence1 = Invoke-FixtureVerifier $consumerRoot ([string]$slice1.verifier)
    if ($evidence1.slice -cne 'SL-001' -or $evidence1.verdict -cne 'PARENT_PLAN_VERIFIED' -or $evidence1.snapshot_state -cne 'Active' -or $evidence1.correlation_id -cne 'pcf-001') { throw 'SL-001 runtime evidence mismatch.' }
    $slice2 = $expected.slices[1]
    Copy-Item -Path (Join-Path $fixtureRoot "$($slice2.payload)/*") -Destination $consumerRoot -Recurse -Force
    $evidence2 = Invoke-FixtureVerifier $consumerRoot ([string]$slice2.verifier)
    if ($evidence2.slice -cne 'SL-002' -or $evidence2.verdict -cne 'PARENT_PLAN_VERIFIED' -or $evidence2.postcondition -cne 'Accepted' -or -not $evidence2.reject_observed) { throw 'SL-002 runtime evidence mismatch.' }
    $cross = Invoke-FixtureVerifier $consumerRoot ([string]$expected.cross_slice_verifier)
    if ($cross.verdict -cne 'CROSS_SLICE_VERIFIED' -or $cross.production_entrypoint -cne 'src/StartupFlow.ps1' -or $cross.postcondition -cne 'Accepted' -or -not $cross.reject_observed) { throw 'Cross-slice runtime evidence mismatch.' }

    $mode = if ([string]::IsNullOrWhiteSpace($InstalledRoot)) { 'source' } else { 'installed' }
    Write-Host "Plan Coverage standalone full-coverage E2E ($mode): PASS"
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('plan-coverage-full-coverage-e2e-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
