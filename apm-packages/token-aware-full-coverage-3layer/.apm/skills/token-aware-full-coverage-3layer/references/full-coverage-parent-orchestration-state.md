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
execution_mode: PREP_ONLY / DELEGATED_IMPLEMENTATION
---

# Full-Coverage Parent Orchestration State

This is the compact resume entrypoint for a fresh full-coverage run. Parent orchestration is the canonical writer. Keep paths, status, and next actions here; retain detailed phase evidence in the Slice Records and Final Record.

## Resume Header

- Process: token-aware-full-coverage-3layer
- ExecutionMode: `PREP_ONLY` / `DELEGATED_IMPLEMENTATION`
- Current parent state: `<one state from Parent State Transition Contract>`
- Parent source revision / watch-path freshness:
- Next required action:
- Stop reason:

## Parent State Transition Contract

| State | Allowed next states | Recovery / terminal semantics |
| --- | --- | --- |
| `DECOMPOSED` | `PREPARING`, `BLOCKED`, `RETURN_TO_ARCHITECTURE` | Start preparation; return to architecture when decomposition contradicts the baseline. |
| `PREPARING` | `PREPARED`, `PARTIALLY_PREPARED`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `RETURN_TO_ARCHITECTURE` | Resume only from current Slice Records; escalate shared drift. |
| `PREPARED` | `AUTHORIZING`, `BLOCKED`, `RETURN_TO_ARCHITECTURE` | Authorize only same-digest preparation. |
| `PARTIALLY_PREPARED` | `PREPARING`, `AUTHORIZING`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `RETURN_TO_ARCHITECTURE` | Prepare remaining slices or authorize only the explicitly complete subset. |
| `AUTHORIZING` | `AUTHORIZED`, `PARTIALLY_AUTHORIZED`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `RETURN_TO_ARCHITECTURE` | Correct authorization evidence or return shared drift. |
| `AUTHORIZED` | `IMPLEMENTING`, `BLOCKED`, `RETURN_TO_ARCHITECTURE` | Begin only the authorized Slice Record set. |
| `PARTIALLY_AUTHORIZED` | `IMPLEMENTING`, `AUTHORIZING`, `NEEDS_HUMAN_DECISION`, `BLOCKED`, `RETURN_TO_ARCHITECTURE` | Implement the authorized subset; recover by authorization or decision. |
| `IMPLEMENTING` | `SLICE_VERIFYING`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `REPLAN_REQUIRED`, `RETURN_TO_ARCHITECTURE` | Resume through the owning Slice Record; replan or return architecture if local work changes shared authority. |
| `SLICE_VERIFYING` | `READY_FOR_FINAL_VERIFICATION`, `FIXING`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `RETURN_TO_ARCHITECTURE` | Rerun verification after a bounded repair; do not close cross-slice facts here. |
| `FIXING` | `SLICE_VERIFYING`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `REPLAN_REQUIRED`, `RETURN_TO_ARCHITECTURE` | Repair only from a compatible selector and rerun formal verification. |
| `READY_FOR_FINAL_VERIFICATION` | `CROSS_SLICE_VERIFYING`, `BLOCKED` | Resume Final Record verification. |
| `CROSS_SLICE_VERIFYING` | `RESIDUAL_DECISION`, `FIXING`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `RETURN_TO_ARCHITECTURE` | Route a local owning-slice fix through the Slice Record; otherwise return architecture. |
| `RESIDUAL_DECISION` | `CLOSE_READY`, `WAITING_FOR_HUMAN`, `READY_FOR_FIX`, `REPLAN_REQUIRED`, `ABORT_RECOMMENDED`, `BLOCKED` | Classify every residual before close. |
| `WAITING_FOR_HUMAN` | `RESIDUAL_DECISION`, `FIXING`, `REPLAN_REQUIRED`, `ABORT_RECOMMENDED` | Resume only after the recorded human decision. |
| `READY_FOR_FIX` | `FIXING`, `BLOCKED`, `REPLAN_REQUIRED`, `ABORT_RECOMMENDED` | Project each selected selector to one owning Slice Record, then repair and reverify. |
| `NEEDS_HUMAN_DECISION` | `PREPARING`, `AUTHORIZING`, `IMPLEMENTING`, `SLICE_VERIFYING`, `FIXING`, `RESIDUAL_DECISION`, `REPLAN_REQUIRED`, `ABORT_RECOMMENDED` | Record the decision and return to the blocked phase; no implicit fallback. |
| `RETURN_TO_ARCHITECTURE` | `DECOMPOSED`, `REPLAN_REQUIRED`, `ABORT_RECOMMENDED` | Rerun Architecture Slice Readiness, then replace the stale decomposition before resuming. |
| `BLOCKED` | `PREPARING`, `AUTHORIZING`, `IMPLEMENTING`, `SLICE_VERIFYING`, `FIXING`, `READY_FOR_FINAL_VERIFICATION`, `CROSS_SLICE_VERIFYING`, `RESIDUAL_DECISION`, `NEEDS_HUMAN_DECISION`, `RETURN_TO_ARCHITECTURE`, `REPLAN_REQUIRED`, `ABORT_RECOMMENDED` | Preserve the stop reason; resume only at the recorded phase after its blocker is resolved. |
| `REPLAN_REQUIRED` | `DECOMPOSED`, `ABORT_RECOMMENDED` | Replace or explicitly abandon the parent Plan; never reuse stale authorization. |
| `ABORT_RECOMMENDED` | terminal after an explicit human decision | Preserve artifacts and reason; a new run requires new authority. |
| `CLOSE_READY` | terminal | Terminal only after Final Record and ledger prove close readiness. |

## Per-Slice State Transition Contract

| State | Allowed next states | Recovery / terminal semantics |
| --- | --- | --- |
| `BASELINED` | `PREP_IN_PROGRESS` | Begin delta-only preparation. |
| `PREP_IN_PROGRESS` | `PREP_READY`, `BLOCKED`, `NEEDS_FURTHER_DECOMPOSITION`, `NEEDS_HUMAN_DECISION` | Resume local preparation or escalate. |
| `PREP_READY` | `AUTHORIZED`, `BLOCKED` | Await same-digest parent authorization. |
| `AUTHORIZED` | `DESIGN_PAIR_WAITING`, `IMPL_RUNNING` | Start only the authorized route. |
| `DESIGN_PAIR_WAITING` | `IMPL_RUNNING`, `BLOCKED`, `NEEDS_HUMAN_DECISION` | Resume only after valid explicit Design Pair evidence. |
| `IMPL_RUNNING` | `IMPL_DONE`, `BLOCKED`, `REPLAN_REQUIRED`, `NEEDS_HUMAN_DECISION` | Preserve implementation handoff; return shared changes to parent. |
| `IMPL_DONE` | `VERIFYING` | Continue to independent verification. |
| `VERIFYING` | `VERIFIED`, `PARTIAL_WITH_FIX`, `MANUAL_RESIDUAL`, `BLOCKED`, `NEEDS_HUMAN_DECISION` | A repair requires a selector and later rerun. |
| `PARTIAL_WITH_FIX` | `FIX_RUNNING`, `MANUAL_RESIDUAL` | Parent chooses selected repair or residual route. |
| `FIX_RUNNING` | `VERIFYING`, `BLOCKED`, `NEEDS_HUMAN_DECISION`, `REPLAN_REQUIRED` | Rerun formal verification before a verified state. |
| `VERIFIED` | terminal for slice-local flow | Final Record owns parent close. |
| `MANUAL_RESIDUAL` | terminal for slice-local flow; parent final gate | Parent residual decision owns recovery. |
| `BLOCKED` | `PREP_IN_PROGRESS`, `AUTHORIZED`, `IMPL_RUNNING`, `VERIFYING`, `FIX_RUNNING`, `NEEDS_HUMAN_DECISION`, `REPLAN_REQUIRED` | Resume at the recorded phase only after the parent resolves its blocker. |
| `NEEDS_FURTHER_DECOMPOSITION` | decomposition | Return to the parent architecture/decomposition route. |
| `NEEDS_HUMAN_DECISION` | `PREP_IN_PROGRESS`, `AUTHORIZED`, `IMPL_RUNNING`, `VERIFYING`, `FIX_RUNNING`, `REPLAN_REQUIRED` | Resume only with recorded human evidence. |
| `REPLAN_REQUIRED` | decomposition | Supersede the stale slice baseline. |

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
