# Codex First State

task_slug:
original_user_intent:
source_of_truth:

task_weight:
expansion_required: Yes / No / Unknown
behavior_spec_artifact:
plan_readiness: ReadyForRiskTriage / NeedsPlanBehaviorExpansion / NeedsHumanDecision / Unknown
case_to_plan_mapping_status: Complete / Incomplete / N/A / Unknown
behavior_case_coverage_ledger_artifact:
behavior_case_coverage_ledger_status: Complete / Incomplete / N/A / Unknown
risk_triage_artifact:
risk_triage_artifact_status: Complete / Incomplete / Missing / Unknown
shape_handoff_status: NotStarted / Pending / Ready / Consumed / Invalidated / NotRequired / Blocked / Unknown
remaining_design_uncertainty: None / Unknown / <evidence-backed summary>
completion_scope: N/A / Unknown / <Work IDs and allowed edit surface>
shape_reentry_reason: N/A / Unknown / <trigger and invalidating evidence>
# Compatibility note: `shape_handoff_status` and `shape_reentry_reason` are stable state-field names retained for existing artifacts. They do not name separate agent aliases or a pre-implementation shape-classification gate.
replan_required_items:
- None
current_gate:
next_gate:
recommended_model_tier:
selected_agent_name:
edit_owner:
allowed_to_edit: false
delegation_required: false
current_status:
stop_reason:

allowed_stop_reasons:
- ManualVerificationRequired
- NeedsHumanDecision
- NeedsPlanBehaviorExpansion
- ReplanRequired
- NeedsHigherModelReview
- NeedsSecretInput
- NeedsExternalOperation
- ReadyForCopilotImplementation
- ReadyForDelegatedImplementation (legacy compatibility only)
- ReadyForHighImplementationStart
- ReadyForStandardCompletion
- NeedsHighModelReentry
- BlockedByInvalidCompletionHandoff
- ReadyForCopilotVerification
- ReadyForImplementationHandoffReview
- BlockedByBehaviorCaseCoverageLedger
- RoutingPolicyViolation

## Routing Plan

| Gate | Recommended tier | Expected agent | Edit owner | Stop if unavailable |
| --- | --- | --- | --- | --- |

## Plan Readiness

- expansion_required: Yes / No / Unknown
- behavior_spec_artifact:
- plan_readiness: ReadyForRiskTriage / NeedsPlanBehaviorExpansion / NeedsHumanDecision / Unknown
- case_to_plan_mapping_status: Complete / Incomplete / N/A / Unknown
- behavior_case_ids:
- behavior_case_coverage_ledger_artifact:
- behavior_case_coverage_ledger_status: Complete / Incomplete / N/A / Unknown
- replan_required_items:

## Risk Triage

- risk_triage_artifact: plans/<ticket-or-slug>-change-risk-triage.md
- risk_triage_artifact_status: Complete / Incomplete / Missing / Unknown
- risk_classification:
- guardrail_focus_required: Yes / No / Unknown
- selected_runtime_contracts: <Contract IDs / none / Unknown>
- implementation_realization_risk: Present / Absent / Unclear / Unknown
- recommended_process: normal / advanced-full-coverage / human-decision-wait / higher-model-review / lower-cost-delegated-scan
- recommended_next_step:

## Adaptive Implementation

- shape_handoff_status: NotStarted / Pending / Ready / Consumed / Invalidated / NotRequired / Blocked / Unknown
- remaining_design_uncertainty: None / Unknown / <evidence-backed summary>
- completion_scope: N/A / Unknown / <Work IDs and allowed edit surface>
- shape_reentry_reason: N/A / Unknown / <trigger and invalidating evidence>
- compatibility_note: `shape_*` fields are stable state vocabulary only; canonical implementation owners remain `high-implementation-starter` and `standard-implementation-completer`.
- owner_and_verdict_sequence:
- implementation_result_artifact: plans/<ticket-or-slug>-implementation-execution.md
- tracked_completion_handoff: N/A / plans/<ticket-or-slug>-implementation-completion-handoff.md

## Edit Permission

- allowed_to_edit: Yes / No
- edit_owner: black-box-behavior-spec-kernel / implementation-handoff-review / copilot-high-planner / copilot-risk-triage / high-implementation-starter / standard-implementation-completer / copilot-standard-implementer-legacy / copilot-standard-verifier / copilot-cheap-repo-scanner / human / none
- allowed_paths:
- forbidden_paths:
- required_authorization_artifact:

human_required_items:
- None

artifacts_created:
- None

artifacts_consumed:
- None

unresolved_residuals:
- None

operations_not_allowed_in_current_state:
- Keep `current_status` equal to the actual Adaptive verdict, and switch `selected_agent_name`, `recommended_model_tier`, and `edit_owner` to the active `high-implementation-starter`, `standard-implementation-completer`, or `copilot-standard-verifier` phase.
- Record `delegation_required: true` for both HIGH implementation start/re-entry and STANDARD completion.
- Do not implement before READY.
- Do not select risk/profile/full-coverage before plan_readiness = ReadyForRiskTriage.
- Do not route requirement-elaboration gaps to full-coverage or fix-slice.
- Do not route to implementation-handoff-review until risk_triage_artifact_status = Complete and `plans/<ticket-or-slug>-change-risk-triage.md` exists.
- Do not route non-trivial implementation directly to a standard agent. Start with high-implementation-starter after implementation-handoff-review or an explicitly equivalent gate creates the parent authorization artifact.
- If expansion_required = Yes, do not route to high-implementation-starter until behavior_case_coverage_ledger_status = Complete.
- Do not run standard-implementation-completer without a complete READY_FOR_STANDARD_COMPLETION handoff.
- Return NEEDS_HIGH_MODEL_REENTRY to high-implementation-starter before further implementation edits and do not overlap write owners.
- Do not mark fake / stub / mock-only success as production success.
- Do not perform secret, external service, billing, or production operations without explicit approval.
- Do not close with unresolved ManualVerificationRequired, NeedsHumanDecision, or NeedsHigherModelReview.

## Agent Usage Ledger

| Gate | Agent name | Tier | Model | Edited? | Artifact | Outcome |
| --- | --- | --- | --- | --- | --- | --- |

next_action:
last_updated_summary:
