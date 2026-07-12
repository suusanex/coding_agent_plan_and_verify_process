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
-> slice-impl for READY slices
-> cross-slice-verification-kernel.agent.md
-> residual decision
```

In `DELEGATED_IMPLEMENTATION` mode, READY slices require observed `slice-impl` runs. Missing `slice-impl` evidence blocks the run with `BlockedByMissingSliceImplDelegation`.

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
