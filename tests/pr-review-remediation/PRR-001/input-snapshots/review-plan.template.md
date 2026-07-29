# PR Review Remediation Plan

## Phase 1 Verdict

- Verdict: READY_FOR_ADAPTIVE_IMPLEMENTATION / HUMAN_DECISION_REQUIRED / BLOCKED
- Production code changed: No
- Process status: Review planning complete / Human decision required / Blocked

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
- Missing input decision:

## Finding Decision Ledger

| Source ID | Source | Location | Summary | Decision | Reason | Duplicate of | Conflicts with | Scope / Acceptance mapping |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LR-001 | Local Codex |  |  | Apply / Hold / Reject |  | N/A | N/A |  |

## Ordered Remediation Plan

| Step | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  |

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
