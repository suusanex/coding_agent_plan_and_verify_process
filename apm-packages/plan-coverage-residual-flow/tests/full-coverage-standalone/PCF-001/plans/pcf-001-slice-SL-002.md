# Plan Kernel

## 目的

Implement the bounded consumer gate and production startup binding slice defined by `SL-002`.

## 非目標

- Producer restore internals and residual policy changes.

## 機能要件

- `SL2-FR-001`: Convert `Active` producer state to `Accepting` and reject non-accepting pushes.

## 受け入れ条件

- `SL2-AC-001`: accepted input returns `Accepted`.
- `SL2-AC-002`: non-accepting input throws the required rejection.

## Black-box behavior coverage

- Expansion required: Yes
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
- Plan readiness: ReadyForRiskTriage
- Expansion decision reason: inherited positive and negative parent cases.
- Blocking requirement-elaboration items: none

### Case-to-Plan mapping

| Case ID | Source IDs | FR / AC | Disposition | Notes |
| --- | --- | --- | --- | --- |
| `CASE-001` | `FR-002`, `AC-001`, `XC-001` | `SL2-FR-001`, `SL2-AC-001` | MappedToPlan | accepted path |
| `CASE-002` | `FR-002`, `AC-002` | `SL2-FR-001`, `SL2-AC-002` | MappedToPlan | rejection path |

## 影響コンポーネント / モジュール

- `src/ConsumerGate.ps1`
- `src/StartupFlow.ps1`

## 実装スコープ

Apply `slices/SL-002` after `SL-001=PARENT_PLAN_VERIFIED` and run its independent verifier.

## 既知の high-risk boundaries

- `XC-001` consumption and production wiring.

## 今回の対象外

- Producer implementation internals and final residual policy.

## change-risk-triage への引き継ぎ

Use inherited `standard-slice` profile and `RC-002`.

## 実装実現性の残留事項

None; production paths and dependency verdict are explicit.

## Handoff Packet

- Profile used: plan-kernel
- Plan artifact: `plans/pcf-001-slice-SL-002.md`
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
- Source artifacts: parent Plan, decomposition, readiness, Slice Architecture, `SL-001` verification
- Selected contracts / IDs: `RC-002`, `TP-002`, `XC-001`
- Implementation-realization residuals: none
- Files inspected: bounded planning artifacts and previous slice verdict
- Files intentionally not inspected: production payload before implementation
- Decisions made: preserve consumer and startup binding scope
- Do not redo unless new evidence appears: inherited slice boundary and dependency
- Remaining work: pre-implementation gates, architecture Match, implementation, verification
- Recommended next step: runtime contract and test design kernels
