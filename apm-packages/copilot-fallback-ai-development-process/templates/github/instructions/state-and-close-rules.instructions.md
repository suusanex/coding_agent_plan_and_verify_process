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
- `risk_triage_artifact`
- `risk_triage_artifact_status`
- `behavior_case_coverage_ledger_artifact`
- `behavior_case_coverage_ledger_status`
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
- missing implementation-handoff-review parent authorization artifact before standard implementation
- `Expansion required = Yes` with `behavior_case_coverage_ledger_status` other than `Complete`
- secret / production / billing / external operation without explicit approval

`ReadyToClose` means all acceptance criteria have evidence and no close blocker remains. `ReadyToCloseWithAcceptedResiduals` requires explicit human decision for every accepted residual.
