# full-coverage decomposition in Plan網羅チェック・残件判定フロー

この file path は互換性のために残しています。内容は、Plan網羅チェック・残件判定フローにおける `full-coverage` 診断時の decomposition policy です。

## Meaning of full-coverage

`full-coverage` は parent Plan coverage を縮小する合図ではありません。

It means the parent Plan is too broad, ambiguous, or interconnected for one bounded parent Plan pass, so the process needs one of:

- bounded execution slice decomposition
- re-plan
- human decision
- manual verification handoff

## Required sequence

```text
change-risk-triage
  -> plan-slice-decomposition
  -> per-slice bounded parent Plan pass
  -> cross-slice-verification-kernel
  -> coverage-gap-triage
  -> residual-decision-gate
```

## Decomposition rules

- Every slice must map to parent Plan FR / AC.
- A slice is execution packaging, not a smaller parent Plan.
- Guardrail Focus within a slice is still deep-check focus only.
- `XC-xxx` must not be completed inside one slice.
- Parent Plan Coverage Ledger must be updated after verification.
- Residual Decision Ledger must be produced before unresolved items are accepted, deferred, delegated, or aborted.

## Parent review gate

Before per-slice implementation, the parent agent or reviewer should confirm:

- all parent Plan items are mapped;
- cross-slice contracts are explicit;
- residual risk candidates are visible;
- per-slice artifacts include required inputs for change-risk-triage, runtime-contract-kernel, test-design-kernel, and implementation-handoff-review;
- final cross-slice verification and Residual Decision Gate are scheduled.
