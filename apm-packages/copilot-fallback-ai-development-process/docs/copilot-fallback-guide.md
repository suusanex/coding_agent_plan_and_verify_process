# GitHub Copilot Fallback Guide

この package は、Codex の利用枠が尽きた場合や利用者環境の都合で GitHub Copilot Chat in VS Code を使う場合の fallback route です。

Codex-first package の `.codex/config.toml`、Codex custom agent TOML、`CODEX_HOME` を移植するものではありません。共通にするのは cost-aware routing、state artifact、gate、stop vocabulary、READY / close policy です。Copilot 向けの入口は repo-local の `.github/` customizations へ置きます。

## Standard route

標準 route の入口は `copilot-cost-router` です。

利用者は次のように普通に依頼します。

```text
この issue を進めてください。
このバグを修正してください。
この機能を実装してください。
この PR の残件を片付けて。
続きやって。
```

router は process 名、agent 名、model tier、full-coverage 分岐を利用者へ要求しません。

1. repo-local instructions と既存 artifact を読む
2. `plans/<slug>/codex-first-state.md` を読む、または作る
3. Intake / Plan / Risk / Scan / Contract / Implementation / Verification / Close の next gate を選ぶ
4. `COPILOT_HIGH_MODEL` / `COPILOT_STANDARD_MODEL` / `COPILOT_CHEAP_MODEL` を割り当てる
5. Plan gate で behavior expansion decision と Plan readiness を記録し、`NeedsPlanBehaviorExpansion` なら risk / full-coverage へ進めない
6. READY でなければ実装しない
7. close 不可なら close しない
8. 必要最小限の human input だけを返す

## State artifact

互換性のため、Copilot fallback でも次を使います。

```text
plans/<slug>/codex-first-state.md
```

この名前は Codex 由来ですが、Routing Plan、Edit Permission、Agent Usage Ledger、DelegationCompliance、`stop_reason`、`unresolved_residuals` を共有できるため残します。

## Advanced route

full-coverage 3層運用は標準 route ではありません。`ReadyForRiskTriage` の Plan が大規模で明示的に分割統治が必要な場合、または熟練 operator が選ぶ場合だけ advanced route として扱います。要求展開不足や Case-to-Plan mapping 不足は Plan gate へ戻します。
