# Token-aware Flow Hardening Requirements

## Purpose

This document defines requirements for hardening the token-aware Plan-first guardrail flow.

It is intended to be committed to the repository and reused as stable input for GitHub Copilot prompts while revising agents, README, and process documentation.

The goal is not to describe one incident only. The goal is to prevent a class of failures where a Plan appears sufficiently constrained at the requirement level, but downstream agents either:

- substitute a nearby existing implementation for the Plan-required implementation path, or
- continue without investigating whether the Plan-required API, dependency, package, release, namespace, type, method, or runtime integration actually exists.

## Background

The repository already has two related process directions:

1. A full autonomous Plan-first flow, which includes implementation contract generation and review.
2. A Plan網羅チェック・残件判定フロー, which narrows the inspected slice while preserving important guardrails.

The Plan網羅チェック・残件判定フロー currently emphasizes:

- creating a bounded Plan,
- triaging risky runtime boundaries,
- creating runtime contract kernels,
- creating test design kernels,
- implementing against the Plan,
- verifying selected contracts and production binding.

That is necessary, but not sufficient.

A bounded Plan can name the correct implementation direction while still leaving unresolved implementation-realization questions. For example, it may name a specific SDK, package version, namespace, provider, extension method, binary artifact, or DI integration point, but not fully prove that the dependency is present in the workspace or that the exact API surface has been inspected.

If the downstream flow skips that investigation, a coding agent may look at the existing codebase, find a similar implementation path, and extend that path instead of materializing the Plan-required implementation.

This creates a dangerous failure mode: the guardrail artifacts can become internally consistent around the wrong implementation path.

## Problem Statement

The current Plan網羅チェック・残件判定フロー needs to distinguish three concerns that are related but not interchangeable:

1. **Plan conformance**
   - Does the downstream artifact still preserve the Plan-required behavior, dependency, provider, and implementation path?

2. **Implementation realization**
   - Has the Plan-required implementation path been concretely investigated and translated into code-level decisions?
   - Are the required binaries, package references, namespaces, types, methods, configuration keys, factories, adapters, and DI registrations known?

3. **Runtime contract verification**
   - Once the implementation path is selected, are the runtime participants, boundaries, fields, error behavior, tests, production implementation, and production wiring connected?

The Plan網羅チェック・残件判定フロー must not treat runtime contract work as a replacement for implementation contract work.

## Required Outcome

After these requirements are implemented, the flow must prevent or explicitly surface these failure modes:

- A Plan names a specific SDK/API/provider, but a downstream agent silently substitutes a similar existing implementation.
- A Plan names a package, namespace, type, method, release, or binary artifact, but no agent verifies whether it exists before implementation.
- A runtime contract uses a nearby existing class as the production implementation address even though the Plan-required implementation path is missing or unconfirmed.
- A test design verifies an adapter/factory shape but does not require production binding to the Plan-required implementation path.
- A verification pass marks a Guardrail Focus coverage as bound because the substituted implementation is wired, even though the Plan-required implementation was not materialized.
- A gap is detected but the recommended repair path lacks the implementation-realization investigation needed to fix it safely.

## Non-goals

These requirements do not require every token-aware run to become a full autonomous flow.

They do not require exhaustive repository exploration for every task.

They do not require the Plan網羅チェック・残件判定フロー to inspect unrelated features, unrelated runtime scenarios, or all possible implementation alternatives.

They do not require replacing the existing full-flow `implementation-contract-generation.agent.md` and `implementation-contract-review.agent.md`.

The intended change is to add a lightweight implementation-realization branch and make downstream artifacts respect its findings.

## Core Principles

### 1. Narrow scope does not permit nearest-neighbor substitution

The Plan網羅チェック・残件判定フロー reduces cost by narrowing breadth, not by replacing a Plan-required implementation with a nearby existing implementation.

If the Plan requires implementation path `X` and the repository only shows similar path `Y`, downstream agents must not treat `Y` as the production implementation address for `X`.

They must record one of:

- `MissingButRequired`,
- `ApiSurfaceUnknown`,
- `DependencyMissing`,
- `NotImplementedOrMismatch`,
- `NeedsHumanDecision`, or
- an explicitly justified decision that the Plan allows replacing `X` with `Y`.

### 2. Plan conformance is necessary but not sufficient

Downstream agents must preserve the Plan as source of truth, but simply checking conformance is not enough.

When the Plan contains unresolved implementation-realization questions, the flow must create or require an implementation contract artifact before treating runtime contracts and test points as stable.

### 3. Implementation contract work is distinct from runtime contract work

Implementation contract work decides and documents:

- which concrete dependency/API/provider path will be used,
- which existing code may be reused,
- which similar existing code must not be used as a substitute,
- which files, references, binaries, configuration keys, factories, adapters, and DI registrations must change,
- how the chosen implementation path will be verified.

Runtime contract work then uses that selected implementation path to describe runtime participants and observable behavior.

### 4. Unknown must remain visible

A token-aware bounded pass must prefer explicit unresolved status over speculative completion.

If a required API surface, package, binary, namespace, method, or wiring point cannot be confirmed within the Guardrail Focus coverage, the artifact must record that as a blocker or residual item. It must not invent a production address or silently redirect to a similar existing path.

### 5. Full-flow concepts should be reused, not duplicated unnecessarily

The existing full-flow implementation contract agents express the correct concept. The Plan網羅チェック・残件判定フロー should either:

- invoke the existing full implementation contract agents when the risk is broad enough, or
- introduce lightweight kernel variants for bounded runs.

The lightweight variant should preserve the same intent: turn a Plan into concrete, reviewable implementation decisions before coding.

## Required Process Changes

### 1. Add implementation-realization risk detection to change-risk-triage

`change-risk-triage.agent.md` must classify not only runtime risk, but also implementation-realization risk.

It must detect at least these triggers:

| Trigger | Description |
| --- | --- |
| Plan names a specific external SDK or API | The Plan requires a concrete SDK/API rather than generic logic. |
| Plan names a package, release, binary artifact, or local lib folder | The dependency may need to be fetched, updated, referenced, or inspected. |
| Plan names a namespace, type, method, extension method, provider ID, or config section | The API surface must be confirmed before implementation. |
| Existing code contains a similar but different implementation path | There is a risk of nearest-neighbor substitution. |
| Implementation requires DI/startup/configuration wiring | The correct production path depends on registration and entrypoint wiring. |
| The affected production address is not known from current evidence | Runtime contract work would otherwise guess the implementation address. |
| Plan contains remaining work about API surface inspection or dependency confirmation | The handoff already says implementation realization is unresolved. |

When any of these are present or unclear, triage must recommend one of:

- `implementation-contract-kernel`,
- existing full `implementation-contract-generation.agent.md`, or
- `full-coverage` if the implementation-realization problem is broad and coupled with complex runtime behavior.

The triage output must include an `Implementation realization risk` section.

Suggested shape:

```md
## Implementation realization risk

| Trigger | Status | Evidence | Required next step |
| --- | --- | --- | --- |
```

### 2. Add a lightweight implementation-contract-kernel agent

Create `implementation-contract-kernel.agent.md` or an equivalent bounded profile.

Purpose:

- Convert the bounded Plan into concrete implementation decisions for the Guardrail Focus coverage.
- Confirm or explicitly mark missing the Plan-named dependency/API/provider/implementation path.
- Prevent downstream agents from substituting a nearby existing implementation.

Required inputs:

- bounded Plan or Plan Kernel,
- change-risk-triage output,
- original user requirement only as supplementary context,
- relevant project files needed to confirm dependency/API surface and implementation path.

Required outputs:

```md
# Implementation Contract Kernel

## Scope

## Plan-named implementation requirements

## Dependency and API surface findings

## Selected implementation approach

## Required code changes

## Prohibited substitutions

## Verification hooks

## Unresolved implementation-realization items

## Handoff Packet
```

Required tables:

```md
| Requirement | Expected by Plan | Evidence found | Status |
| --- | --- | --- | --- |
```

```md
| Dependency / API / symbol | Expected source | Found location | Status | Notes |
| --- | --- | --- | --- | --- |
```

```md
| Similar existing path | Why it is not sufficient | Allowed reuse, if any |
| --- | --- | --- |
```

Allowed statuses should include:

- `Confirmed`,
- `MissingButRequired`,
- `ApiSurfaceUnknown`,
- `DependencyMissing`,
- `NeedsHumanDecision`,
- `RejectedSubstitute`,
- `AllowedReuse`,
- `OutOfScopeForThisPass`.

Stop condition:

- Stop after documenting implementation decisions and unresolved items.
- Do not implement production code.
- Do not create tests.
- Do not continue into broad redesign.

### 3. Add or adapt implementation-contract-review for kernel usage

The Plan網羅チェック・残件判定フロー must include a review step when implementation-realization risk is present and the implementation contract is non-trivial.

This can be either:

- a new `implementation-contract-review-kernel.agent.md`, or
- a bounded mode in the existing `implementation-contract-review.agent.md`.

Purpose:

- Review the implementation contract before runtime-contract-kernel or coding.
- Detect unjustified substitutions, missing API evidence, unsupported dependency assumptions, and vague code-change plans.

Required verdicts:

- `READY_FOR_RUNTIME_CONTRACT`,
- `READY_FOR_IMPLEMENTATION`,
- `BLOCKED_BY_DEPENDENCY_MISSING`,
- `BLOCKED_BY_API_SURFACE_UNKNOWN`,
- `BLOCKED_BY_UNJUSTIFIED_SUBSTITUTION`,
- `BLOCKED_BY_SOURCE_OF_TRUTH_DRIFT`,
- `NEEDS_HUMAN_DECISION`.

The review must not mark the contract ready if:

- the Plan-required implementation path is unconfirmed,
- a nearby existing implementation is used as a substitute without explicit Plan-compatible justification,
- required dependency/package/API evidence is missing,
- required production wiring is only assumed.

### 4. Update runtime-contract-kernel to consume implementation contracts

`runtime-contract-kernel.agent.md` must treat implementation contract artifacts as authoritative for selected implementation paths when present.

Required behavior:

- If an implementation contract exists, runtime contract participants and production implementation addresses must align with it.
- If the implementation contract says a Plan-required implementation is missing or unknown, runtime-contract-kernel must not replace it with a similar existing implementation.
- If runtime-contract-kernel discovers a mismatch between Plan, implementation contract, and code evidence, it must record `NotImplementedOrMismatch` or equivalent unresolved status.

The runtime contract artifact should include a conformance section:

```md
## Plan / implementation contract conformance

| Runtime Contract ID | Plan requirement | Implementation contract decision | Runtime contract address | Conformance |
| --- | --- | --- | --- | --- |
```

### 5. Update test-design-kernel production binding rules

`test-design-kernel.agent.md` currently requires production binding primarily when substitutes such as stubs/fakes/in-memory implementations are used.

This must be expanded.

Production binding must also be required when the selected contract involves any of:

- external SDK/API/provider selection,
- dependency/package/binary update,
- DI/startup/configuration wiring,
- Plan-named namespace/type/method/provider ID,
- implementation contract decisions,
- a similar existing implementation that could be mistaken for the required one.

A test point must not be considered sufficient merely because it verifies a local adapter shape. It must also require verification that the adapter/factory/configuration path reaches the Plan-required production implementation.

### 6. Update verification-kernel to verify Plan-required implementation binding

`verification-kernel.agent.md` must verify not only that some production implementation is wired, but that the Plan-required and implementation-contract-selected production path is wired.

Required behavior:

- Compare Plan requirement, implementation contract decision, runtime contract address, test point, implementation diff, and production wiring.
- Mark a Guardrail Focus coverage as `Bound` only when the production interface, concrete implementation, wiring, and post-wiring behavior match the Plan-required implementation path or an explicitly approved substitute.
- If a nearby implementation is wired but the Plan-required one is missing, use `NotImplementedOrMismatch` or a more specific blocking verdict.

### 7. Update coverage-gap triage and resolution to handle implementation-realization gaps

`coverage-gap-triage.agent.md` must classify gaps caused by missing implementation-realization work.

Add or support gap types such as:

- `ImplementationContractMissing`,
- `DependencyMissing`,
- `ApiSurfaceUnknown`,
- `UnjustifiedSubstitution`,
- `SourceOfTruthDrift`,
- `ProductionImplementationMissing`,
- `ProductionWiringMissing`,
- `ContractMismatch`.

When a gap requires API/dependency/provider investigation, the recommended next step must be `implementation-contract-kernel` or full `implementation-contract-generation.agent.md`, not direct implementation repair.

`coverage-gap-resolution-slice.agent.md` must not repair such a gap by guessing. It must first consume or create the necessary implementation contract artifact within the selected slice.

### 8. Update implementation handoff / preflight behavior

Before coding, the handoff to the implementation agent must include:

- bounded Plan,
- change-risk-triage output,
- implementation contract kernel output when required,
- implementation contract review output when present,
- runtime contract kernel output,
- test design kernel output,
- parent Plan implementation surface,
- non-goals,
- prohibited substitutions,
- unresolved implementation-realization items.

If implementation-realization risk was detected but no implementation contract exists, the handoff must block or explicitly recommend generating one before coding.

A separate `implementation-readiness-preflight.agent.md` may be added if useful, but it must not replace implementation contract generation. Its role should be readiness checking, not implementation-realization design.

## Required README / Process Documentation Changes

The token-aware process documentation must describe the conditional implementation-contract branch.

Recommended flow:

```text
1. plan-kernel
2. change-risk-triage
3. implementation-contract-kernel, when implementation-realization risk is present
4. implementation-contract-review-kernel or bounded implementation-contract-review, when the contract is non-trivial
5. runtime-contract-kernel
6. test-design-kernel
7. implementation
8. verification-kernel
9. coverage-gap-triage, when unresolved items remain
10. coverage-gap-resolution-slice, for selected bounded gaps
```

The documentation must clearly state:

- Runtime contract artifacts are not substitutes for implementation contract artifacts.
- Plan conformance checks are required but do not remove the need to investigate unknown implementation paths.
- A token-aware run must preserve unresolved implementation-realization items instead of converting them into guessed implementation addresses.
- Full-flow implementation contract agents remain available and should be recommended when the kernel variant would be too narrow.

## Expected Incident-Class Handling

For a task where the Plan requires a specific provider or SDK that may not yet exist in the workspace, the desired behavior is:

```text
Plan:
  Requires provider/package/API X.

change-risk-triage:
  Detects external API / SDK risk.
  Detects implementation-realization risk.
  Detects similar existing implementation Y.
  Recommends implementation-contract-kernel before runtime-contract-kernel.

implementation-contract-kernel:
  Confirms whether X exists.
  Records exact API surface, package/reference changes, factory/adapter/config/wiring changes.
  Records Y as prohibited substitute unless explicitly allowed.
  If X is missing, emits DependencyMissing or ApiSurfaceUnknown and blocks direct implementation.

runtime-contract-kernel:
  Uses X as the production implementation path if confirmed.
  If X is missing, records NotImplementedOrMismatch instead of using Y.

test-design-kernel:
  Requires production binding to X, not merely tests for Y-shaped adapter behavior.

implementation:
  Materializes X first, then implements adapters/wiring/tests.

verification-kernel:
  Confirms that production wiring reaches X.
  Does not pass merely because Y is wired.
```

## Acceptance Criteria

The hardening work is complete when all of the following are true:

- The Plan網羅チェック・残件判定フロー has a documented conditional path for implementation-realization risk.
- `change-risk-triage` can recommend implementation contract work before runtime contract work.
- A lightweight implementation contract artifact exists or the existing implementation contract agents support bounded token-aware usage.
- Runtime contract kernel consumes implementation contract decisions when present.
- Test design kernel requires production binding for Plan-named external provider/API/dependency paths even without test substitutes.
- Verification kernel checks binding to the Plan-required or explicitly approved implementation path, not merely any wired implementation.
- Coverage gap triage can classify missing implementation contracts, missing dependencies, unknown API surfaces, and unjustified substitutions.
- Coverage gap resolution does not guess implementation realization details when they are missing.
- README and process docs explain when to use kernel implementation contract work versus full implementation contract work.
- Downstream agents preserve `Remaining work` items about API surface inspection, dependency confirmation, and production implementation address confirmation as consumed, blocking, or explicitly deferred with reason.
- A Plan-required implementation path cannot silently drift into a nearby existing implementation path across triage, runtime contract, test design, implementation, and verification.

## Suggested Copilot Usage

When asking GitHub Copilot to revise the repository, provide this document as stable requirements input.

The prompt should instruct Copilot to:

- update the relevant agent files and process documentation to satisfy this document,
- preserve the existing Plan-first and token-aware design intent,
- avoid turning the lightweight flow into mandatory full coverage,
- add lightweight implementation-contract behavior only where implementation-realization risk requires it,
- keep unresolved unknowns explicit rather than guessing production addresses,
- avoid introducing unrelated process concepts beyond what is needed to satisfy these requirements.

## Terminology

### Plan-required implementation path

The dependency, provider, namespace, type, method, factory, adapter, configuration section, binary artifact, package version, or production wiring path named or implied by the Plan as necessary to satisfy the requested change.

### Implementation realization

The work of translating the Plan-required implementation path into concrete code-level decisions before implementation, including dependency/API inspection, reuse decisions, prohibited substitutions, and required file changes.

### Nearest-neighbor substitution

A failure mode where an agent finds an existing implementation that resembles the Plan-required path and uses it as a substitute without explicit Plan-compatible justification.

### Implementation contract kernel

A lightweight, bounded artifact that documents the selected implementation approach, required code changes, dependency/API findings, prohibited substitutions, and verification hooks for the Guardrail Focus coverage.

### Runtime contract kernel

A lightweight artifact that documents runtime participants, boundary mechanisms, fields, error behavior, production implementation address, and verification hooks for selected high-risk runtime contracts.
