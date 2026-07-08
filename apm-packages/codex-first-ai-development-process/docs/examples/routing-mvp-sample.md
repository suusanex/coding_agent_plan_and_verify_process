# Example: Routing MVP Sample

## Sample input

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- Add a small CLI option `--json` to an existing local report command.
- The command already has tests.
- No external API, secret, production environment, or billing change is needed.
- The output format must remain backward compatible unless `--json` is specified.
```

## Expected task weight

task_weight: `small-bounded`

Reason:

- Scope is one local command and its tests.
- Acceptance criteria are clear.
- There is a compatibility requirement, but no external side effect.
- The change can use the standard route after a bounded Plan and change-risk-triage artifact.

## Expected Routing Plan excerpt

```md
task_weight: small-bounded
current_gate: Intake
next_gate: Plan
selected_process: normal
recommended_model_tier: STANDARD_MODEL
model_tier_recommendation: STANDARD_MODEL for intake / plan; STANDARD_MODEL delegated owner after READY
execution_mode: ROUTE_ONLY
allowed_to_edit: No
current_status: ROUTED
stop_reason: None

## Routing Plan

| Gate | Recommended tier | Delegation required | Expected agent type | Edit owner | Parent may execute directly? | Stop if unavailable |
| --- | --- | --- | --- | --- | --- | --- |
| Intake | STANDARD_MODEL | No | parent | parent | Yes | Blocked |
| Plan | STANDARD_MODEL | No | parent or high-planner | parent | Yes | NeedsHumanDecision |
| Risk | STANDARD_MODEL | No | parent or high-risk-triage | parent | Yes | NeedsHigherModelReview |
| Implementation handoff review | HIGH_MODEL / STANDARD_MODEL | No | implementation-handoff-review | implementation-handoff-review | Yes | ReadyForImplementationHandoffReview |
| Implementation | STANDARD_MODEL | Yes | standard-implementer | standard-implementer | No | ReadyForDelegatedImplementation |
| Verification | STANDARD_MODEL | Yes | standard-verifier | standard-verifier | No | ReadyForDelegatedVerification |
| Close | STANDARD_MODEL | No | parent or high-closure-reviewer | parent | Yes | NeedsHigherModelReview |

## Agent / Subagent Plan

| Gate | Selected agent or subagent | Model tier recommendation | DelegationRequired | Required artifacts | Stop / Ready Gate |
| --- | --- | --- | --- | --- | --- |
| Plan | parent or high-planner | STANDARD_MODEL / HIGH_MODEL if ambiguity appears | No | Issue body, repo rules, state artifact | Ready when bounded Plan defines acceptance and non-goals |
| Implementation handoff review | implementation-handoff-review | HIGH_MODEL / STANDARD_MODEL | No | Bounded Plan, `plans/<slug>-change-risk-triage.md`, state artifact | Stop with ReadyForImplementationHandoffReview until parent authorization artifact exists |
| Implementation | standard-implementer | STANDARD_MODEL | Yes | Bounded Plan, `plans/<slug>-change-risk-triage.md`, implementation-handoff-review artifact, Edit Permission | Stop with ReadyForDelegatedImplementation until observed delegated run exists |
| Verification | standard-verifier | STANDARD_MODEL | Yes | Implementation result, local test command, acceptance mapping | Stop with ReadyForDelegatedVerification until observed delegated run exists |

## Edit Permission

- allowed_to_edit: No
- edit_owner: none
- parent_direct_edit_allowed: No
- allowed_paths:
  - To be filled after Plan / risk gate
- forbidden_paths:
  - Production, secret, billing, external service, or GitHub settings changes
- required_authorization_artifact:
  - Bounded Plan with READY implementation scope
  - implementation-handoff-review artifact before standard implementation
```

## Expected READY transition

After the Plan and risk gates confirm the scope, the state first moves to:

```md
current_gate: Implementation handoff review
next_gate: Implementation
selected_process: normal
recommended_model_tier: HIGH_MODEL / STANDARD_MODEL
execution_mode: ROUTE_ONLY
selected_agent_name: implementation-handoff-review
allowed_to_edit: No
delegation_required: No
stop_reason: ReadyForImplementationHandoffReview
```

After the handoff review creates the parent authorization artifact, the state may move to:

```md
current_gate: Implementation
next_gate: Verification
selected_process: normal
recommended_model_tier: STANDARD_MODEL
execution_mode: DELEGATED_WORK
selected_agent_name: standard-implementer
allowed_to_edit: Yes
delegation_required: Yes
stop_reason: ReadyForDelegatedImplementation
```

The parent thread does not implement the READY scope directly.
It delegates to `standard-implementer`, records the observed run in the audit artifact Agent Usage Ledger, then delegates verification to `standard-verifier`.

## Expected non-READY output

If the issue body does not define backward compatibility behavior, the route stops instead:

```md
current_gate: Plan
next_gate: HumanDecision
selected_process: human-decision-wait
recommended_model_tier: HIGH_MODEL
execution_mode: ROUTE_ONLY
allowed_to_edit: No
delegation_required: No
stop_reason: NeedsHumanDecision

human_required_items:
- Decide whether existing text output must remain byte-for-byte compatible when `--json` is not specified.
```

No implementation starts while this stop reason remains unresolved.
