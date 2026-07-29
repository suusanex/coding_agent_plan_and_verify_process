---
name: goal-context-pr-review
description: Use when a user wants a Goal Context-aware PR review that independently evaluates code quality and purpose achievement, consolidates all review sources into an Adaptive-ready plan, then stops for a separate manual implementation turn.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Goal Context PR Review

このSkillは、基礎版`pr-review-remediation`のcollector、`local-reviewer`、`review-planner`、Adaptive handoffを共有し、Goal Context Authoring Skillのcanonical validatorで選択・検証済みのGoal Contextと独立した`purpose-reviewer`を追加するPhase 1入口です。

Goal Contextが欠落・不正・曖昧な場合はIssue本文だけで目的reviewを代替せず停止します。目的reviewなしで進める場合、利用者が基礎版`$pr-review-remediation`を明示選択します。

## Required inputs and agents

- 基礎版Skillが要求するGitHub、repository、PR、.NET、APM環境
- Issueまたは要求
- 対応する`goal-context-*.md`、または候補を探すsearch root
- APMで導入された`local-reviewer`、`purpose-reviewer`、`review-planner`
- 対象repositoryの規約とvalidation手順

## Phase 1

### 1. Prepare and collect the PR

`../pr-review-remediation/SKILL.md`のPhase 1 steps 1-2を実行します。Ready PRのbase/head identityを確定し、共有collectorを使います。

```powershell
dotnet run --file ../pr-review-remediation/scripts/collect-pr-review-context.cs -- --repo owner/name --pr 123 --out .review/pr-123
```

Draft、identity drift、Copilot timeoutのfail-closed rulesを変更しません。

### 2. Select and validate Goal Context

exact pathがある場合:

```powershell
dotnet run --file scripts/select-goal-context.cs -- --repository-root . --goal-context docs/goal-context-example.md --out .review/pr-123/goal-context-selection.json
```

search rootから一意候補を選ぶ場合:

```powershell
dotnet run --file scripts/select-goal-context.cs -- --repository-root . --search-root docs --out .review/pr-123/goal-context-selection.json
```

候補が0件、不正、複数、または既定lifecycleを満たさない場合は停止します。複数候補からfilename、Issue番号、更新時刻で推測しません。draft利用は、利用者がexact pathを指定し`--allow-draft`を明示した場合だけ許可し、そのoverrideをartifactへ残します。

### 3. Run independent reviews

`local-reviewer`へ基礎版と同じPR identity、context、patch、repository rulesを渡し、`<out>/local-review-findings.md`を作ります。

`purpose-reviewer`へ次を渡し、返却を`templates/purpose-review-findings.md`の形で`<out>/purpose-review-findings.md`へ保存します。

- PR identity、context、remote patch
- Issueまたは要求
- `goal-context-selection.json`とpath／正規化SHA-256が一致するGoal Context
- repository rulesと必要なvalidation results

両agentはread-onlyです。可能なら独立に実行しますが、どちらかの結果をもう一方の前提にしません。multi-roundで継続するのは親Review Threadであり、子agent threadの再利用は要求しません。各子agentは現在roundの正本artifactだけで判定し、code-quality findingをpurpose reviewへ吸収しません。

### 4. Build the integrated review plan

共有`review-planner`へ、基礎版inputに加えてGoal Context selection、Goal Context、`purpose-review-findings.md`を渡します。共有`../pr-review-remediation/templates/review-plan.md`へ適合する`<out>/review-plan.md`を保存します。

plannerはCopilot、local、purpose、PR comments、inline comments、checksをsource ID付きで統合し、各findingの`Apply | Hold | Reject`と理由、duplicate、conflict、修正順序、scope、Non-goals、acceptance、未取得、未検証、human decisionを記録します。

次も満たす場合だけ`READY_FOR_ADAPTIVE_IMPLEMENTATION`です。

- Goal Context selectionが`SELECTED`で、canonical validation contract version、mode、正規化SHA-256が記録されている
- purpose reviewが`PURPOSE_REVIEWED`
- Original problem、Desired outcome、user scenarios、MVP、Non-goals、rejected alternatives、wrong outcomesがplanへ反映される
- Goal Contextにない要求を追加していない
- blocking unknownをopen questionまたはhuman decisionとして残している
- canonical `implementation_intent`が固定されたImplementation Threadの明示ターンへ直接渡せる
- `Production code changed: No`

### 5. Stop and notify

single-round modeのPhase 1 verdictは`READY_FOR_ADAPTIVE_IMPLEMENTATION | HUMAN_DECISION_REQUIRED | BLOCKED`です。plan生成後は必ず親ターンを停止し、Adaptiveを内部呼び出ししません。

`$completion-notification-decorator`が同じ入力で選択されている場合、最終応答へ一つだけenvelopeを追加します。`observed_status`はPhase 1 verdictをそのまま使い、`result_uri`は対象PRの直接URLにします。通知失敗でreview verdictを変えません。

```completion-notification
{"schema_version":1,"primary_process":"goal-context-pr-review","observed_status":"READY_FOR_ADAPTIVE_IMPLEMENTATION","title":"Goal Context PR review planning completed","repository":"owner/repository","result_uri":"https://github.com/owner/repository/pull/123"}
```

## Phase 2

利用者が通知から戻り、Review Threadとは別のImplementation Threadを再開して新しい親ターンを明示開始します。同じPRの後続修正でもこのImplementation Threadを再利用し、新規taskは通常作成しません。

```text
$completion-notification-decorator
$adaptive-implementation-execution

.review/pr-123/review-plan.mdを実装してください。
review-plan.mdのimplementation_intentをsource of truthとし、Goal Context Boundaryを保持してください。
```

このSkillは新しいimplementation agent、route、result schemaを持ちません。

## Explicit multi-round mode

利用者が複数roundのレビュー・修正サイクルを明示した場合だけ、single-round成果物を`.review/pr-123/round-001/`以降へ保存し、`.review/pr-123/review-cycle.json`でround間の証拠を管理します。既存single-round呼び出しは従来どおり`.review/pr-123/`を使い、このcycle管理を必須にしません。

各roundの開始前に、最新base/head、canonical Goal Context identity、現在のReview Thread IDを指定して`manage-review-cycle.cs start`を実行します。通常の`role-thread-reuse`ではround 1にReview ThreadとImplementation ThreadをPR単位で固定し、round 2以降も同じReview Threadの新しい明示ターンで開始します。round 2以降は、固定されたImplementation Threadの別ターンで完了したAdaptive result referenceとAdaptive Thread IDが必須です。同じhead OIDの再reviewは拒否します。

```powershell
dotnet run --file scripts/manage-review-cycle.cs -- start `
  --cycle .review/pr-123/review-cycle.json `
  --repository owner/repository --pr 123 `
  --goal-context-path docs/goal-context-example.md --goal-context-sha <sha256> `
  --base-oid <base-oid> --head-oid <head-oid> --started-at <ISO-8601> `
  --review-thread-id <review-task-id> --implementation-thread-id <implementation-task-id> `
  --adaptive-result-reference <previous-adaptive-result> --adaptive-thread-id <implementation-task-id>
```

round 1ではAdaptive関連optionを省略します。初回実装taskが存在しない場合は、actionable review planを完了する前にImplementation Threadを作成し、`bind-thread`で理由、承認者、timezone付き承認時刻とともに登録します。threadを失った場合は`rebind-thread`を使い、旧bindingを履歴から削除しません。artifactだけで新規taskへ移管する`portable-handoff`は、理由と人間承認を明示した復旧・可搬性経路だけに使います。

round 1の`reviewMode`は`full`です。共有collectorでCopilotレビューを待機・収集し、`local-reviewer`と`purpose-reviewer`を独立に実行してplannerへ渡します。

round 2以降の`reviewMode`は`purpose-only`です。collectorは`--no-wait-for-copilot`で最新identity、正本patch、checks、既存sourceを取得しますが、Copilotレビューの開始・待機は行いません。`local-reviewer`も実行せず、`local-findings` artifactを生成しません。既存および新規のreview/comment/check sourceは監査証跡として理由付き`noAction`へ対応させ、remediation findingへ直接変換しません。`purpose-reviewer`は現在patchと前回planを評価し、前roundまでの全active tracking IDを`Prior Finding Assessment`で`persistent | resolved`へ遷移させます。新規、再open、persistentのactionable findingは現在roundの`PUR-*`だけを使用します。

Goal Context selection、必要なreview findings、machine-readable `review-result.json`、notificationを現在の`round-NNN/`へ保存します。`review-plan.md`はverdictが`READY_FOR_ADAPTIVE_IMPLEMENTATION`の場合だけ保存します。`HUMAN_DECISION_REQUIRED`では実行可能plan、`implementation_intent`、Adaptive handoffを出力しません。schema version 2の`reviewMode`、thread mode／role binding／binding履歴、artifact hash、review-contextのrepository/PR/base/headと全source ID、collectorが指定したremote patch path、Goal Context path/hash、review-resultのverdict/finding delta/source coverage/artifact bindingsを`complete`で相互照合します。schema version 1のcycleは履歴検証だけを許可し、roundを追記しません。Adaptiveへ渡すplanはcanonical `implementation_intent`、SI/AC付きordered remediation、全active finding mapping、同じplan reference、対象Implementation Threadとreturn先Review Threadを使う明示ターンhandoffを含めます。plan hashはround manifestのartifact bindingを正本にします。ordered remediationとintentのSI/AC集合は双方向に完全一致させ、未追跡scopeを追加しません。

cycle rootはsymlink/junctionにできません。cycle file、round directory、artifact fileを含む既存path componentは実体pathへ解決し、cycle root外へ出るinput/output linkをfail closedにします。

```powershell
dotnet run --file scripts/manage-review-cycle.cs -- complete `
  --cycle .review/pr-123/review-cycle.json `
  --round-result .review/pr-123/round-002/round-result.json --format json
```

multi-round verdictは次のとおりです。

- actionable findingがなくなった: `REVIEW_COMPLETE`。空のAdaptive planを作らず停止する。
- actionable findingがあり、現在roundが有効上限未満: `READY_FOR_ADAPTIVE_IMPLEMENTATION`。固定Implementation Threadの新しい明示ターン用handoffを提示して停止する。
- 既定第3roundでactionable findingが残る: `HUMAN_DECISION_REQUIRED`。Adaptive handoffを生成せず、自動継続しない。
- 必須artifact不足などで安全に確定できない: `BLOCKED`。

`HUMAN_DECISION_REQUIRED`後は、利用者が状況を確認して継続を明示した場合だけ、plannerへdecisionと現在roundのfinding deltaを渡して承認用plan候補を作ります。候補のstatusは`APPROVED_FOR_ADAPTIVE_IMPLEMENTATION`、`plan_reference`は`round-NNN/approved-review-plan.md`とします。候補だけではAdaptiveを開始できません。cycle managerの独立した`resolve`操作がpending decision ID、resolution、承認者、承認時刻、plan内容とhashを検証し、canonical planへ非上書きで保存した後にだけ、固定Implementation Threadの明示ターンhandoffが有効になります。

第4round以降は、`resolve`時に直前の上限到達decisionと利用者の明示overrideをすべて記録した場合だけ、承認済みplanをAdaptiveへ渡せます。overrideはround 1〜3の開始時や、上限未到達decisionでは受理されません。

```powershell
dotnet run --file scripts/manage-review-cycle.cs -- resolve `
  --cycle .review/pr-123/review-cycle.json `
  --resolve-decision HD-003 --decision-resolution <resolution> `
  --decision-approved-by <identity> --decision-approved-at <ISO-8601> `
  --approved-plan <approved-plan-candidate> `
  --override-maximum-rounds 4 --override-approved-by <identity> `
  --override-approved-at <ISO-8601> --override-reason <reason>
```

`resolve`が`APPROVED_FOR_ADAPTIVE_IMPLEMENTATION`を返した後、利用者が同じImplementation Threadの新しい親ターンで`round-003/approved-review-plan.md`をAdaptiveへ渡します。Adaptive完了後、同じReview Threadへ戻り、次の明示親ターンで通常の`start --adaptive-result-reference <result> --adaptive-thread-id <implementation-task-id>`を実行します。`start`はdecision resolutionやoverrideを受理しません。

`complete`後はCompletion Notification Decoratorでそのroundのverdict、対象PR直接URL、現在のReview Threadへの復帰手段を通知し、必ず停止します。このDecoratorはcycleを進めず、review SkillもAdaptive Implementationや次roundを内部起動しません。次roundは利用者が同じReview Threadを再開し、別の明示親ターンとして開始します。

## Relative and shared assets

- `scripts/select-goal-context.cs`
- `scripts/manage-review-cycle.cs`
- `templates/purpose-review-findings.md`
- `templates/review-result.example.json`
- `templates/review-round-result.example.json`
- `references/design.md`
- `references/usage.md`
- `references/troubleshooting.md`
- shared: `../pr-review-remediation/scripts/collect-pr-review-context.cs`
- shared: `../pr-review-remediation/templates/local-review-findings.md`
- shared: `../pr-review-remediation/templates/review-plan.md`
