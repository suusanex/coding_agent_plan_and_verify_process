---
artifact_type: full-coverage-slice-record
schema_version: 2
full_coverage_artifact_layout: compact-slice-record-v2
full_coverage_artifact_layout_source: default-new-flow
slice_id: SL-xxx
parent_plan: plans/<slug>.md
slice_decomposition: plans/<slug>-slice-decomposition.md
coverage_ledger: plans/<slug>-coverage-ledger.md
parent_state: plans/<slug>-parent-orchestration-state.md
baseline_revision: 1
baseline_digest: <sha256>
record_state: BASELINED
implementation_route: adaptive
implementation_route_source: default
---

# Full-Coverage Slice Record: SL-xxx — <name>

<!-- BEGIN IMMUTABLE SLICE BASELINE -->

## Slice Baseline Authority

| Field | Value |
| --- | --- |
| Parent Plan | |
| Behavior Spec / inline sketch | |
| Parent triage | |
| Architecture readiness / baseline | |
| Slice decomposition | |
| Parent source revision / commit | |
| Baseline watch paths | |

## Goal

## Non-goals

## Parent Coverage Assignment

| Parent FR / AC | Slice responsibility | Verification route |
| --- | --- | --- |

## Behavior Case Assignment

| Case ID | Parent FR / AC | Disposition | Local / XC evidence route |
| --- | --- | --- | --- |

## Cross-Slice Roles

| XC ID | Role | Producer / consumer | Required fields / state / identifiers | Final verification requirement |
| --- | --- | --- | --- | --- |

## Affected Components and Expected Change Surface

## Dependencies and Execution Constraints

## Shared Architecture Invariants Consumed

## Escalation Boundaries

- Shared semantics that this slice must not redefine:
- Changes requiring Architecture Slice Readiness rerun:
- Conditions requiring further decomposition:
- Conditions requiring human decision:

<!-- END IMMUTABLE SLICE BASELINE -->

## Slice Preparation

### Preparation Metadata

| Field | Value |
| --- | --- |
| Preparation revision | |
| Baseline digest verified | Yes / No |
| Input freshness | Current / Stale / Unclear |
| Prepared by / integrated by | |

### Inherited Authority Check

| Authority | Source | Inherited without re-derivation? | Contradiction / delta |
| --- | --- | --- | --- |

### Slice-Local Risk Delta

| Delta ID | New or changed risk | Local / Shared | Evidence | Required action |
| --- | --- | --- | --- | --- |

### Implementation Realization Delta

| IC ID | Dependency / API / production address | Evidence | Decision / unresolved status | Prohibited substitution |
| --- | --- | --- | --- | --- |

### Slice-Local Runtime Contract Delta

| RC ID | Producer | Consumer | Mechanism | Required behavior / fields | Production address | Status |
| --- | --- | --- | --- | --- | --- | --- |

### Slice-Local Test Design Delta

| TP ID | Related FR / AC / Case / RC | Observable | Test / manual route | Substitute used? | Production binding required? |
| --- | --- | --- | --- | --- | --- |

### Production Binding Requirements

### Architecture Conformance

| Check | Status | Evidence |
| --- | --- | --- |
| Baseline authority current | |
| Shared semantics unchanged | |
| XC role unchanged | |
| Production ownership non-overlapping | |
| Architecture gate rerun required | |

### Inline Slice Ready Gate

| Check | Status | Evidence |
| --- | --- | --- |
| Baseline digest current | PASS / FAIL |
| Parent assignment complete | PASS / FAIL |
| Behavior Case route complete | PASS / FAIL / N/A |
| Slice-local implementation uncertainty resolved or explicitly blocking | PASS / FAIL / N/A |
| Slice-local RC / TP coverage sufficient | PASS / FAIL / N/A |
| Production binding requirements identified | PASS / FAIL / N/A |
| Shared architecture conformance | PASS / FAIL |
| Human decisions resolved | PASS / FAIL / N/A |
| Ready for parent authorization | PASS / FAIL |

### Preparation Verdict

`READY_FOR_PARENT_AUTHORIZATION` / `BLOCKED_BY_SLICE_BASELINE_MISMATCH` / `BLOCKED_BY_IMPLEMENTATION_REALIZATION` / `BLOCKED_BY_ARCHITECTURE_DRIFT` / `NEEDS_FURTHER_DECOMPOSITION` / `NEEDS_HUMAN_DECISION`

## Parent Authorization

| Field | Value |
| --- | --- |
| Authorization revision | |
| Preparation revision authorized | |
| Baseline digest authorized | |
| Verdict | AUTHORIZED_FOR_IMPLEMENTATION / AUTHORIZED_SERIAL_ONLY / BLOCKED / NEEDS_HUMAN_DECISION / RETURN_TO_ARCHITECTURE_READINESS / NEEDS_FURTHER_DECOMPOSITION |
| Parallel group / active edit owner | |
| Allowed bounded scope | |
| Required preconditions / blocking reason | |
| Parent state evidence | |

## Design Pair

- Route: adaptive / design-pair
- Handoff: N/A / path
- Interaction stage:
- User evidence:
- Locked Decision IDs:
- Adaptive allowed now: Yes / No

## Implementation

### Owner and Verdict Sequence

| Run ID | Agent | Model role | Verdict | Edit owner | Evidence |
| --- | --- | --- | --- | --- | --- |

### Implementation Completion Handoff

### Changed Files

### Implementation Self-Map

| Change ID | Change | File / Symbol | Reason | Parent item | Case IDs | SL / XC / RC / TP / IC / Gap | Assumption | Review hint |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Checks Run

### Checks Not Run

### Production Binding Evidence

### Remaining Work

### Implementation Verdict

## Slice Verification

### Verification Metadata

### Verification Scope

### Runtime Contract / Test Point Verification

### Stub-to-Production Binding

### Behavior Case Evidence

### Production Wiring and Forbidden-State Checks

### Direct FixNow Selectors

### Slice Coverage Ledger Delta

### Verification Verdict

`SLICE_VERIFIED` / `SLICE_VERIFIED_WITH_PARENT_RESIDUALS` / `SLICE_PARTIAL_WITH_FIX_CANDIDATES` / applicable `BLOCKED_*`

## Bounded Fix Passes

### FIX-xxx

- Selector source:
- Selector ID / source section-row:
- Owning Slice Record / Slice ID:
- Parent Authorization revision / baseline digest:
- Scope:
- Files changed:
- Checks:
- Result:
- Verification rerun required: Yes

## Current Handoff

- Current slice state:
- Current authority revision:
- Next action:
- Blocking items:
- Do not redo:
- Parent-visible residuals:
