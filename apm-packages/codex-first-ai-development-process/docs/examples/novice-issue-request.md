# Example: Novice Issue Request

## Request

```text
この issue を進めてください。
```

## Expected behavior

- Treat the request as Codex-first cost-aware routing.
- Do not ask for a process name.
- Read repo instructions and the issue body.
- Create or update `plans/<slug>/codex-first-state.md`.
- Choose the next safe gate.
- Do not implement until READY.

## State excerpt

```text
current_gate: Intake
next_gate: Plan
recommended_model_tier: HIGH_MODEL
allowed_to_edit: No
edit_owner: none
delegation_compliance: N/A
stop_reason: None
next_action: Create bounded Plan from issue body and repo rules.

Routing Plan:
| Gate | Recommended tier | Delegation required | Expected agent type | Edit owner | Parent may execute directly? | Stop if unavailable |
| Plan | HIGH_MODEL | No | high-planner or parent | parent | Yes | NeedsHumanDecision |
```
