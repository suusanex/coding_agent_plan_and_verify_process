# Cost Router Goals

`codex-first-cost-router` is the core of this package.
It receives ordinary development requests and routes work by cost, risk, and readiness.

## User experience

Users can start with:

```text
この issue を進めて。
このバグを直して。
この機能を実装して。
この PR の残件を片付けて。
続きやって。
```

Users do not choose process names, agent names, model tiers, subagents, READY gates, close gates, or full-coverage branches.

## Routing responsibilities

- Read repo instructions and existing artifacts first.
- Create or update `plans/<slug>/codex-first-state.md`.
- Split work into gates.
- Assign `HIGH_MODEL`, `STANDARD_MODEL`, or `CHEAP_MODEL`.
- Delegate bounded read-heavy work when useful.
- Prevent implementation before READY.
- Prevent close when human, manual, or higher-model stops remain.
- Save the next action and stop reason.
- Use Codex-readable custom agent file templates when maintainers want hard model routing.

## Gate summary

| Gate | Goal | Tier |
| --- | --- | --- |
| Intake | understand source, state, repo rules, and edit permission | `STANDARD_MODEL` / `HIGH_MODEL` |
| Plan | produce bounded source of truth | `HIGH_MODEL` |
| Risk | classify risk and advanced-route boundary | `STANDARD_MODEL` / `HIGH_MODEL` |
| Scan | collect summarized evidence | `CHEAP_MODEL` |
| Contract | decide implementation approach and human decisions | `HIGH_MODEL` |
| Implementation | edit READY scope only | `STANDARD_MODEL` / `CHEAP_MODEL` |
| Verification | map evidence to acceptance criteria | `STANDARD_MODEL` |
| Close | decide residuals and closure | `STANDARD_MODEL` / `HIGH_MODEL` |

## Safety requirements

- No implementation without READY or an equivalent low-risk trivial-fix decision.
- No production, secret, billing, or external service side effect without explicit approval.
- No fake / stub / mock-only result counted as production success.
- No close with unresolved `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`.
- No hard-coded real model names.

## Executable model routing

The abstract labels stay in process documents, but the team profile may pin real execution defaults in Codex custom agent files.
Use `profiles/codex-first/agents/*.toml` as the editable starting point.
Each template includes `model` and `model_reasoning_effort`, so teams can run it as-is for validation or change it before rollout.
