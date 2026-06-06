# codex-first-cost-router

Use this skill whenever ordinary development work should start or resume through the Codex-first cost-aware process.
Trigger it for natural requests such as "この issue を進めて", "このバグを直して", "この機能を実装して", "この PR の残件を片付けて", and "続きやって".

## Purpose

Route work by difficulty, risk, and edit permission without asking the user to choose a process, agent, subagent, model, or `full-coverage` branch.

The router owns:

- intake and source-of-truth detection
- state artifact creation / update
- model tier assignment
- agent / subagent delegation choice
- READY / implementation permission
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
- allowed to edit
- current status
- stop reason
- human required items
- artifacts created / consumed
- unresolved residuals
- next action
- operations not allowed in current state
- last updated summary

For "続きやって", read the newest matching state artifact before deciding the next step.

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

- delegate read-heavy search, inventory, and consistency checks when useful
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

- implement only READY scope
- stop if new design uncertainty appears
- avoid external API, production, secret, or billing side effects
- avoid endless repair loops

### Test / verification

Default tier: `STANDARD_MODEL`.
Use `CHEAP_MODEL` for formal docs consistency and formatting checks.
Use `HIGH_MODEL` for risky close judgment.

Do:

- map evidence to Plan acceptance criteria
- distinguish fake / mock / stub success from production readiness
- record manual-only verification explicitly

### Close / residual decision

Default tier: `STANDARD_MODEL`.
Use `HIGH_MODEL` for broad impact, difficult residual decisions, or uncertain acceptance coverage.

Do:

- keep `ManualVerificationRequired`, `NeedsHumanDecision`, and `NeedsHigherModelReview` from closing
- distinguish `ReadyToClose` from `ReadyToCloseWithAcceptedResiduals`
- record accepted residuals and their owner

## Model tier labels

- `HIGH_MODEL`: hard judgment, ambiguity, security/auth/DB/public API/production wiring, implementation contract, risky close.
- `STANDARD_MODEL`: normal implementation, verification, test work, moderate repairs.
- `CHEAP_MODEL`: scan, inventory, docs consistency, artifact formatting, simple local fixes.

Do not hard-code real model names. Maintainers own the mapping.

## Predefined agents / subagents

Use the package agents as role descriptions for delegation:

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
Do not make write-heavy parallel editing the default.

## Stop reasons

- `NeedsHumanDecision`
- `ManualVerificationRequired`
- `NeedsHigherModelReview`
- `NeedsSecretInput`
- `NeedsExternalOperation`
- `Blocked`
- `TooCostlyForCurrentPass`
- `ReadyButAwaitingHumanApproval`

Ask the user only for the minimum next input.
Do not ask them to choose a gate, agent, or model.

## Output

Return:

- state artifact path
- current gate
- next gate
- recommended model tier
- allowed-to-edit value
- stop reason, if any
- human-required items
- unresolved residuals
- artifacts created / consumed
- next action
