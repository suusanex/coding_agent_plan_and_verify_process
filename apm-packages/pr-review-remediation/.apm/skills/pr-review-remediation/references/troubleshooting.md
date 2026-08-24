# Troubleshooting

## The PR is a draft

collectorはDraftを自動変更しません。

人手での作業が必要: PRをReady for reviewに変更し、collectorを再実行してください。

## Review request failed

`gh pr edit <number> --repo <owner/name> --add-reviewer @copilot`の権限、policy、利用条件を確認します。要求失敗をreview findingsなしとして続行せず`BLOCKED`にします。

## Review wait timed out

`waitStatus: timeout`は未取得です。コメントなしではありません。再依頼・再待機するか、未取得でも進むことを利用者が明示判断します。判断がなければ`HUMAN_DECISION_REQUIRED`です。

## The PR changed while waiting

base/head OID、Draft状態、PR stateが変化した場合、collectorは古いreviewと新しいdiffを混ぜず停止します。最新PR identityで最初から再収集してください。

## Working tree differs from the PR

未commit・未push変更は`pr-diff.patch`に含まれません。PRで修正済みまたはreview済みと扱わず、必要ならscope確認後にcommit/pushしてから再収集してください。

## Review profile check fails

```powershell
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- . --check
```

review-planner profileが競合する場合だけ`--force`を検討します。repository-wide設定を上書きしません。

## Persistent purpose review is required

このSkillはbaseline PR review専用です。目的達成reviewが必要な場合は、別packageの`$persistent-purpose-review`とuser-level `purpose-review-runner`を導入してください。
