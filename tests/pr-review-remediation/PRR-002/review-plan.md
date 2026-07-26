# PR Review Remediation Plan

## Phase 1 Verdict

- Verdict: READY_FOR_ADAPTIVE_IMPLEMENTATION
- Production code changed: No
- Process status: Review planning complete
- Review mode: Goal Context

## PR Identity

- Repository: fixture/goal-context-review
- PR: 123
- Base branch / OID: main / aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- Head branch / OID: feature / bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
- Context directory: fixture/.review/pr-123

## Review Input Status

- Local Codex review: Collected
- Copilot wait status: completed
- Copilot observed review state: reviewAndInline
- PR comments: Collected
- Inline comments: Collected
- Checks: Collected
- Goal Context selection: SELECTED
- Purpose review: PURPOSE_REVIEWED
- Missing input decision: N/A

## Goal Context Boundary

- Selected Goal Context: fixture/docs/goal-context-direct-review-notification.md
- Goal Context SHA-256: c38af168cfedf31d198f49b8b7a47a91a3f493e129b47e72432589a8e5eb4030
- Original problem: Users repeatedly search for review completion and continuation targets.
- Desired outcome: Direct-link notification plus a safe manual remediation start.
- User scenarios: Open the exact PR and start Adaptive in a separate parent turn.
- MVP guardrails: Independent reviews, integrated plan, stop, notify.
- Non-goals: Automatic remediation and merge.
- Rejected alternatives: A duplicate implementation agent.
- Superficially compliant but wrong / negative conditions: Issue-only purpose review or production edits in Phase 1.
- Open questions / human decisions: N/A

## Finding Decision Ledger

| Source ID | Source | Location | Summary | Decision | Reason | Duplicate of | Conflicts with | Scope / Acceptance mapping |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LR-001 | Local Codex | handoff text | Missing explicit stop wording. | Apply | Prevents ambiguous operation. | N/A | N/A | SI-001 / AC-001 |
| PUR-001 | Purpose | Desired outcome | Separate user-started turn is not explicit. | Apply | Required by Goal Context. | LR-001 | N/A | SI-001 / AC-001 |
| RC-001 | Copilot | handoff text | Add direct PR URL. | Apply | Supports direct return. | N/A | N/A | SI-002 / AC-002 |

## Ordered Remediation Plan

| Step | Scope ID | Acceptance ID | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SI-001 | AC-001 | LR-001, PUR-001 | State the mandatory Phase 1 stop and separate manual Adaptive start. | handoff documentation | No automatic continuation is implied. | Contract test |
| 2 | SI-002 | AC-002 | RC-001 | Preserve the exact PR result URI in the notification envelope. | notification example | Link opens PR 123 directly. | Envelope fixture |

## Implementation Intent

```yaml
implementation_intent:
  goal: Preserve direct return while making the two-turn manual boundary unambiguous.
  scope:
    - Update handoff wording.
    - Preserve the direct PR result URI.
  non_goals:
    - Automatic Adaptive startup.
    - Automatic merge.
  acceptance:
    - Phase 1 explicitly stops before production edits.
    - The separate-turn prompt consumes this plan.
    - The notification result URI opens the exact PR.
  constraints:
    - Do not add another implementation agent.
    - Do not invent requirements outside the Goal Context.
  validation:
    - Run the PR review remediation validator.
  plan_reference: tests/pr-review-remediation/PRR-002/review-plan.md
  goal_context_reference: tests/pr-review-remediation/PRR-002/fixture/docs/goal-context-direct-review-notification.md
```

## Uncollected / Unverified

- Live OS notification delivery is verified by the shared runtime, not this fixture.

## Human-required Work

- 人手での作業が必要: 通知から戻り、別親ターンのAdaptive Implementationを明示開始する。

## Separate Parent Turn Handoff

```text
$completion-notification-decorator
$adaptive-implementation-execution

tests/pr-review-remediation/PRR-002/review-plan.mdを実装してください。
implementation_intentをsource of truthとし、Goal Context Boundaryを保持してください。
```

Phase 1の停止はレビュー反映プロセス全体の完了ではありません。Adaptive Implementationはこの親ターンから自動起動しません。
