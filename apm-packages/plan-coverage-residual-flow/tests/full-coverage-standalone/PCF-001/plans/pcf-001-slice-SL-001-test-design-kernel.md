# Test Design Kernel

## スコープ

Design independent verification for bounded `SL-001` and `RC-001`.

## Test Design Kernel

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `TP-001` | `RC-001` | producer fields and exact correlation continuity | No | Yes | `Active` and `pcf-001` from production function | Done |

## 必須 production binding 確認事項

| Test Point ID | Runtime Contract ID | Substitute used / expected | Production implementation to check | Production wiring / entrypoint to check | Notes |
| --- | --- | --- | --- | --- | --- |
| `TP-001` | `RC-001` | none | `src/ProducerState.ps1` | direct function import by verifier | verification-kernel must confirm |

## 手動確認のみの項目

None.

## Behavior case test mapping

| Case ID | Runtime Contract ID | Test Point ID | Expected behavior | Coverage disposition | Evidence target | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `CASE-001` | `RC-001` | `TP-001` | producer emits approved fields | AutomatedPlanned | `tests/verify-sl-001.ps1` | Done |

## 注記 / 前提

The verifier imports the production implementation directly; no substitute is used.

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: bounded Plan and `RC-001`
- Selected contracts / IDs: `RC-001`, `TP-001`
- Files inspected: planning artifacts only
- Files intentionally not inspected: test and production payloads before implementation
- Decisions made: one direct production verifier covers the bounded contract
- Behavior case coverage: `CASE-001=AutomatedPlanned`
- Do not redo unless new evidence appears: expected observations and binding requirement
- Remaining work: handoff, implementation, verification
- Recommended next step: `implementation-handoff-review.agent.md`
