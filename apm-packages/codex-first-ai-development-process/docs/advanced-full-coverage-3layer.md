# Advanced Full-Coverage 3Layer

Full-coverage 3-layer operation is an advanced route.
It is not the standard user path for Codex-first cost-aware routing.

## Use only when

- an experienced operator explicitly selects it
- the change cannot be safely bounded by the standard cost-router route
- cross-slice contracts are central to correctness
- parent / slice-prep / slice-impl separation is needed
- cost is acceptable in exchange for parallelization or acceleration

## Do not use when

- the request is a simple local fix
- a bounded Plan and single implementation pass are enough
- the user is a beginner asking for ordinary issue work
- the main problem is missing human input, secret, or external environment access

## Route

```text
codex-first-cost-router
-> parent Plan / codex-first-state
-> advanced-route confirmation
-> architecture-slice-readiness
-> architecture-elaboration + readiness rerun when needed
-> plan-slice-decomposition
-> Parent Orchestration State
-> slice-prep
-> slice-impl
-> audit artifact Agent Usage Ledger / DelegationCompliance
-> cross-slice-verification
-> residual decision
```

## Slice granularity

- `full-coverage` does not mean many executable slices are required.
- Prefer the smallest number of useful slices that preserves parent acceptance conditions, cross-slice contracts, field continuity, and Behavior Case mapping.
- `plan-slice-decomposition` must coalesce candidates that share owner, module, production wiring, verification route, and parent acceptance condition.
- Small slices need `Small slice justification`. Candidates marked `merge-candidate`, `too-small-to-delegate`, or `coalesce-with-SL-xxx` are not sent to `slice-prep`.

## Architecture readiness

- `full-coverage` first routes to `architecture-slice-readiness`, not decomposition.
- `ReadyForSliceDecomposition` requires a current `plans/<slug>-slice-architecture.md`.
- `ArchitectureNotRequired` is the lightweight path for a source-backed simple structure.
- `NeedsArchitectureElaboration` runs elaboration and readiness again; `NeedsHumanDecision` stops.
- Parent review blocks any slice-prep drift in state ownership, precedence, identity, temporal sequence, retry / release, capacity, schema, invariant, or production wiring.

## Cost routing

- Parent Plan, decomposition, and cross-slice close risk usually need `HIGH_MODEL`.
- Routine READY slice implementation is delegated to `slice-impl`, usually with `STANDARD_MODEL`.
- Read-heavy slice inventory and doc consistency may use `CHEAP_MODEL`.

## Delegation rules

- `PREP_ONLY` stops after slice-prep and parent review gate. production code / tests are not edited.
- `DELEGATED_IMPLEMENTATION` requires every READY slice to have observed `slice-impl` evidence.
- Missing `slice-impl` evidence is `BlockedByMissingSliceImplDelegation`, not success.
- `PARENT_DIRECT_IMPLEMENTATION_EXCEPTION` needs explicit human approval and is excluded from delegated completion metrics.

## Resume state

- Create or update `plans/<ticket-or-slug>-parent-orchestration-state.md` as the single resume entrypoint for parent orchestration.
- Keep it compact: path, status, next action, and blocking reason. Do not paste full source artifacts, subagent outputs, long reasoning traces, or source excerpts except for short pointers.
- If the file grows too large, compact old completed slice rows into a short summary and keep details in the original slice artifacts.
- Update it at major checkpoints and delegation boundaries, including start, ExecutionMode decision, slice-prep and slice-impl batch boundaries, parent review gate, cross-slice verification, residual decision, planned handoff, tool switch, model switch, and emergency checkpoint.
- When switching between Codex, GitHub Copilot, sessions, or tools, the next parent agent first selects the state matching the current ticket, slug, branch, work item, or PR. If multiple candidates match or none can be matched, fail closed and ask for the target state.
- Then the next parent agent reads the selected state, verifies the audit artifact Agent Usage Ledger and listed artifacts, and continues.
- Agent Usage Ledger records delegation evidence in the audit artifact. Parent Orchestration State records current phase, next action, artifact index, slice queue, parent decisions made, cross-slice blockers, and pending parent decisions.

## Closure

Parent acceptance conditions are not complete until cross-slice evidence exists.
`ManualVerificationRequired`, `NeedsHumanDecision`, and `NeedsHigherModelReview` prevent normal close.
