# Local Review Findings

## Verdict

- Verdict: REVIEWED
- Production code changed: No

## PR Identity

- Repository: example/repo
- PR: 123
- Base branch / OID: main / base-001
- Head branch / OID: feature/review-fixture / head-001
- Review context: review-context.json
- Remote patch: pr-diff.patch

## Findings

| Finding ID | Severity | Location | Summary | Evidence | Risk | Suggested remediation |
| --- | --- | --- | --- | --- | --- | --- |
| LR-001 | P1 | `src/Fixture.cs:1` | Returned value changed without a matching test update | Remote patch changes the return value and no test file is present in the patch | Regression | Add focused behavior coverage |

## Additional Checks Required

- Run the repository focused test command.

## Unknown / Not Verified

- Production wiring outside the PR diff was not inspected.

