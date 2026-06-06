# Example: Full-coverage Feature

## Request

```text
注文作成、在庫予約、決済、失敗時の補償処理をまとめて追加してください。
Codex-first AI Development Process で進めて。
```

## Why full-coverage

- multiple runtime sequences interact
- retry / compensation / durable state are involved
- cross-slice contracts affect correctness
- one bounded implementation pass would hide residual risk

## Expected route

```text
plan-kernel.agent.md
-> change-risk-triage.agent.md
-> plan-slice-decomposition.agent.md
-> per-slice token-aware kernel flow
-> cross-slice-verification-kernel.agent.md
-> residual decision
```

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
