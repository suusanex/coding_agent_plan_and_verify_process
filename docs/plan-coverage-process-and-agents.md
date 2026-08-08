# Plan Coverage Check and Residual Decision Flow: Current Process and Agent Contract

## Purpose of this document

This document defines the current process and agent contract for making the Plan-first workflow bounded and token-conscious while preserving the guardrails that prevent cross-process contract mismatches and stub-only implementation success.

It describes the active Plan Coverage route. It is not a future agent creation plan or an implementation task list.

このdocumentはactive contractのmaintainer向け説明です。agent実行時に、このdocumentや`docs/`配下のfileが存在することを前提にしてはいけません。contractを変更するmaintainerは次を同時に確認します。

- `docs/plan-coverage-purpose.md`
- replace または complement する existing agent files
- 実際の implementation task を想定するために必要な target repository context

agentは別repositoryへ配布される可能性があります。そのため、実行時に必要な目的、方針、profile、handoff、他agentとの関係は、agent file自体または同時に配布される共通instruction fileに含めます。

## Design policy

The process reduces cost by narrowing Guardrail Focus coverage for deep checks, not by shrinking parent Plan implementation scope or removing essential guardrails.

The Plan網羅チェック・残件判定フロー is still a Plan-first flow. It must not start implementation from risk triage or runtime-contract artifacts alone.

The required high-level chain is:

1. decide whether source requirements need black-box behavior expansion
2. create or consume behavior Case IDs when expansion is required
3. create a bounded Plan and map relevant Case IDs to FR / AC or explicit disposition
4. classify Guardrail Focus coverage inside a ready Plan
5. preserve guardrails for Guardrail Focus surfaces
6. implement against the Plan as the source of truth
7. verify Guardrail Focus contracts, test points, production implementation, production wiring, and current Behavior Case evidence
8. update Parent Plan Coverage Ledger / Behavior Case ledgers and route unresolved items through coverage-gap-triage and residual-decision-gate

For Guardrail Focus surfaces, the process must still connect:

1. source requirement
2. black-box behavior case, when expansion is required
3. Plan requirement / acceptance condition
4. runtime contract
5. test point
6. stub / fake / in-memory usage
7. production implementation
8. production wiring / entrypoint
9. explicit unresolved status

## Plan-first boundary

The active route begins with `plan-kernel.agent.md`, not `change-risk-triage.agent.md`. Its goal is not merely to triage risk; it preserves the Plan-first sequence — create Plan, implement, and verify that implementation gaps are not missed — while reducing token consumption and avoiding open-ended repair loops.

The current responsibility boundary is:

- `change-risk-triage.agent.md` should remain `triage-only` and should not become a mixed Plan-generation agent.
- `runtime-contract-kernel.agent.md` is a high-risk boundary guardrail, not a complete requirements specification.
- implementation agents need the overall Plan as the source of truth, plus kernel artifacts as guardrails.
- `plan-kernel.agent.md` keeps the bounded route Plan-first without forcing the explicit Full Autonomous `plan-generation.agent.md` / `runtime-evidence.agent.md` / `integration-test-design.agent.md` chain.

## Requirement-elaboration gap

The process must also block a Plan before risk triage when source requirements have not been elaborated into required black-box behavior cases.

`Requirement-elaboration gap` means the downstream artifacts can be internally consistent while the Plan itself fails to represent the source requirement's case-specific expected behavior, negative expectation, recovery / rollback / retry / replay / cleanup behavior, state transition, or idempotency.

This is not a `full-coverage` trigger.

- `NeedsPlanBehaviorExpansion` routes to `black-box-behavior-spec-kernel.agent.md` when source-to-case expansion is missing.
- `NeedsPlanBehaviorExpansion` routes back to `plan-kernel.agent.md` when Case IDs exist but are not mapped to Plan FR / AC or explicit disposition.
- `NeedsHumanDecision` stops when product semantics or policy is undecided.
- `full-coverage` is available only after `Plan readiness: ReadyForRiskTriage`.

## Process profiles

### `plan-kernel`

Creates a bounded implementation Plan for the requested change.

Use when:

- the user wants bounded Plan-first development with token-conscious guardrails
- full runtime evidence and full integration test design would be too expensive at the Plan stage
- the implementation still needs a complete enough source of truth before risk triage
- the downstream kernel agents need a Plan to map contracts, test points, implementation, and verification back to requirements

Output is a bounded Plan. It is not implementation code, not runtime evidence, and not full test design.

### `black-box-behavior-spec-kernel`

Creates a source-to-case artifact when the Plan phase finds that source requirements need behavior expansion.

Use when:

- source requirements contain case-specific expected outcomes
- negative expectations are central
- behavior depends on input condition, pre-state, history, permission, phase, durable state, retry, replay, rollback, recovery, or cleanup
- Plan readiness is `NeedsPlanBehaviorExpansion` because behavior Case IDs are missing or incomplete

Output is `plans/<ticket-or-slug>-black-box-behavior-spec.md`. It does not edit the Plan. Case-to-Plan mapping remains owned by `plan-kernel.agent.md`.

### `triage-only`

Classifies the Plan and recommends the minimum sufficient process profile.

Use when:

- a bounded Plan already exists
- the required runtime guardrail depth is unclear
- the user wants to avoid unnecessary full processing
- a previous run became too broad
- the task may or may not involve high-risk runtime boundaries

Output is a recommendation. No Plan, code, or test implementation should be changed.

### `contract-kernel`

Creates a narrow guardrail kernel for selected high-risk runtime contracts.

Use when:

- the Plan has cross-boundary risk
- full runtime evidence would be too expensive
- the goal is to preserve the minimum runtime/test/production binding chain for selected contracts

This profile does not require exhaustive scenario coverage. It requires deep enough coverage for selected contracts.

### `standard-slice`

Runs a bounded Plan-first process with Guardrail Focus runtime contracts or explicitly selected integration test IDs.

Use when:

- the task is normal complexity but still has meaningful runtime or production-binding risk
- a selected set of contracts / IDs can be handled in one pass
- the goal is to make bounded progress and leave explicit residual work

### `full-coverage`

Indicates that the current ready bounded Plan is too broad or strongly interconnected to be continued as a single Plan網羅チェック implementation pass.

Use when:

- multiple runtime scenarios interact
- external dependencies, retries, persistence, or recovery semantics are important
- the ready Plan is broad or strongly interconnected
- human review needs detailed runtime evidence
- prior implementation attempts already exposed sequence or production-binding gaps

In the Plan網羅チェック・残件判定フロー, this is not an automatic handoff to Flow C.
The immediate next step is `architecture-slice-readiness.agent.md`, not decomposition. Requirement readiness and Architecture slice readiness are separate gates.
`ReadyForSliceDecomposition` requires a current slice architecture artifact. `ArchitectureNotRequired` permits decomposition without one for a source-backed simple structure. `NeedsArchitectureElaboration` runs `architecture-elaboration.agent.md` and then reruns readiness; `NeedsHumanDecision` stops.
For `ArchitectureNotRequired`, the readiness artifact itself is the lightweight baseline authority. Before implementation authorization for every executable slice, the Plan Coverage parent reconfirms baseline freshness and `implementation-handoff-review` compares slice-local pre-implementation decisions with the current approved Slice Architecture or Lightweight architecture baseline. Only `Match` may proceed; `Drift` returns to Architecture Slice Readiness / Elaboration, and `Unclear` fails closed and reruns Architecture Slice Readiness.
Readiness and architecture artifacts record a source repository commit, tracked source content hashes / explicit revisions, watch paths, explicit artifact revision, and evaluation time. Freshness compares tracked sources and the source-commit-to-current diff on watch paths; HEAD changes containing only generated gate artifacts do not self-invalidate the baseline. A semantic baseline change is `stale`, even when paths are unchanged.
The pre-elaboration readiness R1 is retained in Slice Architecture as an immutable `elaboration_trigger` audit snapshot with `freshness_dependency: false`. Replacing the standard readiness path with post-elaboration R2 does not stale the architecture; R2 instead tracks the Slice Architecture external content hash.
Only an approved readiness verdict may proceed to `plan-slice-decomposition.agent.md`. Each resulting slice then re-enters the Plan網羅チェック・残件判定フロー as a bounded parent Plan pass. After slice verification, the parent flow runs `cross-slice-verification-kernel.agent.md` and then `residual-decision-gate.agent.md`.

`full-coverage` does not require many executable slices. If a small number of slices, including 2 slices, preserves parent acceptance conditions, cross-slice contracts, field continuity, and Behavior Case mapping, that is a valid decomposition. `plan-slice-decomposition.agent.md` must include a `Slice granularity review` before output and must coalesce candidates when delegation overhead would outweigh implementation value.

The decomposition gate must avoid single-function, single-sequence-step, or single-mapping slices unless there is a documented independent verification route, rollback / discard boundary, different owner / model / profile need, blocking dependency, or producer / consumer contract reason. Small slices that remain independent require `Small slice justification`; otherwise they should be classified as `merge-candidate`, `too-small-to-delegate`, or `coalesce-with-SL-xxx` and should not proceed as executable slices.

Missing source-to-case expansion, missing Case-to-Plan mapping, or undecided expected behavior must not be classified as `full-coverage`.

Cross-slice verification is not only a structural wiring check. After producer action and production wiring run, the consumer observable must satisfy the parent acceptance condition runtime postcondition. Forbidden states from the parent acceptance condition must be copied into the cross-slice artifact and denied by evidence before a pass verdict is allowed.

### `fix-slice`

Resolves explicit FixNow gaps only.

Use when:

- triage or verification has already identified target IDs
- the user wants to spend tokens on a known bounded repair
- unresolved work should not expand into unrelated implementation changes

## Lite / standard documentation level

`documentation_level` controls how much artifact structure the bounded Plan網羅チェック pass uses.
It does not change the source of truth, residual decision, or production-binding guardrails.

| Level | Use when | Artifact shape |
| --- | --- | --- |
| `lite` | The change is small, local, clear, and has low behavior / implementation-realization risk | A single Lite artifact or equivalent section includes source of truth, FR / AC coverage, Inline Ready Gate, Implementation Self-Map, Verification Summary, and Residual / Close Decision |
| `standard` | The change has compatibility risk, behavior expansion, implementation-realization risk, canonical ledger / delta needs, non-trivial verification, or residual ambiguity | Separate or canonical artifacts preserve Plan readiness, risk, implementation contract, handoff / readiness, coverage ledger / delta, verification, and residual decision |

`strict` is not a documentation level.
`full-coverage` is a route / selected process for a ready but broad parent Plan, not a documentation level.
When full-coverage decomposition is selected, the documentation level remains `standard` while the selected process records the advanced route.

Lite may use Inline Ready Gate as an implementation authorization source only when the gate is explicitly equivalent to implementation handoff review and complete.
Otherwise, the flow must use `standard` or stop before implementation.

Maintainers should run `apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1` for its implemented package-layout, explicit invocation-authorization, fixture, and manual-smoke-template checks. Use the package-owned `tests/invocation-authorization-scenarios.json` scenarios and `tests/manual-model-smoke/` for authorization behavior and manual smoke evidence; this validator does not perform artifact-count / sections-read comparisons or broad negative scans.

## Current process flows

### Main flow: Plan網羅チェック・残件判定フロー

This is the canonical Plan Coverage route.

1. `plan-kernel.agent.md`
2. If Plan readiness is `NeedsPlanBehaviorExpansion` because source-to-case expansion is missing, run `black-box-behavior-spec-kernel.agent.md`
3. Re-run `plan-kernel.agent.md` when behavior Case IDs must be mapped to FR / AC or explicit disposition
4. `change-risk-triage.agent.md` only when Plan readiness is `ReadyForRiskTriage`
5. If triage recommends `full-coverage`, run `architecture-slice-readiness.agent.md`
6. If needed, run `architecture-elaboration.agent.md` and rerun readiness; stop on human decision or blocking architecture residual
7. Run `plan-slice-decomposition.agent.md` only for `ReadyForSliceDecomposition` or `ArchitectureNotRequired`
8. Run each resulting slice through the bounded Plan網羅チェック・残件判定フロー:
   - `implementation-contract-kernel.agent.md`, when implementation-realization risk is present
   - `implementation-contract-review-kernel.agent.md`, only as an explicit review-only fallback for the implementation contract self-check verdict
   - `runtime-contract-kernel.agent.md`
   - `test-design-kernel.agent.md`
   - `implementation-handoff-review.agent.md`
   - when explicitly selected, Design Pair Target Map presentation and mandatory `AWAITING_USER_INPUT` boundary
   - Adaptive implementation by the canonical HIGH -> optional STANDARD -> HIGH route
   - `verification-kernel.agent.md`
9. When decomposition was used, run `cross-slice-verification-kernel.agent.md`
10. `coverage-gap-triage.agent.md`, when FixNow candidates or unresolved implementation coverage items need classification and no complete `Direct FixNow selectors` table exists
11. `residual-decision-gate.agent.md`, when residual / manual / human-decision candidates remain
12. `coverage-gap-resolution-slice.agent.md`, only when verification-kernel, coverage-gap-triage, or residual-decision-gate emits an explicit FixNow selector

Implementation handoff must include:

- the bounded Plan from `plan-kernel.agent.md`
- Black-box Behavior Spec artifact, when expansion was required
- `change-risk-triage` output
- `architecture-slice-readiness` output for full-coverage work
- current `slice-architecture` artifact when the readiness verdict is `ReadyForSliceDecomposition`
- `plan-slice-decomposition` output when the bounded parent Plan pass comes from full-coverage decomposition
- `implementation-contract-kernel` output when required
- `coverage-ledger` output when present
- `implementation-contract-review-kernel` output when an explicit review-only fallback exists
- `runtime-contract-kernel` output
- `test-design-kernel` output
- `implementation-handoff-review` output
- durable `implementation_route`, `implementation_route_source`, `design_pair_handoff`, and `design_pair_interaction_stage`
- for Design Pair, Target Map presentation / post-map user evidence and selected / delegated / pending Target IDs
- parent Plan implementation surface and non-goals
- Parent Plan Coverage Ledger
- Behavior Case Coverage Ledger, when expansion was required
- Readiness scope: `ParentPlanPass`, `ParentPlanPassWithResidualRisks`, or `Blocked`
- explicit parent Plan residuals when parent Plan implementation surface is narrower than the parent Plan
- prohibited substitutions
- Plan-prohibited substitutions / must-not patterns that `verification-kernel` must smoke-scan
- unresolved implementation-realization items

The implementation agent must treat the Plan as the source of truth. Kernel artifacts are guardrails for Guardrail Focus coverage, not substitutes for the Plan.

When Design Pair is explicitly selected, the first Design Pair turn presents the complete bounded Target Map, saves `AWAITING_USER_INPUT / target-selection`, and stops. A pre-map Plan, Issue, gold document, or initial technical proposal is not Design Pair confirmation. After discussion, missing final disposition produces `AWAITING_USER_INPUT / disposition-confirmation` and another stop. The parent retains the handoff path and interaction stage and does not start Adaptive implementation, verification, or residual handling until valid post-map user evidence makes the handoff `complete / READY_FOR_ADAPTIVE_IMPLEMENTATION`. An explicit post-map all-Adaptive delegation may complete the gate without individual Locked Decisions.

If triage does not recommend `full-coverage`, step 4 can be executed as a single bounded pass without decomposition.

The Plan網羅チェック process documentation must also enforce these points:

- Runtime contract artifacts are not substitutes for implementation contract artifacts.
- Plan conformance checks are required but do not remove the need to investigate unknown implementation paths.
- Unresolved implementation-realization items must stay explicit and must not be converted to guessed production addresses.
- Full-flow implementation contract agents remain available and should be recommended when the kernel variant is too narrow.
- Source-structure tests and CI green are not runtime postcondition proof unless the test body or test-design mapping asserts the required postcondition / forbidden state.
- Previous gaps and residuals must not be closed with evidence that is the same strength or weaker than the evidence previously judged insufficient.

### Flow B: Minimal high-risk guardrail sub-flow

Use only after a bounded Plan exists, Plan readiness is `ReadyForRiskTriage`, and the Guardrail Focus area is already clear.

1. `change-risk-triage.agent.md`
2. `implementation-contract-kernel.agent.md`（when implementation-realization risk is present）
3. `runtime-contract-kernel.agent.md`
4. `test-design-kernel.agent.md`
5. implementation by normal agent or human-guided implementation agent using the Plan plus kernel artifacts
6. `verification-kernel.agent.md`
7. `coverage-gap-triage.agent.md` or `residual-decision-gate.agent.md` when unresolved items remain
8. `coverage-gap-resolution-slice.agent.md` only when an explicit FixNow selector exists

This sub-flow must not be used as a replacement for Plan creation.

### Flow C: Explicit full autonomous flow

Use only when the user explicitly chooses the broad autonomous process for broad, ambiguous, or highly interconnected changes.

This flow remains available, but it is not the automatic interpretation of `full-coverage` inside the Plan網羅チェック `change-risk-triage.agent.md` route.

1. `plan-generation.agent.md`
2. `runtime-evidence.agent.md`
3. `integration-test-design.agent.md`
4. `plan-review.agent.md`
5. optional `implementation-contract-generation.agent.md`
6. optional `implementation-contract-review.agent.md`
7. implementation
8. `integration-test-verification-implementation.agent.md`
9. `coverage-gap-triage.agent.md`
10. `coverage-gap-resolution-slice.agent.md` or full `coverage-gap-resolution.agent.md` only by explicit choice

## Shared output concepts

### Black-box Behavior Spec

When source requirements need expansion, `black-box-behavior-spec-kernel.agent.md` creates:

```md
# Black-box Behavior Spec

## Scope

## Source requirement inventory

| Source ID | Requirement summary | Kind | Source | Notes |
| --- | --- | --- | --- | --- |

## Behavior axes

| Axis ID | Axis | Relevant values | Why behavior changes | Notes |
| --- | --- | --- | --- | --- |

## Case matrix

| Case ID | Source IDs | Input conditions / preconditions | Expected observable behavior | Negative expectation | Status |
| --- | --- | --- | --- | --- | --- |

## Derived invariants

## Excluded combinations / non-goals

## Unresolved requirement-elaboration items

## Handoff Packet
```

Rules:

- The behavior spec owns source-to-case traceability only.
- It must not edit Plan FR / AC.
- It must not choose runtime contracts, implementation contracts, or test points.
- It must not enumerate every Cartesian product by default.
- It must make negative expectations and unresolved product semantics explicit.
- Case-to-Plan mapping belongs in the Plan Kernel artifact.

### Plan Kernel

A bounded Plan artifact should use this shape unless the repository already has a stronger convention:

```md
# Plan Kernel

## Goal

## Non-goals

## Functional requirements

## Acceptance conditions

## Black-box behavior coverage

## Affected components / modules

## Expected implementation scope

## Known high-risk boundaries

## Out of scope for this pass

## Handoff to change-risk-triage

## Handoff Packet
```

Rules:

- The Plan Kernel is the implementation source of truth for the Plan網羅チェック・残件判定フロー.
- It must describe the whole requested change at a useful implementation level, not only high-risk boundaries.
- It must not expand into full runtime evidence or full integration test design.
- It must decide `Expansion required` before FR / AC are finalized.
- When expansion is required, it must record behavior spec path and map relevant Case IDs to FR / AC or explicit disposition.
- It must not advance to `change-risk-triage.agent.md` unless `Plan readiness` is `ReadyForRiskTriage`.
- It must identify known high-risk boundary candidates, but detailed selection belongs to `change-risk-triage.agent.md`.
- It must include non-goals and out-of-scope items so implementation agents do not infer extra work.
- It must include acceptance conditions that can later be mapped to test points or verification items.

`Black-box behavior coverage` should use:

```md
## Black-box behavior coverage

- Expansion required: Yes / No / Unclear
- Behavior spec artifact: <path / N/A>
- Plan readiness: ReadyForRiskTriage / NeedsPlanBehaviorExpansion / NeedsHumanDecision
- Expansion decision reason:
- Blocking requirement-elaboration items:

### Case-to-Plan mapping

| Case ID | Source IDs | FR / AC | Disposition | Notes |
| --- | --- | --- | --- | --- |
```

Allowed dispositions:

- `MappedToPlan`
- `DeferredWithSource`
- `OutOfScopeWithSource`
- `NeedsHumanDecision`
- `UnmappedBlocking`

### Parent Plan Coverage Ledger

A lightweight ledger that prevents Guardrail Focus readiness from being mistaken for bounded parent-Plan pass readiness.

```md
## Parent Plan Coverage Ledger

| Plan item | Type | Status | Covered by Slice ID | Covered by RC ID | Covered by TP ID | Cross-slice Contract ID | Residual / reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
```

Rules:

- Every parent Plan FR / AC must appear in the ledger.
- Selected runtime contracts are allowed to cover only part of the parent Plan, but uncovered items must remain explicit.
- `UnmappedBlocking` blocks implementation handoff.
- `DeferredToKnownSlice` and `CoveredByCrossSliceVerification` allow a bounded parent Plan pass to proceed, but do not imply parent-Plan completion.
- `OutOfScopeByPlan` requires explicit support from Plan Non-goals / Out of scope.
- Downstream agents must not infer completion from absence.
- Handoff review must include both Guardrail Focus readiness and bounded parent-Plan pass readiness.

### Canonical Coverage Ledger and Delta

For standard route work that would otherwise repeat the full parent Plan ledger across many artifacts, create `plans/<ticket-or-slug>-coverage-ledger.md` from the `plan-coverage-residual-flow` Skill's bundled `references/coverage-ledger.md`.

The canonical ledger owns the full parent Plan FR / AC, Behavior Case coverage, and residual decision rows. Intermediate artifacts may emit a `Coverage Ledger Delta` table that records only changed rows. When the canonical ledger exists, handoff and verification artifacts should point their Parent Plan Coverage Ledger section to `plans/<ticket-or-slug>-coverage-ledger.md` instead of restating every FR / AC. A delta never narrows the parent Plan and never replaces the canonical ledger. If a delta contradicts the canonical ledger, treat the mismatch as `SourceOfTruthDrift` and resolve it before claiming close readiness.

### Implementation Contract Kernel

A lightweight implementation-realization artifact should use this shape:

```md
# Implementation Contract Kernel

## Scope

## Plan-named implementation requirements

| Requirement | Expected by Plan | Evidence found | Status |
| --- | --- | --- | --- |

## Dependency and API surface findings

| Dependency / API / symbol | Expected source | Found location | Status | Notes |
| --- | --- | --- | --- | --- |

## Selected implementation approach

## Required code changes

## Prohibited substitutions

| Similar existing path | Why it is not sufficient | Allowed reuse, if any |
| --- | --- | --- |

## Verification hooks

## Unresolved implementation-realization items

## Self-check / Readiness verdict

READY_FOR_RUNTIME_CONTRACT | READY_FOR_IMPLEMENTATION | BLOCKED_BY_DEPENDENCY_MISSING | BLOCKED_BY_API_SURFACE_UNKNOWN | BLOCKED_BY_UNJUSTIFIED_SUBSTITUTION | BLOCKED_BY_SOURCE_OF_TRUTH_DRIFT | NEEDS_HUMAN_DECISION

## Self-check evidence

## Handoff Packet
```

Required statuses include:

- `Confirmed`
- `MissingButRequired`
- `ApiSurfaceUnknown`
- `DependencyMissing`
- `NeedsHumanDecision`
- `RejectedSubstitute`
- `AllowedReuse`
- `OutOfScopeForThisPass`

`implementation-contract-kernel.agent.md` owns the primary readiness verdict. Use `implementation-contract-review-kernel.agent.md` only as an explicit review-only fallback when the self-check verdict itself needs independent documents-only review.

### Runtime Contract Kernel

A lightweight runtime contract artifact should use this shape unless the repository already has a stronger convention:

```md
## Runtime Contract Kernel

| Contract ID | Scenario | Producer | Consumer | Message / API / Event | Required fields | Error / timeout behavior | Production implementation address | Verification hook |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
```

Rules:

- `Contract ID` must be stable and referenced by later artifacts.
- `Producer` and `Consumer` must be concrete runtime participants, not vague layers.
- `Message / API / Event` must name the actual boundary mechanism when known.
- `Required fields` must include identifiers, correlation fields, state keys, or payload fields relevant to the contract.
- `Error / timeout behavior` must state expected handling or explicitly say it is out of scope.
- `Production implementation address` must be a concrete file, module, service, endpoint, or DI registration when known.
- `Verification hook` must point to a test point ID, manual check, or unresolved status.

### Test Design Kernel

A lightweight test design artifact should use this shape:

```md
## Test Design Kernel

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
```

Rules:

- Every selected `Runtime Contract ID` must have at least one test point or an explicit reason why it cannot.
- A test point must describe an observable result, not just an implementation detail.
- If stub / fake / in-memory implementations are allowed, production binding must also be required unless explicitly out of scope.
- When behavior spec exists, selected-scope Case IDs must be connected to a test point or explicit coverage disposition.

Behavior case test mapping should use:

```md
## Behavior case test mapping

| Case ID | Runtime Contract ID | Test Point ID | Expected behavior | Coverage disposition | Evidence target | Status |
| --- | --- | --- | --- | --- | --- | --- |
```

Allowed coverage dispositions:

- `AutomatedPlanned`
- `ManualOnly`
- `CoveredByHigherLevelCase`
- `DeferredWithReason`
- `OutOfScopeWithSource`
- `NeedsHumanDecision`

Not every Case ID requires an automated test. Case IDs outside selected scope must not expand the test-design scope.

### Stub-to-Production Binding

Verification should produce or update this shape when tests use substitutes:

```md
## Stub-to-Production Binding

| Test Point ID | Stub / fake / in-memory used in test | Production interface | Production concrete implementation | Production wiring / entrypoint | Status | Remaining work |
| --- | --- | --- | --- | --- | --- | --- |
```

Rules:

- A passing test using a fake does not imply production readiness.
- `Status` must not be `Bound` unless production interface, production implementation, wiring / entrypoint, and post-wiring behavior against the parent acceptance condition runtime postcondition are all confirmed.
- If only the interface exists, use `NotImplementedOrMismatch`.
- If implementation exists but default wiring is missing, use `NotImplementedOrMismatch` or `PartiallyDone` with explicit remaining work.
- Source-structure tests can provide wiring evidence, but they cannot prove runtime state, phase, durable state, async worker behavior, input acceptance, recovery semantics, or retry / failure behavior.
- CI green is close evidence only when the relevant test body or test-design mapping asserts the required runtime postcondition.

### Cross-slice runtime postcondition oracle

`cross-slice-verification-kernel.agent.md` must include this table when `plan-slice-decomposition` was used:

```md
| ID | Producer action chain | Production wiring path | Consumer observable | Required runtime postcondition | Forbidden state | Evidence type | Evidence strength | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
```

Evidence strength is ordered from weak to strong:

1. `ArtifactStatementOnly`
2. `SourceTextOrSourceStructureTest`
3. `ExactSourceProofOfProducerAndConsumerStateTransition`
4. `UnitBehaviorTestInvokingProducerAndConsumerTogether`
5. `ProductionStartupEquivalentBehaviorTest`
6. `RealRuntimeOrManualOperationEvidence`

For stateful cross-slice contracts, producer state and consumer gate must both be checked. Startup, recovery, async worker, durable state, and state-machine consistency cannot be marked `Done` or `Bound` from source-structure evidence alone.

When rerunning cross-slice verification, include this table:

```md
| Previous ID | Previous failure mode | Required closure evidence | New evidence delta | Evidence strength vs previous | Closure decision |
| --- | --- | --- | --- | --- | --- |
```

If a previous gap was left open because source-level evidence was insufficient, source-structure test plus CI green is not enough to close it.

### Behavior Case Coverage and Evidence Ledgers

Implementation handoff review should include this table when expansion was required:

```md
## Behavior Case Coverage Ledger

| Case ID | Source IDs | FR / AC | Coverage route | Slice / RC / TP | Status | Residual / reason |
| --- | --- | --- | --- | --- | --- | --- |
```

Verification should include this table when behavior Case IDs are in the current pass:

```md
## Behavior Case Evidence Ledger

| Case ID | Source IDs | FR / AC | Coverage route | Evidence target | Evidence status | Residual / reason |
| --- | --- | --- | --- | --- | --- | --- |
```

Rules:

- All relevant Case IDs must appear when expansion was required.
- `UnmappedBlocking` blocks implementation handoff.
- `NeedsHumanDecision` blocks implementation when the decision is needed before implementation.
- `BehaviorCaseWithoutEvidence` is an evidence gap; it may route to FixNow / manual / defer when the Plan mapping is already valid.
- `UnexpandedRequirement`, `SourceRequirementNotMappedToPlan`, and `UnmappedBehaviorCase` are requirement-elaboration gaps and normally require replan.

### Agent version and verdict vocabulary

Plan網羅チェックの gate artifacts that produce a final verdict must record the agent / skill version and verdict vocabulary. This applies to `implementation-handoff-review.agent.md`, `verification-kernel.agent.md`, `cross-slice-verification-kernel.agent.md`, and `residual-decision-gate.agent.md`.

```md
| Item | Value |
| --- | --- |
| Agent file path | |
| Agent file SHA | |
| Skill file path | |
| Skill file SHA | |
| Allowed verdict vocabulary | |
| Actual verdict | |
| Vocabulary valid? | Yes/No |
```

If `Actual verdict` is not present in the allowed vocabulary for that agent file SHA, the artifact is not passable.

### Residual rerun closure rule

`residual-decision-gate.agent.md` must include this table when a previous residual artifact exists:

```md
| RES ID | Previous required decision | Closure type | New evidence | Why human decision no longer needed |
| --- | --- | --- | --- | --- |
```

`NeedsHumanDecision` and previous `RES-*` items cannot be removed by source inspection, source-structure tests, or CI green alone. They can close only when one of these is true:

- an explicit human decision is recorded
- code or tests changed according to a criterion already decided in the parent Plan
- new evidence proves the previous residual premise was wrong

Otherwise the item remains `NeedsHumanDecision` and the verdict must not become close-ready.

### Handoff Packet

Every agent that produces a durable artifact should include or update a compact handoff packet:

```md
## Handoff Packet

- Profile used:
- Source artifacts:
- Selected contracts / IDs:
- Files inspected:
- Files intentionally not inspected:
- Decisions made:
- Do not redo unless new evidence appears:
- Remaining work:
- Recommended next step:
```

Rules:

- The packet should reduce repeated rediscovery.
- `Do not redo` must identify prior analysis that downstream agents can trust unless contradicted.
- `Remaining work` must be specific and actionable.

## Shared status vocabulary

Architecture Slice Readiness verdicts are owned by `architecture-slice-readiness.agent.md` and are not generic progress statuses:

| Verdict | Meaning |
| --- | --- |
| `ReadyForSliceDecomposition` | Shared architecture semantics are complete in a current architecture artifact and decomposition may proceed |
| `NeedsArchitectureElaboration` | Requirements are ready but shared architecture needs elaboration before decomposition |
| `ArchitectureNotRequired` | A source-backed simple structure can be decomposed safely without a separate architecture artifact |
| `NeedsHumanDecision` | Product, architecture, policy, or risk authority is required before progress |

Architecture residual classifications are `ArchitectureCritical`, `NeedsHumanDecision`, `SliceLocalContract`, `ImplementationDetail`, and `OutOfScopeWithSource`. The first two block decomposition.

Use these statuses consistently unless an existing artifact has a stronger convention:

| Status | Meaning |
| --- | --- |
| `Done` | Completed within this pass |
| `PartiallyDone` | Some useful progress was made, but the item is not complete |
| `Deferred` | Intentionally not handled in this pass |
| `ManualOnly` | Requires manual or real-environment validation |
| `NeedsHumanDecision` | Cannot safely proceed without a product, architecture, policy, or risk decision |
| `NotImplementedOrMismatch` | Implementation is missing, mismatched, or only test-side / fake-side exists |
| `OutOfScopeForThisPass` | Valid work, but outside the bounded parent Plan pass or Guardrail Focus coverage |
| `Bound` | Production interface, production implementation, production wiring / entrypoint, and post-wiring behavior against the parent acceptance condition runtime postcondition have been confirmed for a test substitute |
| `CoveredByGuardrailFocus` | Parent Plan item is covered by selected RC / TP / slice |
| `CoveredByCrossSliceVerification` | Parent Plan item is intentionally left for cross-slice verification |
| `DeferredToKnownSlice` | Parent Plan item is deferred to a named slice / RC / gap ID |
| `OutOfScopeByPlan` | Parent Plan item is explicitly excluded by Plan Non-goals / Out of scope |
| `UnmappedBlocking` | Parent Plan item is not mapped to Guardrail Focus coverage, deferral, cross-slice verification, out-of-scope, or human decision |
| `MappedButWeak` | Mapping exists but the oracle, binding, or observable acceptance is weak |
| `ReadyForRiskTriage` | Plan readiness is complete and risk triage may proceed |
| `NeedsPlanBehaviorExpansion` | Source-to-case expansion or Case-to-Plan mapping is missing and the flow must return to Plan phase |
| `CoveredByParentPlanPass` | Behavior Case is covered by the bounded parent Plan pass |
| `OutOfScopeWithSource` | Behavior Case is excluded by source-backed non-goal or out-of-scope decision |

### Shared gap type vocabulary

- `plan-smoke-mismatch`: A Plan-prohibited pattern was found in selected production addresses. verification-kernel uses this in `未解決項目.Type` and keeps `Status` as `NotImplementedOrMismatch`.
- `UnexpandedRequirement`: A source requirement that should have behavior Case IDs was not expanded.
- `SourceRequirementNotMappedToPlan`: A source requirement or Case ID is not mapped to Plan FR / AC or explicit disposition.
- `UnmappedBehaviorCase`: A Case ID has no coverage route.
- `BehaviorCaseWithoutEvidence`: A mapped Case ID in the current pass lacks test / manual / production evidence.
- `AmbiguousExpectedBehavior`: Expected behavior or negative expectation requires product / policy human decision.

## Shared bounded-pass rules

All Plan網羅チェック agents should follow these rules unless the user explicitly asks to leave the bounded route and run the full autonomous flow:

- Perform one bounded pass.
- Do not keep repairing until all issues disappear.
- Prefer explicit residual work over speculative broad fixes.
- Stop when the work would require broad redesign, repeated fix loops, or human judgment.
- Do not expand from Guardrail Focus contracts / explicitly selected IDs into unrelated parts of the system.
- Do not weaken assertions merely to mark an item complete.
- Do not treat test-only implementation as production implementation.
- Do not mark production binding complete without checking wiring or entrypoint.

## Agent requirements

## 1. `black-box-behavior-spec-kernel.agent.md`

### Purpose

Expand source requirements into stable black-box behavior Case IDs before Plan readiness.

### Inputs

- issue, prompt, specification, or high-level requirement
- existing bounded Plan when present
- relevant docs needed to understand source semantics

### Required outputs

```md
# Black-box Behavior Spec

## Scope

## Source requirement inventory

## Behavior axes

## Case matrix

## Derived invariants

## Excluded combinations / non-goals

## Unresolved requirement-elaboration items

## Handoff Packet
```

### Required checks

The agent must:

- inventory source requirements with stable Source IDs
- identify behavior axes that change observable outcomes
- create stable Case IDs for required combinations
- record negative expectations
- record excluded combinations with reasons
- record unresolved product semantics as `NeedsHumanDecision`

### Must not do

- edit Plan FR / AC
- write code or tests
- choose runtime contracts, implementation contracts, or test points
- enumerate every Cartesian product by default
- guess ambiguous expected behavior

### Stop condition

Stop after creating or updating `plans/<ticket-or-slug>-black-box-behavior-spec.md` and recommending `plan-kernel.agent.md` or human decision.

## 2. `plan-kernel.agent.md`

### Purpose

Create a bounded Plan for the requested change. This Plan is the implementation source of truth for the Plan網羅チェック・残件判定フロー.

### Inputs

- issue, prompt, or high-level requirement
- existing repository structure and relevant files only as needed to create the Plan
- existing docs or architecture notes when directly relevant

### Required outputs

```md
# Plan Kernel

## Goal

## Non-goals

## Functional requirements

## Acceptance conditions

## Black-box behavior coverage

## Affected components / modules

## Expected implementation scope

## Known high-risk boundaries

## Out of scope for this pass

## Handoff to change-risk-triage

## Handoff Packet
```

### Required checks

The agent must:

- create a useful bounded Plan before risk triage
- decide behavior expansion readiness before FR / AC are finalized
- map relevant Case IDs to FR / AC or explicit disposition when behavior spec exists
- state what is in scope and out of scope
- identify functional requirements and acceptance conditions
- identify affected components / modules at a practical implementation level
- list known or suspected high-risk boundaries without deep runtime evidence
- prepare the Plan for `change-risk-triage.agent.md`

### Must not do

- implement code
- create tests
- generate full runtime evidence
- generate full integration test design
- select final runtime contracts in place of `change-risk-triage.agent.md`
- continue expanding repository exploration after the Plan is good enough for bounded implementation
- send a Plan to `change-risk-triage.agent.md` when `Plan readiness` is not `ReadyForRiskTriage`
- use `full-coverage` as a substitute for missing behavior expansion

### Stop condition

Stop after creating or updating the bounded Plan and recording `Plan readiness`.

If readiness is `ReadyForRiskTriage`, hand off to `change-risk-triage.agent.md`.
If readiness is `NeedsPlanBehaviorExpansion`, hand off to `black-box-behavior-spec-kernel.agent.md` or rerun `plan-kernel.agent.md` for Case-to-Plan mapping.
If readiness is `NeedsHumanDecision`, stop for human decision.

## 3. `change-risk-triage.agent.md`

### Purpose

Classify the bounded Plan, identify high-risk runtime boundaries, and recommend the minimum sufficient process profile.

### Inputs

- Plan Kernel or other bounded Plan artifact
- original issue / prompt only as supplementary context
- repository structure and relevant files only as needed for risk classification

### Required outputs

```md
# Change Risk Triage

## Plan readiness check

## Recommended profile

## Reasoning

## High-risk boundaries

## Selected runtime contracts to cover

## Implementation realization risk

## Suggested next agent

## Out of scope for this triage

## Handoff Packet
```

### Required checks

Before risk triggers, the agent must run Plan readiness check:

- expansion decision exists
- behavior spec exists when required
- relevant source requirements have Case IDs
- relevant Case IDs are mapped to FR / AC or explicit disposition
- negative expectations are represented
- blocking requirement ambiguity is absent

Only `ReadyForRiskTriage` may proceed to risk trigger scan and profile selection.

The agent must look for risk triggers including:

- cross-process or cross-service sequence
- queue / event / webhook / background worker
- external API / SDK
- authentication / authorization
- durable state / retry / replay / idempotency
- startup wiring / DI / configuration
- production implementation split from test substitute
- Plan names a specific external SDK or API
- Plan names package / release / binary artifact / local lib folder
- Plan names namespace / type / method / extension method / provider ID / config section
- existing code contains a similar but different implementation path
- affected production address is not known from current evidence
- Plan contains remaining work about API surface inspection or dependency confirmation

### Must not do

- create or change the Plan
- create implementation code
- create or revise tests
- perform full Plan generation
- resolve gaps
- select runtime contracts or process profile when Plan readiness is not `ReadyForRiskTriage`
- treat requirement-elaboration gaps as `full-coverage`

### Stop condition

Stop after Plan readiness check.

If Plan readiness is not `ReadyForRiskTriage`, record the Plan-phase next agent or human decision and stop without profile selection.
If ready, stop after recommending a profile and Guardrail Focus contracts / IDs. If risk cannot be classified from available context, recommend `contract-kernel` or `standard-slice` rather than pretending the task is safe.

When implementation-realization risk is `Present` or `Unclear`, the next-step recommendation must be one of:

- `implementation-contract-kernel.agent.md`
- `full-coverage`

Do not recommend immediate `runtime-contract-kernel.agent.md` in this condition. Recommend full `implementation-contract-generation.agent.md` only when the user explicitly chooses Flow C.

## 4. `runtime-contract-kernel.agent.md`

### Purpose

Create or update the minimal runtime contract artifact for Guardrail Focus surfaces.

### Inputs

- Guardrail Focus runtime contracts or change-risk triage output
- Plan Kernel or bounded Plan artifact
- Implementation Contract Kernel artifact when present
- relevant code / docs only for identifying participants, boundaries, and addresses

### Required outputs

```md
# Runtime Contract Kernel

## Scope

## Runtime Contract Kernel

## Plan / implementation contract conformance

## Notes / assumptions

## Handoff Packet
```

### Required checks

For each selected contract, verify or record:

- producer
- consumer
- boundary mechanism
- required fields or state
- error / timeout / retry expectation
- production implementation address if known
- verification hook if known

### Must not do

- generate broad PlantUML evidence for unrelated scenarios
- implement code
- create tests
- invent production addresses without evidence
- substitute nearby existing implementation when implementation-contract says path is missing/unknown
- replace the Plan as source of truth

### Escalation condition

If the selected contracts need decomposition before safe bounded handling, send the work back to `change-risk-triage.agent.md` for reclassification.
If that reclassification returns `full-coverage`, hand off to `architecture-slice-readiness.agent.md`; decomposition requires an approved readiness verdict.
Recommend `runtime-evidence.agent.md` only when the user explicitly wants to leave the Plan網羅チェック flow and run Flow C.

## 5. `test-design-kernel.agent.md`

### Purpose

Create a compact test design mapped to Guardrail Focus runtime contracts.

### Inputs

- Runtime Contract Kernel
- Plan Kernel or bounded Plan artifact
- Black-box Behavior Spec artifact when present
- relevant existing test conventions

### Required outputs

```md
# Test Design Kernel

## Scope

## Test Design Kernel

## Required production binding checks

## Manual-only checks

## Behavior case test mapping

## Handoff Packet
```

### Required checks

For each Guardrail Focus runtime contract:

- define at least one observable verification point or an explicit reason why not
- map the verification point back to the Plan requirement / acceptance condition where possible
- identify whether a stub / fake / in-memory substitute is expected
- require production binding verification when a substitute is used
- also require production binding verification when selected contracts involve external SDK/API/provider selection, dependency/package/binary update, DI/startup/config wiring, Plan-named symbols, implementation-contract decisions, or substitution risk
- include negative / error path checks for boundary contracts when relevant
- when behavior spec exists, map current selected-scope Case IDs to test points or explicit coverage disposition

### Must not do

- implement tests
- expand to full integration test design unless requested
- create test points not connected to Guardrail Focus runtime contracts
- silently omit selected-scope Case IDs
- require automated tests for every Case ID when manual / higher-level / deferred disposition is correct

### Escalation condition

Recommend `full-coverage` / `architecture-slice-readiness.agent.md` when the bounded parent Plan pass cannot be handled safely as one Plan網羅チェック pass. Recommend `integration-test-design.agent.md` only when the user explicitly wants to leave the Plan網羅チェック flow and run Flow C.

## 6. `verification-kernel.agent.md`

### Purpose

Verify Parent Plan coverage and Guardrail Focus runtime contracts/test points after implementation, focusing on production binding and wiring.

### Inputs

- Plan Kernel or bounded Plan artifact
- Black-box Behavior Spec artifact when present
- Runtime Contract Kernel
- Test Design Kernel or integration test points
- Coverage Ledger when present
- implementation diff or repository state
- relevant production startup / DI / entrypoint files
- relevant test files

### Required outputs

```md
# Verification Kernel Result

## Agent version

| Item | Value |
| --- | --- |
| Agent file path | |
| Agent file SHA | |
| Skill file path | |
| Skill file SHA | |
| Allowed verdict vocabulary | |
| Actual verdict | |
| Vocabulary valid? | Yes/No |

## Scope

## Runtime contract verification

## Coverage Ledger Delta

## Parent Plan smoke scan

## Behavior Case Evidence Ledger

## Stub-to-Production Binding

Include `Post-wiring behavior evidence / oracle reference` in the Stub-to-Production Binding table. `Bound` rows must cite concrete post-wiring behavior evidence or a runtime postcondition oracle row.

## Test observations

## Unresolved items

## Direct FixNow selectors

## Verdict

## Handoff Packet
```

### Required checks

For each selected test point:

- whether a test exists or a manual-only reason is recorded
- whether a stub / fake / in-memory substitute is used
- whether the corresponding production interface exists
- whether a production concrete implementation exists
- whether production wiring / entrypoint reaches that implementation
- whether Guardrail Focus runtime contract fields and error behavior are represented
- whether the result is still consistent with the Plan requirement / acceptance condition
- whether selected production addresses contain Plan-prohibited patterns or implementation-contract `RejectedSubstitute` paths
- whether current selected-scope Case IDs connect to test / manual / production evidence
- whether missing behavior expansion should be handed to residual-decision-gate as a replan candidate
- when implementation-contract exists, whether runtime address and wiring are consistent with implementation-contract decisions
- if nearby implementation is wired but Plan-required path is missing, classify as blocking mismatch/gap rather than pass
- when Plan Slice Decomposition exists, keep slice scope / XC IDs visible and defer cross-slice binding to `cross-slice-verification-kernel.agent.md`
- when parent Plan residuals remain outside the bounded parent Plan pass or Guardrail Focus, keep them visible in the Handoff Packet rather than implying parent Plan completion
- when a canonical coverage ledger exists, emit only changed rows as `Coverage Ledger Delta`
- emit a `Direct FixNow selectors` table only for 1〜2 simple gaps with source artifact, source section/table, existing ID, gap type, Plan item / Case ID, target files / addresses, and why direct FixNow is safe

### Verdicts

Use one of:

- `PARENT_PLAN_VERIFIED`
- `PARENT_PLAN_VERIFIED_WITH_ACCEPTED_RESIDUALS`
- `PARENT_PLAN_NEEDS_RESIDUAL_DECISION`
- `PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES`
- `BLOCKED_BY_PRODUCTION_BINDING_GAP`
- `BLOCKED_BY_CONTRACT_MISMATCH`
- `BLOCKED_BY_HUMAN_DECISION`

`PARENT_PLAN_VERIFIED` is valid only when the Parent Plan Coverage Ledger has no unmapped parent Plan items and no unresolved residual decision candidates. Guardrail Focus verification alone does not mean the parent Plan is complete. A Plan-prohibited pattern found inside selected production addresses is a contract mismatch, not a non-blocking note.

### Must not do

- fix all gaps automatically
- broaden to unrelated IDs
- mark fake-only success as pass
- perform large implementation changes

### Stop condition

Stop after updating Parent Plan Coverage Ledger and classifying unresolved items. If FixNow candidates exist, hand them to `coverage-gap-triage.agent.md` unless the direct FixNow selector conditions are fully met and the `Direct FixNow selectors` table is complete. If residual / manual / human-decision candidates remain, hand them to `residual-decision-gate.agent.md`. Do not recommend `coverage-gap-resolution-slice.agent.md` directly unless an explicit FixNow selector exists.

## 7. `coverage-gap-triage.agent.md`

### Purpose

Classify unresolved implementation coverage items without fixing them.
This agent can be skipped only when verification-kernel or residual-decision-gate emitted a complete `Direct FixNow selectors` table for a simple gap.

### Inputs

- verification-kernel output or implementation coverage document
- Plan Kernel or bounded Plan artifact
- Plan Slice Decomposition artifact when classifying gaps from full-coverage decomposition slices
- integration test points or Test Design Kernel
- Runtime Contract Kernel when available

### Required outputs

```md
# Coverage Gap Triage

## Scope

## Gap classification

## Recommended fix slices

## Human decisions required

## Handoff Packet
```

### Gap classification table

```md
| ID | Current status | Plan requirement / contract | Gap type | Suggested next action | Recommended target profile |
| --- | --- | --- | --- | --- | --- |
```

### Gap types

Use a controlled vocabulary:

- `ImplementationContractMissing`
- `DependencyMissing`
- `ApiSurfaceUnknown`
- `UnjustifiedSubstitution`
- `SourceOfTruthDrift`
- `ProductionImplementationMissing`
- `ProductionWiringMissing`
- `ContractMismatch`
- `TestOracleMissing`
- `ManualEnvironmentRequired`
- `PlanAmbiguity`
- `DesignTooBroadForSlice`
- `AlreadyCoveredButDocumentationStale`
- `ParentPlanCoverageGap`
- `UnmappedParentAcceptance`
- `ScopeVerdictAmbiguity`
- `PlanProhibitedPatternDetected`

### Must not do

- implement code
- change tests
- update status to complete without evidence
- create new IDs

## 8. `coverage-gap-resolution-slice.agent.md`

### Purpose

Resolve only explicitly selected coverage gaps in one bounded pass.

### Inputs

- selected gap IDs
- Plan Kernel or bounded Plan artifact
- implementation coverage document or verification status artifact
- integration test points or Test Design Kernel
- Runtime Contract Kernel when available
- coverage gap triage output when available

### Required outputs

```md
# Coverage Gap Resolution Slice Result

## Selected IDs

## Changes made

## Test updates

## Coverage document updates

## Remaining work

## Verdict

## Handoff Packet
```

### Required behavior

For each selected ID:

- map it back to the Plan requirement or runtime contract
- for `ParentPlanCoverageGap`, `UnmappedParentAcceptance`, `ScopeVerdictAmbiguity`, or `PlanProhibitedPatternDetected`, map the gap back to the exact parent Plan FR / AC
- for parent Plan coverage gaps, decide whether the fix is a new slice, cross-slice verification update, implementation-contract update, or production implementation fix
- do not mark a parent Plan coverage gap complete by narrowing Guardrail Focus coverage silently
- update Parent Plan Coverage Ledger in the output/status artifact, or create one in the output if missing
- if the gap is a Plan-prohibited production pattern, include a negative test or verification hook unless explicitly impossible
- for `ImplementationContractMissing` / `DependencyMissing` / `ApiSurfaceUnknown` / `UnjustifiedSubstitution` / `SourceOfTruthDrift`, first consume or create the selected-slice implementation contract artifact before direct repair
- identify the minimal production implementation / wiring / test update needed
- apply only bounded changes required for that ID
- update the active status artifact when appropriate
- leave unresolved status if the fix would exceed the explicit FixNow selector or bounded parent Plan pass

### Must not do

- change unrelated IDs
- add broad abstractions unless required by selected IDs
- replace Plan-required production behavior with local heuristics
- treat interface-only or fake-only code as completion
- continue fix loops until all tests pass at any cost

### Stop condition

Stop after one bounded pass over selected IDs. Remaining issues must be recorded, not chased indefinitely.

## Full Autonomous boundary

`plan-generation.agent.md`, `plan-review.agent.md`, `runtime-evidence.agent.md`, `integration-test-design.agent.md`, `integration-test-verification-implementation.agent.md`, and `coverage-gap-resolution.agent.md` belong to the explicit Full Autonomous flow or compatibility routes. Selecting Plan Coverage `full-coverage` does not invoke them automatically. Inside Plan Coverage, `full-coverage` means Architecture Slice Readiness, bounded decomposition, normal Plan Coverage execution and verification for each slice, Cross-Slice Verification, and Residual Decision.

## Current contract acceptance criteria

The current process contract is satisfied when:

- a bounded Plan is created before risk triage
- expansion decision and Plan readiness are recorded before risk triage
- behavior spec exists when expansion is required
- all relevant Case IDs are mapped to FR / AC or explicit disposition before `ReadyForRiskTriage`
- `NeedsPlanBehaviorExpansion` does not choose `full-coverage`
- implementation agents receive the Plan plus kernel guardrail artifacts
- a bounded run can handle Guardrail Focus cross-boundary coverage without skipping runtime contracts
- a stub-based test cannot be marked complete without production binding verification
- when implementation-realization risk is `Present` / `Unclear`, implementation-contract branch is recommended before `runtime-contract-kernel`
- when Plan-named dependency / API / provider path is unconfirmed, it remains unresolved and is not replaced by nearby existing implementation
- implementation-contract decisions are handed off to and consumed by runtime-contract / test-design / verification artifacts
- production binding required applies not only to stub/fake usage but also to Plan-named external provider/API/dependency paths
- every Guardrail Focus contract / test point and explicit FixNow gap ends with explicit status
- unresolved work is useful enough to drive a later fix slice
- the full process remains available for broad high-risk work
- agent prompts clearly state when to stop rather than continue repairing
- Guardrail Focus readiness cannot be reported as bounded parent-Plan pass readiness unless all parent Plan FR / AC are mapped, deferred, assigned to residual decision, or explicitly out of scope
- implementation-handoff-review is a mandatory gate in the main Plan網羅チェック flow and creates a Parent Plan Coverage Ledger before any READY verdict is issued
- verification-kernel performs a bounded Parent Plan smoke scan for Plan-prohibited patterns in selected production addresses
- Plan-prohibited substitutions found in selected production addresses are classified as contract mismatch, not as non-blocking notes
- parent residuals remain visible until resolved by a named slice, cross-slice verification, human decision, or explicit out-of-scope decision
- implementation-handoff-review includes Behavior Case Coverage Ledger when expansion was required
- verification-kernel records Behavior Case Evidence Ledger for Case IDs in the current pass
- residual-decision-gate treats `UnexpandedRequirement`, `SourceRequirementNotMappedToPlan`, and `UnmappedBehaviorCase` as replan candidates by default
- full-coverage remains self-contained under Plan Coverage ownership from Architecture Slice Readiness through Residual Decision
- every executable full-coverage slice re-enters the standard Plan Coverage chain as a bounded Plan and receives independent verification
- the Plan Coverage parent and implementation-handoff-review allow implementation only for a current-baseline architecture `Match`
- `Drift` returns to Architecture Slice Readiness / Elaboration and `Unclear` fails closed
- Cross-Slice Verification runs after all executable slices and before parent residual closure
- the current repeated per-slice artifact and handoff cost remains explicit; no Living Record or new lightweight slice lifecycle is claimed as implemented
