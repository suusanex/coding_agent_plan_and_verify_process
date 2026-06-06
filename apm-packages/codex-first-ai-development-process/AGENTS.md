# Codex-first AI Development Process

この package は、Codex を第一優先の実行環境として使うための応用運用である。
既存の `token-aware-guardrail-kernel-flow` と `full-autonomous-plan-first-flow` を置き換えず、初心者向けの入口、モデル階層、停止条件、残件判定を上に重ねる。

## 運用原則

- Codex で開始し、必要な場合だけ GitHub Copilot fallback へ切り替える。
- まず `plan-kernel.agent.md` で bounded Plan を作る。
- `change-risk-triage.agent.md` で通常ルートか full-coverage 分岐かを判定する。
- READY でない状態では実装へ進まない。
- `ManualVerificationRequired`、`NeedsHumanDecision`、`NeedsHigherModelReview` を残したまま close しない。
- secret、課金、外部環境設定、本番操作は自動実行しない。
- 1 回の bounded pass で停止し、未解決は artifact に残す。

## モデル階層

| Label | Intended use |
| --- | --- |
| `HIGH_MODEL` | Plan 作成、risk triage、full-coverage parent、最終 gate、曖昧な人間判断の整理 |
| `STANDARD_MODEL` | implementation contract、runtime contract、test design、bounded implementation、verification |
| `CHEAP_MODEL` | 形式確認、README 整形、軽量なサンプル追従、既知 artifact の再チェック |

実名モデルはここでは固定しない。組織の契約、利用枠、品質要求に合わせて保守者が対応表を作る。

## 通常ルート

1. `codex-plan-coverage` Skill で入口を整える。
2. `plan-kernel.agent.md` で bounded Plan を作る。
3. `change-risk-triage.agent.md` でリスクを分類する。
4. 必要に応じて implementation contract / runtime contract / test design を作る。
5. `implementation-handoff-review.agent.md` で READY 判定する。
6. `implementation-execution.agent.md` で選択 scope だけ実装する。
7. `verification-kernel.agent.md` で production binding と wiring を確認する。
8. 未解決があれば `coverage-gap-triage.agent.md` に残し、必要な slice だけ修正する。

## full-coverage 分岐

`change-risk-triage.agent.md` が `full-coverage` を推奨した場合は、広い自走フローへ自動移行しない。
まず `codex-full-coverage-3layer` Skill と `plan-slice-decomposition.agent.md` を使い、parent / slice-prep / slice-impl の 3 層へ分ける。

```text
parent Plan
-> plan-slice-decomposition
-> slice-prep
-> slice-impl
-> cross-slice-verification-kernel
-> residual decision
```

## 既存 APM package との関係

- 初心者やチーム導入では、この `codex-first-ai-development-process` を使う。
- 既存運用に慣れていて、明示的に flow を選べる場合は `token-aware-guardrail-kernel-flow` または `full-autonomous-plan-first-flow` を直接使ってよい。
- この package は既存 package の source を複製せず、同じ agent 群を参照して応用運用だけを追加する。
