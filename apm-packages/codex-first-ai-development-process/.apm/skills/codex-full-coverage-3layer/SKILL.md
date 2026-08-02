# codex-full-coverage-3layer

Use this skill only as an advanced route when `codex-first-cost-router` determines that the requested change cannot be safely bounded inside the standard cost-aware route, or when an experienced operator explicitly asks for broad parallelization.

## Purpose

This skill turns full-coverage into a compact Slice Record operation with one parent authority and slice-local deltas.

## Workflow

1. Treat the parent Plan, approved architecture baseline, Parent Orchestration State, canonical Coverage Ledger, Slice Records, and Full-Coverage Final Record as the authoritative record set.
2. Stop and request experienced-operator confirmation unless the user already explicitly selected advanced full-coverage work.
3. Run `architecture-slice-readiness.agent.md`. If it returns `NeedsArchitectureElaboration`, run `architecture-elaboration.agent.md` and rerun readiness. Stop on `NeedsHumanDecision` or blocking architecture residuals.
4. Run `plan-slice-decomposition.agent.md` only for `ReadyForSliceDecomposition` with a current architecture artifact or `ArchitectureNotRequired` with a source-backed verdict.
5. Read `Slice granularity review` and architecture traceability before routing slices.
6. For each executable slice, create one immutable `compact-slice-record-v2` Slice Record with scope, non-goals, dependencies, parent acceptance mapping, CASE/XC roles, and inherited authority.
7. Do not route `merge-candidate`, `too-small-to-delegate`, or `coalesce-with-SL-xxx` candidates to `slice-prep`.
8. Route Slice Preparation Delta, Parent Authorization, Adaptive Implementation, independent Slice Verification, and Final Record work in that order. Every non-trivial authorized slice starts with `high-implementation-starter`; invoke `standard-implementation-completer` only from a valid handoff.
9. Few executable slices are valid when parent acceptance conditions, cross-slice contracts, field continuity, and Behavior Case mapping remain traceable.
10. Record `ExecutionMode`, expected delegation, observed agent runs, and Delegation Compliance in Parent State. In `DELEGATED_IMPLEMENTATION`, every READY slice MUST have an observed Adaptive HIGH run; missing evidence blocks with `BlockedByMissingAdaptiveImplementationDelegation`.
11. Keep preparation, authorization, implementation, verification, and bounded fixes in their owning Slice Record; do not create a separate audit artifact or Agent Usage Ledger.
12. Do not mark parent acceptance conditions complete inside a single slice when cross-slice evidence is required.
13. After slice work, run `cross-slice-verification-kernel.agent.md`.
14. Use residual decision logic to classify remaining work as FixNow, Deferred, ManualVerificationRequired, NeedsHumanDecision, or NeedsHigherModelReview.
15. Update Parent State after every parent-level transition. A Final Record FixNow selector must project to one owning Slice Record with authorization revision, baseline digest, selector provenance, bounded scope, and verification rerun.

## Rules

- Do not jump from `full-coverage` directly to decomposition or broad implementation.
- Do not allow slice-prep, Adaptive Implementation, or verification to redefine shared architecture semantics; return drift to Architecture Slice Readiness.
- Do not collapse parent authorization, slice-local preparation, implementation, and independent verification into one unbounded pass.
- Do not let the parent directly implement READY slices in `DELEGATED_IMPLEMENTATION`.
- Do not hide cross-slice contracts inside a slice-local completion note.
- Do not treat candidate slice disposition as cross-slice contract or field continuity status.
- Do not spend high-cost model time on routine slice implementation once the slice contract is clear.
- Do not expose this route as the default beginner path.

## Output

Return:

- parent Plan reference
- Parent State path
- Slice Record paths
- Full-Coverage Final Record path
- slice list
- cross-slice contract list
- per-slice next agent
- model tier assignment summary
- residual decision summary
- manual or higher-model review needs

## Legacy compatibility

Existing `legacy-split-v1` runs retain their historical `slice-impl`, separate audit artifact, and Agent Usage Ledger contracts. Fresh `compact-slice-record-v2` work never uses those artifacts as authorization sources. Preserve existing model assignments.
