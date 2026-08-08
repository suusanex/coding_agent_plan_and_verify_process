# Test Design Kernel

## スコープ

Design independent verification for bounded `SL-002` and `RC-002`.

## Test Design Kernel

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `TP-002` | `RC-002` | accepting consumer branch | No | Yes | `Active -> Accepting -> Accepted` | Done |
| `TP-003` | `RC-002` | non-accepting rejection branch | No | Yes | required exception message | Done |

## 必須 production binding 確認事項

| Test Point ID | Runtime Contract ID | Substitute used / expected | Production implementation to check | Production wiring / entrypoint to check | Notes |
| --- | --- | --- | --- | --- | --- |
| `TP-002` | `RC-002` | none | `src/ConsumerGate.ps1` | `src/StartupFlow.ps1` | bounded verifier checks consumer; cross verifier checks entrypoint |
| `TP-003` | `RC-002` | none | `src/ConsumerGate.ps1` | direct rejection call | verification-kernel must confirm |

## 手動確認のみの項目

None.

## Behavior case test mapping

| Case ID | Runtime Contract ID | Test Point ID | Expected behavior | Coverage disposition | Evidence target | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `CASE-001` | `RC-002` | `TP-002` | accepting path reaches `Accepted` | AutomatedPlanned | `tests/verify-sl-002.ps1` and cross verifier | Done |
| `CASE-002` | `RC-002` | `TP-003` | non-accepting path rejects | AutomatedPlanned | `tests/verify-sl-002.ps1` and cross verifier | Done |

## 注記 / 前提

The verifier imports production functions directly; no substitute is used.

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: bounded Plan and `RC-002`
- Selected contracts / IDs: `RC-002`, `TP-002`, `TP-003`
- Files inspected: planning artifacts only
- Files intentionally not inspected: test and production payloads before implementation
- Decisions made: positive and negative test points are both required
- Behavior case coverage: `CASE-001=AutomatedPlanned`, `CASE-002=AutomatedPlanned`
- Do not redo unless new evidence appears: expected observations and binding requirements
- Remaining work: handoff, implementation, verification
- Recommended next step: `implementation-handoff-review.agent.md`
