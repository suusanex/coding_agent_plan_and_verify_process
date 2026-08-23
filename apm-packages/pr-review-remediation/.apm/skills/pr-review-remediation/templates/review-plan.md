# PR Review Remediation Plan

## Phase 1 Verdict

- Verdict: READY_FOR_ADAPTIVE_IMPLEMENTATION / REVIEW_COMPLETE / HUMAN_DECISION_REQUIRED / BLOCKED
- Production code changed: No
- Process status: Review planning complete / Review complete, no remediation required / Human decision required / Blocked

## PR Identity

- Repository:
- PR:
- Base branch / OID:
- Head branch / OID:
- Context directory:

## Remote Review Input Status

- Review request: Requested / Failed / Not requested
- Review wait: completed / timeout / disabled / failed
- Observed review state: reviewAndInline / reviewOnly / inlineOnly / none / UNOBSERVABLE
- PR reviews: Collected / Missing / Blocked
- PR comments: Collected / Missing / Blocked
- Inline comments: Collected / Missing / Blocked
- Checks: Collected / Missing / Blocked
- Missing input decision:

## Finding Decision Ledger

| Source ID | Source | Location | Summary | Decision | Reason | Duplicate of | Conflicts with | Scope / Acceptance mapping |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| review:123 | GitHub PR review |  |  | Apply / Hold / Reject |  | N/A | N/A | SI-001 / AC-001 |

## Source Coverage

| Source ID | Finding / noAction | Reason |
| --- | --- | --- |
| review:123 |  |  |

## Ordered Remediation Plan

`REVIEW_COMPLETE`の場合はこのsectionを`N/A - no remediation required`とし、stepを生成しません。

| Step | Scope ID | Acceptance ID | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SI-001 | AC-001 |  |  |  |  |  |

## Implementation Intent

`REVIEW_COMPLETE`の場合はこのsectionを省略します。

```yaml
implementation_intent:
  goal:
  scope:
    - SI-001:
  non_goals:
  acceptance:
    - AC-001:
  constraints:
  validation:
  plan_reference: .review/pr-123/review-plan.md
```

## Uncollected / Unverified

- N/A

## Human-required Work

- 人手での作業が必要: N/A

## Explicit Implementation Turn Handoff

`REVIEW_COMPLETE`の場合はこのsectionを省略します。

```text
$adaptive-implementation-execution を使って .review/pr-123/review-plan.md を実装してください。
review-plan.md の implementation_intent を source of truth とし、既存Adaptive Implementationのrouter、agents、verdict、handoff、validation contractを変更または複製しないでください。
```

Phase 1の停止はレビュー反映プロセス全体の完了ではありません。Adaptive Implementationはこの親ターンから自動起動しません。
