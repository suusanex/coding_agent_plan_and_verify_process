# Local Review Findings

## Verdict

- Verdict: REVIEWED
- Production code changed: No

## PR Identity

- Repository: fixture/goal-context-review
- PR: 123
- Base branch / OID: main / aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
- Head branch / OID: feature / bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
- Review context: fixture/.review/pr-123/review-context.json
- Remote patch: fixture/.review/pr-123/pr-diff.patch

## Findings

| ID | Severity | Location | Summary | Evidence | Risk | Suggested remediation |
| --- | --- | --- | --- | --- | --- | --- |
| LR-001 | Medium | docs/handoff.md | The handoff text omits the mandatory Phase 1 stop. | The remote patch changes the handoff to a continuation sentence without a separate-turn instruction. | An operator may treat planning as authorization to edit. | Restore explicit stop wording and a separate Adaptive prompt. |

## Additional Checks

- The notification result URI remains a separate concern for Copilot/planner input.

## Unverified

- Live provider delivery is outside local code-quality review.

