# User Guide

## いちばん短い始め方

GitHub Copilot Chat in VS Code で対象 repository を開き、普通に依頼します。

```text
この issue を進めて。
このバグを直して。
続きやって。
```

Copilot fallback package を repo-local install 済みなら、`copilot-cost-router` が次 gate を選びます。利用者は process 名、agent 名、model tier、full-coverage 3層運用を選びません。

## 明示入口

always-on instructions だけでなく明示的に起動したい場合は prompt file を使います。

```text
/cost-route この issue を進めて
/resume-state
/verify-and-close
/fix-selected-residual RES-001
```

`/resume-state` は `plans/<slug>/codex-first-state.md` を読み、next gate だけを実行します。`/verify-and-close` は acceptance criteria と evidence を対応付け、close 不可条件を確認します。

## 止まる理由

次が残る場合は完了扱いしません。

- `ManualVerificationRequired`
- `NeedsHumanDecision`
- `NeedsHigherModelReview`
- fake / stub / mock-only success
- production implementation / wiring の未確認
- secret / production / billing / external operation の未承認

Copilot が止まった場合は、提示された最小の human decision または manual verification result を渡して再開してください。

## Codex-first との関係

Codex-first と思想、state artifact、stop vocabulary は共有します。ただし、Copilot fallback は `.github/copilot-instructions.md`、`.github/instructions`、`.github/agents`、`.github/prompts` を使います。Codex 用 `.toml` や `CODEX_HOME` は Copilot Chat の導入前提ではありません。

