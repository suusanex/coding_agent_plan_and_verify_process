# Plan Kernel

## 目的

Implement the bounded producer restore slice defined by `SL-001`.

## 非目標

- Consumer acceptance, production entrypoint binding, and residual decision.

## 機能要件

- `SL1-FR-001`: Emit `snapshot_state=Active` and preserve `correlation_id`.

## 受け入れ条件

- `SL1-AC-001`: `tests/verify-sl-001.ps1` observes the required fields from `src/ProducerState.ps1`.

## Black-box behavior coverage

- Expansion required: Yes
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
- Plan readiness: ReadyForRiskTriage
- Expansion decision reason: inherited from the parent bounded slice assignment.
- Blocking requirement-elaboration items: none

### Case-to-Plan mapping

| Case ID | Source IDs | FR / AC | Disposition | Notes |
| --- | --- | --- | --- | --- |
| `CASE-001` | `FR-001`, `AC-001`, `XC-001` | `SL1-FR-001`, `SL1-AC-001` | MappedToPlan | producer contribution |

## 影響コンポーネント / モジュール

- `src/ProducerState.ps1`

## 実装スコープ

Apply `slices/SL-001` and run its independent verifier.

## 既知の high-risk boundaries

- `XC-001` producer field shape.

## 今回の対象外

- `SL-002` and cross-slice close decision.

## change-risk-triage への引き継ぎ

Use inherited `contract-kernel` profile and `RC-001`.

## 実装実現性の残留事項

None; production path is explicit.

## Handoff Packet

- Profile used: plan-kernel
- Plan artifact: `plans/pcf-001-slice-SL-001.md`
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
- Source artifacts: parent Plan, decomposition, readiness, Slice Architecture
- Selected contracts / IDs: `RC-001`, `TP-001`, `XC-001`
- Implementation-realization residuals: none
- Files inspected: bounded planning artifacts
- Files intentionally not inspected: production payload before implementation
- Decisions made: preserve producer-only scope
- Do not redo unless new evidence appears: inherited slice boundary
- Remaining work: pre-implementation gates, architecture Match, implementation, verification
- Recommended next step: runtime contract and test design kernels
