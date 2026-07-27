# Goal Context PR review troubleshooting

## Multiple Goal Context candidates

selectorが`HUMAN_DECISION_REQUIRED`で停止した場合、候補pathを確認し、対象を`--goal-context`で一つ指定します。filenameや更新時刻から推測しません。

## Goal Context is missing or invalid

Issue本文だけを読み、目的レビュー済みとして続行しません。Goal Context Authoringで文書を作成・修正してhuman reviewを完了するか、目的レビューなしの基礎版`$pr-review-remediation`を明示選択します。

## Goal Context is draft

既定では`status: human-reviewed`と`sensitive_data_review: passed`が必要です。draftを意図的に使う場合だけexact pathと`--allow-draft`を指定し、selection artifactのoverrideをreview plannerへ渡します。draftのunknownsを暗黙確定しません。

## Purpose and local findings overlap

code bug、test不足、保守性riskは`local-reviewer`へ残します。`purpose-reviewer`は、その問題がOriginal problem、Desired outcome、scenario、boundaryへ与える目的上の影響だけをfinding化します。plannerがsource IDを保って重複を統合します。

## Notification did not arrive

通知delivery失敗はreview verdictを変更しません。review-plan.mdとPR URLを通常出力から確認し、notification runtime logを別途診断します。Phase 2を自動起動して補償しません。

## Duplicate same-head round

同じhead OIDは再reviewしません。前roundのAdaptiveが別親ターンで完了し、新しいheadへpushされたことを確認します。誤ったheadで開始したin-progress roundを上書きせず、artifactとhuman decisionを保持したまま利用者へ判断を求めます。

## Round 3 still has actionable findings

既定上限へ到達したため`HUMAN_DECISION_REQUIRED`で停止します。第4roundを自動開始しません。継続する場合は、pending decision IDのresolutionと承認情報を記録し、さらに利用者のidentity、承認時刻、理由、増加後の上限を`manage-review-cycle.cs start`のoverride optionsへすべて指定します。

## Artifact content mismatch

hashだけを更新して続行しません。review-contextのrepository/PR/OIDとsource IDs、Goal Context selection、local/purpose identity、review-resultのverdict/finding delta/source coverage/bindingsのどれがround-resultと異なるかを確認し、現在のin-progress round内で正しいartifactを再生成します。完了済みroundは変更しません。

## Historical review sources after a head update

collectorが保持した旧headのreview／inline commentは削除しません。target-level headは現在roundに一致させ、個別sourceはcurrent／historical／unknownとしてcoverageへ残します。`commit_id`または`original_commit_id`がGit OID形式でない場合だけcollector inputを再取得します。

## Remote patch path mismatch

`review-context.json`の`artifacts.remotePatch`と、round manifestの`remote-patch` roleが同じ実体fileを指すようにします。別fileのhashへ差し替えたり、context pointerだけを書き換えたりせず、collectorが出力した`pr-diff.patch`を正本としてartifact一式を再生成します。

## Invalid cycle timestamp

`started-at`、completion、decision、overrideの時刻には、`2026-07-28T09:00:00Z`または`2026-07-28T09:00:00+09:00`のようにtimezoneを明示します。locale依存形式やoffsetなしの日時は受理しません。

## Historical artifact hash mismatch

完了済みroundのartifactは修正せず、改変元を調査します。再生成物は新しいroundへ保存し、過去roundを上書きしません。hash不一致を無視してcycleを進めないでください。
