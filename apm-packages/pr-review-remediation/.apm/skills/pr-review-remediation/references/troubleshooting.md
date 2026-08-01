# Troubleshooting

## Goal Context purpose review is required

このSkillは基礎版です。free-form Goal Contextを選択し、`purpose-reviewer`を含む独立reviewが必要な場合は`$goal-context-pr-review`を明示指定してください。Goal Contextが欠落したまま、この基礎版で目的review済みと扱うことはできません。

## The PR is a draft

GitHub Copilot reviewを待つ対象はReady for reviewの通常PRです。collectorはDraftを自動変更しません。

人手での作業が必要: PRをReady for reviewに変更し、collectorを再実行してください。

## Copilot wait timed out

collectorを開始する前に`gh pr edit <number> --repo <owner/name> --add-reviewer @copilot`を実行します。要求が失敗した場合は、GitHub CLI認証のreviewer要求権限とCopilot code reviewの利用条件を確認します。

要求成功後の`waitStatus: timeout`は未取得です。コメントなしではありません。次のどちらかを明示的に決めます。

- Copilot reviewを再依頼・再待機する
- local Codex reviewだけで進むことを人が承認し、そのdecisionをreview planへ記録する

## The PR changed while waiting

base/head OID、Draft状態、PR stateが変化した場合、collectorは古いreviewと新しいdiffを混ぜず停止します。最新PR identityで最初から再収集してください。

## Working tree differs from the PR

未commit・未push変更は`pr-diff.patch`に含まれません。PRで修正済みまたはレビュー済みと扱わず、必要ならscope確認後にcommit/pushしてから再収集してください。

## Review profile check fails

```powershell
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\pr-review-remediation\scripts\sync-pr-review-remediation-local.cs" -- . --check
```

review profileが競合する場合だけ`--force`を検討します。通常の`--check`はcanonical same-parent/基礎版Phase 1だけを検査します。基礎版Phase 2を選び、Adaptive packageを別途導入済みの場合だけ`--check --check-adaptive`を使い、Adaptive profile不足は既存Adaptive helperで修復します。

## `.codex/config.toml`

review helperもAdaptive helperもrepository-wide設定を上書きしません。旧設定のcleanupが必要な場合は、内容を確認して人手で行ってください。

## Actual agent smoke requires approval

実agent smokeはcanonical review agent contract、smoke prompt、fixture repositoryのreview contextとremote patchをCodex model serviceへ送信します。実行環境が外部送信の明示承認を要求した場合、fixtureだけで成功扱いにせず`HUMAN_DECISION_REQUIRED`で停止します。

人手での作業が必要: `run-pr-review-remediation-agent-smoke.ps1 --help`に表示される送信対象を確認し、外部model serviceへの送信を明示承認してから再実行してください。
