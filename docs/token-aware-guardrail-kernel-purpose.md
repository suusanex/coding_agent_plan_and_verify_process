# Token-aware Guardrail Kernel: Purpose and Policy

## Background

This repository defines a Plan-first development process for GitHub Copilot agents.

The original process intentionally combines runtime evidence, integration test design, implementation verification, and coverage gap resolution. That chain exists to prevent two recurring failure modes in AI-assisted implementation:

1. Cross-process or cross-component sequences appear correct inside each process, but fail when connected because contracts, messages, state transitions, or wiring do not match.
2. Automated tests pass against stubs, fakes, or in-memory implementations, while the corresponding production implementation or production wiring is missing.

As GitHub Copilot usage moves toward token-consumption-based cost awareness, the process must reduce avoidable re-reading, rework, and open-ended repair loops. However, the guardrails above are not optional decoration. Removing them would make the process cheaper but would also reintroduce the original quality failures.

## Primary objective

Optimize the process for bounded progress, explicit residual work, and reusable handoff artifacts without removing the guardrail chain that protects runtime contracts and production implementation coverage.

The key policy is:

> Reduce breadth, not depth.

Lightweight execution must narrow the target slice. It must not remove the minimum chain needed to connect runtime contracts, test design, stub usage, production implementation, and production wiring.

## Non-goals

This improvement is not intended to:

- make every agent run shorter by simply deleting important checks
- replace runtime evidence with a shallow checklist
- treat stub-based tests as sufficient proof of production readiness
- make full autonomous completion the default goal
- force every task through the heaviest possible full process
- turn Plan documents into detailed implementation task lists
- make agents keep fixing until all issues are resolved regardless of cost

## Guardrail chain that must be preserved

For any selected high-risk implementation slice, the process must preserve the following chain:

1. Runtime contract identification
2. Runtime participant and boundary mapping
3. Test point mapping
4. Stub / fake / in-memory usage identification
5. Production implementation binding
6. Production wiring / entrypoint verification
7. Explicit unresolved status for anything not completed

The full process may express this through detailed runtime evidence, scenario ledgers, integration test design, implementation coverage documents, and gap resolution.

The lightweight process may express the same chain through smaller kernel artifacts, but it must not skip the chain.

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

## Core operating principles

### 1. Bounded pass over open-ended completion

Agents should perform a bounded pass and then report the remaining work.

They must not assume that their job is to keep repairing until all issues disappear. When completion would require broad redesign, repeated fix loops, missing human judgment, or work outside the selected slice, the agent must stop and classify the residual work.

### 2. Selected slice over whole-system thin coverage

Lightweight mode should select a smaller number of high-risk runtime contracts and handle them deeply enough to preserve the guardrail chain.

It is better to verify three important cross-process contracts properly than to skim twenty requirements without confirming production binding.

### 3. Explicit status over ambiguous partial completion

Every selected contract, test point, or coverage item must end in an explicit status such as:

- `Done`
- `PartiallyDone`
- `Deferred`
- `ManualOnly`
- `NeedsHumanDecision`
- `NotImplementedOrMismatch`
- `OutOfScopeForThisPass`

A missing result is not an acceptable result.

### 4. Handoff artifacts over repeated rediscovery

Each phase should leave a compact handoff artifact that tells the next phase:

- what was inspected
- what was decided
- what was intentionally not inspected
- what must not be redone unless new evidence appears
- what remains unresolved

This reduces repeated repository exploration and repeated reasoning over the same issue.

### 5. Risk-triggered escalation

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
| `contract-kernel` | Minimal high-risk guardrail for a selected runtime slice | Preserved | Narrow |
| `standard-slice` | Normal bounded Plan-first process for selected contracts / IDs | Preserved | Moderate |
| `full-coverage` | Current-style broad process for complex or high-risk changes | Preserved and expanded | Broad |
| `triage-only` | Classify risk and recommend next slice without implementation | Classification only | Variable |
| `fix-slice` | Resolve explicitly selected gaps only | Preserved for selected gaps | Narrow |

## Lightweight mode requirements

A lightweight process is acceptable only when it still produces enough information to answer these questions for each selected high-risk slice:

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

Agents should avoid vague goals such as "make the implementation complete". Prefer goals such as "classify all selected IDs", "verify production binding for selected test points", or "resolve only the selected gap IDs".

## Recommended repository convention

Documents that define this policy and its process should be treated as required authoring-time context for future agent creation and agent revision work.

New agent files should be created or revised only after the authoring process reads:

- this purpose and policy document
- the corresponding process and agent requirements document
- the current agent file being modified, when applicable

These documents are not intended to be runtime dependencies of the generated agents. A generated agent may be copied into another repository without this `docs/` directory. Therefore, any purpose, policy, profile, handoff, or cross-agent relationship that the agent needs during execution must be embedded in the agent file itself or in a common instruction file that is distributed together with the agent.

## Success criteria for this improvement

This improvement succeeds when:

- lightweight runs remain meaningfully cheaper than full runs
- selected high-risk contracts still receive runtime and verification guardrails
- stub-only success is explicitly detected and recorded
- agents stop with useful residual work instead of looping toward perfect completion
- full mode remains available for genuinely complex work
- downstream agents can consume prior artifacts without rediscovering the same context
