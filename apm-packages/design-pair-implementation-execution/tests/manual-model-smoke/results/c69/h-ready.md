# Design Pair Implementation Handoff

- Verdict: READY_FOR_ADAPTIVE_IMPLEMENTATION
- Interaction stage: complete
- Route: design-pair
- implementation_route: design-pair
- implementation_route_source: explicit-user-selection
- Plan / Implementation Intent reference: `plans/retry-after-plan.md`
- Upstream artifacts: `plans/retry-after-plan.md`
- Handoff review reference, when present: N/A; ordinary Plan / Implementation Intent route
- Tracked handoff path: `plans/retry-after-plan-design-pair-implementation-handoff.md`
- Worktree / revision evidence: `master` at `b047ef7ac63d093edf92a6b9094c12f3a0655a25`; pre-existing untracked `smoke-logs/` is unrelated
- Target Map presentation evidence: this Design Pair target-map response, presenting `DP-T01`, `DP-T02`, and `DP-T03`
- Target selection request evidence: this Design Pair target-map response
- Latest user response reference: User turn 4 (`2026-08-05T23:10:04.178+09:00`)
- User response occurred after Target Map presentation: Yes / User turn 4
- Selected Target IDs: `DP-T01`
- Delegated-to-Adaptive Target IDs: `DP-T02`, `DP-T03`
- No-Change Target IDs: None
- Upstream-Decision-Required Target IDs: None
- Explicit all-Adaptive delegation: No
- Pending human-owned Target IDs: None
- Selected Target discussion evidence: `DP-T01` / Assistant turn 3
- Parent / resume state reference: N/A
- Adaptive implementation behavior: unchanged
- Locked decision policy: binding-only-for-explicit-entries
- Production code / tests edited during Design Pair: No

## Design Pair Target Map

| Target ID | File / Symbol | Current responsibility | Current invariant | Relation to requested change | Internal design decision candidate | Expected modification or verification | Relevant evidence | Open question | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-T01 | `src/RetryPolicy.cs` / `RetryPolicy.GetDelay` and constructor | Stores the configured fallback delay and returns it for every retry. | `GetDelay()` returns the constructor-provided `TimeSpan`; no server response data is currently accepted. | This is the planned policy boundary for interpreting a server-provided `Retry-After` delta while retaining fallback behavior for missing, invalid, or negative input. | Use a nullable `TimeSpan` at the policy boundary; keep string parsing at the external boundary and pass typed data between C# classes. | Modify policy behavior and add focused policy-level verification for valid, missing, invalid, and negative values without changing cancellation ownership. | `src/RetryPolicy.cs:5-12`; the plan proposes policy-owned parsing, while the post-map user decision explicitly limits parsing to the external boundary. | How the external boundary maps malformed or negative input to `null` remains implementation-owned under the delegated client/test Targets. | Locked |
| DP-T02 | `src/RetryingClient.cs` / `RetryingClient.WaitBeforeRetryAsync` | Waits before retrying by delaying with the policy's selected delay. | The delay is awaited with the caller's `CancellationToken`, so cancellation must continue to interrupt the wait. | The caller must supply the throttled response's retry information to policy selection while preserving cancellation-aware `Task.Delay` behavior. | Decide how retry metadata reaches the client and whether the client remains a thin orchestration layer or performs any normalization before calling policy. | Wire the selected delay into the existing async wait and verify the caller token is still passed to `Task.Delay`; inspect any signature change for direct callers. | `src/RetryingClient.cs:3-7`; direct symbol search found no other production callers or DI/startup wiring. | What response/header representation should be passed to `WaitBeforeRetryAsync` without making the client own parsing rules? | Adaptive-Owned |
| DP-T03 | `tests/RetryPolicyTests.cs` / `RetryPolicyTests` | Provides manual focused coverage for the configured fallback delay. | A mismatch throws `InvalidOperationException`; the test seam directly constructs `RetryPolicy` and compares `TimeSpan` values. | Acceptance requires focused coverage for server delay and fallback behavior, including invalid and negative inputs. | Decide the minimum case matrix and whether cancellation behavior is tested at policy level, client level, or both given the repository has no project/test runner metadata. | Extend focused tests around the chosen policy/client contract; verify valid delta, missing/invalid/negative fallback, and cancellation-aware client waiting as applicable. | `tests/RetryPolicyTests.cs:3-13`; only test file in repository; no `.csproj`, `.sln`, test fixture, or runner configuration found. | Which test cases are required to prove the final input contract and cancellation seam without inventing a new test harness? | Adaptive-Owned |

## Upstream Binding Constraints

| Constraint ID | Constraint | Source artifact | Evidence | Relation to Target IDs |
| --- | --- | --- | --- | --- |
| UP-C01 | Use a valid server-provided non-negative `Retry-After` delta for the next retry. | `plans/retry-after-plan.md` | Goal and acceptance criterion lines 5 and 15 | `DP-T01`, `DP-T02`, `DP-T03` |
| UP-C02 | Missing, invalid, or negative input uses the configured fallback delay. | `plans/retry-after-plan.md` | Acceptance criterion line 16 | `DP-T01`, `DP-T03` |
| UP-C03 | The caller remains cancellation-aware. | `plans/retry-after-plan.md` | Acceptance criterion line 17 and existing token-aware delay | `DP-T02`, `DP-T03` |
| UP-C04 | Focused tests cover server delay and fallback behavior. | `plans/retry-after-plan.md` | Acceptance criterion line 18 and scope line 12 | `DP-T03` |

## Upstream User Initial Positions

| Position ID | Initial position | Source user message / turn | Relation to Target IDs | Status |
| --- | --- | --- | --- | --- |
| UP-P01 | Keep parsing inside `RetryPolicy`. | `plans/retry-after-plan.md`, initial technical proposal | `DP-T01`, `DP-T02` | Upstream initial position; not a Design Pair confirmation |

## Locked Decisions

| Decision ID | Target ID | Decision | Affected files / symbols | Rationale | Validation expectations | Conflict conditions | User message / turn reference | Confirmed content quote or faithful summary | Confirmation occurred after Target Map presentation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-D01 | DP-T01 | `RetryPolicy` receives `TimeSpan?`; string parsing is restricted to the external boundary, and C# classes exchange typed data. | `src/RetryPolicy.cs` / `RetryPolicy.GetDelay`; external boundary mapping is implementation-owned in the adaptive surface. | Keeps policy and class-to-class communication strongly typed while preserving nullable fallback semantics. | Valid non-negative values use the supplied duration; missing/invalid/negative inputs use fallback under the upstream contract. | A raw string reaches `RetryPolicy`, or policy parses transport syntax internally. | User turn 4 (`2026-08-05T23:10:04.178+09:00`) | User explicitly specified nullable `TimeSpan`, external-boundary-only string parsing, and typed C# class communication. | Yes |

## Target Disposition Evidence

| Target ID | Final disposition | User message / turn reference | Confirmed content quote or faithful summary | Confirmation after Target Map |
| --- | --- | --- | --- | --- |
| DP-T01 | Locked | User turn 4 (`2026-08-05T23:10:04.178+09:00`) | `RetryPolicy` accepts `TimeSpan?`; parsing is external-boundary-only; C# class communication is typed. | Yes |
| DP-T02 | Adaptive-Owned | User turn 4 (`2026-08-05T23:10:04.178+09:00`) | Explicitly delegated to Adaptive. | Yes |
| DP-T03 | Adaptive-Owned | User turn 4 (`2026-08-05T23:10:04.178+09:00`) | Explicitly delegated to Adaptive. | Yes |

## Selected Target Discussion Evidence

| Target ID | Assistant turn reference | Concrete file / symbol / line evidence | Current responsibility / invariant | Caller / wiring / lifecycle / test-seam evidence | Alternatives and trade-offs | Non-binding AI proposal or No proposal reason | Validation expectation | Open questions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

| DP-T01 | Assistant turn 3 (`2026-08-05T23:08:02.469+09:00`) | `src/RetryPolicy.cs:5-12`, especially constructor line 7 and `GetDelay()` line 12. | Owns the configured fallback delay and currently returns it unchanged; it has no response/header input and no async or cancellation responsibility. | `RetryingClient.WaitBeforeRetryAsync` currently calls `retryPolicy.GetDelay()` at `src/RetryingClient.cs:7`; no other production callers, DI, factory, startup, or configuration wiring were found. The existing test seam directly constructs the policy in `tests/RetryPolicyTests.cs:7`. | Raw `string?` parsing inside policy keeps the proposed boundary centralized and lets missing/invalid values map to fallback, but couples policy to header syntax. A typed nullable `TimeSpan` or nullable non-negative delta keeps parsing outside policy and improves separation, but requires a caller/transport parsing seam that does not currently exist. A dedicated value object can make validity explicit, but adds API and test surface to a minimal repository. | Non-binding proposal: accept the server delta at the policy boundary as a nullable raw value and parse it using invariant rules, accepting only a non-negative delta and returning the configured fallback for null, malformed, negative, or out-of-range input. This is supported by the plan's explicit “keep parsing inside `RetryPolicy`” initial proposal and the absence of any existing transport abstraction; it remains subject to user disposition. | Add focused policy cases for valid non-negative input, missing input, malformed input, negative input, and any overflow/out-of-range case implied by the chosen representation. Confirm that fallback behavior remains unchanged. Client cancellation remains a separate verification under `DP-T02`. | Should “delta” be represented as HTTP `delta-seconds` text, a `TimeSpan`, or another typed value? Should whitespace and numeric overflow be accepted or treated as invalid? |

## Discussed but Unlocked

| Topic / Target ID | Observations | Notes for Adaptive Implementation |
| --- | --- | --- |

None.

## Adaptive-Owned

| Topic / Target ID | Why left to HIGH_MODEL | Useful evidence |
| --- | --- | --- |
| DP-T02 | Explicitly delegated by the user after Target Map presentation. | `RetryingClient.WaitBeforeRetryAsync` currently owns cancellation-aware waiting at `src/RetryingClient.cs:5-7`. |
| DP-T03 | Explicitly delegated by the user after Target Map presentation. | `RetryPolicyTests` is the focused test seam at `tests/RetryPolicyTests.cs:3-13`. |

## No-Change

| Target ID | Reason | Verification expectation |
| --- | --- | --- |

None.

## Known Evidence

- `RetryPolicy` is the only current owner of the fallback delay value.
- `RetryingClient.WaitBeforeRetryAsync` is the only current production retry-wait call site found.
- The existing client passes its caller-owned `CancellationToken` directly to `Task.Delay`.
- No DI, factory, startup, entrypoint, configuration, serialized contract, project file, or test runner metadata was found in the bounded repository.

## Known Assumptions

- The server-provided value will represent a delta rather than an absolute HTTP date because the plan's acceptance criteria explicitly require a non-negative delta.
- The existing manual test style is the available focused test seam; implementation may need to preserve that style unless the upstream contract supplies runner metadata.

## Upstream Decisions Required

| Item | Blocking? | Required owner / decision | Evidence |
| --- | --- | --- | --- |

None identified from the Plan / Implementation Intent.

## Knowledge Candidates

| Candidate | Generalization value | Promotion owner / next step |
| --- | --- | --- |

None.

## Readiness Check

| Check | Status | Evidence |
| --- | --- | --- |
| Goal, scope, and acceptance support implementation start | PASS | `plans/retry-after-plan.md` provides a concrete goal, three-file scope, and four acceptance criteria. |
| Target Map was presented to the user | PASS | This Design Pair target-map response presents `DP-T01`, `DP-T02`, and `DP-T03` with all required fields. |
| Target Map presentation includes concrete code structure for every Target | PASS | The response names each file and symbol, current responsibility/invariant, decision candidate, evidence, expected verification, and open question. |
| Target selection was requested and optional initial positions were invited | PASS | This response requests Target IDs, optional concerns/proposals, and explicit delegation for unselected Targets. |
| A user response occurred after Target Map presentation | PASS | User turn 4 (`2026-08-05T23:10:04.178+09:00`) supplied the final `DP-T01` decision and delegated `DP-T02`/`DP-T03` after the Target Map. |
| Non-empty user participation or explicit all-Adaptive delegation exists | PASS | User selected discussion Target `DP-T01`. |
| User-selected discussion targets have final dispositions | PASS | `DP-T01` is `Locked` by User turn 4. |
| Selected Targets have concrete user-facing discussion evidence | PASS | `DP-T01`, Assistant turn 3: concrete policy symbol, caller/test seam, alternatives, proposal, validation, and open questions were presented. |
| Locked Decisions have valid post-map confirmation evidence | PASS | DP-D01 has a unique post-map confirmation from User turn 4, with explicit content and `Yes`. |
| Every Locked, Discussed-Unlocked, and Adaptive-Owned Target has matching post-map Target Disposition Evidence | PASS | Exact matching rows exist for `DP-T01` (`Locked`), `DP-T02` (`Adaptive-Owned`), and `DP-T03` (`Adaptive-Owned`), all referencing User turn 4. |
| Locked Decisions do not conflict with upstream contracts | PASS | DP-D01 preserves the upstream valid-delta and fallback requirements while constraining only the class-to-class representation. |
| No pending human-owned Target remains | PASS | All Targets have final post-map dispositions. |
| No blocking Upstream-Decision-Required remains | PASS | No upstream decision is required by the Plan / Implementation Intent. |
| Target Map covers the bounded planned change surface | PASS | The Plan's entire scope is represented by the policy, client, and focused test seam Targets; no unrelated repository areas were included. |
| Target Map IDs are unique and every summary ID exists in the Target Map | PASS | Map IDs are the unique set `{DP-T01, DP-T02, DP-T03}`; all summary references are pending and introduce no other IDs. |
| Summary Target sets are pairwise disjoint and exactly cover the Target Map | PASS | Selected `{DP-T01}` union delegated `{DP-T02, DP-T03}` equals `{DP-T01, DP-T02, DP-T03}`; all other sets are empty and disjoint. |
| Summary classifications match every Target Map row Disposition | PASS | `DP-T01` is `Locked`; `DP-T02` and `DP-T03` are `Adaptive-Owned`; the summary uses the same classifications. |
| Locked Decision Target IDs are selected and their Target Map rows are Locked | PASS | DP-D01 targets `DP-T01`, which is in Selected Target IDs and has Map disposition `Locked`. |
| Explicit all-Adaptive delegation has None selected/pending, no Locked Decisions, and every Target is Adaptive-Owned | N/A | Explicit all-Adaptive delegation is No. |
