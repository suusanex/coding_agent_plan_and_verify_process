# codex-full-coverage-3layer

Use this skill only as an advanced route when `codex-first-cost-router` determines that the requested change cannot be safely bounded inside the standard cost-aware route, or when an experienced operator explicitly asks for broad parallelization.

## Purpose

This skill turns full-coverage from "do everything in one enormous run" into a three-layer Codex operation:

1. Parent orchestration
2. Slice preparation
3. Slice implementation

## Workflow

1. Treat the parent Plan and `plans/<slug>/codex-first-state.md` as source of truth. Use `plans/<slug>/codex-first-audit.md` for delegation evidence and close audit.
2. Stop and request experienced-operator confirmation unless the user already explicitly selected advanced full-coverage work.
3. Run `architecture-slice-readiness.agent.md`. If it returns `NeedsArchitectureElaboration`, run `architecture-elaboration.agent.md` and rerun readiness. Stop on `NeedsHumanDecision` or blocking architecture residuals.
4. Run `plan-slice-decomposition.agent.md` only for `ReadyForSliceDecomposition` with a current architecture artifact or `ArchitectureNotRequired` with a source-backed verdict.
5. Read `Slice granularity review` and architecture traceability before routing slices.
6. For each executable slice, produce a slice artifact with scope, non-goals, dependencies, parent acceptance condition mapping, and cross-slice contracts.
7. Do not route `merge-candidate`, `too-small-to-delegate`, or `coalesce-with-SL-xxx` candidates to `slice-prep`.
8. Route `slice-prep`, `slice-impl`, and cross-slice verification to appropriate model tiers.
9. Few executable slices are valid when parent acceptance conditions, cross-slice contracts, field continuity, and Behavior Case mapping remain traceable.
10. Record `ExecutionMode`, expected delegation, observed agent runs, and DelegationCompliance in the audit artifact Agent Usage Ledger.
11. In `DELEGATED_IMPLEMENTATION`, every READY slice MUST have an observed `slice-impl` run. Missing evidence blocks with `BlockedByMissingSliceImplDelegation`.
12. Do not mark parent acceptance conditions complete inside a single slice when cross-slice evidence is required.
13. After slice work, run `cross-slice-verification-kernel.agent.md`.
14. Use residual decision logic to classify remaining work as FixNow, Deferred, ManualVerificationRequired, NeedsHumanDecision, or NeedsHigherModelReview.
15. Update the cost-router state artifact after every parent-level transition.

## Rules

- Do not jump from `full-coverage` directly to decomposition or broad implementation.
- Do not allow slice-prep or slice-impl to redefine shared architecture semantics; return drift to Architecture Slice Readiness.
- Do not collapse parent, slice-prep, and slice-impl into one unbounded pass.
- Do not let the parent directly implement READY slices in `DELEGATED_IMPLEMENTATION`.
- Do not count `PARENT_DIRECT_IMPLEMENTATION_EXCEPTION` as delegated success.
- Do not hide cross-slice contracts inside a slice-local completion note.
- Do not treat candidate slice disposition as cross-slice contract or field continuity status.
- Do not spend high-cost model time on routine slice implementation once the slice contract is clear.
- Do not expose this route as the default beginner path.

## Output

Return:

- parent Plan reference
- state artifact path
- audit artifact path
- slice list
- cross-slice contract list
- per-slice next agent
- model tier assignment summary
- residual decision summary
- manual or higher-model review needs
