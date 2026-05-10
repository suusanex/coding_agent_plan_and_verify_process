# Token-aware Guardrail Kernel: Process and Agent Requirements

## Purpose of this document

This document defines a concrete process and agent structure for making the Plan-first workflow token-aware while preserving the guardrails that prevent cross-process contract mismatches and stub-only implementation success.

This document is a requirements specification for creating or revising agents. It is not an implementation task list.

この document は、agent を作成または改訂する側が読む authoring-time context です。agent 実行時に、この document や `docs/` 配下の file が存在することを前提にしてはいけません。

この document に基づいて agent を作成または改訂する場合、作成者または作成プロセスは次を authoring-time context として読む必要があります。

- `docs/token-aware-guardrail-kernel-purpose.md`
- replace または complement する existing agent files
- 実際の implementation task を想定するために必要な target repository context

作成された agent は、別 repository に単体で配置される可能性があります。そのため、agent の実行時に必要な目的、方針、profile、handoff、他 agent との関係は、agent file 自体、または同時に配布される共通 instruction file に含めてください。

## Design policy

The process reduces cost by narrowing the target slice, not by removing essential guardrails.

The token-aware flow is still a Plan-first flow. It must not start implementation from risk triage or runtime-contract artifacts alone.

The required high-level chain is:

1. create a bounded Plan for the requested change
2. classify high-risk runtime slices inside that Plan
3. preserve guardrails for selected high-risk slices
4. implement against the Plan as the source of truth
5. verify selected contracts, test points, production implementation, and production wiring
6. classify and resolve remaining gaps through bounded slices

For selected high-risk slices, the process must still connect:

1. Plan requirement / acceptance condition
2. runtime contract
3. test point
4. stub / fake / in-memory usage
5. production implementation
6. production wiring / entrypoint
7. explicit unresolved status

## Corrected process gap

The originally drafted token-aware kernel process began with `change-risk-triage.agent.md`. That was incomplete for the intended purpose.

The goal of this repository is not merely to triage risk. The goal is to keep the existing Plan-first sequence — create Plan, implement, and verify that implementation gaps are not missed — while reducing token consumption and avoiding open-ended repair loops.

Therefore, the token-aware flow needs a lightweight Plan creation phase before risk triage.

The chosen direction is to add a dedicated `plan-kernel.agent.md` instead of making `change-risk-triage.agent.md` generate a Plan.

Reasoning:

- `change-risk-triage.agent.md` should remain `triage-only` and should not become a mixed Plan-generation agent.
- `runtime-contract-kernel.agent.md` is a high-risk boundary guardrail, not a complete requirements specification.
- implementation agents need the overall Plan as the source of truth, plus kernel artifacts as guardrails.
- a dedicated Plan Kernel keeps the lightweight flow Plan-first without forcing the full `plan-generation.agent.md` / `runtime-evidence.agent.md` / `integration-test-design.agent.md` chain.

## Process profiles

### `plan-kernel`

Creates a bounded implementation Plan for the requested change.

Use when:

- the user wants token-aware Plan-first development
- full runtime evidence and full integration test design would be too expensive at the Plan stage
- the implementation still needs a complete enough source of truth before risk triage
- the downstream kernel agents need a Plan to map contracts, test points, implementation, and verification back to requirements

Output is a bounded Plan. It is not implementation code, not runtime evidence, and not full test design.

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

Runs a bounded Plan-first process for selected runtime contracts or selected integration test IDs.

Use when:

- the task is normal complexity but still has meaningful runtime or production-binding risk
- a selected set of contracts / IDs can be handled in one pass
- the goal is to make bounded progress and leave explicit residual work

### `full-coverage`

Runs the broad process for complex or high-risk work.

Use when:

- multiple runtime scenarios interact
- external dependencies, retries, persistence, or recovery semantics are important
- the feature is broad or ambiguous
- human review needs detailed runtime evidence
- prior implementation attempts already exposed sequence or production-binding gaps

### `fix-slice`

Resolves explicitly selected gaps only.

Use when:

- triage or verification has already identified target IDs
- the user wants to spend tokens on a known bounded repair
- unresolved work should not expand into unrelated implementation changes

## Recommended process flows

### Flow A: Token-aware Plan-first guardrail flow

Use for the main lightweight process this repository now targets.

1. `plan-kernel.agent.md`
2. `change-risk-triage.agent.md`
3. `implementation-contract-kernel.agent.md`, when implementation-realization risk is present
4. `implementation-contract-review-kernel.agent.md` or bounded `implementation-contract-review.agent.md`, when the contract is non-trivial
5. `runtime-contract-kernel.agent.md`
6. `test-design-kernel.agent.md`
7. implementation by normal agent or human-guided implementation agent
8. `verification-kernel.agent.md`
9. `coverage-gap-triage.agent.md`, when unresolved items remain
10. `coverage-gap-resolution-slice.agent.md`, for selected bounded gaps

Implementation handoff for step 5 must include:

- the bounded Plan from `plan-kernel.agent.md`
- `change-risk-triage` output
- `implementation-contract-kernel` output when required
- `implementation-contract-review-kernel` output when present
- `runtime-contract-kernel` output
- `test-design-kernel` output
- selected implementation scope and non-goals
- prohibited substitutions
- unresolved implementation-realization items

The implementation agent must treat the Plan as the source of truth. Kernel artifacts are guardrails for high-risk slices, not substitutes for the Plan.

The token-aware process documentation must also enforce these points:

- Runtime contract artifacts are not substitutes for implementation contract artifacts.
- Plan conformance checks are required but do not remove the need to investigate unknown implementation paths.
- Unresolved implementation-realization items must stay explicit and must not be converted to guessed production addresses.
- Full-flow implementation contract agents remain available and should be recommended when the kernel variant is too narrow.

### Flow B: Minimal high-risk guardrail sub-flow

Use only after a bounded Plan exists and the selected risky area is already clear.

1. `change-risk-triage.agent.md`
2. `implementation-contract-kernel.agent.md`（when implementation-realization risk is present）
3. `runtime-contract-kernel.agent.md`
4. `test-design-kernel.agent.md`
5. implementation by normal agent or human-guided implementation agent using the Plan plus kernel artifacts
6. `verification-kernel.agent.md`
7. optional `coverage-gap-resolution-slice.agent.md`

This sub-flow must not be used as a replacement for Plan creation.

### Flow C: Full coverage flow

Use for broad, ambiguous, or highly interconnected changes.

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

### Plan Kernel

A bounded Plan artifact should use this shape unless the repository already has a stronger convention:

```md
# Plan Kernel

## Goal

## Non-goals

## Functional requirements

## Acceptance conditions

## Affected components / modules

## Expected implementation scope

## Known high-risk boundaries

## Out of scope for this pass

## Handoff to change-risk-triage

## Handoff Packet
```

Rules:

- The Plan Kernel is the implementation source of truth for the token-aware flow.
- It must describe the whole requested change at a useful implementation level, not only high-risk boundaries.
- It must not expand into full runtime evidence or full integration test design.
- It must identify known high-risk boundary candidates, but detailed selection belongs to `change-risk-triage.agent.md`.
- It must include non-goals and out-of-scope items so implementation agents do not infer extra work.
- It must include acceptance conditions that can later be mapped to test points or verification items.

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

### Stub-to-Production Binding

Verification should produce or update this shape when tests use substitutes:

```md
## Stub-to-Production Binding

| Test Point ID | Stub / fake / in-memory used in test | Production interface | Production concrete implementation | Production wiring / entrypoint | Status | Remaining work |
| --- | --- | --- | --- | --- | --- | --- |
```

Rules:

- A passing test using a fake does not imply production readiness.
- `Status` must not be `Bound` unless production interface, production implementation, and wiring / entrypoint are all confirmed.
- If only the interface exists, use `NotImplementedOrMismatch`.
- If implementation exists but default wiring is missing, use `NotImplementedOrMismatch` or `PartiallyDone` with explicit remaining work.

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

Use these statuses consistently unless an existing artifact has a stronger convention:

| Status | Meaning |
| --- | --- |
| `Done` | Completed within this pass |
| `PartiallyDone` | Some useful progress was made, but the item is not complete |
| `Deferred` | Intentionally not handled in this pass |
| `ManualOnly` | Requires manual or real-environment validation |
| `NeedsHumanDecision` | Cannot safely proceed without a product, architecture, policy, or risk decision |
| `NotImplementedOrMismatch` | Implementation is missing, mismatched, or only test-side / fake-side exists |
| `OutOfScopeForThisPass` | Valid work, but outside the selected slice |
| `Bound` | Production interface, production implementation, and production wiring / entrypoint have been confirmed for a test substitute |

## Shared bounded-pass rules

All token-aware agents should follow these rules unless the user explicitly asks for full coverage:

- Perform one bounded pass.
- Do not keep repairing until all issues disappear.
- Prefer explicit residual work over speculative broad fixes.
- Stop when the work would require broad redesign, repeated fix loops, or human judgment.
- Do not expand from selected contracts / IDs into unrelated parts of the system.
- Do not weaken assertions merely to mark an item complete.
- Do not treat test-only implementation as production implementation.
- Do not mark production binding complete without checking wiring or entrypoint.

## Agent requirements

## 1. `plan-kernel.agent.md`

### Purpose

Create a bounded Plan for the requested change. This Plan is the implementation source of truth for the token-aware flow.

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

### Stop condition

Stop after creating or updating the bounded Plan and handoff to `change-risk-triage.agent.md`.

## 2. `change-risk-triage.agent.md`

### Purpose

Classify the bounded Plan, identify high-risk runtime boundaries, and recommend the minimum sufficient process profile.

### Inputs

- Plan Kernel or other bounded Plan artifact
- original issue / prompt only as supplementary context
- repository structure and relevant files only as needed for risk classification

### Required outputs

```md
# Change Risk Triage

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

### Stop condition

Stop after recommending a profile and selected contracts / IDs. If risk cannot be classified from available context, recommend `contract-kernel` or `standard-slice` rather than pretending the task is safe.

When implementation-realization risk is `Present` or `Unclear`, the next-step recommendation must be one of:

- `implementation-contract-kernel.agent.md`
- `implementation-contract-generation.agent.md`
- `full-coverage`

Do not recommend immediate `runtime-contract-kernel.agent.md` in this condition.

## 3. `runtime-contract-kernel.agent.md`

### Purpose

Create or update the minimal runtime contract artifact for selected high-risk slices.

### Inputs

- selected runtime contracts or change-risk triage output
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

Recommend `runtime-evidence.agent.md` or `full-coverage` if the selected contracts cannot be safely represented without detailed sequence evidence.

## 4. `test-design-kernel.agent.md`

### Purpose

Create a compact test design mapped to selected runtime contracts.

### Inputs

- Runtime Contract Kernel
- Plan Kernel or bounded Plan artifact
- relevant existing test conventions

### Required outputs

```md
# Test Design Kernel

## Scope

## Test Design Kernel

## Required production binding checks

## Manual-only checks

## Handoff Packet
```

### Required checks

For each selected runtime contract:

- define at least one observable verification point or an explicit reason why not
- map the verification point back to the Plan requirement / acceptance condition where possible
- identify whether a stub / fake / in-memory substitute is expected
- require production binding verification when a substitute is used
- also require production binding verification when selected contracts involve external SDK/API/provider selection, dependency/package/binary update, DI/startup/config wiring, Plan-named symbols, implementation-contract decisions, or substitution risk
- include negative / error path checks for boundary contracts when relevant

### Must not do

- implement tests
- expand to full integration test design unless requested
- create test points not connected to selected runtime contracts

### Escalation condition

Recommend `integration-test-design.agent.md` when the selected slice requires broader feature, error, load, or continuous-operation coverage.

## 5. `verification-kernel.agent.md`

### Purpose

Verify selected runtime contracts and test points after implementation, focusing on production binding and wiring.

### Inputs

- Plan Kernel or bounded Plan artifact
- Runtime Contract Kernel
- Test Design Kernel or integration test points
- implementation diff or repository state
- relevant production startup / DI / entrypoint files
- relevant test files

### Required outputs

```md
# Verification Kernel Result

## Scope

## Runtime contract verification

## Stub-to-Production Binding

## Test observations

## Unresolved items

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
- whether selected runtime contract fields and error behavior are represented
- whether the result is still consistent with the Plan requirement / acceptance condition
- when implementation-contract exists, whether runtime address and wiring are consistent with implementation-contract decisions
- if nearby implementation is wired but Plan-required path is missing, classify as blocking mismatch/gap rather than pass

### Verdicts

Use one of:

- `PASS_FOR_SELECTED_SCOPE`
- `PASS_WITH_RESIDUAL_WORK`
- `BLOCKED_BY_PRODUCTION_BINDING_GAP`
- `BLOCKED_BY_CONTRACT_MISMATCH`
- `BLOCKED_BY_HUMAN_DECISION`

### Must not do

- fix all gaps automatically
- broaden to unrelated IDs
- mark fake-only success as pass
- perform large implementation changes

### Stop condition

Stop after classifying selected contracts and test points. If repair is needed, recommend `coverage-gap-resolution-slice.agent.md` with target IDs.

## 6. `coverage-gap-triage.agent.md`

### Purpose

Classify unresolved implementation coverage items without fixing them.

### Inputs

- verification-kernel output or implementation coverage document
- Plan Kernel or bounded Plan artifact
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

### Must not do

- implement code
- change tests
- update status to complete without evidence
- create new IDs

## 7. `coverage-gap-resolution-slice.agent.md`

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
- for `ImplementationContractMissing` / `DependencyMissing` / `ApiSurfaceUnknown` / `UnjustifiedSubstitution` / `SourceOfTruthDrift`, first consume or create the selected-slice implementation contract artifact before direct repair
- identify the minimal production implementation / wiring / test update needed
- apply only bounded changes required for that ID
- update the active status artifact when appropriate
- leave unresolved status if the fix would exceed the selected slice

### Must not do

- change unrelated IDs
- add broad abstractions unless required by selected IDs
- replace Plan-required production behavior with local heuristics
- treat interface-only or fake-only code as completion
- continue fix loops until all tests pass at any cost

### Stop condition

Stop after one bounded pass over selected IDs. Remaining issues must be recorded, not chased indefinitely.

## 8. Revisions to existing agents

### `plan-generation.agent.md`

May remain the full-flow Plan generation agent. Do not overload it if doing so would make the lightweight flow ambiguous.

If revised, it should clearly separate full mode from token-aware Plan Kernel behavior.

### `plan-review.agent.md`

Should support review-only and review-and-fix behavior.

Required changes:

- allow a mode that only reports issues without editing
- in bounded mode, limit deterministic fixes to selected scope
- flag missing runtime contract / production binding chains explicitly

### `integration-test-design.agent.md`

Should support selected-contract mode.

Required changes:

- allow generation for selected Runtime Contract IDs only
- keep the full feature / abnormal / load / continuous-operation coverage for full mode
- require production binding checks when stubs are expected

### `integration-test-verification-implementation.agent.md`

Should support selected-ID mode.

Required changes:

- allow verifying only selected Test Point IDs or Runtime Contract IDs
- keep the existing production implementation existence check
- produce Stub-to-Production Binding output when substitutes are used
- stop after classification and bounded test additions

### `coverage-gap-resolution.agent.md`

Should not be the default next step for all unresolved work.

Required changes:

- prefer `coverage-gap-triage.agent.md` before repair
- create or use a slice-oriented variant for selected IDs
- keep full resolution only as an explicit full-coverage choice

## Agent creation order

Recommended order after this correction:

1. Create `plan-kernel.agent.md`
2. Revise `change-risk-triage.agent.md` if needed so its primary input is the bounded Plan
3. Revise README so token-aware flow begins with `plan-kernel.agent.md`
4. Verify the existing kernel agents still reference the Plan as source of truth where necessary
5. Continue with any revisions to existing full-flow agents

For a fresh implementation of the token-aware flow, the intended order is:

1. `plan-kernel.agent.md`
2. `change-risk-triage.agent.md`
3. `implementation-contract-kernel.agent.md`（when implementation-realization risk is present）
4. `implementation-contract-review-kernel.agent.md` or bounded `implementation-contract-review.agent.md`（when non-trivial）
5. `runtime-contract-kernel.agent.md`
6. `test-design-kernel.agent.md`
7. implementation
8. `verification-kernel.agent.md`
9. `coverage-gap-triage.agent.md`
10. `coverage-gap-resolution-slice.agent.md`

## Acceptance criteria for the corrected process

The corrected process is acceptable when:

- a bounded Plan is created before risk triage
- implementation agents receive the Plan plus kernel guardrail artifacts
- a lightweight run can handle a selected cross-boundary slice without skipping runtime contracts
- a stub-based test cannot be marked complete without production binding verification
- every selected contract / test point / gap ends with explicit status
- unresolved work is useful enough to drive a later fix slice
- the full process remains available for broad high-risk work
- agent prompts clearly state when to stop rather than continue repairing

## Suggested README update after `plan-kernel.agent.md` exists

After `plan-kernel.agent.md` is created, update `README.md` to describe the corrected token-aware flow:

- token-aware flow starts with bounded Plan creation
- `change-risk-triage.agent.md` consumes the Plan and selects high-risk runtime slices
- implementation-realization risk uses conditional `implementation-contract-kernel` / review before runtime-contract
- implementation receives Plan + triage + implementation-contract artifacts (when required) + runtime-contract-kernel + test-design-kernel
- full Plan-first flow remains available for broad autonomous work

The README should make clear that the lightweight flow narrows the selected scope, but does not remove Plan creation or the guardrail chain for selected high-risk contracts.
