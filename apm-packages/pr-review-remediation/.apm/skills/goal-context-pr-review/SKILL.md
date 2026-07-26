---
name: goal-context-pr-review
description: Use when a user wants a Goal Context-aware PR review that independently evaluates code quality and purpose achievement, consolidates all review sources into an Adaptive-ready plan, then stops for a separate manual implementation turn.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Goal Context PR Review

このSkillは、基礎版`pr-review-remediation`のcollector、`local-reviewer`、`review-planner`、Adaptive handoffを共有し、選択・検証済みGoal Contextと独立した`purpose-reviewer`を追加するPhase 1入口です。

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
- `goal-context-selection.json`と選択されたGoal Context
- repository rulesと必要なvalidation results

両agentはread-onlyです。可能なら独立に実行しますが、どちらかの結果をもう一方の前提にしません。code-quality findingをpurpose reviewへ吸収しません。

### 4. Build the integrated review plan

共有`review-planner`へ、基礎版inputに加えてGoal Context selection、Goal Context、`purpose-review-findings.md`を渡します。共有`../pr-review-remediation/templates/review-plan.md`へ適合する`<out>/review-plan.md`を保存します。

plannerはCopilot、local、purpose、PR comments、inline comments、checksをsource ID付きで統合し、各findingの`Apply | Hold | Reject`と理由、duplicate、conflict、修正順序、scope、Non-goals、acceptance、未取得、未検証、human decisionを記録します。

次も満たす場合だけ`READY_FOR_ADAPTIVE_IMPLEMENTATION`です。

- Goal Context selectionが`SELECTED`
- purpose reviewが`PURPOSE_REVIEWED`
- Original problem、Desired outcome、user scenarios、MVP、Non-goals、rejected alternatives、wrong outcomesがplanへ反映される
- Goal Contextにない要求を追加していない
- blocking unknownをopen questionまたはhuman decisionとして残している
- canonical `implementation_intent`が別親ターンのAdaptiveへ直接渡せる
- `Production code changed: No`

### 5. Stop and notify

Phase 1 verdictは`READY_FOR_ADAPTIVE_IMPLEMENTATION | HUMAN_DECISION_REQUIRED | BLOCKED`です。plan生成後は必ず親ターンを停止し、Adaptiveを内部呼び出ししません。

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

## Relative and shared assets

- `scripts/select-goal-context.cs`
- `templates/purpose-review-findings.md`
- `references/design.md`
- `references/usage.md`
- `references/troubleshooting.md`
- shared: `../pr-review-remediation/scripts/collect-pr-review-context.cs`
- shared: `../pr-review-remediation/templates/local-review-findings.md`
- shared: `../pr-review-remediation/templates/review-plan.md`

