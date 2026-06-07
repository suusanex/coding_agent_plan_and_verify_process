# codex-first-cost-router

Use this skill whenever ordinary development work should start or resume through the Codex-first cost-aware process.
Trigger it for natural requests such as "この issue を進めて", "このバグを直して", "この機能を実装して", "この PR の残件を片付けて", and "続きやって".

## Purpose

Route work by difficulty, risk, and edit permission without asking the user to choose a process, agent, subagent, model, or `full-coverage` branch.

The router owns:

- intake and source-of-truth detection
- state artifact creation / update
- model tier assignment
- agent / subagent delegation requirement
- READY / implementation permission
- routing plan and edit owner
- agent usage ledger and delegation compliance
- stop reason and residual classification
- close permission

## State artifact

Use `plans/<slug>/codex-first-state.md`.
If a better repo-local plan directory already exists, use that directory but preserve the same fields.

Minimum fields:

- task slug
- original user intent
- current gate
- next gate
- recommended model tier
- routing plan
- edit permission
- current status
- stop reason
- human required items
- agent usage ledger
- delegation compliance
- artifacts created / consumed
- unresolved residuals
- next action
- operations not allowed in current state
- last updated summary

For "続きやって", read the newest matching state artifact before deciding the next step.

### Routing Plan

Before executing a gate, write this table to the state artifact.

```md
## Routing Plan

| Gate | Recommended tier | Delegation required | Expected agent type | Edit owner | Parent may execute directly? | Stop if unavailable |
| --- | --- | --- | --- | --- | --- | --- |
```

Rules:

- `CHEAP_MODEL` read-heavy scan, docs consistency, and artifact format checks SHOULD delegate to cheap agents when the work is more than trivial.
- `STANDARD_MODEL` READY implementation MUST delegate to `standard-implementer` when the parent is running as `HIGH_MODEL` or otherwise owns orchestration.
- `STANDARD_MODEL` READY verification MUST delegate to `standard-verifier` before close, unless close risk requires `high-closure-reviewer`.
- `HIGH_MODEL` plan, risk, implementation contract, and dangerous close judgment may stay with the parent or high agents.
- A gate with `Delegation required = Yes` cannot be marked successful without observed delegation or an accepted parent-direct exception.

### Edit Permission

Replace the old single `allowed to edit` decision with this block.

```md
## Edit Permission

- allowed_to_edit: Yes / No
- edit_owner: parent / standard-implementer / standard-verifier / cheap-fixer / human / none
- parent_direct_edit_allowed: Yes / No
- allowed_paths:
- forbidden_paths:
- required_authorization_artifact:
```

For READY implementation, default to `edit_owner = standard-implementer` and `parent_direct_edit_allowed = No`.
For READY verification, default to `edit_owner = standard-verifier` and `parent_direct_edit_allowed = No`, except for final close permission retained by the parent or `high-closure-reviewer`.

### Agent Usage Ledger

State artifacts must include expected vs observed delegation.

```md
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
```

## Gates

### Intake / Request understanding

Default tier: `STANDARD_MODEL`.
Use `HIGH_MODEL` when the request is broad, ambiguous, or high risk.

Do:

- identify issue / PR / branch / file / supplied text inputs
- read repo instructions before editing
- separate work assumptions from missing information
- avoid immediate implementation

### Plan / Goal framing

Default tier: `HIGH_MODEL`.
Use `STANDARD_MODEL` only for small, explicit fixes.

Do:

- create or consume a bounded Parent Plan or equivalent artifact
- record acceptance criteria, non-goals, and completion criteria
- preserve the Plan as source of truth for later gates

### Risk triage

Default tier: `STANDARD_MODEL`.
Use `HIGH_MODEL` for broad, ambiguous, security, auth, DB, public API, external SDK, async, or production wiring risk.

Do:

- classify implementation-realization risk
- decide whether standard routing can bound the work safely
- treat full-coverage 3-layer operation as advanced route only

### Repository scan / evidence collection

Default tier: `CHEAP_MODEL`.
Use `STANDARD_MODEL` if the scan directly affects implementation API choice.

Do:

- delegate read-heavy search, inventory, and consistency checks to `cheap-repo-scanner`, `cheap-doc-consistency`, or `cheap-artifact-format-checker` when delegation is required by the Routing Plan
- summarize findings instead of dumping raw output
- avoid final implementation decisions inside cheap scan work

### Implementation contract / design decision

Default tier: `HIGH_MODEL`.
Use `STANDARD_MODEL` only when API surface and implementation approach are already obvious.

Do:

- choose the implementation approach
- resolve SDK / API / dependency uncertainty
- split human decisions from implementation work
- stop with `NeedsHumanDecision` or `NeedsHigherModelReview` when needed

### Implementation

Default tier: `STANDARD_MODEL`.
Use `CHEAP_MODEL` only for simple, local, low-risk edits.

Do:

- set `Delegation required = Yes` and `Edit owner = standard-implementer` for normal READY implementation
- delegate READY implementation serially to `standard-implementer`; serial delegation is required even when write-heavy parallel editing is not allowed
- implement only READY scope
- stop if new design uncertainty appears
- avoid external API, production, secret, or billing side effects
- avoid endless repair loops
- stop with `DelegationUnavailable`, `ParentDirectExecutionException`, or `NeedsHigherModelReview` if required delegation cannot run

### Test / verification

Default tier: `STANDARD_MODEL`.
Use `CHEAP_MODEL` for formal docs consistency and formatting checks.
Use `HIGH_MODEL` for risky close judgment.

Do:

- set `Delegation required = Yes` and `Edit owner = standard-verifier` for normal READY verification
- delegate verification to `standard-verifier`; use `high-closure-reviewer` when close judgment is risky
- map evidence to Plan acceptance criteria
- distinguish fake / mock / stub success from production readiness
- record manual-only verification explicitly

### Close / residual decision

Default tier: `STANDARD_MODEL`.
Use `HIGH_MODEL` for broad impact, difficult residual decisions, or uncertain acceptance coverage.

Do:

- keep `ManualVerificationRequired`, `NeedsHumanDecision`, and `NeedsHigherModelReview` from closing
- keep `DelegationRequired` gates from closing when no observed run or accepted exception exists
- require `DelegationCompliance = PASS` or `DelegationCompliance = EXCEPTION_ACCEPTED` with explicit human decision
- distinguish `ReadyToClose` from `ReadyToCloseWithAcceptedResiduals`
- record accepted residuals and their owner

## Model tier labels

- `HIGH_MODEL`: hard judgment, ambiguity, security/auth/DB/public API/production wiring, implementation contract, risky close.
- `STANDARD_MODEL`: normal implementation, verification, test work, moderate repairs.
- `CHEAP_MODEL`: scan, inventory, docs consistency, artifact formatting, simple local fixes.

Do not hard-code real model names. Maintainers own the mapping.

## Predefined agents / subagents

Use the package agents as role descriptions for delegation.
For Codex-readable custom agent files with concrete `model` and `model_reasoning_effort` defaults, use `profiles/codex-first/agents/*.toml`.

- `high-planner`
- `high-risk-triage`
- `high-implementation-contract`
- `high-closure-reviewer`
- `standard-implementer`
- `standard-verifier`
- `cheap-repo-scanner`
- `cheap-doc-consistency`
- `cheap-artifact-format-checker`

Subagents are a way to assign bounded work to the right tier.
They still require explicit subagent / parallel work instructions from the parent thread or launcher.
Do not make write-heavy parallel editing the default.
This does not permit parent-direct implementation: READY implementation is serial delegated work owned by `standard-implementer` unless a recorded exception is accepted.

## Stop reasons

- `NeedsHumanDecision`
- `ManualVerificationRequired`
- `NeedsHigherModelReview`
- `NeedsSecretInput`
- `NeedsExternalOperation`
- `Blocked`
- `TooCostlyForCurrentPass`
- `ReadyButAwaitingHumanApproval`
- `DelegationRequired`
- `DelegationUnavailable`
- `DelegationEvidenceMissing`
- `ParentDirectExecutionException`
- `ParentDirectExecutionNotAllowed`
- `RoutingPolicyViolation`
- `BlockedByMissingDelegationLedger`
- `ReadyForDelegatedImplementation`
- `ReadyForDelegatedVerification`

Ask the user only for the minimum next input.
Do not ask them to choose a gate, agent, or model.

## Output

Return:

- state artifact path
- current gate
- next gate
- recommended model tier
- routing plan summary
- edit permission / edit owner
- delegation compliance
- stop reason, if any
- human-required items
- unresolved residuals
- agent usage ledger summary
- artifacts created / consumed
- next action
