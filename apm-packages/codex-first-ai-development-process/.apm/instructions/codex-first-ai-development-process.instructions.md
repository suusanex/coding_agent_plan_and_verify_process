# Codex-first AI Development Process Instructions

Use this instruction set when ordinary development work should start through Codex-first cost-aware routing without requiring the user to name a process, choose an agent, choose `full-coverage`, or pick a model.

## Entry behavior

- Treat short requests such as "この issue を進めて", "このバグを直して", and "続きやって" as Codex-first cost-aware routing requests.
- Do not ask the user to choose `plan-kernel`, `full-coverage`, a subagent, or a model tier.
- Start by reading repo-local instructions, existing artifacts, and the latest `plans/<slug>/codex-first-state.md` if present. Read `plans/<slug>/codex-first-audit.md` when delegation evidence, model-observability detail, route history, or close permission depends on it.
- Create or update state so the next "続きやって" request can resume safely.
- Keep `codex-first-state.md` focused on resume-critical current state. Put Agent Usage Ledger, DelegationCompliance detail, model-observability detail, and route history in `codex-first-audit.md`.
- Keep the user-facing entry small, but keep internal gates explicit in artifacts.
- Write task weight, documentation level, selected process, Routing Plan, Agent / Subagent Plan, Edit Permission block, audit artifact path, and delegation compliance summary into the state artifact before treating a delegated gate as successful.
- Keep abstract model tier, configured model, hook observed model, reported model, and effective model as separate audit ledger fields.
- Record execution_mode as `ROUTE_ONLY`, `DELEGATED_WORK`, `PARENT_DIRECT_WORK`, or `TRIVIAL_PARENT_FIX`.
- Use Codex as the primary execution environment.
- Treat GitHub Copilot as a later fallback route, not the first deliverable.

## Required gates

1. Intake gate: classify source of truth, ambiguity, repo rules, current state, and whether editing is allowed.
2. Plan gate: create or consume a bounded Plan or equivalent parent artifact, including behavior expansion decision, behavior spec path when required, Case-to-Plan mapping, and Plan readiness.
3. Risk gate: classify external API, SDK, DI, config, public API, DB, auth, async, production wiring, and cross-slice risk only after `ReadyForRiskTriage`; create or update `plans/<slug>-change-risk-triage.md` and record `risk_triage_artifact_status`.
4. Scan gate: delegate read-heavy discovery to low-cost workers when useful, and summarize evidence instead of flooding the main context.
5. Contract gate: resolve implementation approach and human decisions before editing.
6. READY gate: confirm Plan, selected scope, non-goals, required contract/test handoff when Guardrail Focus exists, Behavior Case coverage when required, and unresolved implementation-realization items before implementation.
7. Implementation handoff review gate: run `implementation-handoff-review` or an explicitly equivalent pre-implementation gate only after `plans/<slug>-change-risk-triage.md` exists and `risk_triage_artifact_status = Complete`; create the parent authorization artifact, Parent Plan Coverage Ledger, and Behavior Case Coverage Ledger when required.
8. Implementation gate: initialize `implementation_route: adaptive` / `implementation_route_source: default` only at fresh intake when no durable route, resume, or Design Pair evidence exists. On resume, require both route fields from durable state and stop on missing or contradictory metadata instead of defaulting to Adaptive; the only compatibility exception is an exact pre-Design-Pair Adaptive completion handoff accepted by the canonical `Legacy Adaptive handoff normalization`. Only explicit user selection may use `design-pair / explicit-user-selection`; never select, recommend, or propose it from difficulty, risk, size, or architecture. When selected, run `design-pair-implementation-execution` after handoff authorization, allow only its tracked handoff write until `READY_FOR_ADAPTIVE_IMPLEMENTATION`, then delegate the selected non-trivial READY scope first to `high-implementation-starter`. Delegate only a valid decision-free remainder to `standard-implementation-completer`, and return to HIGH_MODEL on re-entry, unless a recorded `ParentDirectExecutionException` has explicit human approval.
9. Verification gate: delegate ordinary verification to `standard-verifier`; route dangerous close judgment to `high-closure-reviewer`.
10. Close gate: do not close when unresolved items include `ManualVerificationRequired`, `NeedsHumanDecision`, `NeedsHigherModelReview`, missing required audit evidence, or failing `DelegationCompliance`.

## Task weight and process selection

Classify task weight before selecting the next gate.
Record the result as `task_weight`, `documentation_level`, and `selected_process`.

- `trivial-local`: obvious typo, formatting-only edit, no behavior change.
- `small-bounded`: one component, clear acceptance, local checks available.
- `medium-bounded`: multiple files or tests, clear source of truth, manageable production risk.
- `high-risk-bounded`: auth, security, DB, public API, production wiring, external SDK, async/event boundary, or compatibility uncertainty.
- `needs-plan-behavior-expansion`: source requirements contain unexpanded behavior cases, negative expectations, recovery / rollback / retry / replay / cleanup, state transitions, or unmapped Case IDs.
- `broad-full-coverage-candidate`: ready Plan is broad, strongly interconnected, has cross-slice contracts, or previous sequence / production-binding gaps.
- `blocked-human-required`: missing human decision, secret, external service operation, production/billing/GitHub settings change, or manual-only verification owner.

Allowed `selected_process` values are `normal`, `advanced-full-coverage`, `human-decision-wait`, `higher-model-review`, and `lower-cost-delegated-scan`.
Choose these internally; do not ask the user to select them.

Allowed `documentation_level` values are `lite` and `standard`.
Use `lite` only when one compact Plan Coverage artifact can preserve source-of-truth, FR / AC coverage, implementation authorization, verification summary, and residual decision fields.
Use `standard` when separate risk, behavior, contract, verification, or residual-decision artifacts are needed, and default to `standard` whenever the classification is unclear.
Do not add `strict` as a `documentation_level`.
`full-coverage` is not a `documentation_level`; it remains an advanced `selected_process` after `Plan readiness = ReadyForRiskTriage`.
Choose `documentation_level` internally; do not ask the user to select it.

## Stop vocabulary

- `Blocked`
- `NeedsHumanDecision`
- `ManualVerificationRequired`
- `NeedsHigherModelReview`
- `NeedsExternalOperation`
- `NeedsSecretInput`
- `TooCostlyForCurrentPass`
- `NeedsPlanBehaviorExpansion`
- `ReplanRequired`
- `ReadyButAwaitingHumanApproval`
- `DelegationRequired`
- `DelegationUnavailable`
- `DelegationEvidenceMissing`
- `ParentDirectExecutionException`
- `ParentDirectExecutionNotAllowed`
- `RoutingPolicyViolation`
- `BlockedByMissingDelegationLedger`
- `ReadyForImplementationHandoffReview`
- `BlockedByBehaviorCaseCoverageLedger`
- `ReadyForDelegatedImplementation`
- `ReadyForDelegatedVerification`
- `ReadyToClose`
- `ReadyToCloseWithAcceptedResiduals`
- `ResidualWorkRecorded`

## Cost-aware model routing

- Use `HIGH_MODEL` for ambiguous requirements, bounded Plan framing, behavior expansion, difficult risk triage, implementation handoff review, implementation contract decisions, security/auth/DB/public API/production wiring, and dangerous closure decisions.
- Use `HIGH_MODEL` for non-trivial READY implementation start and re-entry. Use `STANDARD_MODEL` for bounded completion, verification, test design/update, and moderate-risk repairs.
- Use `CHEAP_MODEL` for repo scan, read-heavy inventory, documentation consistency, artifact formatting, and simple local fixes.
- MUST delegate when the Routing Plan assigns a gate owner that differs from the parent tier or parent thread. Required delegated gates cannot be completed by parent-direct execution without a recorded exception and explicit human approval.
- Run `implementation-handoff-review` before ordinary READY implementation, after the Risk gate has produced `plans/<slug>-change-risk-triage.md`. When `Expansion required = Yes`, require `Behavior Case Coverage Ledger` status `Complete` before handing off to `high-implementation-starter`.
- Persist implementation_route, implementation_route_source, and design_pair_handoff in state. Do not edit production code / tests during an explicitly selected Design Pair pre-stage, and do not silently fall back to Adaptive when the Design Pair skill or handoff is unavailable.
- Delegate ordinary non-trivial READY implementation serially to `high-implementation-starter`, then conditionally to `standard-implementation-completer`, and ordinary verification to `standard-verifier`. Do not overlap write owners.
- At every implementation phase boundary, update the four Adaptive state fields and the active verdict, selected agent, recommended tier, and edit owner.
- Do not count parent-direct work, trivial parent fixes, or delegation violations as cost-saving delegation.
- Keep the main thread responsible for final implementation permission, state updates, delegation compliance audit, and close decisions.

Do not hard-code model names here. The consuming organization owns the mapping from labels to actual model names.
The Codex custom agent TOML top-level `model` and `model_reasoning_effort` fields are the configured execution defaults; natural-language model text in output is only `reported_model`.

## Advanced route boundary

Full-coverage 3-layer operation is an advanced route, not the default. Use it only when the work cannot be safely bounded inside the standard cost-router flow or when an experienced operator explicitly asks for broad parallelization.
Do not use full-coverage for missing behavior expansion, missing Case-to-Plan mapping, or undecided expected behavior. Those stop in Plan gate as `NeedsPlanBehaviorExpansion` or `NeedsHumanDecision`.
