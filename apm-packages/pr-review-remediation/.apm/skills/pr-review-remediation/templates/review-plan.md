# PR Review Remediation Result

## Planning Verdict

- Verdict: REMEDIATION_REQUIRED / REVIEW_COMPLETE / HUMAN_DECISION_REQUIRED / BLOCKED
- Planning status: Complete / Human decision required / Blocked
- Production / tests / docs changed during planning: No
- Execution owner: CURRENT_PARENT / EXPLICIT_ADAPTIVE / NO_REMEDIATION / NONE
- Adaptive selection evidence: N/A / 利用者の明示指定を記録

`REMEDIATION_REQUIRED`は同じ親が処理を継続する内部状態です。terminal verdictとして利用者へ別turnを要求しません。

## PR Identity

- Repository:
- PR:
- Base branch / OID:
- Head branch / OID:
- Context directory:
- Initial working tree:

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

| Source ID | Source | Location | Summary | Planner recommendation | Final decision | Reason | Resolution / Evidence | Duplicate of | Conflicts with | Scope / Acceptance mapping |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| review:123 | GitHub PR review |  |  | Apply / Hold / Reject | Apply / Reject / Human decision required / Pending |  |  | N/A | N/A | SI-001 / AC-001 |

親はterminal verdictの前にすべての`Pending`を解消します。`Hold`または`Human decision required`を通常完了へ混ぜません。

## Source Coverage

| Source ID | Finding / noAction | Reason |
| --- | --- | --- |
| review:123 |  |  |

## Ordered Remediation Plan

`REVIEW_COMPLETE`で修正不要の場合はこのsectionを`N/A - no remediation required`とし、stepを生成しません。

| Step | Scope ID | Acceptance ID | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SI-001 | AC-001 |  |  |  |  |  |

## Implementation Intent

`REVIEW_COMPLETE`で修正不要の場合はこのsectionを省略します。

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

## Execution Result

このsectionは親が最終判断、remediation、validation、Git操作の後に更新します。

- Final verdict: REVIEW_COMPLETE / HUMAN_DECISION_REQUIRED / BLOCKED / Pending
- Production / tests / docs changed: Yes / No / Pending
- Unresolved findings: 0 / count / Pending
- Human-required work: N/A / details

### Validation Evidence

| Command | Result | Covered findings / acceptance |
| --- | --- | --- |
|  | PASS / FAIL / NOT_RUN |  |

### Git Result

- Git outcome: COMMITTED_AND_PUSHED / NO_CHANGES / SKIPPED_BY_USER / NOT_PUSHED / NOT_ATTEMPTED / Pending
- Commit:
- Remote PR head before commit / push:
- Remote PR head after push:
- Unrelated local changes excluded:

## Uncollected / Unverified

- N/A

## Human-required Work

- 人手での作業が必要: N/A
