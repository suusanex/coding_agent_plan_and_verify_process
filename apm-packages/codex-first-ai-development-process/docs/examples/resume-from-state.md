# Example: Resume From State

## Request

```text
続きやって。
```

## Expected behavior

- Locate the latest matching `codex-first-state.md`.
- Read `current_gate`, `next_gate`, Routing Plan, Edit Permission, DelegationCompliance summary, audit artifact path, and `stop_reason`.
- Read the matching `codex-first-audit.md` when the next gate depends on delegation evidence, model-observability detail, or close permission.
- Execute only the next allowed gate.
- Update the state artifact.
- Update the audit artifact if delegation or close-audit evidence changes.
- Do not ask the user to choose an agent or model.

## Stop example

```text
current_gate: Contract
next_gate: Implementation handoff review
recommended_model_tier: STANDARD_MODEL
allowed_to_edit: No
edit_owner: none
delegation_required: No
delegation_compliance: N/A
stop_reason: NeedsHumanDecision
human_required_items:
- Choose whether public API compatibility must be preserved.
```
