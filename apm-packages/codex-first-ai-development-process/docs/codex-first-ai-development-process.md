# Codex-first AI Development Process

この document は、Codex を第一優先にした cost-aware development process の全体像をまとめる。
既存の `token-aware-guardrail-kernel-flow`、`full-autonomous-plan-first-flow`、full-coverage 3層運用はそのまま利用可能だが、この package の標準ルートではない。
標準ルートの中核は `codex-first-cost-router` であり、利用者に process 名、agent 名、model tier、full-coverage 分岐を選ばせない。

## Goal

詳しくない開発者が短い依頼から始めても、Codex 側が工程を分け、難しさとリスクに応じて model tier / agent / subagent を割り当てる状態を作る。

- ordinary natural-language intake
- cost-aware routing
- Plan / risk / scan / contract / implementation / verification / close gate
- state artifact based resume
- READY 判定
- bounded implementation
- residual decision
- human / higher-model stop

## Non-goals

- すべてを上位モデルで処理すること
- すべての課題を full-coverage 3層運用へ送ること
- 利用者に process 名や agent 名を覚えさせること
- 実名モデルを固定すること
- GitHub Copilot fallback を主経路にすること
- secret、課金、本番環境、外部サービス設定を AI が自動操作すること

## Standard route: cost-aware routing

| Gate | Main output | Default tier |
| --- | --- |
| Intake | source of truth, current state, allowed-to-edit | `STANDARD_MODEL` |
| Plan | bounded Plan or equivalent artifact | `HIGH_MODEL` |
| Risk | risk class and advanced-route boundary | `STANDARD_MODEL` / `HIGH_MODEL` |
| Scan | summarized repo evidence | `CHEAP_MODEL` |
| Contract | implementation approach and human decisions | `HIGH_MODEL` |
| Implementation | READY scope edits | `STANDARD_MODEL` |
| Verification | evidence and manual-only checks | `STANDARD_MODEL` |
| Close | residual and close decision | `STANDARD_MODEL` / `HIGH_MODEL` |

`CHEAP_MODEL` workers may help with read-heavy scan, docs consistency, or artifact formatting.
They do not own final implementation permission or close decisions.

## Close rules

Close してよいのは、次が満たされるときだけ。

- Plan の acceptance conditions に対応する evidence がある。
- production implementation と wiring が確認済み、または manual-only として明示済み。
- `ManualVerificationRequired` を残す場合は close ではなく human review 待ちにする。
- `NeedsHumanDecision` と `NeedsHigherModelReview` は未解決のまま完了扱いしない。
- residual work がある場合は、FixNow / Deferred / Manual / HigherModel のいずれかに分類されている。

## State artifact

通常は次の state artifact を使う。

```text
plans/<slug>/codex-first-state.md
```

この artifact は、`current_gate`、`next_gate`、`recommended_model_tier`、`allowed_to_edit`、`stop_reason`、`human_required_items`、`unresolved_residuals`、`next_action` を持つ。
ユーザーが「続きやって」と依頼したら、まずこの artifact を読む。

## Advanced route

full-coverage 3層運用は advanced route である。
scope が広すぎる、cross-slice contract が強い、標準 cost-router では安全に bounded 化できない、または熟練 operator が明示的に選ぶ場合だけ使う。

標準 user guide では full-coverage のプロンプト例を示さない。
詳細は `advanced-full-coverage-3layer.md` に分離する。

## Compatibility with existing packages

- `plan-coverage-residual-gate-flow`: cost-router が内部で参照する既存 kernel 群。
- `full-autonomous-plan-first-flow`: broad autonomous flow を明示的に選ぶ場合の既存資産。
- `token-aware-full-coverage-3layer`: advanced route の既存資産。

この package は既存資産を複製せず、初心者向けの入口、state、model tier routing、stop vocabulary を上に重ねる。
