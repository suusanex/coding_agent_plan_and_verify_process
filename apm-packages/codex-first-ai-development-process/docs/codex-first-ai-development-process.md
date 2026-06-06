# Codex-first AI Development Process

この document は、Codex を第一優先にした応用運用の全体像をまとめる。
既存の `token-aware-guardrail-kernel-flow` と `full-autonomous-plan-first-flow` はそのまま利用可能であり、この package はそれらを beginner-friendly な入口へ束ねる layer として追加する。

## Goal

詳しくない開発者が短い依頼から始めても、AI が次を自然に通る状態を作る。

- Plan-first
- risk triage
- READY 判定
- bounded implementation
- verification
- residual decision
- human / higher-model stop

## Non-goals

- すべてを上位モデルで処理すること
- すべての課題を full-coverage 3層運用へ送ること
- GitHub Copilot fallback を主経路にすること
- secret、課金、本番環境、外部サービス設定を AI が自動操作すること

## Route selection

| Situation | Route |
| --- | --- |
| 普通の feature / bugfix | `codex-plan-coverage` |
| runtime boundary や production wiring がある | `codex-plan-coverage` + selected contract kernels |
| 実装先 API / SDK / provider が曖昧 | implementation contract branch |
| scope が広すぎる / cross-slice contract が強い | `codex-full-coverage-3layer` |
| operator が既存 flow を直接選べる | existing APM package を直接使用 |

## Close rules

Close してよいのは、次が満たされるときだけ。

- Plan の acceptance conditions に対応する evidence がある。
- production implementation と wiring が確認済み、または manual-only として明示済み。
- `ManualVerificationRequired` を残す場合は close ではなく human review 待ちにする。
- `NeedsHumanDecision` と `NeedsHigherModelReview` は未解決のまま完了扱いしない。
- residual work がある場合は、FixNow / Deferred / Manual / HigherModel のいずれかに分類されている。

## Compatibility with existing packages

既存 APM package を直接使う場合:

- `token-aware-guardrail-kernel-flow`: operator が Plan / triage / implementation / verification の順序を理解している場合。
- `full-autonomous-plan-first-flow`: broad autonomous flow を明示的に選ぶ場合。

Codex-first package を使う場合:

- 初心者向けに入口を短くしたい場合。
- モデル階層と停止語彙を package 側で揃えたい場合。
- full-coverage を通常ルートにせず、必要時だけ3層へ分岐させたい場合。
