# Codex First State

task_slug:
original_user_intent:
source_of_truth:

current_gate:
next_gate:
recommended_model_tier:
allowed_to_edit: false
current_status:
stop_reason:

allowed_stop_reasons:
- DelegationRequired
- DelegationUnavailable
- DelegationEvidenceMissing
- ParentDirectExecutionException
- ParentDirectExecutionNotAllowed
- RoutingPolicyViolation
- BlockedByMissingDelegationLedger
- ReadyForDelegatedImplementation
- ReadyForDelegatedVerification

## Routing Plan

| Gate | Recommended tier | Delegation required | Expected agent type | Edit owner | Parent may execute directly? | Stop if unavailable |
| --- | --- | --- | --- | --- | --- | --- |

## Edit Permission

- allowed_to_edit: Yes / No
- edit_owner: parent / standard-implementer / standard-verifier / cheap-repo-scanner / cheap-doc-consistency / cheap-artifact-format-checker / human / none
- parent_direct_edit_allowed: Yes / No
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
- Do not parent-direct execute a gate with DelegationRequired = Yes unless ParentDirectExecutionException has explicit human approval.
- Do not mark implementation complete without observed standard-implementer run or accepted exception.
- Do not mark verification complete without observed standard-verifier run or accepted exception.
- Do not perform secret, external service, billing, or production operations without explicit approval.
- Do not close with unresolved ManualVerificationRequired, NeedsHumanDecision, or NeedsHigherModelReview.
- Do not close with DelegationCompliance = FAIL or missing Agent Usage Ledger.

## Agent Usage Ledger

### Expected delegation

| Gate | Delegation required | Expected agent | Expected tier | Edit owner | Reason |
| --- | --- | --- | --- | --- | --- |

### Observed runs

| Run ID | Gate | Agent name | Agent type | Model | Reasoning effort | Edited? | Artifact | Outcome |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Delegation compliance

| Check | Status | Evidence |
| --- | --- | --- |
| CHEAP work delegated when required | PASS / FAIL / N/A | |
| STANDARD implementation delegated | PASS / FAIL / N/A | |
| STANDARD verification delegated | PASS / FAIL / N/A | |
| Parent direct execution exception documented | PASS / FAIL / N/A | |

delegation_compliance: PASS / FAIL / EXCEPTION_ACCEPTED / N/A

next_action:
last_updated_summary:
