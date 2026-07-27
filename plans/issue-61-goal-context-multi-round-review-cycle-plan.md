# Issue #61 Goal Context multi-round review cycle implementation plan

## Source of truth

- Issue #61のGoal、Scope、Acceptance criteria、Non-goals
- `docs/goal-context-multi-project-ai-development-notification-and-purpose-review.md`の3.1、9、10、および手動工程境界
- PR #60で導入された`goal-context-pr-review`、`purpose-reviewer`、`review-planner`、Adaptive handoff、Completion Notification Decorator

## Compatibility and responsibility boundary

- 既存の単一round `$goal-context-pr-review`は、従来の`.review/pr-<number>/`、`READY_FOR_ADAPTIVE_IMPLEMENTATION | HUMAN_DECISION_REQUIRED | BLOCKED`、別親ターンhandoffを維持する。
- multi-round modeは利用者が明示した場合、または`.review/pr-<number>/review-cycle.json`が存在する場合だけ有効にする。
- review Skillはround reviewを完了して停止し、Adaptive Implementationを内部起動しない。
- Adaptive完了後の次roundも利用者が別親ターンで明示開始する。
- Completion Notification Decoratorは各親ターンのterminal verdictとdirect linkを通知するだけで、cycle stateや次工程を所有しない。
- Adaptive Implementationのrouter、agent、verdict、handoff、validation contractは変更・複製しない。

## Implementation surfaces

### 1. Review-cycle state manager

File-based C# app `manage-review-cycle.cs`をGoal Context review Skillへ追加する。`.csproj`は作成しない。

Commands:

- `start`: identity、Goal Context、前round、上限、overrideを検証し、新しい`round-NNN/`とin-progress round recordを作る。
- `complete`: round result、artifact hash、finding delta、notificationを検証し、verdictとcycle ledgerを確定する。
- `validate`: committed cycleと全historical artifact hash、finding history、round identityを読み取り検証する。

共通exit codeは0=success、2=contract violation、1=runtime errorとし、`--format json|text`を提供する。

### 2. Artifact schema

`.review/pr-<number>/review-cycle.json` schema version 1:

- repository、pullRequest
- Goal Context path、normalized SHA-256
- defaultMaximumRounds: 3
- effectiveMaximumRounds
- currentRound、status
- overrides: approvedBy、approvedAt、reason、maximumRounds
- rounds:
  - roundNumber、artifactDirectory
  - base/head OID
  - previousRound
  - startedAt、completedAt
  - verdict
  - previous Adaptive result reference
  - actionable finding count
  - artifact role/path/normalized SHA-256
  - notification round number/observed status/result URI
  - finding delta
  - source coverage: sourceId、finding tracking IDsまたは理由付きnoAction
- findingLedger:
  - trackingId
  - currentState、lastRound
  - round別history、finding IDs、source IDs
- humanDecisions

各`round-NNN/round-result.json` schema version 1:

- roundNumber、base/head OID、completedAt
- optional humanDecisionReason
- artifact manifest
- notification envelope projection
- findingDelta entries
  - trackingId
  - state: `new | persistent | resolved | reopened`
  - findingIds
  - sourceIds
- sourceCoverage entries
  - sourceId
  - disposition: `finding | noAction`
  - trackingIdsまたはnoAction reason

round-result自身はstate managerがhashを計算してcycle manifestへ加える。全artifact pathは対象round directory内に限定する。

### 3. Verdict transition

| Condition | Verdict | Adaptive plan |
| --- | --- | --- |
| actionable=0、blocking human decisionなし | `REVIEW_COMPLETE` | 生成しない |
| actionable>0、round < effective maximum | `READY_FOR_ADAPTIVE_IMPLEMENTATION` | 必須 |
| actionable>0、round >= effective maximum | `HUMAN_DECISION_REQUIRED` | 人間が継続判断できるplanは保持するが、自動handoffしない |
| finding同一性、scope等に明示的human decisionが必要 | `HUMAN_DECISION_REQUIRED` | 状況に応じて保持 |
| identity drift、必須artifact欠落、Goal Context不正 | `BLOCKED` | 生成しない |

第3roundでactionable findingが残る場合、既定では`READY_FOR_ADAPTIVE_IMPLEMENTATION`を禁止する。第4round以降の`start`は、記録済みまたは同時指定されたmaximum-round overrideと、前roundを反映したAdaptive result referenceを要求する。

### 4. Finding transition rules

- round 1は`new`だけを許可する。
- `persistent`は直前までactiveだったtracking IDだけを許可する。
- `resolved`は直前までactiveだったtracking IDだけを許可する。
- `reopened`はledger上で`resolved`になったtracking IDだけを許可する。
- 前roundのactive findingは、次roundで`persistent`または`resolved`のいずれかへ必ず対応させる。
- 文章類似度による自動対応は行わず、plannerがstable tracking IDまたは明示mappingを出す。
- finding IDsとreview/comment/check source IDsを各history entryへ保存する。

### 5. Skill, agent, template, documentation

- `goal-context-pr-review/SKILL.md`: explicit multi-round mode、round start/complete、停止条件、overrideを追加する。
- `review-planner.agent.md`: multi-round input、delta分類、`REVIEW_COMPLETE`、round-limit verdictを追加する。
- shared `review-plan.md`: optional Round StateとFinding Deltaを追加し、Baseline／single-roundでは省略可能と明記する。
- multi-round用`round-result` example schemaを追加する。
- usage/design/troubleshooting、package README、root READMEへmanual parent-turn sequenceとoverride CLIを追加する。
- Completion Notification DecoratorとAdaptive packageには変更を加えない。

## Fixtures and negative tests

`tests/pr-review-remediation/PRR-003/`を追加し、modelを呼ばないdeterministic cycle replayを行う。

Positive scenarios:

1. round 1 new finding → Adaptive result → round 2 persistent/new finding → Adaptive result → round 3 resolved → `REVIEW_COMPLETE`
2. round 1-3でpersistent findingが残り、round 3が`HUMAN_DECISION_REQUIRED`
3. human overrideでmaximum roundsを4へ変更し、Adaptive result後にround 4を開始
4. `new → resolved → reopened → resolved`のtracking history
5. 各roundのnotificationが対象PR direct URLを保持
6. 既存PRR-002 single-round replayが変更なしで成功

Negative scenarios:

- 同一head OIDでの重複round
- `round-NNN/`の既存directoryへの上書き
- historical artifact改変／hash mismatch
- round 4をoverrideなしで開始
- overrideの承認者、日時、理由、新上限の欠落
- round 3 actionableで`READY_FOR_ADAPTIVE_IMPLEMENTATION`を宣言
- actionable=0でAdaptive planを添付
- active findingのdelta欠落
- invalid `persistent`／`resolved`／`reopened` transition
- previous Adaptive result reference欠落
- repository／PR／base-head／Goal Context identity drift
- notification statusまたはdirect link不一致

## Verification

- cycle managerのpositive／negative replay
- PRR-003 contract fixture validation
- PRR-002 deterministic replayと既存PR Review Remediation validator
- Goal Context Authoring、Adaptive Implementation、Completion Notificationの既存validator
- File-based appの`dotnet publish`
- remote APM install smokeでcycle managerとtemplateの配布・起動確認
- `git diff --check origin/<stacked-base>...HEAD`
- GitHub Actionsの成功確認

## Delivery

- PR #60 headから`codex/issue-61-goal-context-multi-round-review`を作成する。
- stacked PRのbaseは`codex/issue-55-goal-contextpr`とする。
- PR本文に`Fixes #61`、追加verdict、default maximum 3、override方法、検証結果、PR #60 dependencyを記載する。
