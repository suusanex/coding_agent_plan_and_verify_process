---
applyTo: "**"
---

# State And Close Rules

Use `plans/<slug>/codex-first-state.md` as the compatible state artifact.

## Required state fields

- `task_slug`
- `original_user_intent`
- `source_of_truth`
- `current_gate`
- `next_gate`
- `recommended_model_tier`
- `selected_agent_name`
- `edit_owner`
- `delegation_required`
- `risk_triage_artifact`
- `risk_triage_artifact_status`
- `behavior_case_coverage_ledger_artifact`
- `behavior_case_coverage_ledger_status`
- `shape_handoff_status`
- `remaining_design_uncertainty`
- `completion_scope`
- `shape_reentry_reason`
- `allowed_to_edit`
- `current_status`
- `stop_reason`
- Routing Plan
- Edit Permission
- Agent Usage Ledger
- `unresolved_residuals`
- `next_action`

## Close blockers

Do not close when any of these remain unresolved:

- `ManualVerificationRequired`
- `NeedsHumanDecision`
- `NeedsHigherModelReview`
- missing production implementation or wiring
- fake / stub / mock-only success
- missing or incomplete `plans/<slug>-change-risk-triage.md` before implementation-handoff-review
- missing implementation-handoff-review parent authorization artifact before HIGH_MODEL implementation start
- STANDARD_MODEL implementation without a valid `READY_FOR_STANDARD_COMPLETION` handoff
- `NEEDS_HIGH_MODEL_REENTRY` that did not return to `high-implementation-starter`
- overlapping HIGH_MODEL and STANDARD_MODEL write ownership
- `Expansion required = Yes` with `behavior_case_coverage_ledger_status` other than `Complete`
- secret / production / billing / external operation without explicit approval

`ReadyToClose` means all acceptance criteria have evidence and no close blocker remains. `ReadyToCloseWithAcceptedResiduals` requires explicit human decision for every accepted residual.
