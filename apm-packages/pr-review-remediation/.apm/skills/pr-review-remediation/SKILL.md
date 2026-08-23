---
name: pr-review-remediation
description: Use when a user explicitly wants a Ready GitHub PR reviewed from remote PR review evidence, converted into a remediation plan, and stopped before a separate Adaptive Implementation turn.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# PR Review Remediation

このSkillは、Goal Contextを使わないbaseline PR reviewの入口です。GitHub上のReady PRに紐付くreview、inline comment、PR comment、checkを収集し、別の明示turnでAdaptive Implementationへ渡せるreview planを作成して停止します。

repository外のlocal agent reviewerは起動しません。目的達成reviewと同一parent内の修正roundが必要な場合は、別packageの`$persistent-purpose-review`を明示的に使います。

## Required tools and inputs

- GitHub CLIと対象repositoryを読み書きでき、GitHub上のreviewを要求できる認証
- File-based Appsを実行できる.NET 10 SDK以降
- APMで導入された`review-planner`
- repository、Ready PR番号または現在branch、出力先。既定出力先は`.review/pr-<number>`
- 対象repositoryの`AGENTS.md`、README、build/test手順
- Phase 2を開始する場合だけ、別途導入した`adaptive-implementation-execution`

## Phase 1

### 1. Prepare a Ready PR

1. repository root、current branch、base candidate、working tree、upstream、push状態、既存PRを確認する。
2. 未commit変更へ無関係な差分があれば混在させない。
3. 必要なら通常branchを作り、対象変更をcommit、pushして通常PRを作る。Draft PRを作成しない。
4. 既存PRがDraftなら自動でReadyへ変更せず、`人手での作業が必要: PRをReady for reviewに変更してください。`と返す。
5. repository、PR番号、base/head branch、base/head OIDを確定する。以後はremote PR diffだけをreview対象にする。

### 2. Request and collect remote review evidence

GitHub上のreviewを明示要求します。標準review sourceはGitHub Copilot Code Reviewです。

```powershell
gh pr edit 123 --repo owner/name --add-reviewer @copilot
```

要求が権限、policy、利用条件によって失敗した場合は、未取得reviewを「findingsなし」に変換せず`BLOCKED`で停止します。成功後、Skill内のcollectorを実行します。

```powershell
dotnet run --file .agents/skills/pr-review-remediation/scripts/collect-pr-review-context.cs -- --repo owner/name --pr 123 --out .review/pr-123
```

生成物:

- `review-context.json`
- `review-context.md`
- `pr-diff.patch`

collectorがDraft、base/head drift、GitHub CLI失敗、不正JSON、permission failureを報告した場合は推測で続行しません。`waitStatus: timeout`、`observedReviewState: none`、`UNOBSERVABLE`も「指摘なし」ではありません。利用者が未取得reviewでも進むと明示しない限り`HUMAN_DECISION_REQUIRED`とします。

### 3. Build the remediation plan

`review-planner`へ次を渡します。

- 確定したPR identity
- `review-context.json`または`review-context.md`
- `pr-diff.patch`
- repository instructionsとvalidation手順
- 未取得sourceについて利用者が行った明示判断

返却内容を`templates/review-plan.md`の形で`<out>/review-plan.md`へ保存します。

すべてのremote finding/comment/checkにsource IDを維持し、`Apply | Hold | Reject`と理由を付けます。duplicate/conflict、remediation scope、acceptance、`implementation_intent`、human decision、blockerを隠しません。

Phase 1 verdictは`READY_FOR_ADAPTIVE_IMPLEMENTATION | HUMAN_DECISION_REQUIRED | BLOCKED`のいずれかです。次をすべて満たす場合だけ`READY_FOR_ADAPTIVE_IMPLEMENTATION`を受理します。

- PR identityがcollector outputと一致する
- 必須remote review sourceが取得済み、または未取得でも進む利用者の明示判断が記録されている
- 全source IDがdecision ledgerまたは理由付き`noAction`へ対応する
- すべての`Apply` findingがscopeまたはacceptanceへmappedしている
- `implementation_intent.goal`、`scope`、`acceptance`が存在する
- blocking conflict、product判断不足、head driftがない
- `Production code changed: No`

### 4. Stop the parent turn

`READY_FOR_ADAPTIVE_IMPLEMENTATION`でもAdaptiveを起動しません。成果物path、Phase 1 verdict、未取得・未検証事項、人手作業、次のpromptを報告して親ターンを終了します。

## Phase 2

利用者が別の明示turnでreview planを実装すると指示した場合だけ、別途導入した`$adaptive-implementation-execution`へ渡します。このSkillはimplementation agent、model route、result schema、purpose review、reviewer sessionを所有しません。

```text
$adaptive-implementation-execution を使って .review/pr-123/review-plan.md を実装してください。
review-plan.md の implementation_intent を source of truth とし、既存Adaptive Implementationのrouter、agents、verdict、handoff、validation contractを変更または複製しないでください。
```

## Relative assets

- `scripts/collect-pr-review-context.cs`
- `templates/review-plan.md`
- `references/usage.md`
- `references/migration.md`
- `references/troubleshooting.md`
