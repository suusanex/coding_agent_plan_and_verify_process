# Troubleshooting

## The PR is a draft

collectorはDraftを自動変更しません。

人手での作業が必要: PRをReady for reviewに変更し、collectorを再実行してください。

## Review request failed

`gh pr edit <number> --repo <owner/name> --add-reviewer @copilot`の権限、policy、利用条件を確認します。要求失敗をreview findingsなしとして続行せず`BLOCKED`にします。

## Review wait timed out

collectorは通常のreview所要時間を制限せず、completionを待ち続けます。標準のhard timeoutは1時間（3600秒）、poll間隔は30秒です。数分以上かかる通常のreviewでは待機を継続します。必要なら`--copilot-timeout-seconds`と`--copilot-poll-interval-seconds`で明示overrideできます。

`waitStatus: timeout`は未取得です。コメントなしではありません。1時間経過後もcompletionを観測できない場合は、従来通り再依頼・再待機するか、未取得でも進むことを利用者が明示判断します。判断がなければ`HUMAN_DECISION_REQUIRED`です。

## The PR changed while waiting or before push

base/head OID、head repository、Draft状態、PR stateが変化した場合、古いreviewと新しいdiffを混ぜません。収集中のdriftは最新PR identityで最初から再収集します。remediation中またはpush前のremote head driftは、force pushや上書きをせず`BLOCKED`として差分、validation、local commitの有無を報告します。

## Push destination differs from the PR head repository

local upstreamのpush URLをGitHub上のcanonical `owner/name`へ解決し、collectorが記録した`headRepository.nameWithOwner`と比較します。一致しない、解決できない、またはpush refがPR head branchと異なる場合はpushせず`BLOCKED`にします。同名branchがある別remoteへplain `git push`しません。

## Working tree differs from the PR

未commit・未push変更は`pr-diff.patch`に含まれません。PRでreview済みと扱わず、開始時差分とremediation差分を分離します。無関係な差分をremediation commitへstageしてはいけません。安全に分離できない場合は`BLOCKED`です。

## Remediation validation failed

失敗したcommandと対象finding / acceptanceを記録し、`BLOCKED`にします。validation failureを無視してcommit / pushしません。

## Commit succeeded but push failed

Git outcomeを`NOT_PUSHED`とし、local commit、remote head、権限または競合エラーを報告します。正常完了に変換せず、force pushしません。

## Unexpected planner or profile remains after update

0.9.0は`review-planner`、planner用Codex profile、`codex-profile-finalizer` dependencyを導入しません。以前のversionが生成したruntime projectionはAPMのupdate / uninstall結果を確認し、ownershipが確認できないfileを推測で上書きまたは削除しません。

## Persistent purpose review is required

このSkillはbaseline PR review専用です。目的達成reviewが必要な場合は、別packageの`$persistent-purpose-review`とuser-level `purpose-review-runner`を導入してください。
