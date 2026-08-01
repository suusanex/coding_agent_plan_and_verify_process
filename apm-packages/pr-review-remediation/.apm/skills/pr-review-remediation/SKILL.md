---
name: pr-review-remediation
description: Use when a user explicitly wants the baseline PR review flow without Goal Context purpose review: prepare a GitHub PR, consolidate local Codex and GitHub Copilot reviews, create a remediation plan, then stop before a separate Adaptive turn.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# PR Review Remediation

このSkillは、Goal Contextを使わない基礎版入口です。PRを成立させ、local Codex reviewとGitHub Copilot reviewを統合し、別の親ターンで既存Adaptive Implementationが修正を実装できるplanを作る二親ターンのレビュー反映workflowです。

Goal Contextによる目的達成reviewが必要な場合は`$goal-context-pr-review`を使います。この基礎版をGoal Context欠落時に暗黙選択せず、利用者が目的reviewなしで進めることを明示した場合だけ使います。

Phase 1の停止点はprocess boundaryであり、レビュー反映全体の完了ではありません。Phase 1からAdaptiveを自動起動せず、利用者がPhase 2を明示的に開始します。

## Required tools and inputs

- GitHub CLIと対象repositoryを読書きでき、Copilot reviewerを要求できる認証
- File-based Appsを実行できる.NET 10 SDK以降
- APMで導入された`local-reviewer`、`review-planner`
- Phase 2を開始する場合だけ、別途導入したoptional `adaptive-implementation-execution`
- repository、PR番号または現在branch、出力先。既定出力先は`.review/pr-<number>`
- 対象repositoryの`AGENTS.md`、README、build/test手順

## Phase 1

### 1. Prepare a ready PR

1. repository root、current branch、base candidate、working tree、upstream、push状態、既存PRを確認する。
2. 未commit変更がある場合、PRへ含める範囲が利用者の依頼とrepository規約に一致することを確認する。無関係な差分をcommitしない。
3. 必要なら通常branchを作り、対象変更をcommitし、pushする。
4. PRがない場合、base/headを明示して通常PRを作成する。Draft PRを作成してはいけない。
5. 既存PRがDraftなら自動でReady for reviewへ変更せず停止し、`人手での作業が必要: PRをReady for reviewに変更してください。`と返す。
6. repository、PR番号、base/head branch、base/head OIDを確定する。以後、remote PR diffだけをreview対象にする。

GitHubへのbranch作成、commit、push、PR作成は、この準備段階だけで対象とscopeを確認して行います。review plan生成後のproduction変更、commit、pushはPhase 1の責務ではありません。

### 2. Collect remote PR context

まずCopilot reviewを明示要求します。対象repositoryのautomatic review設定は前提にしません。

```powershell
gh pr edit 123 --repo owner/name --add-reviewer @copilot
```

要求が権限・policy・利用条件によって失敗した場合は、collectorのtimeoutまで待たず`BLOCKED`で停止します。成功後、Skill内のcollectorを実行します。

```powershell
dotnet run --file .agents/skills/pr-review-remediation/scripts/collect-pr-review-context.cs -- --repo owner/name --pr 123 --out .review/pr-123
```

標準ではGitHub Copilot reviewを待ちます。必要な場合だけ待機設定を変更します。

```powershell
dotnet run --file .agents/skills/pr-review-remediation/scripts/collect-pr-review-context.cs -- --repo owner/name --pr 123 --out .review/pr-123 --copilot-timeout-seconds 300 --copilot-poll-interval-seconds 10 --copilot-stable-samples 2
```

`--no-wait-for-copilot`は明示的に待機を省略する場合だけ使います。timeout、disabled、observed `none`を「指摘なし」と読み替えません。

生成物:

- `review-context.json`
- `review-context.md`
- `pr-diff.patch`

collectorがDraft、base/head変更、GitHub CLI失敗、不正JSONを報告した場合は推測で続行しません。

### 3. Run local review

`local-reviewer`へ次を渡します。

- 確定したPR identity
- `review-context.json`または`review-context.md`
- `pr-diff.patch`
- repository instructions
- working tree status。PR外差分の除外確認にだけ使う

返却内容を`templates/local-review-findings.md`の形で`<out>/local-review-findings.md`へ保存します。agent自身にfileを編集させません。

### 4. Build the remediation plan

`review-planner`へcontext、patch、local findings、repository validation手順を渡します。返却内容を`templates/review-plan.md`の形で`<out>/review-plan.md`へ保存します。

Phase 1 verdictは`READY_FOR_ADAPTIVE_IMPLEMENTATION | HUMAN_DECISION_REQUIRED | BLOCKED`のいずれかです。

次をすべて満たす場合だけ`READY_FOR_ADAPTIVE_IMPLEMENTATION`を受理します。

- PR identityがcollector outputと一致する
- すべてのfinding/commentに`Apply | Hold | Reject`と理由がある
- duplicateとconflictがsource IDを失わず整理されている
- すべての`Apply` findingがscopeまたはacceptanceへmapped
- `implementation_intent.goal`、`scope`、`acceptance`が存在する
- blockingな未取得review、未解決競合、product判断不足がない
- `Production code changed: No`

Copilot waitがtimeoutで、Copilot未取得でも進む明示判断がない場合は`HUMAN_DECISION_REQUIRED`です。

### 5. Stop the parent turn

`READY_FOR_ADAPTIVE_IMPLEMENTATION`でもAdaptiveを起動しません。成果物path、Phase 1 verdict、未取得・未検証事項、人手作業、次のpromptを報告して親ターンを終了します。

## Phase 2

Phase 2はcanonical same-parent flowの導入要件ではありません。利用者が基礎版のreview planを別の親ターンで実装すると明示した場合だけ、`adaptive-implementation-execution` packageとprofilesを別途導入して次を実行します。

```text
$adaptive-implementation-execution を使って .review/pr-123/review-plan.md を実装してください。
review-plan.md の implementation_intent を source of truth とし、既存 Adaptive Implementation の router、agents、verdict、handoff、validation contract を変更または複製しないでください。
```

Phase 2の実装、tests、build、lint、format、type check、HIGH/STANDARD delegation、re-entry、resultは既存Adaptive contractの責務です。このSkillは独自implementation agentやresult schemaを持ちません。

## Relative assets

- `scripts/collect-pr-review-context.cs`
- `templates/local-review-findings.md`
- `templates/review-plan.md`
- `references/usage.md`
- `references/migration.md`
- `references/troubleshooting.md`
