# Plan網羅チェック・残件判定フロー: Process and Agent Requirements

この file path は互換性のために残しています。内容は Plan網羅チェック・残件判定フローの authoring-time requirements です。

## Design policy

The process reduces unbounded work by using bounded passes and explicit residual decisions. It does not reduce the parent Plan.

Required high-level chain:

1. `plan-kernel.agent.md` creates the parent Plan.
2. `change-risk-triage.agent.md` builds parent Plan risk inventory and recommends Guardrail Focus.
3. implementation-contract agents confirm dependency / API / provider / substitution risk when needed.
4. `runtime-contract-kernel.agent.md` fixes Guardrail Focus RC.
5. `test-design-kernel.agent.md` maps Guardrail Focus TP and production binding checks.
6. `implementation-handoff-review.agent.md` creates Parent Plan Coverage Ledger.
7. `implementation-execution.agent.md` runs one bounded parent Plan pass.
8. `code-review-focus-kernel.agent.md` optionally prepares human review.
9. `verification-kernel.agent.md` updates Parent Plan Coverage Ledger and emits parent Plan verdict.
10. `coverage-gap-triage.agent.md` separates FixNow items and residual decision candidates.
11. `residual-decision-gate.agent.md` creates Residual Decision Ledger and next-step verdict.
12. `coverage-gap-resolution-slice.agent.md` repairs explicit FixNow selectors only.

## Required artifacts

| Artifact | Purpose |
| --- | --- |
| `plans/<ticket-or-slug>.md` | parent Plan source of truth |
| `plans/<ticket-or-slug>-change-risk-triage.md` | risk inventory, Guardrail Focus recommendation, residual risks |
| `plans/<ticket-or-slug>-runtime-contract-kernel.md` | Guardrail Focus RC |
| `plans/<ticket-or-slug>-test-design-kernel.md` | Guardrail Focus TP and production binding checks |
| `plans/<ticket-or-slug>-implementation-handoff-review.md` | Parent Plan Coverage Ledger before implementation |
| `plans/<ticket-or-slug>-implementation-execution.md` | Implementation Self-Map and Remaining Work |
| `plans/<ticket-or-slug>-verification-kernel.md` | Parent Plan Coverage Ledger after verification |
| `plans/<ticket-or-slug>-coverage-gap-triage.md` | FixNow and residual decision candidates |
| `plans/<ticket-or-slug>-residual-decision-gate.md` | Residual Decision Ledger |

## Parent Plan Coverage Ledger

Every parent Plan FR / AC must be classified.

Allowed examples:

- `MappedToGuardrailFocus`
- `MappedToNormalParentPlanPass`
- `MappedToDecompositionSlice`
- `MappedToCrossSliceVerification`
- `ResidualDecisionCandidate`
- `ManualVerificationRequired`
- `NeedsHumanDecision`
- `UnmappedBlocking`

## Residual Decision Ledger

Residual Decision Gate records:

- explicit human decision source
- accepted residuals
- manual verification handoff
- deferred items with owner
- abort / re-plan recommendations
- decisions not made

`READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS` is only valid when the required explicit human decisions are present.

## Cross-slice requirements

When `full-coverage` requires decomposition:

- slice decomposition preserves parent Plan coverage.
- each slice maps back to parent Plan items.
- `XC-xxx` is verified by `cross-slice-verification-kernel.agent.md`.
- unresolved cross-slice items go to coverage-gap-triage or residual-decision-gate.

## Repair slice requirements

`coverage-gap-resolution-slice.agent.md` is post-verification repair only.

It requires explicit FixNow selector from coverage-gap-triage or residual-decision-gate. It must not approve defer / manual / abort decisions.
