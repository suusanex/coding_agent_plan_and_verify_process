[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Fail([string]$message) { $failures.Add($message); Write-Error $message -ErrorAction Continue }
function Text([string]$relative) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing file: $relative"; return '' }
    return [System.IO.File]::ReadAllText($path)
}
function Require([string]$relative, [string]$pattern, [string]$label) {
    if ((Text $relative) -notmatch "(?m)$pattern") { Fail "Missing $label in $relative" }
}
function Forbid([string]$relative, [string]$pattern, [string]$label) {
    if ((Text $relative) -match "(?m)$pattern") { Fail "Prohibited $label in $relative" }
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
foreach ($section in @('Slice Execution and Authorization', 'Parent Authorization Decisions', 'Delegation Audit', 'Delegation Compliance', 'Artifact Exception Register')) { Require $stateTemplate "^## $section$" "Parent State $section" }
Require $stateTemplate 'Current parent state: `<one state from Parent State Transition Contract>`' 'single-source parent current-state reference'
Forbid $stateTemplate 'Current parent state: DECOMPOSED /' 'stale partial parent state list'
foreach ($state in @('DECOMPOSED','PREPARING','PREPARED','PARTIALLY_PREPARED','AUTHORIZING','AUTHORIZED','PARTIALLY_AUTHORIZED','BLOCKED','NEEDS_HUMAN_DECISION','RETURN_TO_ARCHITECTURE','IMPLEMENTING','SLICE_VERIFYING','FIXING','READY_FOR_FINAL_VERIFICATION','CROSS_SLICE_VERIFYING','RESIDUAL_DECISION','CLOSE_READY','WAITING_FOR_HUMAN','READY_FOR_FIX','REPLAN_REQUIRED','ABORT_RECOMMENDED')) { Require $stateTemplate ([regex]::Escape(('`' + $state + '`'))) "parent state $state" }
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
Require 'apm-packages/token-aware-full-coverage-3layer/apm.yml' 'version: 0.6.0' 'full-coverage package version'
Require 'apm-packages/plan-coverage-residual-flow/apm.yml' 'version: 0.9.0' 'plan-coverage package version'
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
foreach ($legacyPath in @('plans/<ticket-or-slug>-implementation-handoff-review.md','plans/<ticket-or-slug>-implementation-execution.md','plans/<ticket-or-slug>-verification-kernel.md','plans/<ticket-or-slug>-cross-slice-verification-kernel.md','plans/<ticket-or-slug>-residual-decision-gate.md')) {
    $allAgentText = (Text '.github/agents/implementation-handoff-review.agent.md') + (Text '.github/agents/implementation-execution.agent.md') + (Text '.github/agents/verification-kernel.agent.md') + (Text '.github/agents/cross-slice-verification-kernel.agent.md') + (Text '.github/agents/residual-decision-gate.agent.md')
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
    foreach ($name in @('input.md', 'actual-artifacts.md', 'expected-summary.md', 'run.json')) {
        if (-not (Test-Path (Join-Path $fixture $name))) { Fail "Fixture $($entry.Key) missing $name" }
    }
    $run = Get-Content -Raw -LiteralPath (Join-Path $fixture 'run.json') | ConvertFrom-Json
    $expectedId = $entry.Key.Substring(0, 7)
    if ($run.id -ne $expectedId) { Fail "Fixture $($entry.Key) run ID must be $expectedId" }
    if (-not $run.layout -or -not $run.result) { Fail "Fixture $($entry.Key) run evidence lacks layout or result" }
    if ($entry.Key -ne 'FCV-006-legacy-resume' -and $run.layout -ne 'compact-slice-record-v2') { Fail "Fixture $($entry.Key) must use v2 layout" }
    if ($entry.Key -eq 'FCV-006-legacy-resume' -and $run.layout -ne 'legacy-split-v1') { Fail 'FCV-006 must use legacy layout' }
    if ($run.result -ne $entry.Value) { Fail "Fixture $($entry.Key) result mismatch" }
}
$happy = Text 'tests/full-coverage-slice-flow/FCV-001-happy-two-slice/actual-artifacts.md'
if (($happy -split "`n" | Where-Object { $_ -match '^plans/' }).Count -ne 6) { Fail 'FCV-001 must list exactly six standard durable artifacts including parent plan' }
if ($happy -match 'parent-review-gate|slice-execution-table|agent-usage-ledger|verification-kernel\.md|residual-decision-gate\.md') { Fail 'FCV-001 contains prohibited post-slice split artifact' }
$fixtureEvidence = @{
    'FCV-001-happy-two-slice' = @('PREP_READY','AUTHORIZED_FOR_IMPLEMENTATION','SLICE_VERIFIED','CROSS_SLICE_VERIFIED','CLOSE_READY')
    'FCV-002-focused-contract-inline' = @('Implementation Realization Delta','embedded_output_target','no separate IC artifact','READY_FOR_PARENT_AUTHORIZATION')
    'FCV-003-shared-semantics-drift' = @('BLOCKED_BY_ARCHITECTURE_DRIFT','Architecture Slice Readiness rerun','Implementation started: No')
    'FCV-004-direct-fixnow' = @('Direct FixNow selector','Bounded Fix Passes','Verification rerun: PASS','SLICE_VERIFIED')
    'FCV-005-human-residual' = @('NEEDS_HUMAN_RESIDUAL_DECISION','Close readiness: No','explicit human decision: missing')
    'FCV-006-legacy-resume' = @('legacy-split-v1','auto merge: No','legacy artifacts remain canonical')
    'FCV-007-parallel-ownership' = @('Parallel group: A','Parallel group: serialized-config','AUTHORIZED_SERIAL_ONLY')
}
foreach ($entry in $fixtureEvidence.GetEnumerator()) { foreach ($token in $entry.Value) { if ((Text (Join-Path 'tests/full-coverage-slice-flow' $entry.Key 'actual-artifacts.md')) -notmatch [regex]::Escape($token)) { Fail "Fixture $($entry.Key) lacks actual evidence '$token'" } } }

if ($failures.Count -gt 0) { Write-Host "Full-coverage slice flow validation: FAILED ($($failures.Count))"; exit 1 }
Write-Host 'Full-coverage slice flow validation: PASS'
