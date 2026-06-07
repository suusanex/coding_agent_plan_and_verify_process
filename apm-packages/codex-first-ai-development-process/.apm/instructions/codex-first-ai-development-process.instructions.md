# Codex-first AI Development Process Instructions

Use this instruction set when ordinary development work should start through Codex-first cost-aware routing without requiring the user to name a process, choose an agent, choose `full-coverage`, or pick a model.

## Entry behavior

- Treat short requests such as "この issue を進めて", "このバグを直して", and "続きやって" as Codex-first cost-aware routing requests.
- Do not ask the user to choose `plan-kernel`, `full-coverage`, a subagent, or a model tier.
- Start by reading repo-local instructions, existing artifacts, and the latest `plans/<slug>/codex-first-state.md` if present.
- Create or update state so the next "続きやって" request can resume safely.
- Keep the user-facing entry small, but keep internal gates explicit in artifacts.
- Write a Routing Plan, Edit Permission block, Agent Usage Ledger, and DelegationCompliance into the state artifact before treating a delegated gate as successful.
- Use Codex as the primary execution environment.
- Treat GitHub Copilot as a later fallback route, not the first deliverable.

## Required gates

1. Intake gate: classify source of truth, ambiguity, repo rules, current state, and whether editing is allowed.
2. Plan gate: create or consume a bounded Plan or equivalent parent artifact.
3. Risk gate: classify external API, SDK, DI, config, public API, DB, auth, async, production wiring, and cross-slice risk.
4. Scan gate: delegate read-heavy discovery to low-cost workers when useful, and summarize evidence instead of flooding the main context.
5. Contract gate: resolve implementation approach and human decisions before editing.
6. READY gate: confirm Plan, selected scope, non-goals, contract/test handoff, and unresolved implementation-realization items before implementation.
7. Implementation gate: delegate the selected READY scope to `standard-implementer` unless a recorded `ParentDirectExecutionException` has explicit human approval.
8. Verification gate: delegate ordinary verification to `standard-verifier`; route dangerous close judgment to `high-closure-reviewer`.
9. Close gate: do not close when unresolved items include `ManualVerificationRequired`, `NeedsHumanDecision`, `NeedsHigherModelReview`, missing delegation evidence, or failing `DelegationCompliance`.

## Stop vocabulary

- `Blocked`
- `NeedsHumanDecision`
- `ManualVerificationRequired`
- `NeedsHigherModelReview`
- `NeedsExternalOperation`
- `NeedsSecretInput`
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
- `ReadyToClose`
- `ReadyToCloseWithAcceptedResiduals`
- `ResidualWorkRecorded`

## Cost-aware model routing

- Use `HIGH_MODEL` for ambiguous requirements, bounded Plan framing, difficult risk triage, implementation contract decisions, security/auth/DB/public API/production wiring, and dangerous closure decisions.
- Use `STANDARD_MODEL` for normal READY implementation, verification, test design/update, and moderate-risk repairs.
- Use `CHEAP_MODEL` for repo scan, read-heavy inventory, documentation consistency, artifact formatting, and simple local fixes.
- MUST delegate when the Routing Plan assigns a gate owner that differs from the parent tier or parent thread. Required delegated gates cannot be completed by parent-direct execution without a recorded exception and explicit human approval.
- Delegate ordinary READY implementation serially to `standard-implementer` and ordinary verification to `standard-verifier`. Do not standardize write-heavy parallel editing; serial delegated implementation is still required.
- Keep the main thread responsible for final implementation permission, state updates, delegation compliance audit, and close decisions.

Do not hard-code model names here. The consuming organization owns the mapping from labels to actual model names.

## Advanced route boundary

Full-coverage 3-layer operation is an advanced route, not the default. Use it only when the work cannot be safely bounded inside the standard cost-router flow or when an experienced operator explicitly asks for broad parallelization.
