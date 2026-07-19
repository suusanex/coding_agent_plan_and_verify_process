# Codex First State

task_slug:
original_user_intent:
source_of_truth:

task_weight:
documentation_level: lite / standard / Unknown
expansion_required: Yes / No / Unknown
behavior_spec_artifact:
plan_readiness: ReadyForRiskTriage / NeedsPlanBehaviorExpansion / NeedsHumanDecision / Unknown
case_to_plan_mapping_status: Complete / Incomplete / N/A / Unknown
behavior_case_coverage_ledger_artifact:
behavior_case_coverage_ledger_status: Complete / Incomplete / N/A / Unknown
risk_triage_artifact:
risk_triage_artifact_status: Complete / Incomplete / Missing / Unknown
implementation_route: adaptive / design-pair
implementation_route_source: default / explicit-user-selection
design_pair_handoff: N/A / plans/<ticket-or-slug>-design-pair-implementation-handoff.md
shape_handoff_status: NotStarted / Pending / Ready / Consumed / Invalidated / NotRequired / Blocked / Unknown
remaining_design_uncertainty: None / Unknown / <evidence-backed summary>
completion_scope: N/A / Unknown / <Work IDs and allowed edit surface>
shape_reentry_reason: N/A / Unknown / <trigger and invalidating evidence>
# Compatibility note: `shape_handoff_status` and `shape_reentry_reason` are stable state-field names retained for existing artifacts. They do not name separate agent aliases or a pre-implementation shape-classification gate.
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
edit_owner:

allowed_to_edit: No
delegation_required: No
current_status:
stop_reason:
stop_ready_gate:
parent_direct_work_reason:
delegation_violation: No
cost_saving_delegation_countable: No
delegation_compliance_summary: PASS / FAIL / EXCEPTION_ACCEPTED / N/A / Unknown
audit_artifact: plans/<ticket-or-slug>/codex-first-audit.md

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
- ReadyForHighImplementationStart
- ReadyForStandardCompletion
- NeedsHighModelReentry
- BlockedByInvalidCompletionHandoff
- ReadyForDelegatedVerification
- ReadyForImplementationHandoffReview
- BlockedByBehaviorCaseCoverageLedger
- ReadyForDesignPair
- BlockedByMissingDesignPairSkill

## Routing Plan

| Gate | Recommended tier | Delegation required | Expected agent type | Edit owner | Parent may execute directly? | Stop if unavailable |
| --- | --- | --- | --- | --- | --- | --- |

## Task Weight

- task_weight: trivial-local / small-bounded / medium-bounded / high-risk-bounded / needs-plan-behavior-expansion / broad-full-coverage-candidate / blocked-human-required
- documentation_level: lite / standard / Unknown
- classification_reason:
- selected_process: normal / advanced-full-coverage / human-decision-wait / higher-model-review / lower-cost-delegated-scan
- documentation_level_reason:

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

- implementation_route: adaptive / design-pair
- implementation_route_source: default / explicit-user-selection
- design_pair_handoff: N/A / plans/<ticket-or-slug>-design-pair-implementation-handoff.md
- design_pair_status: NotSelected / Pending / Ready / Blocked / Invalid / Unknown
- design_pair_locked_decision_ids: N/A / <DP-Dxx list>
- design_pair_conflict: N/A / None / <Decision ID and evidence>
- shape_handoff_status: NotStarted / Pending / Ready / Consumed / Invalidated / NotRequired / Blocked / Unknown
- remaining_design_uncertainty: None / Unknown / <evidence-backed summary>
- completion_scope: N/A / Unknown / <Work IDs and allowed edit surface>
- shape_reentry_reason: N/A / Unknown / <trigger and invalidating evidence>
- compatibility_note: `shape_*` fields are stable state vocabulary only; canonical implementation owners remain `high-implementation-starter` and `standard-implementation-completer`.
- owner_and_verdict_sequence:
- implementation_result_artifact: plans/<ticket-or-slug>-implementation-execution.md
- tracked_completion_handoff: N/A / plans/<ticket-or-slug>-implementation-completion-handoff.md

## Execution Mode

- execution_mode: ROUTE_ONLY / DELEGATED_WORK / PARENT_DIRECT_WORK / TRIVIAL_PARENT_FIX
- ROUTE_ONLY: intake / plan / risk / contract / close judgment only; no production code or test edits.
- DELEGATED_WORK: selected agent / subagent owns the bounded work; parent updates state, audit, and close decision.
- PARENT_DIRECT_WORK: parent works without agent / subagent delegation; reason required and not cost-saving delegation.
- TRIVIAL_PARENT_FIX: explicit low-risk local fix only; not cost-saving delegation.

## Edit Permission

- allowed_to_edit: Yes / No
- edit_owner: parent / design-pair-implementation-execution / high-implementation-starter / standard-implementation-completer / standard-implementer-legacy / standard-verifier / high-planner / black-box-behavior-spec-kernel / implementation-handoff-review / high-implementation-contract / high-risk-triage / high-closure-reviewer / cheap-repo-scanner / cheap-doc-consistency / cheap-artifact-format-checker / human / none
- parent_direct_edit_allowed: Yes / No
- allowed_paths:
- forbidden_paths:
- required_authorization_artifact:

## Agent / Subagent Plan

| Gate | Selected agent or subagent | Model tier recommendation | DelegationRequired | Required artifacts | Stop / Ready Gate |
| --- | --- | --- | --- | --- | --- |

## Audit Link

- audit_artifact: plans/<ticket-or-slug>/codex-first-audit.md
- audit_required_when: delegated run evidence, model-observability detail, route history, or close-time DelegationCompliance evidence is needed
- audit_summary_to_keep_here: delegation_compliance_summary, delegation_violation, cost_saving_delegation_countable, parent_direct_work_reason

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
- Do not infer, recommend, or propose design-pair from task weight, risk, size, or architecture. Initialize adaptive / default only at fresh intake with no durable route, resume, or Design Pair evidence. On resume, preserve both durable route fields and stop on missing or contradictory metadata instead of defaulting to Adaptive, except for an exact legacy handoff accepted by `Legacy Adaptive handoff normalization`.
- Do not edit production code / tests during the Design Pair pre-stage. Allow only the tracked design_pair_handoff path until READY_FOR_ADAPTIVE_IMPLEMENTATION.
- Do not silently fall back to Adaptive when an explicitly selected Design Pair skill or valid handoff is missing.
- Keep `current_status` equal to the actual Adaptive verdict, and switch `selected_agent_name`, `recommended_model_tier`, and `edit_owner` to the active `high-implementation-starter`, `standard-implementation-completer`, or `standard-verifier` phase.
- Record `delegation_required: Yes` for both HIGH implementation start/re-entry and STANDARD completion.
- Do not implement before READY.
- Do not record `strict` or `full-coverage` as documentation_level; use only `lite` or `standard`.
- Do not select risk/profile/full-coverage before plan_readiness = ReadyForRiskTriage.
- Do not route requirement-elaboration gaps to full-coverage or fix-slice.
- Do not route to implementation-handoff-review until risk_triage_artifact_status = Complete and `plans/<ticket-or-slug>-change-risk-triage.md` exists.
- Do not route non-trivial READY implementation directly to standard-implementer or standard-implementation-completer. Start with high-implementation-starter after implementation-handoff-review or an explicitly equivalent pre-implementation gate creates the parent authorization artifact.
- If expansion_required = Yes, do not route to high-implementation-starter until behavior_case_coverage_ledger_status = Complete.
- Do not route to standard-implementation-completer until shape_handoff_status = Ready and a complete READY_FOR_STANDARD_COMPLETION handoff exists.
- If standard-implementation-completer returns NEEDS_HIGH_MODEL_REENTRY, set shape_handoff_status = Invalidated and return to high-implementation-starter before any further implementation edit.
- Do not overlap high-implementation-starter and standard-implementation-completer write ownership.
- Do not parent-direct execute a gate with DelegationRequired = Yes unless ParentDirectExecutionException has explicit human approval.
- Do not mark implementation complete without an observed high-implementation-starter run and any required standard completion/re-entry runs, or an accepted exception in the audit artifact.
- Do not mark verification complete without observed standard-verifier run or accepted exception in the audit artifact.
- Do not perform secret, external service, billing, or production operations without explicit approval.
- Do not close with unresolved ManualVerificationRequired, NeedsHumanDecision, or NeedsHigherModelReview.
- Do not close with DelegationCompliance = FAIL or missing audit artifact when delegated evidence is required.

next_action:
last_updated_summary:
