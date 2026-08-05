[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Fail([string]$message) { $failures.Add($message); Write-Error $message -ErrorAction Continue }
function Text([string]$relative) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing file: $relative"; return '' }
    return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
}
function Require([string]$relative, [string]$pattern, [string]$label) {
    if ((Text $relative) -notmatch "(?m)$pattern") { Fail "Missing $label in $relative" }
}
function Forbid([string]$relative, [string]$pattern, [string]$label) {
    if ((Text $relative) -match "(?m)$pattern") { Fail "Prohibited $label in $relative" }
}
function Read-NormalizedText([string]$path) {
    return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
}
function Test-ParentStateHistory([string]$history, [string]$fixtureName) {
    $allowed = @{
        DECOMPOSED = @('PREPARING','BLOCKED','RETURN_TO_ARCHITECTURE'); PREPARING = @('PREPARED','PARTIALLY_PREPARED','BLOCKED','NEEDS_HUMAN_DECISION','RETURN_TO_ARCHITECTURE')
        PREPARED = @('AUTHORIZING','BLOCKED','RETURN_TO_ARCHITECTURE'); PARTIALLY_PREPARED = @('PREPARING','AUTHORIZING','BLOCKED','NEEDS_HUMAN_DECISION','RETURN_TO_ARCHITECTURE')
        AUTHORIZING = @('AUTHORIZED','PARTIALLY_AUTHORIZED','BLOCKED','NEEDS_HUMAN_DECISION','RETURN_TO_ARCHITECTURE'); AUTHORIZED = @('IMPLEMENTING','BLOCKED','RETURN_TO_ARCHITECTURE')
        PARTIALLY_AUTHORIZED = @('IMPLEMENTING','AUTHORIZING','NEEDS_HUMAN_DECISION','BLOCKED','RETURN_TO_ARCHITECTURE'); IMPLEMENTING = @('SLICE_VERIFYING','BLOCKED','NEEDS_HUMAN_DECISION','REPLAN_REQUIRED','RETURN_TO_ARCHITECTURE')
        SLICE_VERIFYING = @('READY_FOR_FINAL_VERIFICATION','FIXING','BLOCKED','NEEDS_HUMAN_DECISION','RETURN_TO_ARCHITECTURE'); FIXING = @('SLICE_VERIFYING','BLOCKED','NEEDS_HUMAN_DECISION','REPLAN_REQUIRED','RETURN_TO_ARCHITECTURE')
        READY_FOR_FINAL_VERIFICATION = @('CROSS_SLICE_VERIFYING','BLOCKED'); CROSS_SLICE_VERIFYING = @('RESIDUAL_DECISION','FIXING','BLOCKED','NEEDS_HUMAN_DECISION','RETURN_TO_ARCHITECTURE')
        RESIDUAL_DECISION = @('CLOSE_READY','WAITING_FOR_HUMAN','READY_FOR_FIX','REPLAN_REQUIRED','ABORT_RECOMMENDED','BLOCKED'); WAITING_FOR_HUMAN = @('RESIDUAL_DECISION','FIXING','REPLAN_REQUIRED','ABORT_RECOMMENDED')
        READY_FOR_FIX = @('FIXING','BLOCKED','REPLAN_REQUIRED','ABORT_RECOMMENDED')
    }
    $states = @($history -split '\s*->\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($states.Count -lt 1) { Fail "Fixture $fixtureName has no parent state history"; return }
    for ($index = 0; $index -lt ($states.Count - 1); $index++) {
        if (-not $allowed.ContainsKey($states[$index]) -or $allowed[$states[$index]] -notcontains $states[$index + 1]) { Fail "Fixture $fixtureName has illegal parent transition $($states[$index]) -> $($states[$index + 1])" }
    }
}

$sliceTemplate = 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/references/full-coverage-slice-record.md'
$finalTemplate = 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/references/full-coverage-final.md'
$stateTemplate = 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/references/full-coverage-parent-orchestration-state.md'
$skill = 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md'
$slicePrep = 'apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-prep.agent.md'

foreach ($template in @($sliceTemplate, $finalTemplate, $stateTemplate)) {
    Require $template '^---' 'frontmatter'
    Require $template 'full_coverage_artifact_layout: compact-slice-record-v2' 'v2 layout metadata'
}
foreach ($field in @('artifact_type:', 'schema_version: 2', 'full_coverage_artifact_layout:', 'parent_plan:')) { Require $stateTemplate $field "State frontmatter $field" }
Require $stateTemplate 'execution_mode: PREP_ONLY / DELEGATED_IMPLEMENTATION' 'Parent State ExecutionMode frontmatter'
foreach ($field in @('artifact_type:', 'schema_version: 2', 'full_coverage_artifact_layout:', 'slice_id:', 'parent_plan:', 'slice_decomposition:', 'coverage_ledger:', 'parent_state:', 'baseline_revision:', 'baseline_digest:', 'record_state:', 'implementation_route:', 'implementation_route_source:')) { Require $sliceTemplate $field "Slice frontmatter $field" }
foreach ($field in @('artifact_type:', 'schema_version: 2', 'full_coverage_artifact_layout:', 'parent_plan:', 'parent_state:', 'coverage_ledger:')) { Require $finalTemplate $field "Final frontmatter $field" }
Require $sliceTemplate '<!-- BEGIN IMMUTABLE SLICE BASELINE -->' 'immutable baseline begin marker'
Require $sliceTemplate '<!-- END IMMUTABLE SLICE BASELINE -->' 'immutable baseline end marker'
if (([regex]::Matches((Text $sliceTemplate), '<!-- BEGIN IMMUTABLE SLICE BASELINE -->')).Count -ne 1) { Fail 'Slice template baseline begin marker must be unique' }
if (([regex]::Matches((Text $sliceTemplate), '^## (Slice Preparation|Parent Authorization|Implementation|Slice Verification|Bounded Fix Passes|Current Handoff)$', 'Multiline')).Count -ne 6) { Fail 'Slice template has missing or duplicate required sections' }
Require $sliceTemplate 'Implementation Completion Handoff' 'tracked implementation handoff section'
Require $finalTemplate '^## Final Verification Snapshot$' 'Final Verification Snapshot'
Require $finalTemplate '^## Residual Decision$' 'Residual Decision'
Require $finalTemplate '^## Close Decision$' 'Close Decision'
Require $finalTemplate 'Owning Slice Record' 'v2 Final Record FixNow owning-slice projection'
Require $finalTemplate 'Authorization revision' 'v2 Final Record FixNow authorization provenance'
foreach ($section in @('Slice Execution and Authorization', 'Parent Authorization Decisions', 'Delegation Audit', 'Delegation Compliance', 'Artifact Exception Register')) { Require $stateTemplate "^## $section$" "Parent State $section" }
Require $stateTemplate 'Current parent state: `<one state from Parent State Transition Contract>`' 'single-source parent current-state reference'
Forbid $stateTemplate 'Current parent state: DECOMPOSED /' 'stale partial parent state list'
foreach ($state in @('DECOMPOSED','PREPARING','PREPARED','PARTIALLY_PREPARED','AUTHORIZING','AUTHORIZED','PARTIALLY_AUTHORIZED','BLOCKED','NEEDS_HUMAN_DECISION','RETURN_TO_ARCHITECTURE','IMPLEMENTING','SLICE_VERIFYING','FIXING','READY_FOR_FINAL_VERIFICATION','CROSS_SLICE_VERIFYING','RESIDUAL_DECISION','CLOSE_READY','WAITING_FOR_HUMAN','READY_FOR_FIX','REPLAN_REQUIRED','ABORT_RECOMMENDED')) { Require $stateTemplate ([regex]::Escape(('`' + $state + '`'))) "parent state $state" }
foreach ($state in @('BLOCKED','NEEDS_HUMAN_DECISION','RETURN_TO_ARCHITECTURE','READY_FOR_FIX','REPLAN_REQUIRED','ABORT_RECOMMENDED','CLOSE_READY')) { Require $stateTemplate ([regex]::Escape('| `' + $state + '` |')) "parent transition row $state" }
Require $stateTemplate 'Recovery / terminal semantics' 'explicit parent recovery semantics'
foreach ($state in @('BASELINED','PREP_IN_PROGRESS','PREP_READY','AUTHORIZED','DESIGN_PAIR_WAITING','IMPL_RUNNING','IMPL_DONE','VERIFYING','VERIFIED','PARTIAL_WITH_FIX','FIX_RUNNING','MANUAL_RESIDUAL','BLOCKED','NEEDS_FURTHER_DECOMPOSITION','NEEDS_HUMAN_DECISION','REPLAN_REQUIRED')) { Require $stateTemplate ([regex]::Escape(('`' + $state + '`'))) "per-slice state $state" }

Require $skill 'compact-slice-record-v2' 'v2 skill route'
Require $skill 'Separate Artifact Creation Gate' 'separate artifact gate'
Require $slicePrep 'READY_FOR_PARENT_AUTHORIZATION' 'v2 slice prep verdict'
Require $slicePrep 'BlockedByArtifactLayoutMismatch' 'layout mismatch fail-closed verdict'
Forbid $slicePrep 'per-slice kernel artifact' 'legacy mandatory slice artifact wording'
Require '.github/agents/plan-slice-decomposition.agent.md' 'Compact Slice Record v2 output' 'decomposition authority inheritance'
Require '.github/agents/verification-kernel.agent.md' 'full-coverage-slice-v2' 'v2 verification context'
Require '.github/agents/cross-slice-verification-kernel.agent.md' 'Full-coverage final record v2' 'v2 final verification output'
Require '.github/agents/residual-decision-gate.agent.md' 'Full-coverage final record v2' 'v2 residual output'
Require 'apm-packages/token-aware-full-coverage-3layer/apm.yml' 'version: 0.6.1' 'full-coverage package version'
Require 'apm-packages/plan-coverage-residual-flow/apm.yml' 'version: 0.9.1' 'plan-coverage package version'
Require 'apm-packages/token-aware-full-coverage-3layer/apm.yml' '^includes: auto\r?$' 'full-coverage automatic reference distribution'
Require 'apm-packages/token-aware-full-coverage-3layer/apm.yml' 'focused embedded checks or legacy compatibility' 'non-mandatory generic dependency semantics'
foreach ($dependency in @('.github/agents/plan-slice-decomposition.agent.md','.github/agents/verification-kernel.agent.md','.github/agents/cross-slice-verification-kernel.agent.md','.github/agents/residual-decision-gate.agent.md','apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution')) { $dependencyPattern = [regex]::Escape($dependency); Require 'apm-packages/token-aware-full-coverage-3layer/apm.yml' $dependencyPattern "required manifest dependency $dependency" }
foreach ($invariant in @('Copyright \(c\) 2026','SPDX-License-Identifier: CC-BY-4.0','PREP_ONLY','DELEGATED_IMPLEMENTATION','Parent State is the mandatory resume entrypoint','Few valid slices and coalescing','Design Pair')) { Require $skill $invariant "preserved operational invariant $invariant" }

# Current v2 contracts must not prescribe a recursive per-slice chain. Historical plans and explicit legacy sections are intentionally excluded.
foreach ($relative in @($skill, 'apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md', 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md', 'docs/token-aware-full-coverage-decomposition-flow.md')) {
    Forbid $relative 'each slice re-enters the complete parent Plan Coverage flow' 'recursive v2 wording'
    Forbid $relative 'every slice must run per-slice `change-risk-triage`' 'mandatory per-slice triage wording'
    Forbid $relative 'every slice must create separate IC / RC / TP artifact' 'mandatory separate contract wording'
    Forbid $relative 'every slice must create separate handoff review artifact' 'mandatory separate handoff wording'
    Forbid $relative 'separate parent review / execution table / usage ledger required in v2' 'mandatory parent split wording'
}

# Generic routes remain installed even though fresh v2 does not create their default artifacts.
foreach ($relative in @('.github/agents/implementation-handoff-review.agent.md', '.github/agents/implementation-execution.agent.md', '.github/agents/verification-kernel.agent.md')) {
    if (-not (Test-Path (Join-Path $repoRoot $relative))) { Fail "Generic compatibility agent missing: $relative" }
}
$allAgentText = (Text '.github/agents/implementation-handoff-review.agent.md') + (Text '.github/agents/implementation-execution.agent.md') + (Text '.github/agents/verification-kernel.agent.md') + (Text '.github/agents/cross-slice-verification-kernel.agent.md') + (Text '.github/agents/residual-decision-gate.agent.md')
foreach ($legacyPath in @('plans/<ticket-or-slug>-implementation-handoff-review.md','plans/<ticket-or-slug>-implementation-execution.md','plans/<ticket-or-slug>-verification-kernel.md','plans/<ticket-or-slug>-cross-slice-verification-kernel.md','plans/<ticket-or-slug>-residual-decision-gate.md')) {
    if (-not $allAgentText.Contains($legacyPath, [StringComparison]::Ordinal)) { Fail "Generic legacy output path missing: $legacyPath" }
}

$fixtureRoot = Join-Path $repoRoot 'tests/full-coverage-slice-flow'
$fixtureExpectations = @{
    'FCV-001-happy-two-slice' = 'CLOSE_READY'
    'FCV-002-focused-contract-inline' = 'READY_FOR_PARENT_AUTHORIZATION'
    'FCV-003-shared-semantics-drift' = 'BLOCKED_BY_ARCHITECTURE_DRIFT'
    'FCV-004-direct-fixnow' = 'SLICE_VERIFIED'
    'FCV-005-human-residual' = 'NEEDS_HUMAN_RESIDUAL_DECISION'
    'FCV-006-legacy-resume' = 'legacy-resume'
    'FCV-007-parallel-ownership' = 'AUTHORIZED_SERIAL_ONLY'
}
foreach ($entry in $fixtureExpectations.GetEnumerator()) {
    $fixture = Join-Path $fixtureRoot $entry.Key
    foreach ($name in @('input.md', 'expected-summary.md', 'run.json')) {
        if (-not (Test-Path (Join-Path $fixture $name))) { Fail "Fixture $($entry.Key) missing $name" }
    }
    $run = Get-Content -Raw -LiteralPath (Join-Path $fixture 'run.json') | ConvertFrom-Json
    $expectedId = $entry.Key.Substring(0, 7)
    if ($run.id -ne $expectedId) { Fail "Fixture $($entry.Key) run ID must be $expectedId" }
    if (-not $run.layout -or -not $run.result) { Fail "Fixture $($entry.Key) run evidence lacks layout or result" }
    if ($entry.Key -ne 'FCV-006-legacy-resume' -and $run.layout -ne 'compact-slice-record-v2') { Fail "Fixture $($entry.Key) must use v2 layout" }
    if ($entry.Key -eq 'FCV-006-legacy-resume' -and $run.layout -ne 'legacy-split-v1') { Fail 'FCV-006 must use legacy layout' }
    if ($run.result -ne $entry.Value) { Fail "Fixture $($entry.Key) result mismatch" }
    if ($entry.Key -ne 'FCV-006-legacy-resume') {
        foreach ($name in @('parent-state.md', 'full-coverage-final.md', 'coverage-ledger.md')) {
            if (-not (Test-Path (Join-Path $fixture $name))) { Fail "Fixture $($entry.Key) missing v2 artifact $name" }
        }
        $sliceRecords = @(Get-ChildItem -LiteralPath $fixture -Filter 'slice-SL-*.md' -File)
        if ($sliceRecords.Count -lt 1) { Fail "Fixture $($entry.Key) must contain at least one Slice Record" }
        $parentState = Text (Join-Path 'tests/full-coverage-slice-flow' $entry.Key 'parent-state.md')
        $finalRecord = Text (Join-Path 'tests/full-coverage-slice-flow' $entry.Key 'full-coverage-final.md')
        $ledger = Text (Join-Path 'tests/full-coverage-slice-flow' $entry.Key 'coverage-ledger.md')
        if ($parentState -notmatch '(?m)^full_coverage_artifact_layout: compact-slice-record-v2$') { Fail "Fixture $($entry.Key) Parent State layout is not v2" }
        if ($parentState -notmatch '(?m)^execution_mode: (PREP_ONLY|DELEGATED_IMPLEMENTATION)$') { Fail "Fixture $($entry.Key) Parent State lacks ExecutionMode" }
        $history = [regex]::Match($parentState, '(?m)^State history: (?<value>.+)$').Groups['value'].Value
        Test-ParentStateHistory $history $entry.Key
        if ($finalRecord -notmatch '(?m)^full_coverage_artifact_layout: compact-slice-record-v2$') { Fail "Fixture $($entry.Key) Final Record layout is not v2" }
        if (($ledger -match '(?m)^\|.*(?:Unclassified|Unknown).*\|') -and $run.result -eq 'CLOSE_READY') { Fail "Fixture $($entry.Key) close-ready ledger has unclassified rows" }
        $digest = [regex]::Match($parentState, '(?m)^authorized_baseline_digest: (?<value>\S+)$').Groups['value'].Value
        $revision = [regex]::Match($parentState, '(?m)^authorization_revision: (?<value>\S+)$').Groups['value'].Value
        if (-not $digest -or -not $revision) { Fail "Fixture $($entry.Key) lacks parent authorization identity" }
        foreach ($sliceRecord in $sliceRecords) {
            $sliceText = Read-NormalizedText $sliceRecord.FullName
            foreach ($section in @('Slice Preparation','Parent Authorization','Implementation','Slice Verification','Bounded Fix Passes','Current Handoff')) {
                if (([regex]::Matches($sliceText, "(?m)^## " + [regex]::Escape($section) + '$')).Count -ne 1) { Fail "Fixture $($entry.Key) Slice Record $($sliceRecord.Name) has non-unique $section section" }
            }
            if ($sliceText -notmatch '(?m)^full_coverage_artifact_layout: compact-slice-record-v2$') { Fail "Fixture $($entry.Key) Slice Record $($sliceRecord.Name) layout is not v2" }
            if ($sliceText -notmatch ('(?m)^baseline_digest: ' + [regex]::Escape($digest) + '$')) { Fail "Fixture $($entry.Key) Slice Record $($sliceRecord.Name) digest is not authorized" }
            if ($sliceText -notmatch ('(?m)^authorization_revision: ' + [regex]::Escape($revision) + '$')) { Fail "Fixture $($entry.Key) Slice Record $($sliceRecord.Name) revision is not authorized" }
        }
        if ($entry.Key -eq 'FCV-004-direct-fixnow') {
            $fixRecord = Read-NormalizedText (Join-Path $fixture 'slice-SL-001.md')
            foreach ($requiredFixField in @('Selector ID / source section-row: FIX-001','Owning Slice Record / Slice ID:','Parent Authorization revision / baseline digest:','Verification rerun required: Yes')) {
                if ($fixRecord -notmatch [regex]::Escape($requiredFixField)) { Fail "Fixture FCV-004 lacks v2 FixNow projection field '$requiredFixField'" }
            }
            foreach ($requiredFinalField in @('| FIX-001 |','| SL-001 | slice-SL-001.md | 4 | digest-fcv004 |','| Yes | reverified |')) {
                if ($finalRecord -notmatch [regex]::Escape($requiredFinalField)) { Fail "Fixture FCV-004 Final Record lacks v2 FixNow projection field '$requiredFinalField'" }
            }
        }
        if ($entry.Key -eq 'FCV-005-human-residual' -and $finalRecord -match 'Close readiness: Yes') { Fail 'Fixture FCV-005 must not become close-ready without a human residual decision' }
        $separateArtifacts = @(Get-ChildItem -LiteralPath $fixture -File | Where-Object { $_.Name -match 'implementation-execution|verification-kernel|residual-decision-gate|agent-usage-ledger|parent-review-gate|slice-execution-table' })
        if ($separateArtifacts.Count -ne 0) { Fail "Fixture $($entry.Key) contains prohibited separate v2 artifacts" }
    }
}
$fixtureEvidence = @{
    'FCV-001-happy-two-slice' = @('PREP_READY','AUTHORIZED_FOR_IMPLEMENTATION','SLICE_VERIFIED','CROSS_SLICE_VERIFIED','CLOSE_READY')
    'FCV-002-focused-contract-inline' = @('Implementation Realization Delta','embedded_output_target','no separate IC artifact','READY_FOR_PARENT_AUTHORIZATION')
    'FCV-003-shared-semantics-drift' = @('BLOCKED_BY_ARCHITECTURE_DRIFT','Architecture Slice Readiness rerun','Implementation started: No')
    'FCV-004-direct-fixnow' = @('Direct FixNow selector','Bounded Fix Passes','Verification rerun: PASS','SLICE_VERIFIED')
    'FCV-005-human-residual' = @('NEEDS_HUMAN_RESIDUAL_DECISION','Close readiness: No','explicit human decision: missing')
    'FCV-006-legacy-resume' = @('legacy-split-v1','auto merge: No','legacy artifacts remain canonical')
    'FCV-007-parallel-ownership' = @('Parallel group: A','Parallel group: serialized-config','AUTHORIZED_SERIAL_ONLY')
}
foreach ($entry in $fixtureEvidence.GetEnumerator()) {
    $fixture = Join-Path $fixtureRoot $entry.Key
    $evidence = ((Get-ChildItem -LiteralPath $fixture -File | ForEach-Object { Read-NormalizedText $_.FullName }) -join "`n")
    foreach ($token in $entry.Value) { if ($evidence -notmatch [regex]::Escape($token)) { Fail "Fixture $($entry.Key) lacks artifact evidence '$token'" } }
}

if ($failures.Count -gt 0) { Write-Host "Full-coverage slice flow validation: FAILED ($($failures.Count))"; exit 1 }
Write-Host 'Full-coverage slice flow validation: PASS'
