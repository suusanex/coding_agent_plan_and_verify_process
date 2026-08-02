# Example: Full-coverage Feature

この例は熟練 operator / maintainer 向けの advanced route 例である。
標準 user guide には載せない。

## Request

```text
注文作成、在庫予約、決済、失敗時の補償処理をまとめて追加してください。
大きな変更なので、必要なら並列化も検討してください。
```

## Why full-coverage

- multiple runtime sequences interact
- retry / compensation / durable state are involved
- cross-slice contracts affect correctness
- one bounded implementation pass would hide residual risk

## Expected route

```text
codex-first-cost-router
-> parent Plan / state artifact
-> risk triage
-> advanced-route confirmation
-> architecture-slice-readiness.agent.md
-> architecture-elaboration.agent.md
-> architecture-slice-readiness.agent.md (rerun: ReadyForSliceDecomposition)
-> plan-slice-decomposition.agent.md
-> slice-prep for executable slices
-> high-implementation-starter for each non-trivial READY slice
-> standard-implementation-completer only after a valid slice-local handoff
-> high-implementation-starter on re-entry
-> cross-slice-verification-kernel.agent.md
-> residual decision
```

In `DELEGATED_IMPLEMENTATION` mode, non-trivial READY slices require observed `high-implementation-starter` runs. Missing HIGH start evidence blocks the run with `BlockedByMissingAdaptiveImplementationDelegation`. STANDARD completion is valid only after a complete handoff, and each slice keeps HIGH -> STANDARD -> HIGH ownership serial.

## Slice example

| Slice | Scope | Cross-slice contract |
| --- | --- | --- |
| SL-001 | order command and persistence | `XC-001 order_id is stable across reservation/payment` |
| SL-002 | inventory reservation | `XC-002 reservation timeout returns compensatable state` |
| SL-003 | payment request | `XC-003 payment failure triggers compensation state` |
| SL-004 | compensation worker | `XC-004 compensation is idempotent` |

## Residual decision example

| Item | Decision | Reason |
| --- | --- | --- |
| Missing retry dashboard | Deferred | Not required for MVP acceptance |
| Real payment sandbox validation | ManualVerificationRequired | Requires external credential and sandbox access |
| Compensation idempotency mismatch | FixNow | Blocks parent acceptance condition |

## Compact record layout

Even with four slices, use one Parent State, four Slice Records, one canonical Coverage Ledger, and one Final Record. A record moves through immutable baseline, preparation delta, Parent Authorization, Adaptive Implementation, independent verification, and any bounded fix; cross-slice evidence belongs in the Final Record.
