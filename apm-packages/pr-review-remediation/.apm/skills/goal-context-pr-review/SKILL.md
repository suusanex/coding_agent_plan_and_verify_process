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

両agentはread-onlyです。可能なら独立に実行しますが、どちらかの結果をもう一方の前提にしません。code-quality findingをpurpose reviewへ吸収しません。

### 4. Build the integrated review plan

共有`review-planner`へ、基礎版inputに加えてGoal Context selection、Goal Context、`purpose-review-findings.md`を渡します。共有`../pr-review-remediation/templates/review-plan.md`へ適合する`<out>/review-plan.md`を保存します。

plannerはCopilot、local、purpose、PR comments、inline comments、checksをsource ID付きで統合し、各findingの`Apply | Hold | Reject`と理由、duplicate、conflict、修正順序、scope、Non-goals、acceptance、未取得、未検証、human decisionを記録します。

次も満たす場合だけ`READY_FOR_ADAPTIVE_IMPLEMENTATION`です。

- Goal Context selectionが`SELECTED`で、canonical validation contract version、mode、正規化SHA-256が記録されている
- purpose reviewが`PURPOSE_REVIEWED`
- Original problem、Desired outcome、user scenarios、MVP、Non-goals、rejected alternatives、wrong outcomesがplanへ反映される
- Goal Contextにない要求を追加していない
- blocking unknownをopen questionまたはhuman decisionとして残している
- canonical `implementation_intent`が別親ターンのAdaptiveへ直接渡せる
- `Production code changed: No`

### 5. Stop and notify

single-round modeのPhase 1 verdictは`READY_FOR_ADAPTIVE_IMPLEMENTATION | HUMAN_DECISION_REQUIRED | BLOCKED`です。plan生成後は必ず親ターンを停止し、Adaptiveを内部呼び出ししません。

`$completion-notification-decorator`が同じ入力で選択されている場合、最終応答へ一つだけenvelopeを追加します。`observed_status`はPhase 1 verdictをそのまま使い、`result_uri`は対象PRの直接URLにします。通知失敗でreview verdictを変えません。

```completion-notification
{"schema_version":1,"primary_process":"goal-context-pr-review","observed_status":"READY_FOR_ADAPTIVE_IMPLEMENTATION","title":"Goal Context PR review planning completed","repository":"owner/repository","result_uri":"https://github.com/owner/repository/pull/123"}
```

## Phase 2

利用者が通知から戻り、別の親ターンで明示開始します。

```text
$completion-notification-decorator
$adaptive-implementation-execution

.review/pr-123/review-plan.mdを実装してください。
review-plan.mdのimplementation_intentをsource of truthとし、Goal Context Boundaryを保持してください。
```

このSkillは新しいimplementation agent、route、result schemaを持ちません。

## Explicit multi-round mode

利用者が複数roundのレビュー・修正サイクルを明示した場合だけ、single-round成果物を`.review/pr-123/round-001/`以降へ保存し、`.review/pr-123/review-cycle.json`でround間の証拠を管理します。既存single-round呼び出しは従来どおり`.review/pr-123/`を使い、このcycle管理を必須にしません。

各roundの開始前に、最新base/headとcanonical Goal Context identityを指定して`manage-review-cycle.cs start`を実行します。round 2以降は、別の親ターンで完了したAdaptive result referenceが必須です。同じhead OIDの再reviewは拒否します。

```powershell
dotnet run --file scripts/manage-review-cycle.cs -- start `
  --cycle .review/pr-123/review-cycle.json `
  --repository owner/repository --pr 123 `
  --goal-context-path docs/goal-context-example.md --goal-context-sha <sha256> `
  --base-oid <base-oid> --head-oid <head-oid> --started-at <ISO-8601> `
  --adaptive-result-reference <previous-adaptive-result>
```

collector、Goal Context selection、local/purpose findings、machine-readable `review-result.json`、notification、およびactionable findingがある場合のreview planを現在の`round-NNN/`へ保存します。`templates/review-result.example.json`と`templates/review-round-result.example.json`を埋め、`complete`でartifact hashだけでなく、review-contextのrepository/PR/base/headと全source ID、Goal Context path/hash、review-resultのverdict/finding delta/source coverage/artifact bindingsを相互照合します。source coverageはfinding deltaから導出したsource-to-tracking mappingと双方向に一致しなければなりません。Adaptiveへ渡すplanはcanonical `implementation_intent`、SI/AC付きordered remediation、全active finding mapping、および同じplan referenceを使う別親ターンhandoffを含めます。

cycle rootはsymlink/junctionにできません。cycle file、round directory、artifact fileを含む既存path componentは実体pathへ解決し、cycle root外へ出るinput/output linkをfail closedにします。

```powershell
dotnet run --file scripts/manage-review-cycle.cs -- complete `
  --cycle .review/pr-123/review-cycle.json `
  --round-result .review/pr-123/round-002/round-result.json --format json
```

multi-round verdictは次のとおりです。

- actionable findingがなくなった: `REVIEW_COMPLETE`。空のAdaptive planを作らず停止する。
- actionable findingがあり、現在roundが有効上限未満: `READY_FOR_ADAPTIVE_IMPLEMENTATION`。別親ターン用handoffを提示して停止する。
- 既定第3roundでactionable findingが残る: `HUMAN_DECISION_REQUIRED`。自動継続しない。
- 必須artifact不足などで安全に確定できない: `BLOCKED`。

`HUMAN_DECISION_REQUIRED`後は、cycleが発行したpending decision IDに対応するresolution、承認者、承認時刻を記録しない限り、Adaptive result referenceがあっても次roundを開始できません。

第4round以降は、直前の上限到達decisionを解決し、利用者の明示overrideをすべて記録した場合だけ開始できます。overrideはround 1〜3では受理されません。

```powershell
dotnet run --file scripts/manage-review-cycle.cs -- start `
  --cycle .review/pr-123/review-cycle.json `
  --repository owner/repository --pr 123 `
  --goal-context-path docs/goal-context-example.md --goal-context-sha <sha256> `
  --base-oid <base-oid> --head-oid <head-oid> --started-at <ISO-8601> `
  --adaptive-result-reference <previous-adaptive-result> `
  --resolve-decision HD-003 --decision-resolution <resolution> `
  --decision-approved-by <identity> --decision-approved-at <ISO-8601> `
  --override-maximum-rounds 4 --override-approved-by <identity> `
  --override-approved-at <ISO-8601> --override-reason <reason>
```

`complete`後はCompletion Notification Decoratorでそのroundのverdictと対象PR直接URLを通知し、必ず停止します。このDecoratorはcycleを進めず、review SkillもAdaptive Implementationや次roundを内部起動しません。次roundは利用者が別のCodex親ターンで明示開始します。

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
