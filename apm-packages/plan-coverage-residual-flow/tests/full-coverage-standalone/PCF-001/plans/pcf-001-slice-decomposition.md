# Plan Slice Decomposition

## 親 Plan の要約

Recover and atomically publish producer state, replay it during consumer startup, and verify the production path while preserving `XC-001`.

## full-coverage 判定の理由

Producer recovery/publication and consumer startup/replay are independently owned sequences with separate retry and verification surfaces. Both must preserve one durable identity, state authority, publication protocol, and forbidden-state rule, so one bounded parent pass cannot safely isolate their failures.

### Why standard-slice is insufficient

- Candidate bounded sequence: one parent pass combining recovery, atomic publication, startup, and replay.
- Independent implementation slices required: producer recovery/publish (`SL-001`) and consumer startup/replay (`SL-002`).
- Shared semantics that must remain fixed before decomposition: `correlation_id` plus `generation`, producer-only state authority, atomic `published` protocol, and the stale/incomplete-generation forbidden state.
- Why one bounded parent pass is insufficient: each sequence has an independent owner, entrypoint, recovery lifecycle, and verifier while sharing a protocol that neither slice may redefine.
- Failure mode that decomposition prevents: consumer startup accepts a stale or partially published generation after producer recovery.
- Escalation gate result: Satisfied

## Architecture Slice Readiness

- Readiness artifact: `plans/pcf-001-architecture-slice-readiness.md`
- Verdict: ReadyForSliceDecomposition
- Architecture artifact: `plans/pcf-001-slice-architecture.md`
- Blocking architecture residuals: 0

## Record Metadata

- documentation_level: standard
- selected_process: full-coverage
- artifact_mode: slice-living-record
- Canonical Coverage Ledger: `plans/pcf-001-coverage-ledger.md`

## 分割方針

Split producer recovery/atomic publication from consumer startup/idempotent replay; preserve the durable protocol and production entrypoint as cross-slice bindings.

## Slice 一覧

| Slice ID | Name | Goal | Recommended profile | Immediate next agent | Depends on | Can run in parallel? |
| --- | --- | --- | --- | --- | --- | --- |
| `SL-001` | Producer restore | emit approved producer fields | contract-kernel | slice-local risk delta | none | No |
| `SL-002` | Consumer and entrypoint | consume fields and enforce acceptance | standard-slice | slice-local risk delta | `SL-001` verified | No |

## Slice granularity review

| Slice ID | Too small? | Coalesce target | Reason to keep separate | Decision |
| --- | --- | --- | --- | --- |
| `SL-001` | No | N/A | independently verifiable producer contract | Keep |
| `SL-002` | No | N/A | owns consumer behavior and production wiring | Keep |

## Slice 詳細

### SL-001: Producer restore

- Goal: recover `snapshot_state=Active` and atomically publish `correlation_id`, `generation`, and `published`.
- Non-goals: consumer gate, production entrypoint, residual decision.
- Parent requirements covered: `FR-001`.
- Parent acceptance conditions covered: contribution to `AC-001`.
- Affected components / modules: `src/ProducerState.ps1`.
- Expected implementation scope: one producer function.
- Internal high-risk boundary candidates: output field shape.
- Cross-slice dependencies: none; produces input for `SL-002`.
- Related Cross-slice Contract IDs: `XC-001`.
- Architecture readiness verdict: ReadyForSliceDecomposition.
- Architecture baseline: `plans/pcf-001-slice-architecture.md`.
- Architecture baseline identity: deterministic-fixture-v1 + pcf-001-readiness-v1.
- Architecture source IDs / sections: `SL-001`, `XC-001`.
- Shared invariants consumed: exact field names and correlation value.
- Architecture residuals assigned to this slice: none.
- Black-box behavior coverage:
  - Parent behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
  - Expansion required: Yes
  - Slice Plan readiness: ReadyForRiskTriage
  - Assigned Behavior Case IDs: `CASE-001`
- Case-to-Slice mapping:
  - Case ID: `CASE-001`
  - Parent FR / AC: `FR-001`, `AC-001`
  - Slice FR / AC: `SL1-FR-001`, `SL1-AC-001`
  - Cross-slice Contract ID: `XC-001`
  - Disposition: MappedToPlan
- Cross-slice contract excerpt:
  - XC ID: `XC-001`
  - Architecture source: Slice Architecture
  - This slice role: Producer
  - Mechanism: PowerShell object fields
  - Required fields / state / identifiers: `snapshot_state`, `correlation_id`, `generation`, `published`
  - Owned by this slice: both fields
  - Consumed by this slice: input `correlation_id` and `generation`
  - Deferred / unresolved fields: none
- Small slice justification: N/A unless this is a small independent slice.
  - Independent verification: Yes
  - Independent rollback/discard: Yes
  - Different owner/model/profile needed: No
  - Blocks or unblocks another slice: Yes
  - Why not merged: producer contract must be verified before consumer implementation.
- Implementation-realization risks: none.
- Recommended process profile: contract-kernel.
- Immediate next agent: `change-risk-triage.agent.md` in slice-local delta mode.
- Required inputs for next agent: parent Plan, decomposition, readiness, architecture, canonical ledger.
- Stop condition for this slice: `PARENT_PLAN_VERIFIED` for the bounded slice.

### SL-002: Consumer and production entrypoint

- Goal: derive `Accepting`, reject non-accepting states, and bind the production startup path.
- Non-goals: producer restoration internals and residual policy.
- Parent requirements covered: `FR-002`.
- Parent acceptance conditions covered: `AC-001`, `AC-002`.
- Affected components / modules: `src/ConsumerGate.ps1`, `src/StartupFlow.ps1`.
- Expected implementation scope: consumer functions and startup wiring.
- Internal high-risk boundary candidates: acceptance branch and rejection branch.
- Cross-slice dependencies: `SL-001=PARENT_PLAN_VERIFIED`.
- Related Cross-slice Contract IDs: `XC-001`.
- Architecture readiness verdict: ReadyForSliceDecomposition.
- Architecture baseline: `plans/pcf-001-slice-architecture.md`.
- Architecture baseline identity: deterministic-fixture-v1 + pcf-001-readiness-v1.
- Architecture source IDs / sections: `SL-002`, `XC-001`.
- Shared invariants consumed: exact producer fields and startup postcondition.
- Architecture residuals assigned to this slice: none.
- Black-box behavior coverage:
  - Parent behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
  - Expansion required: Yes
  - Slice Plan readiness: ReadyForRiskTriage
  - Assigned Behavior Case IDs: `CASE-001`, `CASE-002`
- Case-to-Slice mapping:
  - Case ID: `CASE-001`, `CASE-002`
  - Parent FR / AC: `FR-002`, `AC-001`, `AC-002`
  - Slice FR / AC: `SL2-FR-001`, `SL2-AC-001`, `SL2-AC-002`
  - Cross-slice Contract ID: `XC-001`
  - Disposition: MappedToPlan
- Cross-slice contract excerpt:
  - XC ID: `XC-001`
  - Architecture source: Slice Architecture
  - This slice role: Consumer
  - Mechanism: PowerShell function calls
  - Required fields / state / identifiers: `snapshot_state`, `correlation_id`, `generation`, `published`
  - Owned by this slice: consumer state and postcondition
  - Consumed by this slice: producer fields
  - Deferred / unresolved fields: none
- Small slice justification: N/A unless this is a small independent slice.
  - Independent verification: Yes
  - Independent rollback/discard: Yes
  - Different owner/model/profile needed: No
  - Blocks or unblocks another slice: No
  - Why not merged: owns separate consumer and production binding semantics.
- Implementation-realization risks: none.
- Recommended process profile: standard-slice.
- Immediate next agent: `change-risk-triage.agent.md` in slice-local delta mode.
- Required inputs for next agent: parent Plan, decomposition, readiness, architecture, canonical ledger, `SL-001` verification.
- Stop condition for this slice: `PARENT_PLAN_VERIFIED` for the bounded slice.

## Cross-slice contracts

| Cross-slice Contract ID | Producer slice | Consumer slice | Runtime participants | Mechanism | Required fields / state / identifiers | Error / retry / recovery expectation | Verification requirement | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `XC-001` | `SL-001` | `SL-002` | producer, durable store, consumer, startup entrypoint | atomic file publication and later read-only observation | `snapshot_state`, `correlation_id`, `generation`, `published`, `Accepting`, `Accepted` | producer retry replaces one generation atomically; consumer replay is idempotent; stale/incomplete state rejects | production entrypoint, replay, and forbidden-state paths | Deferred |

### Architecture traceability

| XC / Slice / Invariant | Architecture source | Projected semantics | Drift allowed? |
| --- | --- | --- | --- |
| `XC-001` | `plans/pcf-001-slice-architecture.md` | exact field continuity and acceptance gate | No |

## Cross-slice field continuity

| Field / state / identifier | Required by | Source artifact / owner | Producer XC | Intermediate storage / artifact | Consumer XC | Fabrication allowed? | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `snapshot_state` | `FR-001`, `AC-001` | `SL-001` | `XC-001` | runtime object | `XC-001` | No | Deferred | must remain `Active` |
| `correlation_id` | `FR-001`, `XC-001` | parent input / `SL-001` | `XC-001` | runtime object | `XC-001` | No | Deferred | exact value preserved |
| `generation` | `FR-001`, `FR-002`, `XC-001` | parent input / `SL-001` | `XC-001` | durable store | `XC-001` | No | Deferred | exact generation preserved and stale generations rejected |
| `published` | `AC-001`, `AC-002`, `XC-001` | `SL-001` | `XC-001` | durable store | `XC-001` | No | Deferred | only a completed atomic publication is observable |

## Parent contract mapping

| Parent Contract ID | Disposition | Slice ID | Cross-slice Contract ID | Notes |
| --- | --- | --- | --- | --- |
| `FR-001` | MappedToSlice | `SL-001` | `XC-001` | producer ownership |
| `FR-002` | MappedToSlice | `SL-002` | `XC-001` | consumer ownership |
| `AC-001` | CrossSlice | `SL-001`, `SL-002` | `XC-001` | production startup path |
| `AC-002` | MappedToSlice | `SL-002` | `XC-001` | rejection branch |

## Behavior Case mapping

| Case ID | Parent FR / AC | Disposition | Slice ID | Cross-slice Contract ID | Evidence route | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `CASE-001` | `FR-001`, `FR-002`, `AC-001` | CrossSlice | `SL-001`, `SL-002` | `XC-001` | three runtime verifiers | accepted path |
| `CASE-002` | `FR-002`, `AC-002` | MappedToSlice | `SL-002` | `XC-001` | slice and cross verifier | rejection path |

## Execution order

1. Update the `SL-001` Living Record by section delta, require architecture `Match`, aggregate Adaptive Implementation evidence, and run independent verification.
2. Before HIGH to STANDARD delegation for `SL-002`, apply its tracked-handoff Artifact Exception row, create the supplemental completion handoff, finish implementation, and verify the slice after `SL-001=PARENT_PLAN_VERIFIED` with pending ledger delta count 0.
3. Run Cross-Slice Verification after both bounded Plan verdicts are `PARENT_PLAN_VERIFIED`.
4. Consume `CROSS_SLICE_PARTIAL_WITH_FIX_CANDIDATES` through target-slice triage, one bounded repair pass, `SL-002` re-verification, and a cross-slice verification rerun.
5. Run Residual Decision only after the rerun returns `CROSS_SLICE_VERIFIED`.

## Artifact Budget

- Base parent artifacts: 5
- Executable slices: 2
- Slice Living Records: 2
- Final close artifact: 1
- Base expected total: 8
- Conditional artifacts: Behavior Spec (`Expansion required: Yes`); Slice Architecture (`ReadyForSliceDecomposition`); tracked `SL-002` Bounded Residual Implementation Handoff (`READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION`); tracked `SL-002` Decision-Surface Re-entry Handoff (`NEEDS_DECISION_SURFACE_REENTRY`)
- Exceptions: `plans/pcf-001-slice-SL-002-bounded-residual-implementation-handoff.md` / `cross-thread-handoff`, pre-applied before bounded-residual-implementation-owner delegation; `plans/pcf-001-slice-SL-002-decision-surface-reentry-handoff.md` / `cross-thread-handoff`, applied by the parent after bounded-residual-implementation-owner returned an unpersisted payload and before the parent saved it

## Final cross-slice verification requirements

Verify the accepted and rejected postconditions through `src/StartupFlow.ps1`, with exact `XC-001` field continuity.

## Human decisions required

None.

## 今回の decomposition の対象外

External model execution, parallel orchestration, and external services.

## Handoff Packet

- Profile used: plan-slice-decomposition
- Parent Plan artifact: `plans/pcf-001.md`
- Change Risk Triage artifact: `plans/pcf-001-change-risk-triage.md`
- Slice Decomposition artifact: `plans/pcf-001-slice-decomposition.md`
- Slice artifacts: `plans/pcf-001-slice-SL-001.md`, `plans/pcf-001-slice-SL-002.md`
- Slice IDs: `SL-001`, `SL-002`
- Cross-slice Contract IDs: `XC-001`
- Cross-slice field continuity items: `snapshot_state`, `correlation_id`, `generation`, `published`
- Slice granularity review: both slices kept
- Behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
- Behavior Case IDs: `CASE-001`, `CASE-002`
- Source artifacts: parent Plan, triage, readiness, Slice Architecture
- Files inspected: planning artifacts only
- Files intentionally not inspected: production payloads; decomposition is document-only
- Decisions made: producer then consumer, followed by cross-slice verification
- Do not redo unless new evidence appears: slice ownership and execution order
- Remaining work: both Slice Living Record lifecycles, cross-slice verification, residual decision
- Recommended next step: run slice-local risk delta for `SL-001`
- Required downstream guardrails: each slice reads parent and decomposition; bounded scope/non-goals; RC/XC mapping; architecture Match; parent-only Living Record and ledger writes; independent verification
- Artifact mode: `slice-living-record`
- Living Record writer: Plan Coverage parent/router only
- Canonical Coverage Ledger writer: Plan Coverage parent/router only
