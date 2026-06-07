# Copilot Model Tier Mapping

Copilot fallback の model mapping は Codex-first の model mapping とは別管理です。

VS Code / GitHub Copilot 側で利用可能な model 名、組織 policy、premium request、品質要求は変わるため、次の対応は初期例として扱ってください。

| Tier | Example model | Use |
| --- | --- | --- |
| `COPILOT_HIGH_MODEL` | `GPT-5.5 (copilot)` | 曖昧な要求整理、high-risk planning、auth/security/production close 判断 |
| `COPILOT_STANDARD_MODEL` | `GPT-5.5 (copilot)` | READY 後の通常実装、通常 verification |
| `COPILOT_CHEAP_MODEL` | `GPT-5.4 mini (copilot)` | read-heavy scan、docs consistency、trivial local fix |

`STANDARD` と `HIGH` が同じ実名 model の場合は、cost-aware routing として弱い default です。組織が lower-cost model を使えるなら `copilot-standard-implementer`、`copilot-standard-verifier`、`copilot-cheap-repo-scanner` の frontmatter を調整してください。

未指定の場合は VS Code の model picker の現在値が使われます。この package は route policy を固定しますが、実名 model は固定しません。

