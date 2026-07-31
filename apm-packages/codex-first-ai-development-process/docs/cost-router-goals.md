# Cost Router Goals

`codex-first-cost-router` is the core of this package.
It receives ordinary development requests and routes work by cost, risk, and readiness.

## User experience

Users can start with:

```text
この issue を進めてください。
このバグを修正してください。
この機能を実装してください。
この PR の残件を片付けて。
続きやって。
```

Users do not need to choose process names, agent names, model tiers, subagents, READY gates, close gates, or full-coverage branches.
The implementation route defaults to `adaptive`. `design-pair` is used only when the user explicitly selects it; the router does not infer, suggest, or recommend that route.

## Routing responsibilities

- Read repo instructions and existing artifacts first.
- Create or update `plans/<slug>/codex-first-state.md`.
- Create or update `plans/<slug>/codex-first-audit.md` when delegation evidence, model-observability detail, route history, or close audit is needed.
- Split work into gates.
- Assign `HIGH_MODEL`, `STANDARD_MODEL`, or `CHEAP_MODEL`.
- Write Routing Plan, Edit Permission, audit artifact path, and DelegationCompliance summary in state.
- Record Agent Usage Ledger, DelegationCompliance detail, route history, execution_mode evidence, and separate abstract model tier from configured, hook observed, reported, and effective model fields in audit.
- Delegate bounded read-heavy work when required by the Routing Plan.
- Require the Risk gate to create or update `plans/<slug>-change-risk-triage.md` and record `risk_triage_artifact_status`.
- Require `implementation-handoff-review` or an explicitly equivalent pre-implementation gate before normal READY implementation.
- Require `Behavior Case Coverage Ledger` status `Complete` before implementation when behavior expansion is required.
- Record `implementation_route`, `implementation_route_source`, `design_pair_handoff`, `design_pair_interaction_stage`, and stage-appropriate user evidence in durable state. Use `design-pair` only with `implementation_route_source = explicit-user-selection`.
- When `design-pair` is selected, present the complete bounded Target Map, persist `AWAITING_USER_INPUT / target-selection`, and end the first turn. After discussion, persist `AWAITING_USER_INPUT / disposition-confirmation` and stop again when the user has not supplied a final disposition. Complete the tracked handoff without editing production code or tests before the HIGH implementation owner starts.
- MUST start normal non-trivial READY implementation with `high-implementation-starter`.
- MUST use `standard-implementation-completer` only after a valid decision-free completion handoff and return re-entry to `high-implementation-starter`.
- MUST delegate normal READY verification to `standard-verifier`.
- Prevent implementation before READY.
- Prevent parent-direct execution of delegated gates without explicit exception approval.
- Prevent parent-direct work and trivial parent fixes from being counted as cost-saving delegation.
- Prevent close when human, manual, or higher-model stops remain.
- Prevent close when delegation evidence is missing.
- Save the next action and stop reason.
- Use Codex-readable custom agent file templates when maintainers want hard model routing.

## Gate summary

| Gate | Goal | Tier |
| --- | --- | --- |
| Intake | understand source, state, repo rules, and edit permission | `STANDARD_MODEL` / `HIGH_MODEL` |
| Plan | produce bounded source of truth, behavior expansion decision, Case-to-Plan mapping, and Plan readiness | `HIGH_MODEL` |
| Risk | classify risk and advanced-route boundary after `ReadyForRiskTriage`; create `plans/<slug>-change-risk-triage.md` | `STANDARD_MODEL` / `HIGH_MODEL` |
| Scan | collect summarized evidence | `CHEAP_MODEL` |
| Contract | decide implementation approach and human decisions | `HIGH_MODEL` |
| Implementation handoff review | create parent authorization and coverage ledgers before implementation | `HIGH_MODEL` / `STANDARD_MODEL` |
| Design Pair pre-stage | when explicitly selected, produce bounded evidence, stop for post-map user selection, discuss and obtain human-owned dispositions, then create a tracked handoff without implementation edits | `HIGH_MODEL` |
| Implementation start / re-entry | edit non-trivial READY scope through delegated high owner | `HIGH_MODEL` |
| Bounded completion | edit only valid handoff remainder through delegated standard owner | `STANDARD_MODEL` |
| Verification | map evidence to acceptance criteria through delegated owner | `STANDARD_MODEL` |
| Close | decide residuals and closure | `STANDARD_MODEL` / `HIGH_MODEL` |

## Task weight classification

The router classifies task weight before selecting the next gate.
This classification is not a user-facing menu; it is written into the state artifact so later agents can see why the route was chosen.

| Weight | Typical signals | Default route |
| --- | --- | --- |
| `trivial-local` | Single obvious docs typo, formatting-only edit, no behavior change, no external dependency | Cheap or parent `TRIVIAL_PARENT_FIX`; state artifact optional unless the repo requires it |
| `small-bounded` | One component, clear acceptance criteria, low production risk, local tests available | Standard route with READY gate; non-trivial implementation starts with `high-implementation-starter` |
| `medium-bounded` | Multiple files or tests, clear source of truth, manageable risk, no broad cross-slice contract | Standard route with bounded Plan, change-risk-triage artifact, implementation contract if needed |
| `high-risk-bounded` | Auth, security, DB, public API, production wiring, migration, async/event boundary, external SDK, or ambiguous compatibility policy | High model planning / risk / contract before READY; may stop with `NeedsHumanDecision` or `NeedsHigherModelReview` |
| `needs-plan-behavior-expansion` | Source requirements have unexpanded cases, negative expectations, recovery / rollback / retry / replay / cleanup, state transitions, or unmapped Case IDs | Plan gate stop; run `black-box-behavior-spec-kernel` or rerun `plan-kernel`, not full-coverage |
| `broad-full-coverage-candidate` | Ready Plan has broad scope, strongly interconnected changes, multiple runtime sequences, cross-slice contracts, or previous sequence / production-binding gaps | Advanced full-coverage route candidate; do not start implementation before decomposition and parent review |
| `blocked-human-required` | Missing spec decision, missing secret, external service action, production/billing/GitHub settings change, or manual-only verification | Stop with the matching reason and do not implement |

Classification axes:

- scope breadth: number of components, files, workflows, and user-facing paths
- ambiguity: missing behavior, priority, compatibility, or acceptance detail
- production-binding risk: real implementation / wiring / provider path uncertainty
- external side-effect risk: secret, billing, production, GitHub settings, or third-party service mutation
- verification cost: local automated checks versus manual-only or environment-bound evidence
- delegation suitability: read-heavy scan, READY implementation, READY verification, or high-risk judgment

## Route decision conditions

| Route | Select when | Required output |
| --- | --- | --- |
| Normal standard route | Task is `small-bounded`, `medium-bounded`, or safely reducible to a bounded Plan | Routing Plan, Edit Permission, required artifacts, READY / close gates |
| Design Pair implementation route | User explicitly selected Design Pair before implementation | durable route plus handoff path and interaction stage; mandatory post-map user response; then continue through Adaptive HIGH implementation only after `complete / READY_FOR_ADAPTIVE_IMPLEMENTATION` |
| Plan behavior expansion route | Task is `needs-plan-behavior-expansion` or Plan readiness is not `ReadyForRiskTriage` because source-to-case expansion or Case-to-Plan mapping is missing | `NeedsPlanBehaviorExpansion`, behavior spec next action or Plan rerun, no risk/profile selection |
| Advanced full-coverage route | Ready Plan is broad, strongly interconnected, or unsafe to bound as one implementation pass | Advanced-route note, decomposition next action, no READY implementation until slice readiness exists |
| Human decision wait | Required behavior, scope, priority, rollout target, secret, external operation, or manual evidence owner is missing | `NeedsHumanDecision`, `NeedsSecretInput`, `NeedsExternalOperation`, or `ManualVerificationRequired` |
| Higher-model review | Close risk, security/auth/DB/API/provider decision, or residual acceptance is too risky for current tier | `NeedsHigherModelReview` or selected high-agent review gate |
| Lower-cost delegated scan | Evidence collection is read-heavy, docs consistency, or artifact format checking | `CHEAP_MODEL` route with expected cheap agent and audit ledger placeholder |

READY implementation is only selected when the state has a bounded source of truth, complete change-risk-triage artifact, implementation-handoff-review parent authorization artifact, edit owner, allowed paths, required artifacts, and no unresolved stop reason. If `Expansion required = Yes`, `behavior_case_coverage_ledger_status` must be `Complete`.

## Safety requirements

- No implementation without READY or an equivalent low-risk trivial-fix decision.
- No automatic selection, suggestion, or recommendation of Design Pair; absent explicit user selection, record or retain `implementation_route = adaptive`.
- No Design Pair implementation handoff before its tracked artifact is complete, and no production or test edits during the Design Pair pre-stage.
- No READY verdict, Adaptive start, verification, or fallback while Design Pair is `target-selection` or `disposition-confirmation`. Do not reconstruct user confirmation from upstream artifacts or pre-map initial positions.
- No treatment of Target Map file or symbol references as an allowed edit surface; only explicit Locked Decisions are binding on Adaptive implementation.
- On a conflict between a Locked Decision and current repository evidence or a higher-priority contract, stop with the conflicting decision ID and evidence. Do not automatically re-enter Design Pair.
- No risk/profile selection before `ReadyForRiskTriage`.
- No full-coverage route for `NeedsPlanBehaviorExpansion`.
- No implementation handoff review before `risk_triage_artifact_status = Complete` and `plans/<slug>-change-risk-triage.md` exists.
- No standard implementation before implementation-handoff-review or an explicitly equivalent pre-implementation gate.
- No standard implementation with `Expansion required = Yes` unless `Behavior Case Coverage Ledger` is `Complete`.
- No parent-direct implementation when `DelegationRequired = Yes`, except recorded `ParentDirectExecutionException` with explicit human approval.
- No READY implementation success without an observed `high-implementation-starter` run or accepted exception.
- No `standard-implementation-completer` edit without a valid handoff, no unresolved HIGH re-entry, and no overlapping implementation write owners.
- No verification success without observed `standard-verifier` run or accepted exception.
- No cost-reduction claim from tier recommendation alone; count cost-saving delegation only when delegated run evidence exists in the ledger.
- No mixing `configured_model`, `hook_model`, `reported_model`, and `effective_model`.
- No production, secret, billing, or external service side effect without explicit approval.
- No fake / stub / mock-only result counted as production success.
- No close with unresolved `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`.
- No close with `DelegationCompliance = FAIL` or missing required audit evidence.
- No hard-coded real model names.

## Executable model routing

The abstract labels stay in process documents, but the team profile may pin real execution defaults in Codex custom agent files.
Use `profiles/codex-first/agents/*.toml` as the editable starting point.
Each template includes `model` and `model_reasoning_effort`, so teams can run it as-is for validation or change it before rollout.
These TOML values are configured execution defaults, not process-document recommendations. Ledger evidence, not tier selection alone, is what lets maintainers evaluate whether cheaper delegated work actually happened.
