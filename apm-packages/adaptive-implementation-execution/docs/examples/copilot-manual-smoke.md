# GitHub Copilot Chat in VS Code Manual Smoke

このrunbookはstatic fixtureで検証できない実model、agent picker、handoff buttonを確認します。未実行項目をPASSにしません。

## Setup

1. disposable repositoryと開始commitを固定する。
2. candidate commitのAdaptive 0.6.0をAPM installする。
3. implementationでdecision surfaceが解消されるfixture、inspection-only transfer fixture、natural first-owner completion fixture、re-entry fixtureを用意する。
4. secret、課金操作、production変更をfixtureへ含めない。
5. write-heavy ownerを同時に実行しない。

## Scenario 0: Explicit invocation

- 通常の「実装して」でSkillが自動選択されない
- 自然文の名前言及でも自動選択されない
- `/adaptive-implementation-execution`で利用者起動できる

## Scenario 1: Decision-surface implementation

1. `decision-surface-implementation-owner`を選ぶ。
2. requested / observed modelを記録する。
3. ownerがproduction code、tests、wiring、focused verificationを必要に応じて実行する。
4. implementation結果からDecision surface assessmentを更新する。
5. code editを避けることや一定量書くことを目的にしない。

## Scenario 2: Inspection-only transfer

1. 既存patternにより残作業が実質一意なfixtureを使う。
2. actual code evidenceとcomplete handoffがある場合だけ`READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION`を受理する。
3. code editなしを成功条件にしない。

## Scenario 3: Natural completion

1. decision surfaceがimplementation完了まで残るfixtureを使う。
2. first ownerが不自然な途中状態を作らず`IMPLEMENTATION_COMPLETED`を返す。
3. transfer例外理由が要求されないことを確認する。

## Scenario 4: Bounded residual and re-entry

1. valid tracked handoff後だけ`bounded-residual-implementation-owner`へ移る。
2. locked semanticsの適用だけで完了するcaseは`IMPLEMENTATION_COMPLETED`になる。
3. 新しいdecision surfaceが開くcaseはtracked `NEEDS_DECISION_SURFACE_REENTRY`になる。
4. 元handoff、re-entry handoff、route identity、worktreeを渡してfirst ownerへ戻る。

## Negative checks

- old 0.5 handoffとold agent名は拒否する
- incomplete assessmentや`Open` concernではtransferしない
- edit typeだけではre-entryしない
- invalid route identityを補完しない
- stop verdictとcompletionではunexpected handoffしない

## Evidence record

| Phase | Semantic role | Selected agent | Requested model | Observed model | Files changed | Validation | Verdict | Unexpected transition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Initial owner | Decision-Surface Implementation Owner | NOT RUN | Terra | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Residual owner | Bounded-Residual Implementation Owner | NOT RUN | Luna | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Re-entry | Decision-Surface Implementation Owner | NOT RUN | Terra | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

## Completion decision

- semantic role and runtime topology remained distinct: NOT RUN
- required implementation was not deferred merely to create a transfer: NOT RUN
- valid bounded residual transfer only: NOT RUN
- natural first-owner completion accepted: NOT RUN
- new decision surface returned to first owner: NOT RUN
- terminal verdict: NOT RUN

実行環境が必要: 利用可能なCopilot環境で観測し、requested / observed model差異を記録する。未観測behaviorをPASSにしない。
