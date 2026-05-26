# Token-aware full-coverage decomposition agents

このリポジトリは、`suusanex/coding_agent_plan_and_verify_process` の Token-aware guardrail kernel flow で、`change-risk-triage.agent.md` が `full-coverage` と診断した場合に Full autonomous Plan-first flow へ自動エスカレーションせず、実装前に Plan を slice 分割するためのカスタムエージェント一式を収録しています。

## 含まれるファイル

- `.github/agents/change-risk-triage.agent.md`
  - 既存ファイルの置き換え用です。
  - `full-coverage` の immediate next agent を `plan-slice-decomposition.agent.md` に変更しています。
  - `plan-generation.agent.md` / `runtime-evidence.agent.md` / `integration-test-design.agent.md` へつなぐ指示を禁止しています。

- `.github/agents/plan-slice-decomposition.agent.md`
  - `full-coverage` 判定された parent Plan を、Token-aware flow で実装可能な slice に分解する新規エージェントです。
  - `plans/<ticket-or-slug>-slice-decomposition.md` を作成する想定です。
  - 各 slice の推奨 profile、実装順序、cross-slice contracts、final cross-slice verification requirements を出します。

- `.github/agents/cross-slice-verification-kernel.agent.md`
  - slice ごとの実装・検証が終わった後、parent acceptance conditions と cross-slice contracts を bounded に検証する新規エージェントです。
  - Full autonomous flow の verification ではなく、Token-aware flow の最後の接続確認 gate です。

## 想定フロー

```text
plan-kernel.agent.md
→ change-risk-triage.agent.md
→ full-coverage 判定
→ plan-slice-decomposition.agent.md
→ slice ごとに token-aware kernel flow
   → change-risk-triage.agent.md
   → implementation-contract-kernel.agent.md（必要な場合）
   → implementation-contract-review-kernel.agent.md（必要な場合）
   → runtime-contract-kernel.agent.md
   → test-design-kernel.agent.md
   → implementation-execution.agent.md または人間主導実装
   → verification-kernel.agent.md
→ cross-slice-verification-kernel.agent.md
→ coverage-gap-triage.agent.md（未解決がある場合）
→ coverage-gap-resolution-slice.agent.md（選択 gap のみ）
```

## 配置

外部リポジトリへ導入する場合は、対象リポジトリの `.github/agents/` に配置してください。

このリポジトリ自身では、このリポジトリに含まれる更新済み `.github/agents/change-risk-triage.agent.md` をそのまま source of truth として使います。外部リポジトリへ導入する場合は、既存の同名ファイルが置き換え対象になります。差分確認したい場合は、先にバックアップしてください。

## 意図的に含めていないもの

- `plan-kernel.agent.md` は既存のものを使う前提です。
- `implementation-contract-kernel.agent.md`、`runtime-contract-kernel.agent.md`、`test-design-kernel.agent.md`、`verification-kernel.agent.md` も既存のものを使う前提です。
- Full autonomous Plan-first flow 用の `plan-generation.agent.md` や `runtime-evidence.agent.md` へは接続しません。
