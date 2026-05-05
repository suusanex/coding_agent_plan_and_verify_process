# Token-aware Guardrail Kernel: Purpose and Policy

## Background

This repository defines a Plan-first development process for GitHub Copilot agents.

The original process intentionally combines Plan generation, runtime evidence, integration test design, implementation verification, and coverage gap resolution. That chain exists to prevent two recurring failure modes in AI-assisted implementation:

1. Cross-process or cross-component sequences appear correct inside each process, but fail when connected because contracts, messages, state transitions, or wiring do not match.
2. Automated tests pass against stubs, fakes, or in-memory implementations, while the corresponding production implementation or production wiring is missing.

As GitHub Copilot usage moves toward token-consumption-based cost awareness, the process must reduce avoidable re-reading, rework, and open-ended repair loops. However, the guardrails above are not optional decoration. Removing them would make the process cheaper but would also reintroduce the original quality failures.

## Primary objective

Optimize the Plan-first process for bounded progress, explicit residual work, and reusable handoff artifacts without removing the guardrail chain that protects runtime contracts and production implementation coverage.

The token-aware process is still a Plan-first process.

The intended sequence is:

1. Create a bounded Plan for the requested change.
2. Use that Plan to identify the high-risk runtime slice.
3. Preserve the guardrail chain for the selected high-risk slice.
4. Implement against the Plan as the source of truth.
5. Verify that selected contracts, test points, production implementation, and production wiring are aligned.
6. Record unresolved work instead of continuing indefinitely.

The key policy is:

> Reduce breadth, not depth.

Lightweight execution must narrow the target slice. It must not remove the Plan, and it must not remove the minimum chain needed to connect runtime contracts, test design, stub usage, production implementation, and production wiring.

## Corrected scope of the token-aware flow

The token-aware guardrail kernel flow is not intended to start directly from risk triage.

Risk triage is meaningful only after there is a Plan or equivalent bounded Plan artifact that describes:

- what behavior should be implemented
- what is out of scope
- which components or modules are expected to change
- what acceptance conditions matter
- where high-risk runtime boundaries may exist

Therefore, a lightweight Plan-generation step is required before `change-risk-triage.agent.md`.

The current conclusion is to add a dedicated `plan-kernel.agent.md` rather than overloading `change-risk-triage.agent.md`.

`plan-kernel.agent.md` should create a bounded implementation Plan that is lighter than the existing full `plan-generation.agent.md` flow. It should not create detailed runtime evidence or full integration test design by itself. Instead, it should hand off high-risk boundary candidates to `change-risk-triage.agent.md` and the downstream kernel agents.

## Non-goals

This improvement is not intended to:

- skip Plan creation
- make risk triage replace Plan generation
- implement directly from `runtime-contract-kernel` artifacts alone
- make every agent run shorter by simply deleting important checks
- replace runtime evidence with a shallow checklist
- treat stub-based tests as sufficient proof of production readiness
- make full autonomous completion the default goal
- force every task through the heaviest possible full process
- turn Plan documents into detailed implementation task lists
- make agents keep fixing until all issues are resolved regardless of cost

## Guardrail chain that must be preserved

For any selected high-risk implementation slice, the process must preserve the following chain:

1. Plan requirement / acceptance condition
2. Runtime contract identification
3. Runtime participant and boundary mapping
4. Test point mapping
5. Stub / fake / in-memory usage identification
6. Production implementation binding
7. Production wiring / entrypoint verification
8. Explicit unresolved status for anything not completed

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

### 3. High-risk kernel without complete implementation context

A runtime contract kernel artifact intentionally focuses on high-risk boundaries. It is not a complete requirements specification.

If implementation is started from `runtime-contract-kernel` alone, the implementation agent may overfit to the high-risk contract while missing the overall requested behavior.

The implementation handoff must therefore include:

- the bounded Plan created by `plan-kernel.agent.md`
- the risk triage output
- the runtime contract kernel
- the test design kernel
- explicit scope and non-goals

## Core operating principles

### 1. Plan-first before risk-first

The token-aware flow must begin by creating a bounded Plan. `change-risk-triage.agent.md` should classify risk within that Plan, not replace the Plan.

The Plan is the source of truth for implementation behavior. Kernel artifacts are guardrails for the high-risk slice, not substitutes for the Plan.

### 2. Bounded pass over open-ended completion

Agents should perform a bounded pass and then report the remaining work.

They must not assume that their job is to keep repairing until all issues disappear. When completion would require broad redesign, repeated fix loops, missing human judgment, or work outside the selected slice, the agent must stop and classify the residual work.

### 3. Selected slice over whole-system thin coverage

Lightweight mode should select a smaller number of high-risk runtime contracts and handle them deeply enough to preserve the guardrail chain.

It is better to verify three important cross-process contracts properly than to skim twenty requirements without confirming production binding.

### 4. Explicit status over ambiguous partial completion

Every selected contract, test point, or coverage item must end in an explicit status such as:

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
| `plan-kernel` | Create the bounded Plan that remains the implementation source of truth | Plan preserved | Narrow to moderate |
| `contract-kernel` | Minimal high-risk guardrail for a selected runtime slice | Preserved | Narrow |
| `standard-slice` | Normal bounded Plan-first process for selected contracts / IDs | Preserved | Moderate |
| `full-coverage` | Current-style broad process for complex or high-risk changes | Preserved and expanded | Broad |
| `triage-only` | Classify risk and recommend next slice without implementation | Classification only | Variable |
| `fix-slice` | Resolve explicitly selected gaps only | Preserved for selected gaps | Narrow |

## Lightweight mode requirements

A lightweight process is acceptable only when it still produces enough information to answer these questions for the overall change and for each selected high-risk slice.

For the overall change:

1. What behavior is being implemented?
2. What is out of scope?
3. Which components or modules are expected to change?
4. What acceptance conditions define successful implementation?
5. Which areas are suspected high-risk boundaries?

For each selected high-risk slice:

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

Agents should avoid vague goals such as "make the implementation complete". Prefer goals such as "create a bounded Plan", "classify all selected IDs", "verify production binding for selected test points", or "resolve only the selected gap IDs".

## Recommended repository convention

Documents that define this policy and its process should be treated as required authoring-time context for future agent creation and agent revision work.

New agent files should be created or revised only after the authoring process reads:

- this purpose and policy document
- the corresponding process and agent requirements document
- the current agent file being modified, when applicable

These documents are not intended to be runtime dependencies of the generated agents. A generated agent may be copied into another repository without this `docs/` directory. Therefore, any purpose, policy, profile, handoff, or cross-agent relationship that the agent needs during execution must be embedded in the agent file itself or in a common instruction file that is distributed together with the agent.

## Success criteria for this improvement

This improvement succeeds when:

- the token-aware flow still begins with a bounded Plan
- lightweight runs remain meaningfully cheaper than full runs
- selected high-risk contracts still receive runtime and verification guardrails
- implementation agents receive both the Plan and kernel guardrail artifacts
- stub-only success is explicitly detected and recorded
- agents stop with useful residual work instead of looping toward perfect completion
- full mode remains available for genuinely complex work
- downstream agents can consume prior artifacts without rediscovering the same context
