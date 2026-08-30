# SL-002: Bind consumer gate and startup flow

## Record Metadata

- Parent Plan: `plans/pcf-001.md`
- Slice ID: `SL-002`
- artifact_mode: slice-living-record
- documentation_level: standard
- implementation_route: adaptive
- implementation_route_source: default
- design_pair_handoff: N/A
- design_pair_interaction_stage: not-started
- Canonical Coverage Ledger: `plans/pcf-001-coverage-ledger.md`
- Current architecture baseline: `plans/pcf-001-slice-architecture.md` via current readiness verdict
- Artifact exceptions: tracked implementation completion handoff registered before cross-model delegation.

## Slice Plan / Scope

- Goal: bind the consumer gate and production startup flow after `SL-001` verification.
- Non-goals: change the producer contract or redefine shared architecture.
- Parent requirements covered: `FR-002`
- Parent acceptance conditions covered: `AC-001`, `AC-002`
- Affected components / modules: `src/ConsumerGate.ps1`, `src/StartupFlow.ps1`
- Expected implementation scope: apply `slices/SL-002` and run positive and negative independent verification.
- Stop condition: `PARENT_PLAN_VERIFIED` with the consumer ledger delta applied.

## Parent / Behavior Mapping

### FR / AC mapping

| Parent item | Slice item | Disposition |
| --- | --- | --- |
| `FR-002` | `SL2-FR-001` | ImplementInSlice |
| `AC-001` | `SL2-AC-001` | CoveredByCrossSliceVerification after slice contribution |
| `AC-002` | `SL2-AC-002` | ImplementInSlice |

### Black-box Behavior Coverage

- Behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
- Expansion required: Yes
- Slice Plan readiness: ReadyForRiskTriage

### Case-to-Slice Mapping

| Case ID | Parent FR / AC | Slice FR / AC | Cross-slice Contract ID | Disposition |
| --- | --- | --- | --- | --- |
| `CASE-001` | `FR-002`, `AC-001` | `SL2-FR-001`, `SL2-AC-001` | `XC-001` | ImplementInSlice |
| `CASE-002` | `FR-002`, `AC-002` | `SL2-FR-001`, `SL2-AC-002` | `XC-001` | ImplementInSlice |

## Cross-Slice Contracts / Field Continuity

- Related XC IDs: `XC-001`
- Producer / Consumer role: Consumer
- Required fields / state / identifiers: consume `SnapshotState=Active` and the exact `CorrelationId`; consumer must be `Accepting` before push.
- Source authority: `plans/pcf-001-slice-decomposition.md`, `plans/pcf-001-slice-architecture.md`, verified `SL-001` record.
- Deferred / unresolved items: parent production postcondition remains for final cross-slice verification.

### Unresolved Decision Ownership

| Item ID | Item | Classification | Decision owner | Human input required | Blocking | Resolution phase | Source evidence / next action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| none | none | none | none | No | No | none | No unresolved decision ownership is assigned to this slice. |

## Slice Risk / Guardrail Selection

- Inherited parent risks: startup wiring, positive/negative state handling, cross-slice field continuity, no fake-only completion.
- Slice-local added risks: production entrypoint binding.
- Slice-local removed / not-applicable risks: producer implementation is verified in `SL-001`.
- Implementation realization risk: Absent
- Selected Runtime Contract IDs: `RC-002`
- Selected Test Point scope: `TP-002`, `TP-003`
- Human decision blockers: none
- Recommended next phase: Runtime Contract, Test Design, Inline Ready Gate

## Implementation Contract Decisions

N/A - the approved consumer functions and production startup address are explicit.

### Independent Review

N/A - no explicit review-only fallback was invoked.

## Runtime Contract

| Contract ID | Scenario | Producer | Consumer | Message / API / Event | Required fields | Error / timeout behavior | Production implementation address | Verification hook |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `RC-002` | observe durable producer state, replay startup, and push item | durable snapshot reader | `Push-ConsumerItem` | read-only durable observation plus PowerShell calls | `SnapshotState`, `CorrelationId`, `Generation`, `Published`, consumer `State` | stale or incomplete identity rejects before admission; non-accepting state throws `Consumer is not accepting items.` | `src/ConsumerGate.ps1`, `src/StartupFlow.ps1` | `TP-002`, `TP-003` |

## Test Design

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `TP-002` | `RC-002` | matching published generation and idempotent replay | No | Yes | generation 7 replays repeatedly as `Active -> Accepting -> Accepted` | Done |
| `TP-003` | `RC-002` | non-accepting, stale-generation, and incomplete-publication rejection | No | Yes | no forbidden state becomes `Accepting`; required exceptions are observed | Done |

## Inline Ready Gate

- Formal implementation-handoff-review verdict: `READY_FOR_BOUNDED_PARENT_PLAN_PASS`
- Readiness scope: `SL-002` only after verified `SL-001`
- Parent coverage state: `FR-002`, `AC-001`, `AC-002` mapped
- Behavior Case coverage state: `CASE-001`, `CASE-002` mapped to `RC-002` / `TP-002` / `TP-003` / `XC-001`
- Architecture baseline identity: current `plans/pcf-001-slice-architecture.md` tracked by readiness
- Architecture compatibility: Match
- Implementation allowed: Yes
- Blocking issues: none

| Slice ID | Readiness verdict | Baseline authority | Baseline identity | Observed semantics | Architecture compatibility | Required action |
| --- | --- | --- | --- | --- | --- | --- |
| `SL-002` | `ReadyForSliceDecomposition` | Slice Architecture artifact | current tracked content hash | consumer and startup follow approved transition | Match | proceed to Adaptive Implementation |

## Implementation Evidence

- Implementation route: adaptive / default
- Model / owner sequence: decision-surface-implementation-owner -> `READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION` -> bounded-residual-implementation-owner -> `NEEDS_DECISION_SURFACE_REENTRY` payload -> Plan Coverage parent Artifact Creation Gate -> decision-surface-implementation-owner -> `IMPLEMENTATION_COMPLETED`
- Re-entry persistence sequence: bounded-residual-implementation-owner returned an unpersisted payload -> Plan Coverage parent applied the exact-path Artifact Exceptions row -> parent persisted the tracked handoff -> decision-surface-implementation-owner resumed.
- Files / symbols changed: `src/ConsumerGate.ps1`, `src/StartupFlow.ps1`
- Validation performed: implementation-local syntax/load check passed after `SL-001=PARENT_PLAN_VERIFIED`.
- Acceptance evidence: accepting and rejecting production paths implemented; independent verifier remained separate.
- Remaining work: independent verification only.

### Implementation Self-Map

| Change ID | Change | File / Symbol | Reason | Related Plan item | Related Behavior Case IDs | Related SL / XC / RC / TP / IC / Gap item | Assumption made | Review hint |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `SL-002-IMPL-001` | add consumer gate and startup binding | `src/ConsumerGate.ps1`, `src/StartupFlow.ps1` | implement approved consumer role and wiring | `FR-002`, `AC-001`, `AC-002` | `CASE-001`, `CASE-002` | `SL-002`, `XC-001`, `RC-002`, `TP-002`, `TP-003` | none | verify both accepting and rejecting paths |

## Gap Repair Evidence

- Selected selectors: `GAP-001`
- Production / test changes: corrected the bounded `SL-002` startup acceptance wiring and retained the negative-path verifier.
- Targeted validation: `tests/verify-sl-002.ps1` and `tests/verify-cross-slice.ps1` passed after the repair.
- Repair verdict: `RESOLVED_FOR_SELECTED_SCOPE`
- Re-verification required: Yes; completed with `PARENT_PLAN_VERIFIED`
- Remaining repair scope: none

## Verification Result

- Formal verification-kernel verdict: `PARENT_PLAN_VERIFIED`
- Verification scope: `SL-002`, `RC-002`, `TP-002`, `TP-003`
- Production binding evidence: `tests/verify-sl-002.ps1` imports the production consumer functions and observes idempotent replay, `Accepting`, `Accepted`, non-accepting rejection, and stale-generation rejection.
- Behavior Case evidence: `CASE-001` and `CASE-002` slice contributions observed.
- Fake / stub / mock assessment: no substitute used.
- Remaining gaps: final production entrypoint and full `XC-001` postcondition require cross-slice verification.

## Coverage Ledger Delta

| Delta ID | Source phase | Plan item / Case ID / Residual ID | Previous status | New status | Evidence / reason | Applied to canonical ledger? |
| --- | --- | --- | --- | --- | --- | --- |
| `SL-002-READY-001` | Inline Ready Gate | `FR-002`, `AC-001`, `AC-002`, `CASE-001`, `CASE-002` | Planned | ReadyForImplementation | formal handoff verdict and architecture Match | Yes |
| `SL-002-IMPL-001` | Adaptive implementation | `FR-002` | ReadyForImplementation | Implemented | production consumer and startup implementation applied | Yes |
| `SL-002-VERIFY-001` | Verification | `FR-002`, `AC-002`, `CASE-001`, `CASE-002` | Implemented | VerifiedInSlice | independent positive and negative verifier passed | Yes |
| `SL-002-TRIAGE-001` | Gap Triage | `GAP-001`, `AC-001`, `XC-001` | CrossSliceFixCandidate | FixNowSelected | target slice and bounded selector classified | Yes |
| `SL-002-REPAIR-001` | Gap Repair | `GAP-001`, `AC-001`, `XC-001` | FixNowSelected | RepairedPendingVerification | bounded production wiring repair and targeted tests passed | Yes |
| `SL-002-REVERIFY-001` | Verification Rerun | `GAP-001`, `AC-001`, `XC-001` | RepairedPendingVerification | VerifiedInSlice | independent slice verification rerun returned PARENT_PLAN_VERIFIED | Yes |

## Slice Residuals / Handoff

- FixNow candidates: none
- Manual verification candidates: none
- NeedsHumanDecision: none
- Cross-slice verification dependencies: `XC-001`, `AC-001`, production `src/StartupFlow.ps1`
- Remaining blocking items: none within this slice
- Recommended next step: run cross-slice verification after confirming all slice pending ledger delta counts are 0.

## Artifact Exceptions

| Path | Reason code | Why separate artifact is required | Owner | Canonical or supplemental | Lifecycle |
| --- | --- | --- | --- | --- | --- |
| `plans/pcf-001-slice-SL-002-bounded-residual-implementation-handoff.md` | `cross-thread-handoff` | decision-surface to bounded-residual cross-model delegation requires tracked state | Plan Coverage parent / Adaptive implementation | supplemental | created only after this row was applied; retained through verification |
| `plans/pcf-001-slice-SL-002-decision-surface-reentry-handoff.md` | `cross-thread-handoff` | bounded-residual to decision-surface re-entry requires tracked state after the trigger is known | Plan Coverage parent / Adaptive implementation | supplemental | parent persisted only after payload returned and this row was applied; retained through verification |
