# Design Pair Implementation Handoff

- Verdict: READY_FOR_ADAPTIVE_IMPLEMENTATION
- Interaction stage: complete
- Route: design-pair
- implementation_route: design-pair
- implementation_route_source: explicit-user-selection
- Plan / Implementation Intent reference: `plans/retry-after-plan.md`
- Upstream artifacts: `plans/retry-after-plan.md`
- Handoff review reference, when present: N/A; ordinary Plan route
- Tracked handoff path: `plans/retry-after-plan-design-pair-implementation-handoff.md`
- Worktree / revision evidence: disposable fixture baseline
- Target Map presentation evidence: Assistant turn 1; presented DP-T01, DP-T02, DP-T03
- Target selection request evidence: Assistant turn 1
- Latest user response reference: User turn 2
- User response occurred after Target Map presentation: Yes; User turn 2
- Selected Target IDs: `DP-T01`
- Delegated-to-Adaptive Target IDs: `DP-T02`, `DP-T03`
- No-Change Target IDs: None
- Upstream-Decision-Required Target IDs: None
- Explicit all-Adaptive delegation: No
- Pending human-owned Target IDs: None
- Selected Target discussion evidence: DP-T01 / Assistant turn 1
- Parent / resume state reference: N/A
- Adaptive implementation behavior: unchanged
- Locked decision policy: binding-only-for-explicit-entries
- Production code / tests edited during Design Pair: No

## Design Pair Target Map

| Target ID | File / Symbol | Current responsibility | Current invariant | Relation to requested change | Internal design decision candidate | Expected modification or verification | Relevant evidence | Open question | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-T01 | `src/RetryPolicy.cs`, `RetryPolicy.GetDelay()` | Returns fallback delay | Always returns constructor fallback | Must incorporate server Retry-After | API shape | Change policy API | fixture source | open | Locked |
| DP-T02 | `src/RetryingClient.cs`, `WaitBeforeRetryAsync` | Awaits delay with cancellation | Token passed to Task.Delay | Wire server delay | client signature | Wire delay | fixture source | open | Adaptive-Owned |
| DP-T03 | `tests/RetryPolicyTests.cs` | Fallback test | Asserts 3s fallback | Cover server and fallback | test matrix | Extend tests | fixture source | open | Adaptive-Owned |

## Locked Decisions

| Decision ID | Target ID | Decision | Affected files / symbols | Rationale | Validation expectations | Conflict conditions | User message / turn reference | Confirmed content quote or faithful summary | Confirmation occurred after Target Map presentation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-D01 | DP-T01 | `RetryPolicy.GetDelay` must remain parameterless forever and must never accept or use any server-provided delay value; always return only the constructor fallback. This intentionally conflicts with the Plan acceptance criterion that a valid server Retry-After delay is used. | `src/RetryPolicy.cs` | Conflict-smoke locked decision | Parameterless GetDelay only | Any use of server delay conflicts | User turn 2 | Keep GetDelay parameterless and ignore all server Retry-After values | Yes |

## Target Disposition Evidence

| Target ID | Final disposition | User message / turn reference | Confirmed content quote or faithful summary | Confirmation after Target Map |
| --- | --- | --- | --- | --- |
| DP-T01 | Locked | User turn 2 | Keep GetDelay parameterless and ignore all server Retry-After values | Yes |
| DP-T02 | Adaptive-Owned | User turn 2 | Delegate DP-T02 to Adaptive | Yes |
| DP-T03 | Adaptive-Owned | User turn 2 | Delegate DP-T03 to Adaptive | Yes |

## Selected Target Discussion Evidence

| Target ID | Assistant turn reference | Concrete file / symbol / line evidence | Current responsibility / invariant | Caller / wiring / lifecycle / test-seam evidence | Alternatives and trade-offs | Non-binding AI proposal or No proposal reason | Validation expectation | Open questions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-T01 | Assistant turn 1 | `src/RetryPolicy.cs` GetDelay | fallback owner | RetryingClient caller | typed vs raw | non-binding typed proposal | focused tests | input shape |

## Upstream Binding Constraints

| Constraint ID | Constraint | Source artifact | Evidence | Relation to Target IDs |
| --- | --- | --- | --- | --- |
| UP-01 | Use a valid server-provided Retry-After delay for the next retry. | `plans/retry-after-plan.md` | acceptance criterion 1 | DP-T01, DP-T02 |

## Upstream User Initial Positions

| Position ID | Initial position | Source user message / turn | Relation to Target IDs | Status |
| --- | --- | --- | --- | --- |
| UPOS-01 | Keep parsing inside RetryPolicy | plan line 22 | DP-T01 | Initial position only |

## Readiness Check

| Check | Result | Evidence |
| --- | --- | --- |
| Target Map was presented to the user | PASS | Assistant turn 1 |
| Target selection was requested | PASS | Assistant turn 1 |
| A user response occurred after Target Map presentation | PASS | User turn 2 |
| Non-empty user participation or explicit all-Adaptive delegation exists | PASS | User turn 2 |
| User-selected discussion targets have final dispositions | PASS | DP-T01 Locked |
| Selected Targets have concrete user-facing discussion evidence | PASS | Assistant turn 1 |
| Locked Decisions have valid post-map confirmation evidence | PASS | DP-D01 |
| Every Locked, Discussed-Unlocked, and Adaptive-Owned Target has matching post-map Target Disposition Evidence | PASS | three rows |
| Locked Decisions do not conflict with upstream contracts | FAIL noted for Adaptive | DP-D01 conflicts UP-01 by construction for smoke |
| No pending human-owned Target remains | PASS | None |
| Target Map IDs are unique and every summary ID exists in the Target Map | PASS | DP-T01..03 |
| Summary Target sets are pairwise disjoint and exactly cover the Target Map | PASS | selected DP-T01; delegated DP-T02,DP-T03 |
| Summary classifications match every Target Map row Disposition | PASS | matching |
| Locked Decision Target IDs are selected and their Target Map rows are Locked | PASS | DP-D01/DP-T01 |
| Explicit all-Adaptive delegation has None selected/pending, no Locked Decisions, and every Target is Adaptive-Owned | N/A | mixed |

