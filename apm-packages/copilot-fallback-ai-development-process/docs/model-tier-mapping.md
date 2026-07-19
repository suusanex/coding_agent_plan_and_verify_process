# Copilot Model Tier Mapping

Copilot fallback の model mapping は Codex-first の model mapping とは別管理です。

VS Code / GitHub Copilot 側で利用可能な model 名、組織 policy、premium request、品質要求は変わるため、次の対応は初期例として扱ってください。

| Tier | Example model | Use |
| --- | --- | --- |
| `COPILOT_HIGH_MODEL` | `GPT-5.6 Terra (copilot)` | 曖昧な要求整理、非自明な実装開始・再入場、auth/security/production close 判断 |
| `COPILOT_STANDARD_MODEL` | `GPT-5.6 Luna/Terra (copilot)` | valid handoff 後の bounded completion は Luna、通常 verification は Terra |
| `COPILOT_CHEAP_MODEL` | `GPT-5.6 Luna (copilot)` | read-heavy scan、docs consistency、trivial local fix |

## Agent / handoff mapping

```text
high-planner, risk-triage, implementation-handoff-review, high-implementation-starter, close-reviewer = Terra
standard-implementation-completer (valid handoff 後のみ) = Luna
standard-verifier = Terra
cheap-repo-scanner = Luna
selected residual fix / high re-entry = Terra
higher-risk recheck handoff = Terra
```

Recommended runtime reasoning is Terra/high for planner, risk, implementation start/re-entry, contract, and close decisions; Terra/medium for handoff review and verification; Luna/high for bounded standard completion; and Luna/medium for repository scanning. Copilot templates do not add a reasoning frontmatter field.

`copilot-standard-implementer` は既存 invocation の互換入口としてのみ残します。標準ルートは `high-implementation-starter -> standard-implementation-completer -> high-implementation-starter` です。

未指定の場合は VS Code の model picker の現在値が使われます。この package は route policy と template model を固定しますが、selected / observed reasoning、reported model、effective model は Agent Usage Ledger で別々に記録します。
