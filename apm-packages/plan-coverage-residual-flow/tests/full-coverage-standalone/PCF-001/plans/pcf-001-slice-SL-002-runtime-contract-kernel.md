# Runtime Contract Kernel

## スコープ

Bounded `SL-002` consumer and production binding contract inherited from `RC-002` and `XC-001`.

## Runtime Contract Kernel

| Contract ID | Scenario | Producer | Consumer | Message / API / Event | Required fields | Error / timeout behavior | Production implementation address | Verification hook |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `RC-002` | consume producer state and push item | `Get-ConsumerState` | `Push-ConsumerItem` | PowerShell function calls | `SnapshotState`, `CorrelationId`, consumer `State` | non-accepting state throws `Consumer is not accepting items.`; timeout N/A | `src/ConsumerGate.ps1`, `src/StartupFlow.ps1` | `TP-002`, `TP-003` |

## Plan / implementation contract 適合性

| Runtime Contract ID | Plan requirement | Implementation contract decision | Runtime contract address | Conformance |
| --- | --- | --- | --- | --- |
| `RC-002` | `SL2-FR-001`, `SL2-AC-001`, `SL2-AC-002`, `FR-002`, `AC-001`, `AC-002` | use approved consumer and startup paths | `src/ConsumerGate.ps1`, `src/StartupFlow.ps1` | Conformant |

## 注記 / 前提

Cross-slice production postcondition is independently verified after this bounded pass.

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: bounded Plan, parent Plan, decomposition, Slice Architecture, `SL-001` verification
- Selected contracts / IDs: `RC-002`, `XC-001`
- Files inspected: planning artifacts and previous verdict
- Files intentionally not inspected: production payload before implementation
- Decisions made: accepting/rejecting contract and production addresses
- Do not redo unless new evidence appears: `RC-002` behavior contract
- Remaining work: test design, handoff, implementation, verification
- Recommended next step: `test-design-kernel.agent.md`
