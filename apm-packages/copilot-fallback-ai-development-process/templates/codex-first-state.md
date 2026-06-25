# Codex First State

task_slug:
original_user_intent:
source_of_truth:

task_weight:
expansion_required: Yes / No / Unknown
behavior_spec_artifact:
plan_readiness: ReadyForRiskTriage / NeedsPlanBehaviorExpansion / NeedsHumanDecision / Unknown
case_to_plan_mapping_status: Complete / Incomplete / N/A / Unknown
replan_required_items:
- None
current_gate:
next_gate:
recommended_model_tier:
allowed_to_edit: false
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
- ReadyForCopilotVerification
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
- replan_required_items:

## Edit Permission

- allowed_to_edit: Yes / No
- edit_owner: black-box-behavior-spec-kernel / copilot-high-planner / copilot-risk-triage / copilot-standard-implementer / copilot-standard-verifier / copilot-cheap-repo-scanner / human / none
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
- Do not implement before READY.
- Do not select risk/profile/full-coverage before plan_readiness = ReadyForRiskTriage.
- Do not route requirement-elaboration gaps to full-coverage or fix-slice.
- Do not mark fake / stub / mock-only success as production success.
- Do not perform secret, external service, billing, or production operations without explicit approval.
- Do not close with unresolved ManualVerificationRequired, NeedsHumanDecision, or NeedsHigherModelReview.

## Agent Usage Ledger

| Gate | Agent name | Tier | Model | Edited? | Artifact | Outcome |
| --- | --- | --- | --- | --- | --- | --- |

next_action:
last_updated_summary:
