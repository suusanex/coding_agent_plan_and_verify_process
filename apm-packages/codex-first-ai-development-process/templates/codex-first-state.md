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
replan_required_items:
- None
current_gate:
next_gate:
selected_process: normal / advanced-full-coverage / human-decision-wait / higher-model-review / lower-cost-delegated-scan
recommended_model_tier:
model_tier_recommendation:
execution_mode: ROUTE_ONLY / DELEGATED_WORK / PARENT_DIRECT_WORK / TRIVIAL_PARENT_FIX
selected_agent_name:
selected_agent_type:
agent_subagent_plan:
configured_model:
configured_reasoning_effort:
hook_model: unknown
reported_model:
effective_model: unknown
allowed_to_edit: No
delegation_required: No
current_status:
stop_reason:
stop_ready_gate:
parent_direct_work_reason:
delegation_violation: No
cost_saving_delegation_countable: No

allowed_stop_reasons:
- DelegationRequired
- NeedsHumanDecision
- NeedsPlanBehaviorExpansion
- ReplanRequired
- ManualVerificationRequired
- NeedsHigherModelReview
- NeedsSecretInput
- NeedsExternalOperation
- Blocked
- TooCostlyForCurrentPass
- ReadyButAwaitingHumanApproval
- DelegationUnavailable
- DelegationEvidenceMissing
- ParentDirectExecutionException
- ParentDirectExecutionNotAllowed
- RoutingPolicyViolation
- BlockedByMissingDelegationLedger
- ReadyForDelegatedImplementation
- ReadyForDelegatedVerification
- ReadyForImplementationHandoffReview
- BlockedByBehaviorCaseCoverageLedger

## Routing Plan

| Gate | Recommended tier | Delegation required | Expected agent type | Edit owner | Parent may execute directly? | Stop if unavailable |
| --- | --- | --- | --- | --- | --- | --- |

## Task Weight

- task_weight: trivial-local / small-bounded / medium-bounded / high-risk-bounded / needs-plan-behavior-expansion / broad-full-coverage-candidate / blocked-human-required
- classification_reason:
- selected_process: normal / advanced-full-coverage / human-decision-wait / higher-model-review / lower-cost-delegated-scan

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

## Execution Mode

- execution_mode: ROUTE_ONLY / DELEGATED_WORK / PARENT_DIRECT_WORK / TRIVIAL_PARENT_FIX
- ROUTE_ONLY: intake / plan / risk / contract / close judgment only; no production code or test edits.
- DELEGATED_WORK: selected agent / subagent owns the bounded work; parent updates state, ledger, and close decision.
- PARENT_DIRECT_WORK: parent works without agent / subagent delegation; reason required and not cost-saving delegation.
- TRIVIAL_PARENT_FIX: explicit low-risk local fix only; not cost-saving delegation.

## Edit Permission

- allowed_to_edit: Yes / No
- edit_owner: parent / standard-implementer / standard-verifier / high-planner / black-box-behavior-spec-kernel / implementation-handoff-review / high-implementation-contract / high-risk-triage / high-closure-reviewer / cheap-repo-scanner / cheap-doc-consistency / cheap-artifact-format-checker / human / none
- parent_direct_edit_allowed: Yes / No
- allowed_paths:
- forbidden_paths:
- required_authorization_artifact:

## Agent / Subagent Plan

| Gate | Selected agent or subagent | Model tier recommendation | DelegationRequired | Required artifacts | Stop / Ready Gate |
| --- | --- | --- | --- | --- | --- |

human_required_items:
- None

artifacts_created:
- None

artifacts_consumed:
- None

required_artifacts:
- None

unresolved_residuals:
- None

operations_not_allowed_in_current_state:
- Do not implement before READY.
- Do not select risk/profile/full-coverage before plan_readiness = ReadyForRiskTriage.
- Do not route requirement-elaboration gaps to full-coverage or fix-slice.
- Do not route to implementation-handoff-review until risk_triage_artifact_status = Complete and `plans/<ticket-or-slug>-change-risk-triage.md` exists.
- Do not route to standard-implementer before implementation-handoff-review or an explicitly equivalent pre-implementation gate creates the parent authorization artifact.
- If expansion_required = Yes, do not route to standard-implementer until behavior_case_coverage_ledger_status = Complete.
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

| Run ID | Gate | Work item | Model tier | Agent name | Agent type | Configured model | Configured reasoning effort | Hook model | Reported model | Effective model | Delegation required | Edit owner | Delegation violation | Cost-saving delegation countable | Outcome | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Model field meanings

- model_tier: abstract routing label, one of HIGH_MODEL / STANDARD_MODEL / CHEAP_MODEL.
- configured_model: Codex custom agent file top-level `model`.
- configured_reasoning_effort: Codex custom agent file top-level `model_reasoning_effort`.
- hook_model: model observed from hook payload or hook log, otherwise unknown.
- reported_model: model self-reported by the agent; lower confidence than configured_model or hook_model.
- effective_model: billing or runtime-effective model only when independently verified, otherwise unknown.

### Delegation compliance

| Check | Status | Evidence |
| --- | --- | --- |
| CHEAP work delegated when required | PASS / FAIL / N/A | |
| STANDARD implementation delegated | PASS / FAIL / N/A | |
| STANDARD verification delegated | PASS / FAIL / N/A | |
| Parent direct execution exception documented | PASS / FAIL / N/A | |
| Delegation violation absent or accepted | PASS / FAIL / N/A | |
| Cost-saving delegation has observed delegated run evidence | PASS / FAIL / N/A | |

delegation_compliance: PASS / FAIL / EXCEPTION_ACCEPTED / N/A

next_action:
last_updated_summary:
