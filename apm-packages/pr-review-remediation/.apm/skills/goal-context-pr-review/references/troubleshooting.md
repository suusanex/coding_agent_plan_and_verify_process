# Goal Context same-parent PR review troubleshooting

## No Ready PR, multiple Ready PRs, or Draft

まずcurrent branchのReady PRを使います。存在しない場合だけrepository全体のunique Ready PRへfallbackします。それでも複数なら、利用者へ短いPR番号またはURLを確認し、`start --pr <number-or-url>`で再開します。Draftを指定した場合はReadyへ変更してから再開します。

## Goal Context missing, invalid, or ambiguous

Issue本文で代替しません。Goal Contextが存在しない場合は用意し、複数候補ならexact repository-relative pathを選択します。Goal Contextに特定のfilename、frontmatter、見出し、lifecycle、approval recordは不要です。empty、読取不能、repository外escapeだけを入力blockerにします。目的reviewを不要とする場合だけ利用者が基礎版`$pr-review-remediation`を明示選択します。

## GitHub Copilot or reviewer source missing

`start`はGitHub Copilot reviewを明示要求します。要求自体が失敗した場合は、GitHub CLI認証がreviewer要求権限を持つことと、対象organization/repositoryでCopilot code reviewが利用可能なことを確認します。automatic review設定は前提にしません。

Round 1のCopilot、local、purposeはいずれもmandatoryです。collectorがcompleteとしたterminal `reviewOnly`はinline指摘0件の正常系として受理します。timeout、read-only reviewer failure、raw output欠落をno findingsへ変換せず`Blocked`にします。raw evidenceを親agentの自己評価で置き換えません。

## Executor launch / capture failure

`execute-reviewer.cs`のtimeout、auth failure、non-zero exit、empty/malformed output、process start failureはreview成功ではありません。final `*.raw.md`が無い、または`*.execution.json`の`exitStatus`が`succeeded`以外の場合はassessmentへ進まず`Blocked`にします。「findingsなし」へ読み替えません。任意の`--command`文字列、unsupported app/model/roleはtyped設定エラーです。詳細は`execute-reviewer.md`を参照します。

## Reviewer reports a write

raw outputが`Production code changed: No`を満たさない場合、roundを受理しません。worktree diffを確認し、reviewerがproduction/tests/docsへwriteした可能性を解消してから新しいread-only reviewを実行します。

## Head did not change after remediation

`next-round`はsame headを拒否します。親agentのvalidation、commit/push権限、remote PR headを確認します。old patchのままpurpose reviewを続行しません。

## Purpose-only source rejection

round 2/3でlocal reviewer、Copilot wait、non-`PUR-*` actionable sourceを追加しません。current purpose reviewerのraw outputと、全active `TRK-*`のexplicit `persistent | resolved` assessmentだけを使います。

## Round 3 still has active findings

`HumanDecisionRequired`で停止します。automatic round 4、empty close、黙示的受容は行いません。

## Notification did not arrive

notification failureはreview verdictを変更しません。terminal response末尾に`completion-notification.txt`のfenced blockがverbatimで一度だけ含まれることを確認し、run summaryとcurrent PR URL、runtime/providerを診断します。thread/turn IDをterminal projectionへ追加しません。

## Historical cycle validation

既存`review-cycle.json`の監査は`manage-review-cycle.cs validate`を使います。historical fixed-task contractを修正してcanonical same-parent runへ変換しません。
