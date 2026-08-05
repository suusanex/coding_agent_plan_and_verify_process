# Design Pair Implementation Handoff

- Verdict: AWAITING_USER_INPUT
- Interaction stage: disposition-confirmation
- Route: design-pair
- implementation_route: design-pair
- implementation_route_source: explicit-user-selection
- Plan / Implementation Intent reference: `plans/retry-after-plan.md`
- Upstream artifacts: `plans/retry-after-plan.md`
- Handoff review reference: N/A
- Tracked handoff path: `plans/retry-after-plan-design-pair-implementation-handoff.md`
- Worktree / revision evidence: `master` at `8a7553a`; unrelated untracked `smoke-logs/` present; no production code or tests edited during Design Pair
- Target Map presentation evidence: Assistant turn 2 (this response), Target IDs `DP-T01`, `DP-T02`, `DP-T03`
- Target selection request evidence: Assistant turn 2 (this response)
- Latest user response reference: User turn 3 (`Discuss DP-T01.`)
- User response occurred after Target Map presentation: Yes
- Selected Target IDs: Pending final disposition (`DP-T01` selected for discussion)
- Delegated-to-Adaptive Target IDs: Pending
- No-Change Target IDs: Pending
- Upstream-Decision-Required Target IDs: Pending
- Explicit all-Adaptive delegation: Pending
- Pending human-owned Target IDs: `DP-T01`, `DP-T02`, `DP-T03`
- Selected Target discussion evidence: `DP-T01` — Assistant turn 4 (this response)
- Parent / resume state reference: `smoke-logs/wait-turn1.txt`; no prior Target Map presentation evidence
- Adaptive implementation behavior: unchanged
- Locked decision policy: binding-only-for-explicit-entries
- Production code / tests edited during Design Pair: No

## Design Pair Target Map

| Target ID | File / Symbol | Current responsibility | Current invariant | Relation to requested change | Internal design decision candidate | Expected modification or verification | Relevant evidence | Open question | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-T01 | `src/RetryPolicy.cs:3-12`, `RetryPolicy.GetDelay()` | Stores the configured fallback and returns it for every retry wait. | `GetDelay()` always returns the constructor-supplied `fallbackDelay`; no server input is parsed or validated. | Must select a valid non-negative server-provided Retry-After delta while retaining fallback behavior for missing, invalid, or negative input. | Decide the input shape and parsing boundary for Retry-After (for example, nullable string/header text versus a typed delta) and whether parsing remains in `RetryPolicy`, as proposed upstream. | Modify or verify the policy API and parsing/validation so valid delta values win and all invalid cases use the fallback without allowing negative delay values. | `RetryPolicy.cs:5-12`; upstream plan acceptance criteria 1-2 and initial proposal line 22. No retry-response/header type exists in the repository. | How should the server value reach the policy, and should the policy accept raw header text or a pre-parsed value? | Pending-User-Disposition |
| DP-T02 | `src/RetryingClient.cs:3-8`, `RetryingClient.WaitBeforeRetryAsync()` | Applies the policy delay before retrying and exposes the cancellation-aware wait. | Calls `Task.Delay(retryPolicy.GetDelay(), cancellationToken)`, so cancellation is propagated and the current wait uses only the fallback. | Must pass the throttled response's Retry-After value into delay selection without losing `CancellationToken` propagation. | Decide where the retry response/header is observed and whether the client method signature changes, while preserving async cancellation and avoiding delay selection in the caller. | Modify or verify the call path to supply server delay input and continue using `Task.Delay(..., cancellationToken)`; focused verification should cover cancellation-aware invocation. | `RetryingClient.cs:3-8`; `rg` found the only production call to `GetDelay()` here; no request/response loop or DI/entrypoint is present. | What concrete response/header representation is available at this seam, given the current method only receives a token? | Pending-User-Selection |
| DP-T03 | `tests/RetryPolicyTests.cs:3-14`, `RetryPolicyTests` | Provides a manual focused check that the configured fallback is returned. | The existing test throws when `GetDelay()` differs from a three-second fallback; there is no test harness project or test runner metadata. | Must cover valid server delay, missing/invalid/negative fallback behavior, and preserve the existing fallback assertion. | Decide the smallest test seam matching the chosen policy/client API, including whether parsing cases are table-driven and how cancellation behavior is observed without introducing a new harness. | Add focused assertions for server delay and fallback cases, plus cancellation-aware client behavior if the API change makes that directly testable; verify via the repository's available smoke/test mechanism. | `RetryPolicyTests.cs:5-13`; repository contains only three C# source files and no `*.csproj`, `*.sln`, test project, or fixture files. | Which available validation command or smoke harness should execute these manual tests after the API shape is chosen? | Pending-User-Selection |

This Target Map is the bounded planned change surface, not a repository-wide inventory or an Adaptive Implementation allowed edit surface.

## Coverage check

| Surface | Checked? | Evidence or N/A reason |
| --- | --- | --- |
| Production symbol and direct call sites | Yes | `RetryPolicy.GetDelay()` is defined in `src/RetryPolicy.cs:12` and called only by `RetryingClient.WaitBeforeRetryAsync()` at `src/RetryingClient.cs:7`; no other C# call sites were found. |
| Tests / fixtures / test seam | Yes | `tests/RetryPolicyTests.cs` is the only test file and contains the fallback assertion; no fixture or test project files were found. |
| DI / factory / startup / entrypoint / production wiring | Yes | No DI, factory, startup, entrypoint, project, or host files are present; the client receives `RetryPolicy` through its primary constructor, so additional wiring is N/A for the current bounded surface. |
| Config / serialized shape / public API | Yes | No config or serialized shape exists; `RetryPolicy(TimeSpan)` and `GetDelay()` plus `WaitBeforeRetryAsync(CancellationToken)` are public API surfaces directly implicated by passing Retry-After input. |
| Event / callback / async lifecycle / cancellation / state ownership | Yes | The only lifecycle is the awaited `Task.Delay` in `WaitBeforeRetryAsync`; the caller-owned `CancellationToken` is passed directly to it. No event/callback, retry loop, response state, or additional cancellation source exists in the repository. |

## Upstream Binding Constraints

| Constraint ID | Constraint | Source artifact | Evidence | Relation to Target IDs |
| --- | --- | --- | --- | --- |
| UP-01 | Use a valid server-provided Retry-After delay for the next retry. | `plans/retry-after-plan.md` | Goal and acceptance criterion 1 | `DP-T01`, `DP-T02` |
| UP-02 | Missing, invalid, or negative input must use the configured fallback delay. | `plans/retry-after-plan.md` | Goal and acceptance criterion 2 | `DP-T01`, `DP-T03` |
| UP-03 | Preserve cancellation awareness in the caller. | `plans/retry-after-plan.md` | Acceptance criterion 3; current `Task.Delay` token usage | `DP-T02`, `DP-T03` |
| UP-04 | Focused tests must cover server delay and fallback behavior. | `plans/retry-after-plan.md` | Acceptance criterion 4 and scope | `DP-T03` |

## Upstream User Initial Positions

| Position ID | Initial position | Source user message / turn | Relation to Target IDs | Status |
| --- | --- | --- | --- | --- |
| UP-IP-01 | Keep Retry-After parsing inside `RetryPolicy`. | `plans/retry-after-plan.md`, line 22 | `DP-T01`, `DP-T02` | Initial position only; not a Design Pair confirmation |

## Locked Decisions

| Decision ID | Target ID | Decision | Affected files / symbols | Rationale | Validation expectations | Conflict conditions | User message / turn reference | Confirmed content quote or faithful summary | Confirmation occurred after Target Map presentation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Target Disposition Evidence

| Target ID | Final disposition | User message / turn reference | Confirmed content quote or faithful summary | Confirmation after Target Map |
| --- | --- | --- | --- | --- |

## Selected Target Discussion Evidence

| Target ID | Assistant turn reference | Concrete file / symbol / line evidence | Current responsibility / invariant | Caller / wiring / lifecycle / test-seam evidence | Alternatives and trade-offs | Non-binding AI proposal or No proposal reason | Validation expectation | Open questions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-T01 | Assistant turn 4 (this response) | `src/RetryPolicy.cs:3-12`, especially the constructor and `GetDelay()` | The policy owns only the configured `fallbackDelay`; `GetDelay()` currently returns it unconditionally, and there is no server-value validation boundary. | `RetryingClient.WaitBeforeRetryAsync()` is the only production caller of `GetDelay()` (`src/RetryingClient.cs:5-8`); no response/header type, DI wiring, retry loop, or separate test seam exists. The fallback assertion is in `tests/RetryPolicyTests.cs:5-13`. | Raw header text at the policy boundary keeps parsing centralized and lets the policy enforce missing/invalid/negative fallback behavior, but couples the policy to header representation. A pre-parsed nullable `TimeSpan` keeps the policy typed and simpler, but moves parsing and invalid-input semantics to the caller and requires a response/header seam that does not currently exist. A typed delta plus an explicit parse helper separates concerns, but adds a new surface to this three-file scope. | Non-binding proposal: prefer a nullable raw Retry-After value at the policy boundary only if the intended source is an HTTP header; otherwise prefer a nullable typed delta and keep parsing outside the policy. Evidence: the current repository has no response/header abstraction, so the correct boundary cannot be established from existing code alone. | Focused tests should preserve the three-second fallback assertion and cover valid non-negative input plus missing, invalid, and negative input resolving to fallback. The selected API should also make the client path verifiable without weakening cancellation propagation. | Confirm the server-value representation and whether `RetryPolicy` should own raw-header parsing. Also confirm how invalid fallback configuration itself should be treated, since the plan specifies invalid server input but not constructor validation. |

## Discussed but Unlocked

| Topic / Target ID | Observations | Notes for Adaptive Implementation |
| --- | --- | --- |

## Adaptive-Owned

| Topic / Target ID | Why left to HIGH_MODEL | Useful evidence |
| --- | --- | --- |

## No-Change

| Target ID | Reason | Verification expectation |
| --- | --- | --- |

## Known Evidence

- The repository has no project or test-runner metadata; validation mechanism is unresolved until the API/test seam is selected.
- The current client surface is a delay helper rather than a complete throttled-request retry loop.

## Known Assumptions

- `Retry-After` means a non-negative delta value as specified by the plan; date-form parsing is not assumed by the plan and remains an open design question.

## Upstream Decisions Required

| Item | Blocking? | Required owner / decision | Evidence |
| --- | --- | --- | --- |

## Knowledge Candidates

| Candidate | Generalization value | Promotion owner / next step |
| --- | --- | --- |

## Readiness Check

| Check | Status | Evidence |
| --- | --- | --- |
| Goal, scope, and acceptance support implementation start | PASS | `plans/retry-after-plan.md` specifies goal, three-file scope, four acceptance criteria, and validation expectation. |
| Target Map was presented to the user | PASS | Assistant turn 2 (this response), all Target IDs `DP-T01`, `DP-T02`, `DP-T03` presented in the required seven-column table. |
| Target Map presentation includes concrete code structure for every Target | PASS | Assistant turn 2 includes concrete files, symbols/lines, responsibility/invariant, decision candidate, expected verification, evidence, and open question for each Target. |
| Target selection was requested and optional initial positions were invited | PASS | Assistant turn 2 Selection request asks for Target IDs, optional initial positions/concerns, and delegation for unselected Targets. |
| A user response occurred after Target Map presentation | PASS | User turn 3 (`Discuss DP-T01.`), after Assistant turn 2 Target Map presentation. |
| Non-empty user participation or explicit all-Adaptive delegation exists | PASS | User turn 3 selected `DP-T01` for discussion. |
| User-selected discussion targets have final dispositions | FAIL | `DP-T01` is selected but remains `Pending-User-Disposition`; `DP-T02` and `DP-T03` remain `Pending-User-Selection`. |
| Selected Targets have concrete user-facing discussion evidence | PASS | Assistant turn 4 presents the required DP-T01 discussion surface with concrete code locations, invariants, callers/wiring/lifecycle/test seam, alternatives, proposal, validation, and open questions. |
| Locked Decisions have valid post-map confirmation evidence | N/A | No Locked Decision exists. |
| Every Locked, Discussed-Unlocked, and Adaptive-Owned Target has matching post-map Target Disposition Evidence | N/A | No final disposition exists. |
| Locked Decisions do not conflict with upstream contracts | N/A | No Locked Decision exists. |
| No pending human-owned Target remains | FAIL | `DP-T01` is `Pending-User-Disposition`; `DP-T02` and `DP-T03` remain `Pending-User-Selection`. |
| No blocking Upstream-Decision-Required remains | PASS | No Target is classified `Upstream-Decision-Required`. |
| Target Map covers the bounded planned change surface | PASS | The three scoped files, their direct production relationship, test seam, public API, and cancellation path are mapped; repository-wide unrelated areas are excluded. |
| Target Map IDs are unique and every summary ID exists in the Target Map | PASS | Target IDs are exactly `{DP-T01, DP-T02, DP-T03}` and are unique; summary sets remain pending until user disposition. |
| Summary Target sets are pairwise disjoint and exactly cover the Target Map | FAIL | Summary sets are pending and do not yet classify the three Target rows. |
| Summary classifications match every Target Map row Disposition | FAIL | `DP-T01` is `Pending-User-Disposition`; `DP-T02` and `DP-T03` are `Pending-User-Selection`; no final summary classification exists. |
| Locked Decision Target IDs are selected and their Target Map rows are Locked | N/A | No Locked Decision exists. |
| Explicit all-Adaptive delegation has None selected/pending, no Locked Decisions, and every Target is Adaptive-Owned | N/A | All-Adaptive delegation has not been provided. |

## Adaptive Implementation Result

- Status: Pending
- Route used: design-pair -> adaptive-implementation-execution
- Target Map: this artifact / Design Pair Target Map
- Locked Decision IDs: None
- Discussed-Unlocked / Adaptive-Owned items: Pending user response
- Adaptive Implementation verdict sequence: Pending
- Implementation owner sequence: Pending
- Locked Decision compliance evidence: Pending
- Locked Decision conflict: None
- Validation performed: None during Design Pair
- Files changed: `plans/retry-after-plan-design-pair-implementation-handoff.md` only
- Remaining work / human-required work: User must provide DP-T01's final disposition and classify DP-T02 and DP-T03, or explicitly delegate the remaining Targets to Adaptive.
- Final review status: Not performed by this flow
