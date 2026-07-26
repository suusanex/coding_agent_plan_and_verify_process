# Troubleshooting

## The PR is a draft

GitHub Copilot reviewを待つ対象はReady for reviewの通常PRです。collectorはDraftを自動変更しません。

人手での作業が必要: PRをReady for reviewに変更し、collectorを再実行してください。

## Copilot wait timed out

`waitStatus: timeout`は未取得です。コメントなしではありません。次のどちらかを明示的に決めます。

- Copilot reviewを再依頼・再待機する
- local Codex reviewだけで進むことを人が承認し、そのdecisionをreview planへ記録する

## The PR changed while waiting

base/head OID、Draft状態、PR stateが変化した場合、collectorは古いreviewと新しいdiffを混ぜず停止します。最新PR identityで最初から再収集してください。

## Working tree differs from the PR

未commit・未push変更は`pr-diff.patch`に含まれません。PRで修正済みまたはレビュー済みと扱わず、必要ならscope確認後にcommit/pushしてから再収集してください。

## Review profile check fails

```powershell
dotnet run --file apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs -- . --check
```

review profileが競合する場合だけ`--force`を検討します。Adaptive profile不足は既存Adaptive helperで修復します。

## `.codex/config.toml`

review helperもAdaptive helperもrepository-wide設定を上書きしません。旧設定のcleanupが必要な場合は、内容を確認して人手で行ってください。

