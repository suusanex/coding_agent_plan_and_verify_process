# SL-002 Runtime Contract Kernel

- Input: `snapshot_state` and `correlation_id` from `SL-001`.
- Accepting branch: `snapshot_state=Active` produces consumer state `Accepting` and push postcondition `Accepted`.
- Rejecting branch: any non-accepting consumer state throws `Consumer is not accepting items.`.
- Production bindings: `src/ConsumerGate.ps1`, `src/StartupFlow.ps1`.
- Coverage: `FR-002`, `AC-001`, `AC-002`, `CASE-001`, `CASE-002`, `XC-001`.
