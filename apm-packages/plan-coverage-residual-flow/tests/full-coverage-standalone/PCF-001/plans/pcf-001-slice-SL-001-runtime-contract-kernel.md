# Runtime Contract Kernel

## スコープ

Bounded `SL-001` producer contract inherited from `RC-001` and `XC-001`.

## Runtime Contract Kernel

| Contract ID | Scenario | Producer | Consumer | Message / API / Event | Required fields | Error / timeout behavior | Production implementation address | Verification hook |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `RC-001` | restore producer snapshot | `Restore-ProducerSnapshot` | `SL-002` consumer gate | PowerShell object return | `SnapshotState`, `CorrelationId` | invalid/missing correlation is rejected by mandatory parameter binding; timeout N/A | `src/ProducerState.ps1` | `TP-001` |

## Plan / implementation contract 適合性

| Runtime Contract ID | Plan requirement | Implementation contract decision | Runtime contract address | Conformance |
| --- | --- | --- | --- | --- |
| `RC-001` | `SL1-FR-001`, `FR-001`, `XC-001` | use approved producer path | `src/ProducerState.ps1` | Conformant |

## 注記 / 前提

No unresolved production address or error behavior.

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: bounded Plan, parent Plan, decomposition, Slice Architecture
- Selected contracts / IDs: `RC-001`, `XC-001`
- Files inspected: planning artifacts only
- Files intentionally not inspected: production payload before implementation
- Decisions made: exact output fields and production address
- Do not redo unless new evidence appears: `RC-001` field contract
- Remaining work: test design, handoff, implementation, verification
- Recommended next step: `test-design-kernel.agent.md`
