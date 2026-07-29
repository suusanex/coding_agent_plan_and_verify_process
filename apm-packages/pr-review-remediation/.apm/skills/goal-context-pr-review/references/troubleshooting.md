# Goal Context same-parent PR review troubleshooting

## No Ready PR, multiple Ready PRs, or Draft

Current repositoryにはexactly one Ready PRが必要です。DraftをReadyへ変更する、不要なopen PRを整理する、または対象repositoryを確認してから、同じ親taskで再開します。PR番号を手入力して曖昧さを迂回しません。

## Goal Context missing, invalid, or ambiguous

Issue本文で代替しません。Goal Contextを作成・修正するか、複数候補ならexact repository-relative pathを選択します。目的reviewを不要とする場合だけ利用者が基礎版`$pr-review-remediation`を明示選択します。

## GitHub Copilot or reviewer source missing

Round 1のCopilot、local、purposeはいずれもmandatoryです。timeout、read-only reviewer failure、raw output欠落をno findingsへ変換せず`Blocked`にします。raw evidenceを親agentの自己評価で置き換えません。

## Reviewer reports a write

raw outputが`Production code changed: No`を満たさない場合、roundを受理しません。worktree diffを確認し、reviewerがproduction/tests/docsへwriteした可能性を解消してから新しいread-only reviewを実行します。

## Head did not change after remediation

`next-round`はsame headを拒否します。親agentのvalidation、commit/push権限、remote PR headを確認します。old patchのままpurpose reviewを続行しません。

## Purpose-only source rejection

round 2/3でlocal reviewer、Copilot wait、non-`PUR-*` actionable sourceを追加しません。current purpose reviewerのraw outputと、全active `TRK-*`のexplicit `persistent | resolved` assessmentだけを使います。

## Round 3 still has active findings

`HumanDecisionRequired`で停止します。automatic round 4、empty close、黙示的受容は行いません。

## Notification did not arrive

notification failureはreview verdictを変更しません。run summaryとcurrent PR URLを確認し、runtime/providerは別途診断します。thread/turn IDをterminal projectionへ追加しません。

## Historical cycle validation

既存`review-cycle.json`の監査は`manage-review-cycle.cs validate`を使います。historical fixed-task contractを修正してcanonical same-parent runへ変換しません。
