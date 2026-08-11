# Goal Context same-parent real-model smoke

この手順は、deterministic fixtureでは証明できないreal model reviewer independence、元の親agentによるremediation、real GitHub current-head更新、Codex/Windows notification observationを記録します。検証対象process PR自身ではなく、機密情報を含まないdisposable target repositoryの小さなReady PRを使用します。

## Human authorization

人手での作業が必要: target repository/branch/PR write、external model payload、notification runtime install、cleanupは実行前に範囲を確認して承認します。承認されていないexternal writeやmodel送信は行いません。

## Preconditions

- process packageの対象refを固定してAPM install済み
- `finalize-codex-agent-profiles.cs --check`がPASS
- GitHub CLI認証が対象PRへreviewerを要求でき、対象organization/repositoryでCopilot code reviewが利用可能
- current branchにReady PR、またはrepository全体にunique Ready PR。複数なら開始promptでPR番号/URLを短く指定
- readable non-empty Goal Context。形式、filename、拡張子、作成元は任意。discoveryが曖昧なら開始promptでexact pathを選択
- 初回実装、validation、commit/push、Ready PR作成を担当した元のCodex parent taskを、同じ親taskとして再開可能
- target diff、Goal Context、promptにsecret/personal dataがない

## One-operation start

初回実装を担当した元のparent taskで次を一度だけ送ります。

```text
$goal-context-pr-review

この実装のReady PRをGoal Contextに照らしてreviewし、必要な修正と再reviewを同じtask内で完了してください。
```

別top-level Review/Implementation taskを作成せず、thread ID、cycle path、hash、JSON、result referenceを転記しません。PRが曖昧な場合だけ短い番号またはURLを追加します。

## Required observations

### Intake

- `.review/pr-N/same-thread/<run-id>/`が自動生成される
- `run-state.json`がcurrent repository / Ready PR / head / Goal Contextを保持する
- Draft、候補曖昧、head driftをfail closedにする

### Round 1

- managerがGitHub Copilot reviewを明示要求し、automatic review設定なしでもreviewが開始される
- GitHub Copilot terminal reviewがcurrent headにbindingされる。inline指摘が0件ならcollector-completeな`reviewOnly`、1件以上なら`reviewAndInline`を記録する
- `local-reviewer`と`purpose-reviewer`が`execute-reviewer.cs`（typed `codex-exec`または`copilot-cli`）で独立に実行される
- raw outputと`{role}.execution.json`が別artifactとして保持され、両方に`Production code changed: No`がある
- reviewer role/countとreviewed headがrun summaryへ記録される
- reviewer実行中にproduction/tests/docsのdiffが増えない

### Parent remediation

- actionable findingを元のparentだけが修正する
- repositoryの関連validationを実行する
- human authorizationの範囲内でcommit/pushし、PR current headを更新する
- old headのままpurpose rerunしない

### Round 2/3 purpose-only

- collectorはCopilot wait disabledでcurrent head/patchをrefreshする
- local reviewerを再実行しない
- 新しいpurpose reviewerだけを実行する
- 全active `TRK-*`がcurrent `PUR-*` evidenceで`persistent | resolved`に明示遷移する
- round 3にactive findingが残る場合は`HumanDecisionRequired`、round 4を自動開始しない

### Terminal and notification

- terminal statusは`Complete | HumanDecisionRequired | Blocked`
- terminal projectionにthread/turn IDがなく、current concrete HTTPS PR URIがある
- user-visible notificationから元のparent taskとPRへ戻れる
- reviewer subagent roles/countとuser-visible notification count/targetsをprivacy-safeに記録する
- unsupported callback hierarchy filterを推測しない

## Manual notification E2E

人手での作業が必要: Windows notificationの表示とbutton遷移は自動fixtureでは証明できないため、次を実機で順番に確認します。

1. notification runtimeの`--check`がPASSし、WindowsでCodexの通知が許可されていることを確認する。
2. 新しい通常のCodex taskでDecoratorや`completion-notification` blockを指定せず、短い通常turnを完了する。Windows通知が一件表示されることを確認する。
3. その通知の「このタスクを開く」を押し、手順2の入力と回答がある発火元taskをCodex Appが開くことを確認する。
4. disposable Ready PRを持つ元の実装taskで`$goal-context-pr-review`を完了させる。terminal response末尾にrun rootの`completion-notification.txt`と同一のfenced blockが一度だけあり、block後に本文がないことを確認する。
5. terminal通知の「このタスクを開く」が手順4の元の実装taskを開き、「結果を開く」が同じrunの対象PRを開くことをそれぞれ確認する。
6. round 1と必要なpurpose-only roundの間に表示されたreviewer subagent由来の通知件数とtargetを記録する。親taskのterminal通知を見失うspamになっていないかを判定し、過剰なら実数と状況を残す。公開callbackにない親子fieldを仮定してfilterしない。

各手順はPass/Failと観察時刻だけを`result-template.md`へ記録します。private thread ID、turn ID、callback payload、credentialは保存しません。

## Evidence boundary

次はManualOnlyです。

- real model reviewer independence and output quality
- real GitHub Copilot review request and no-inline completion path
- real parent-owned remediation and GitHub write
- real Windows/Codex callback count and targets
- notification button operation

`validate-same-parent-review.ps1`、fake-gh、APM install、source/profile checksは補助証拠であり、このManualOnly evidenceを置き換えません。

## Result

`result-template.md`をコピーして記録します。private task/turn/callback IDを本文へ保存せず、同じparentを利用した事実、reviewer roles/count、current head、artifact path、observed notification count/targetsを記録します。

## Cleanup

人手での作業が必要: 承認済みcleanup policyに従い、disposable PR/branch/repositoryと一時notification installationを削除または復元します。run artifactsは監査要件に従って保持または削除します。
