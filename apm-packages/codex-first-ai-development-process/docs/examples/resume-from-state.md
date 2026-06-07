# Example: Resume From State

## Request

```text
続きやって。
```

## Expected behavior

- Locate the latest matching `codex-first-state.md`.
- Read `current_gate`, `next_gate`, Routing Plan, Edit Permission, DelegationCompliance, and `stop_reason`.
- Execute only the next allowed gate.
- Update the state artifact.
- Do not ask the user to choose an agent or model.

## Stop example

```text
current_gate: Contract
next_gate: Implementation
recommended_model_tier: STANDARD_MODEL
allowed_to_edit: false
edit_owner: none
delegation_required: No
delegation_compliance: N/A
stop_reason: NeedsHumanDecision
human_required_items:
- Choose whether public API compatibility must be preserved.
```
