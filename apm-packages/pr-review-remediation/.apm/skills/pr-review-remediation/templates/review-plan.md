# PR Review Remediation Plan

## Phase 1 Verdict

- Verdict: READY_FOR_ADAPTIVE_IMPLEMENTATION / HUMAN_DECISION_REQUIRED / BLOCKED
- Production code changed: No
- Process status: Review planning complete / Human decision required / Blocked
- Review mode: Baseline / Goal Context

## PR Identity

- Repository:
- PR:
- Base branch / OID:
- Head branch / OID:
- Context directory:

## Review Input Status

- Local Codex review: Collected / Missing / Blocked
- Copilot wait status: completed / timeout / disabled
- Copilot observed review state: reviewAndInline / reviewOnly / inlineOnly / none
- PR comments: Collected / Missing
- Inline comments: Collected / Missing
- Checks: Collected / Missing
- Goal Context selection: N/A / SELECTED / Missing / Invalid / Ambiguous
- Purpose review: N/A / PURPOSE_REVIEWED / HUMAN_DECISION_REQUIRED / BLOCKED
- Missing input decision:

## Goal Context Boundary

- Selected Goal Context: N/A
- Goal Context SHA-256: N/A
- Original problem: N/A
- Desired outcome: N/A
- User scenarios: N/A
- MVP guardrails: N/A
- Non-goals: N/A
- Rejected alternatives: N/A
- Superficially compliant but wrong / negative conditions: N/A
- Open questions / human decisions: N/A

## Finding Decision Ledger

`PUR-*` rows are Goal Context mode only; omit them in Baseline mode.

| Source ID | Source | Location | Summary | Decision | Reason | Duplicate of | Conflicts with | Scope / Acceptance mapping |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LR-001 | Local Codex |  |  | Apply / Hold / Reject |  | N/A | N/A | SI-001 / AC-001 |
| PUR-001 | Purpose (Goal Context mode only) |  |  | Apply / Hold / Reject |  | N/A | N/A | SI-001 / AC-001 |

## Ordered Remediation Plan

| Step | Scope ID | Acceptance ID | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SI-001 | AC-001 |  |  |  |  |  |

## Implementation Intent

```yaml
implementation_intent:
  goal:
  scope:
  non_goals:
  acceptance:
  constraints:
  validation:
  plan_reference:
  goal_context_reference:
```

## Uncollected / Unverified

- N/A

## Human-required Work

- 人手での作業が必要:

## Separate Parent Turn Handoff

```text
$adaptive-implementation-execution を使って <review-plan-path> を実装してください。
review-plan.md の implementation_intent を source of truth とし、既存 Adaptive Implementation の router、agents、verdict、handoff、validation contract を変更または複製しないでください。
```

Phase 1の停止はレビュー反映プロセス全体の完了ではありません。Adaptive Implementationはこの親ターンから自動起動しません。
