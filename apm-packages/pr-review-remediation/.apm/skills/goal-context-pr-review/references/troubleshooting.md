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

