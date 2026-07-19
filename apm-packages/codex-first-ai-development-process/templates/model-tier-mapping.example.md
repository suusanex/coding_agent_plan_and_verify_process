# Model Tier Mapping Example

This file is an example for maintainers.
Do not treat these labels as fixed model names.

| Tier | Real model | Notes |
| --- | --- | --- |
| `HIGH_MODEL` | `gpt-5.6-terra` | Use for hard judgment and high-risk planning. Agent-specific reasoning is high except where noted below. |
| `STANDARD_MODEL` | `gpt-5.6-luna` / `gpt-5.6-terra` | Use the agent-specific mapping below: implementation uses Luna/high and verification uses Terra/medium. |
| `CHEAP_MODEL` | `gpt-5.6-luna` | Use for read-heavy scan, docs consistency, and simple local fixes with the agent-specific reasoning below. |

Review this mapping when contracts, available models, pricing, or quality requirements change.
The matching runnable examples live in `profiles/codex-first/agents/*.toml`.

## Agent-specific mapping

```text
HIGH_MODEL:
  high-planner                  = Terra / high
  black-box-behavior-spec-kernel = Terra / high
  high-risk-triage              = Terra / high
  high-implementation-contract  = Terra / high
  high-closure-reviewer         = Terra / high
  implementation-handoff-review = Terra / medium
  high-implementation-starter    = Terra / high

STANDARD_MODEL:
  standard-implementation-completer = Luna / high
  standard-verifier                 = Terra / medium

CHEAP_MODEL:
  cheap-repo-scanner            = Luna / medium
  cheap-doc-consistency         = Luna / low
  cheap-artifact-format-checker = Luna / low
```

The configured model and configured reasoning effort come from the runnable TOML. Recommended reasoning is a routing recommendation; selected/observed reasoning, reported model, and effective model must be recorded separately when available.

## Mapping review checklist

- `HIGH_MODEL` is reserved for hard planning, risk, implementation contract, and dangerous close judgment.
- Non-trivial READY implementation starts with `high-implementation-starter` on Terra/high. `standard-implementation-completer` uses Luna/high only after a valid delegation handoff, while `standard-verifier` remains Terra/medium.
- `CHEAP_MODEL` is suitable for read-heavy scan, docs consistency, artifact format check, and simple local fixes.
- Implementation handoff review creates the parent authorization artifact before standard implementation.
- When behavior expansion is required, the Behavior Case Coverage Ledger is Complete before standard implementation.
- READY implementation starts with `high-implementation-starter`, delegates only a decision-free remainder to `standard-implementation-completer`, and returns to HIGH_MODEL when structural decisions reappear.
- READY verification delegates to `standard-verifier`.
