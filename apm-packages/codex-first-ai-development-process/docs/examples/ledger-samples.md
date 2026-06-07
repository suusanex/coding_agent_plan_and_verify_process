# Ledger Samples

この例は、Codex-first process が「実装できたか」だけでなく「Plan の受け入れ条件を満たしたか」「残件を残したまま close してよいか」を確認するための最小サンプルである。

## 通常フロー: close 可能な例

### Parent Plan Coverage Ledger

| Plan item | Expected evidence | Actual evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| AC-001: CLI が設定ファイルから `greeting` を読む | production CLI entrypoint の差分 | `src/cli/config.ts` と `src/cli/main.ts` が実 entrypoint で接続済み | Covered | fake reader だけではなく production wiring を確認済み |
| AC-002: 設定がない場合は既定値を使う | unit test または runtime evidence | `ConfigReaderTests.UsesDefaultGreeting` | Covered | fallback の仕様が確認済み |
| AC-003: README に設定例がある | docs diff | `README.md` の config section | Covered | 利用者向け手順がある |

### Residual Decision Ledger

| Residual item | Decision | Close impact | Reason | Next owner |
| --- | --- | --- | --- | --- |
| 設定ファイルの探索パスを増やす | Deferred | CloseAllowed | 今回の受け入れ条件外であり、既定 path だけで要求を満たす | Backlog |
| Windows 以外の shell example を追加する | Deferred | CloseAllowed | 機能の production readiness をブロックしない | Docs follow-up |

Close result: `ReadyToCloseWithAcceptedResiduals`

## READY でないため実装しない例

| Gate | Finding | Required action |
| --- | --- | --- |
| Plan | 受け入れ条件が「いい感じに設定対応する」だけで曖昧 | bounded Plan に AC を追加する |
| Risk | production entrypoint が複数あり、どれを接続すべきか不明 | repo scan または human decision を要求する |
| Handoff | runtime contract はあるが、親 Plan の AC と対応していない | implementation handoff review をやり直す |

Result: `ReadyForDelegatedImplementation` ではないため、`standard-implementer` へ進めない。

## ManualVerificationRequired が残るため close しない例

### Parent Plan Coverage Ledger

| Plan item | Expected evidence | Actual evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| AC-101: 決済 sandbox で成功決済を確認する | sandbox credential を使った実行ログ | なし | ManualOnly | credential と sandbox access が必要 |
| AC-102: 決済失敗時に補償 state を保存する | integration test または local durable state evidence | `PaymentFailureCompensationTests` | Covered | local durable state は確認済み |

### Residual Decision Ledger

| Residual item | Decision | Close impact | Reason | Next owner |
| --- | --- | --- | --- | --- |
| 決済 sandbox の実確認 | ManualVerificationRequired | CloseBlocked | secret と外部 sandbox access が必要 | Human |
| 決済 provider の rate limit 条件 | NeedsHumanDecision | CloseBlocked | 社内運用の許容範囲を人が決める必要がある | Product / Ops |

Close result: `BlockedByManualVerification`

この状態では、local test が通っていても close しない。最終報告では、未解決項目、必要な人間操作、再開条件を明記する。
