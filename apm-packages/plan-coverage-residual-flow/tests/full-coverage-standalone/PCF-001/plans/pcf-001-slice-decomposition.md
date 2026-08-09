# Plan Slice Decomposition

## 親 Plan の要約

Restore producer state, gate consumer work, and verify the production startup path while preserving `XC-001`.

## full-coverage 判定の理由

Two runtime participants and their production wiring require dependent bounded slices and cross-slice verification.

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

Split by producer and consumer ownership; preserve the production entrypoint as the final cross-slice binding.

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

- Goal: restore `snapshot_state=Active` and preserve `correlation_id`.
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
  - Required fields / state / identifiers: `snapshot_state`, `correlation_id`
  - Owned by this slice: both fields
  - Consumed by this slice: input `correlation_id`
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
  - Required fields / state / identifiers: `snapshot_state`, `correlation_id`
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
| `XC-001` | `SL-001` | `SL-002` | producer, consumer, startup entrypoint | object fields and function wiring | `snapshot_state`, `correlation_id`, `Accepting`, `Accepted` | non-accepting rejects; no retry | production entrypoint positive and negative paths | Deferred |

### Architecture traceability

| XC / Slice / Invariant | Architecture source | Projected semantics | Drift allowed? |
| --- | --- | --- | --- |
| `XC-001` | `plans/pcf-001-slice-architecture.md` | exact field continuity and acceptance gate | No |

## Cross-slice field continuity

| Field / state / identifier | Required by | Source artifact / owner | Producer XC | Intermediate storage / artifact | Consumer XC | Fabrication allowed? | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `snapshot_state` | `FR-001`, `AC-001` | `SL-001` | `XC-001` | runtime object | `XC-001` | No | Deferred | must remain `Active` |
| `correlation_id` | `FR-001`, `XC-001` | parent input / `SL-001` | `XC-001` | runtime object | `XC-001` | No | Deferred | exact value preserved |

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
- Conditional artifacts: Behavior Spec (`Expansion required: Yes`); Slice Architecture (`ReadyForSliceDecomposition`); tracked `SL-002` Implementation Completion Handoff (`READY_FOR_STANDARD_COMPLETION`); tracked `SL-002` High-model Re-entry Handoff (`NEEDS_HIGH_MODEL_REENTRY`)
- Exceptions: `plans/pcf-001-slice-SL-002-implementation-completion-handoff.md` / `cross-thread-handoff`, pre-applied before STANDARD delegation; `plans/pcf-001-slice-SL-002-high-model-reentry-handoff.md` / `cross-thread-handoff`, applied by the parent after STANDARD returned an unpersisted payload and before the parent saved it

## Final cross-slice verification requirements

Verify the accepted and rejected postconditions through `src/StartupFlow.ps1`, with exact `XC-001` field continuity.

## Human decisions required

None.

## 今回の decomposition の対象外

External model execution, parallel orchestration, retries, and persistence.

## Handoff Packet

- Profile used: plan-slice-decomposition
- Parent Plan artifact: `plans/pcf-001.md`
- Change Risk Triage artifact: `plans/pcf-001-change-risk-triage.md`
- Slice Decomposition artifact: `plans/pcf-001-slice-decomposition.md`
- Slice artifacts: `plans/pcf-001-slice-SL-001.md`, `plans/pcf-001-slice-SL-002.md`
- Slice IDs: `SL-001`, `SL-002`
- Cross-slice Contract IDs: `XC-001`
- Cross-slice field continuity items: `snapshot_state`, `correlation_id`
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
