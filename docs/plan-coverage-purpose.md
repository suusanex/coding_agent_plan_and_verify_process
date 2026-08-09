# Plan Coverage Check and Residual Decision Flow: Purpose and Policy

## Background

This repository defines a Plan-first development process for GitHub Copilot agents.

The original process intentionally combines Plan generation, runtime evidence, integration test design, implementation verification, and coverage gap resolution. That chain exists to prevent recurring failure modes in AI-assisted implementation:

1. Cross-process or cross-component sequences appear correct inside each process, but fail when connected because contracts, messages, state transitions, or wiring do not match.
2. Automated tests pass against stubs, fakes, or in-memory implementations, while the corresponding production implementation or production wiring is missing.
3. Guardrail Focus verification passes while parent Plan coverage or residual decisions are still incomplete.
4. The Plan itself fails to elaborate source requirements into required black-box behavior cases, so downstream artifacts stay internally consistent while the final implementation misses the original expected behavior.

As GitHub Copilot usage moves toward token-consumption-based cost awareness, the process must reduce avoidable re-reading, rework, and open-ended repair loops. However, the guardrails above are not optional decoration. Removing them would make the process cheaper but would also reintroduce the original quality failures.

## Primary objective

Optimize the Plan-first process for bounded progress, explicit residual work, and reusable handoff artifacts without removing the guardrail chain that protects runtime contracts and production implementation coverage.

The current Plan網羅チェック・残件判定フロー is a Plan-first process.

The current standard sequence is:

1. Read source requirements and decide whether black-box behavior expansion is required.
2. Create or consume black-box behavior cases when source requirements need case expansion.
3. Create a bounded Plan and map relevant Case IDs to FR / AC or explicit disposition.
4. Use a ready Plan to identify Guardrail Focus coverage for deep runtime / production-binding checks.
5. Preserve the guardrail chain for the Guardrail Focus surface.
6. Implement against the Plan as the source of truth.
7. Verify that Guardrail Focus contracts, test points, production implementation, production wiring, and current Behavior Case evidence are aligned.
8. Record unresolved work instead of continuing indefinitely.

When a ready parent Plan selects `full-coverage`, Plan Coverage owns the complete bounded-slice lifecycle:

```text
Architecture Slice Readiness / Elaboration
  -> Plan Slice Decomposition
  -> each executable slice uses one canonical Slice Living Record
  -> existing semantic agents return owned section deltas
  -> independent per-slice verification
  -> one Full-Coverage Close Record
     -> Cross-Slice Verification
     -> conditional target-slice triage / repair / re-verification / cross-slice rerun
     -> Residual Decision
```

`full-coverage` is selected only after Change Risk Triage builds the minimum bounded runtime sequence and records a source-backed `Why standard-slice is insufficient` escalation gate. Risk trigger count, changed file/project count, security importance, same-process ABI/FFI, local async work, shared durable storage, or production wiring do not independently justify decomposition. Guardrail depth remains available in `standard-slice` when the sequence is bounded.

Before each slice enters implementation, the Plan Coverage parent reconfirms the current architecture baseline and `implementation-handoff-review` records `Match / Drift / Unclear`. Only a current-baseline `Match` may proceed. `Drift` returns to Architecture Slice Readiness / Elaboration, and `Unclear` fails closed and reruns readiness. This also applies when the readiness verdict is `ArchitectureNotRequired` and the readiness artifact is the Lightweight architecture baseline.

Before decomposition, Architecture Slice Readiness also rechecks whether decomposition is necessary. `StandardSliceSufficient` returns the parent Plan to `selected_process: standard-slice` without creating Slice Architecture, decomposition, Living Records, or cross-slice verification artifacts. `ArchitectureNotRequired` remains distinct: decomposition is still required, but existing source-backed shared semantics make a separate architecture artifact unnecessary.

When implementation-realization risk is present (for example: Plan-named external SDK/API/provider, unresolved dependency/API surface confirmation, or nearest-neighbor substitution risk), the Plan網羅チェック・残件判定フロー must add a conditional implementation-contract branch before runtime-contract work.

The key policy is:

> Reduce breadth, not depth.

Lightweight execution narrows Guardrail Focus coverage for deep checks. It does not shrink the parent Plan implementation scope or final completion criteria. It must not remove the Plan, and it must not remove the minimum chain needed to connect runtime contracts, test design, stub usage, production implementation, and production wiring.

## Current scope of the Plan網羅チェック・残件判定フロー

The Plan網羅チェック・残件判定フロー is not intended to start directly from risk triage.

Risk triage is meaningful only after there is a Plan or equivalent bounded Plan artifact that describes:

- what behavior should be implemented
- what is out of scope
- which components or modules are expected to change
- what acceptance conditions matter
- where high-risk runtime boundaries may exist

Therefore, `plan-kernel.agent.md` creates or refreshes the bounded Plan before `change-risk-triage.agent.md`.

`plan-kernel.agent.md` owns bounded Plan creation instead of overloading `change-risk-triage.agent.md`. It does not create detailed runtime evidence or full integration test design by itself. It hands high-risk boundary candidates to `change-risk-triage.agent.md` and the downstream kernel agents.

## Non-goals

This improvement is not intended to:

- skip Plan creation
- make risk triage replace Plan generation
- implement directly from `runtime-contract-kernel` artifacts alone
- make every agent run shorter by simply deleting important checks
- replace runtime evidence with a shallow checklist
- treat stub-based tests as sufficient proof of production readiness
- treat requirement-elaboration gaps as `full-coverage` candidates
- make unbounded autonomous completion the default goal
- force every task through the heaviest possible full process
- turn Plan documents into detailed implementation task lists
- make agents keep fixing until all issues are resolved regardless of cost

## Guardrail chain that must be preserved

For any Guardrail Focus coverage, the process must preserve the following chain:

1. Source requirement
2. Black-box behavior case, when expansion is required
3. Plan requirement / acceptance condition
4. Runtime contract identification
5. Runtime participant and boundary mapping
6. Test point mapping
7. Stub / fake / in-memory usage identification
8. Production implementation binding
9. Production wiring / entrypoint verification
10. Explicit unresolved status for anything not completed

The full process may express this through detailed runtime evidence, scenario ledgers, integration test design, implementation coverage documents, and gap resolution.

The lightweight process may express the same chain through smaller kernel artifacts, but it must not skip the Plan or the chain.

## Failure modes this policy protects against

### 1. Sequence contract mismatch

AI-assisted implementation often succeeds locally inside individual modules or processes while failing across the full sequence.

Typical examples:

- UI calls an API shape that the backend does not actually expose
- producer and consumer disagree on message schema
- queue payload contains fields not read by the worker
- retry or timeout behavior is described in one component but not implemented in the other
- state transitions are handled in tests but not connected to the runtime entrypoint
- logging or correlation is asserted in one process but not propagated across the boundary

Runtime contracts and scenario mapping exist to make these mismatches reviewable before the real smoke test.

### 2. Stub-complete but production-missing implementation

Stub-based automated tests are useful as an early guardrail, but they create a specific risk: the fake implementation becomes complete while the production implementation remains absent or unwired.

Typical examples:

- tests use `FakeGitHubClient`, but no production `GitHubClient` exists
- tests use `InMemoryJobStore`, while the planned durable store is not implemented
- tests register a mock service, but default DI still points to a stub
- tests verify behavior through a helper that is not reachable from the production entrypoint
- an interface is implemented only in test code

The process must therefore verify not only whether a test exists, but whether the tested responsibility has a production implementation and production wiring path.

The process must also prevent silent implementation-path drift: runtime-contract, test-design, and verification artifacts must not substitute a nearby existing implementation when the Plan-required implementation path remains unconfirmed.

### 3. High-risk kernel without complete implementation context

A runtime contract kernel artifact intentionally focuses on high-risk boundaries. It is not a complete requirements specification.

If implementation is started from `runtime-contract-kernel` alone, the implementation agent may overfit to the high-risk contract while missing the overall requested behavior.

The implementation handoff must therefore include:

- the bounded Plan created by `plan-kernel.agent.md`
- the risk triage output
- implementation-contract artifacts when implementation-realization risk is present
- the runtime contract kernel
- the test design kernel
- explicit scope and non-goals

### 4. Requirement-elaboration gap

Plan readiness can fail before runtime risk exists.

A bounded Plan is not ready when source requirements contain case-specific expected outcomes, negative expectations, recovery / rollback / retry / replay / cleanup behavior, state transitions, idempotency, or history-dependent results that are not expanded into black-box behavior cases or mapped to FR / AC.

This gap must not be handled by choosing `full-coverage`.

`full-coverage` is a decomposition decision for a ready Plan. Requirement elaboration is a Plan readiness decision. When expansion is required but missing, the next step is `black-box-behavior-spec-kernel.agent.md`; when behavior cases exist but the Plan does not map them, the next step is `plan-kernel.agent.md`; when expected behavior itself is undecided, the flow stops for human decision.

## Core operating principles

### 1. Plan-first before risk-first

The Plan網羅チェック・残件判定フロー must begin by creating a bounded Plan. `change-risk-triage.agent.md` should classify risk within that Plan, not replace the Plan.

The Plan is the source of truth for implementation behavior. Kernel artifacts are guardrails for Guardrail Focus coverage, not substitutes for the Plan.

Before `change-risk-triage.agent.md` classifies runtime or implementation risk, the Plan must record `Expansion required`, behavior spec artifact path when required, Case-to-Plan mapping, and `Plan readiness`. Only `ReadyForRiskTriage` may proceed to process profile selection.

### 2. Bounded pass over open-ended completion

Agents should perform a bounded pass and then report the remaining work.

They must not assume that their job is to keep repairing until all issues disappear. When completion would require broad redesign, repeated fix loops, missing human judgment, or work outside the bounded parent Plan pass, the agent must stop and classify the residual work.

### 3. Guardrail Focus depth over whole-system thin coverage

Lightweight mode may narrow Guardrail Focus coverage to a smaller number of high-risk runtime contracts and handle them deeply enough to preserve the guardrail chain.

It is better to verify three important cross-process contracts properly than to skim twenty requirements without confirming production binding.

### 4. Explicit status over ambiguous partial completion

Every Guardrail Focus contract, test point, or coverage item must end in an explicit status such as:

- `Done`
- `PartiallyDone`
- `Deferred`
- `ManualOnly`
- `NeedsHumanDecision`
- `NotImplementedOrMismatch`
- `OutOfScopeForThisPass`

A missing result is not an acceptable result.

### 5. Handoff artifacts over repeated rediscovery

Each phase should leave a compact handoff artifact that tells the next phase:

- what was inspected
- what was decided
- what was intentionally not inspected
- what must not be redone unless new evidence appears
- what remains unresolved

This reduces repeated repository exploration and repeated reasoning over the same issue.

### 6. Risk-triggered escalation

The process should escalate from a kernel slice to a fuller process when the task involves high-risk boundaries such as:

- multiple processes or services
- queues, events, webhooks, or background workers
- external APIs or SDKs
- authentication or authorization
- durable state, retry, replay, or idempotency
- production DI, configuration, or startup wiring
- observable behavior spanning multiple components

Escalation should be explicit rather than accidental.

## Process profile policy

The process should not be described as merely `lite`, `standard`, and `full` if those names imply removing core checks.

Preferred profile names are based on scope and intent:

| Profile | Purpose | Guardrail depth | Breadth |
| --- | --- | --- | --- |
| `black-box-behavior-spec-kernel` | Expand source requirements into stable behavior Case IDs before Plan readiness | Source-to-case traceability preserved | Narrow to source requirements |
| `plan-kernel` | Create the bounded Plan that remains the implementation source of truth | Plan preserved | Narrow to moderate |
| `contract-kernel` | Minimal high-risk guardrail for Guardrail Focus runtime coverage | Preserved | Narrow |
| `standard-slice` | Normal bounded Plan-first process for Guardrail Focus contracts / IDs | Preserved | Moderate |
| `full-coverage` | Decompose a ready parent Plan only after the standard-slice insufficiency gate is satisfied; update one canonical Living Record per executable slice, then verify and decide residuals across slices | Preserved and expanded | Broad |
| `triage-only` | Classify risk and recommend next slice without implementation | Classification only | Variable |
| `fix-slice` | Resolve explicit FixNow gaps only | Preserved for explicit FixNow gaps | Narrow |

## Lightweight mode requirements

A lightweight process is acceptable only when it still produces enough information to answer these questions for the overall change and for each Guardrail Focus surface.

For the overall change:

1. What behavior is being implemented?
2. What is out of scope?
3. Which components or modules are expected to change?
4. What acceptance conditions define successful implementation?
5. Is black-box behavior expansion required?
6. If required, which Case IDs map to FR / AC, explicit defer, out-of-scope, or human decision?
7. Which areas are suspected high-risk boundaries?

For each Guardrail Focus surface:

1. Which runtime participants are involved?
2. What contract, message, API, event, or state transition connects them?
3. Which test point observes that contract or behavior?
4. Does the test use a stub, fake, mock, or in-memory implementation?
5. Where is the corresponding production implementation?
6. How is that production implementation wired into the real runtime path?
7. What remains unresolved if any of the above cannot be confirmed?

If the process cannot answer these questions, it is too light for high-risk work.

## Full mode requirements

Full mode remains appropriate when:

- the feature is broad or ambiguous
- multiple runtime sequences interact
- data consistency, retry, rollback, or recovery behavior matters
- several external interfaces are involved
- the implementation has already shown symptoms of contract mismatch
- human review needs detailed scenario evidence

Full mode may continue to use detailed runtime evidence, scenario ledgers, integration test design, implementation coverage documents, and gap resolution.

Full mode is not a substitute for missing Plan readiness. If the ambiguity is that source behavior has not been expanded or mapped to the Plan, the flow must return to behavior expansion or human decision before any full-coverage decomposition.

Inside Plan Coverage, `full-coverage` is self-contained: Architecture Slice Readiness / Elaboration precedes decomposition; every executable slice becomes one canonical Slice Living Record; existing semantic agents return owned section deltas; each slice is independently verified; then Cross-Slice Verification and Residual Decision update one Full-Coverage Close Record in that order. A `CROSS_SLICE_PARTIAL_WITH_FIX_CANDIDATES` result conditionally returns to the affected Living Record for triage, bounded repair, slice re-verification, and a cross-slice rerun before Residual Decision. The Plan Coverage parent and `implementation-handoff-review` enforce the current-baseline `Match` requirement immediately before slice implementation.

`documentation_level: standard` still selects the semantic rigor; `artifact_mode: slice-living-record` separately selects the durable full-coverage layout. The parent/router is the only Living Record and canonical ledger writer. A two-slice base run uses at most eight durable artifacts before explicitly conditioned artifacts. A tracked Implementation Completion Handoff requires a pre-applied exact-path Artifact Exception. A High-model Re-entry Handoff uses delayed registration: STANDARD returns an unpersisted payload, then the parent applies the exact-path exception and persists it before HIGH resumes. Review-only fallback and gap repair otherwise remain subsection/section deltas; when repair needs missing implementation decisions, it requests the implementation-contract semantic owner instead of creating that section or a separate artifact. Pre-redesign separate-artifact runs may resume without forced migration.

## Agent design implications

New or revised agents should be designed around bounded responsibilities.

Each agent should state:

- its target profile
- its required inputs
- its required outputs
- what it must verify
- what it must not do
- how it records remaining work
- when it must stop rather than continue fixing

Agents should avoid vague goals such as "make the implementation complete". Prefer goals such as "create a bounded Plan", "classify all Guardrail Focus IDs", "verify production binding for Guardrail Focus test points", or "resolve only explicit FixNow gap IDs".

## Recommended repository convention

Documents that define this policy and its process should be treated as required authoring-time context for future agent creation and agent revision work.

New agent files should be created or revised only after the authoring process reads:

- this purpose and policy document
- the corresponding process and agent requirements document
- the current agent file being modified, when applicable

These documents are not intended to be runtime dependencies of the generated agents. A generated agent may be copied into another repository without this `docs/` directory. Therefore, any purpose, policy, profile, handoff, or cross-agent relationship that the agent needs during execution must be embedded in the agent file itself or in a common instruction file that is distributed together with the agent.

## Current contract criteria

The current contract remains satisfied when:

- the Plan網羅チェック・残件判定フロー still begins with a bounded Plan
- Plan readiness blocks risk triage until expansion decision and required Case-to-Plan mapping are present
- Requirement-elaboration gaps route to `black-box-behavior-spec-kernel.agent.md`, `plan-kernel.agent.md`, or human decision, not to `full-coverage`
- lightweight runs remain meaningfully cheaper than full runs
- Guardrail Focus contracts still receive runtime and verification guardrails
- implementation agents receive both the Plan and kernel guardrail artifacts
- stub-only success is explicitly detected and recorded
- agents stop with useful residual work instead of looping toward perfect completion
- full mode remains available for genuinely complex work
- downstream agents can consume prior artifacts without rediscovering the same context
- full-coverage keeps Architecture Slice Readiness, Slice Living Records, per-slice verification, Cross-Slice Verification, and Residual Decision in one Plan Coverage-owned lifecycle
- only a current-baseline architecture `Match` authorizes slice implementation
- the parent/router is the only Living Record and canonical Coverage Ledger writer, while semantic owners return section deltas
- the base artifact budget is five parent artifacts plus one Living Record per executable slice plus one close record
