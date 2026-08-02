---
artifact_type: full-coverage-parent-orchestration-state
schema_version: 2
full_coverage_artifact_layout: compact-slice-record-v2
full_coverage_artifact_layout_source: default-new-flow
parent_plan: plans/<slug>.md
coverage_ledger: plans/<slug>-coverage-ledger.md
implementation_route: adaptive / design-pair
implementation_route_source: default / explicit-user-selection
design_pair_handoff: N/A / plans/<slug>-design-pair-implementation-handoff.md
design_pair_interaction_stage: N/A / target-selection / disposition-confirmation / complete
design_pair_user_evidence: N/A / user-facing turn reference
---

# Full-Coverage Parent Orchestration State

This is the compact resume entrypoint for a fresh full-coverage run. Parent orchestration is the canonical writer. Keep paths, status, and next actions here; retain detailed phase evidence in the Slice Records and Final Record.

## Resume Header

- Process: token-aware-full-coverage-3layer
- Current parent state: `<one state from Parent State Transition Contract>`
- Parent source revision / watch-path freshness:
- Next required action:
- Stop reason:

## Parent State Transition Contract

| State | Allowed next states |
| --- | --- |
| `DECOMPOSED` | `PREPARING`, `BLOCKED` |
| `PREPARING` | `PREPARED`, `PARTIALLY_PREPARED`, `BLOCKED` |
| `PREPARED` | `AUTHORIZING` |
| `AUTHORIZING` | `AUTHORIZED`, `PARTIALLY_AUTHORIZED`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `RETURN_TO_ARCHITECTURE` |
| `AUTHORIZED` | `IMPLEMENTING` |
| `PARTIALLY_AUTHORIZED` | `IMPLEMENTING`, `NEEDS_HUMAN_DECISION` |
| `IMPLEMENTING` | `SLICE_VERIFYING`, `BLOCKED` |
| `SLICE_VERIFYING` | `READY_FOR_FINAL_VERIFICATION`, `FIXING`, `BLOCKED` |
| `FIXING` | `SLICE_VERIFYING`, `BLOCKED` |
| `READY_FOR_FINAL_VERIFICATION` | `CROSS_SLICE_VERIFYING` |
| `CROSS_SLICE_VERIFYING` | `RESIDUAL_DECISION`, `FIXING`, `BLOCKED` |
| `RESIDUAL_DECISION` | `CLOSE_READY`, `WAITING_FOR_HUMAN`, `READY_FOR_FIX`, `REPLAN_REQUIRED`, `ABORT_RECOMMENDED` |
| `WAITING_FOR_HUMAN` | `RESIDUAL_DECISION`, `FIXING`, `ABORT_RECOMMENDED` |
| `CLOSE_READY` | terminal |

## Per-Slice State Transition Contract

| State | Allowed next states |
| --- | --- |
| `BASELINED` | `PREP_IN_PROGRESS` |
| `PREP_IN_PROGRESS` | `PREP_READY`, `BLOCKED`, `NEEDS_FURTHER_DECOMPOSITION`, `NEEDS_HUMAN_DECISION` |
| `PREP_READY` | `AUTHORIZED`, `BLOCKED` |
| `AUTHORIZED` | `DESIGN_PAIR_WAITING`, `IMPL_RUNNING` |
| `DESIGN_PAIR_WAITING` | `IMPL_RUNNING`, `BLOCKED` |
| `IMPL_RUNNING` | `IMPL_DONE`, `BLOCKED`, `REPLAN_REQUIRED`, `NEEDS_HUMAN_DECISION` |
| `IMPL_DONE` | `VERIFYING` |
| `VERIFYING` | `VERIFIED`, `PARTIAL_WITH_FIX`, `MANUAL_RESIDUAL`, `BLOCKED` |
| `PARTIAL_WITH_FIX` | `FIX_RUNNING` |
| `FIX_RUNNING` | `VERIFYING`, `BLOCKED` |
| `VERIFIED` | terminal for slice-local flow |
| `MANUAL_RESIDUAL` | terminal for slice-local flow; parent final gate |
| `BLOCKED` | parent decision / replan |
| `NEEDS_FURTHER_DECOMPOSITION` | decomposition |

## Artifact Index

| Kind | Path | Status | Next action |
| --- | --- | --- | --- |
| Parent Plan | | current / stale / missing / contradicted | |
| Behavior Spec / inline sketch | | current / n/a / stale / missing / contradicted | |
| Parent triage | | current / stale / missing / contradicted | |
| Architecture readiness / baseline | | current / n/a / stale / missing / contradicted | |
| Slice decomposition | | current / stale / missing / contradicted | |
| Canonical Coverage Ledger | | current / stale / missing / contradicted | |
| Full-Coverage Final Record | | pending / current / stale / missing | |

## Slice Execution and Authorization

| Slice | Record | Baseline digest | Prep state | Authorization | Impl state | Verification state | Parallel group | Active owner | Next action |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Parent Authorization Decisions

| Slice | Preparation revision | Baseline digest | Verdict | Parallel group | Blocking reason | Slice record updated? |
| --- | --- | --- | --- | --- | --- | --- |

## Delegation Audit

| Run ID | Phase | Slice | Agent type | Configured model | Hook model | Edit owner | Outcome | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Delegation Compliance

| Rule | Status | Evidence |
| --- | --- | --- |
| Every executable slice has prep evidence | |
| Every authorized non-trivial slice started with HIGH | |
| STANDARD ran only after valid handoff | |
| Re-entry returned to HIGH | |
| Parent did not edit production code/tests | |
| Cross-slice verification completed | |

## Cross-Slice Blockers

| ID | Kind | Status | Next check |
| --- | --- | --- | --- |

## Pending Parent Decisions

| Decision | Required evidence | Owner | Blocking? |
| --- | --- | --- | --- |

## Parent Decisions Made

| Decision | Applies to | Evidence | Status |
| --- | --- | --- | --- |

## Artifact Exception Register

| Artifact | Why separate file is required | Canonical owner | Lifecycle | Merge-back / close rule |
| --- | --- | --- | --- | --- |

Only independent human, tool, confidentiality, concurrent-ownership, or resume-safety lifecycles may use this register. Generic phase output paths are not an exception.

## Final Gate Status

- Cross-slice verification:
- Residual decision:
- Close readiness:

## Recent Checkpoint Delta

- Last state change:
- Files / records updated:
- Important caution for next owner:
