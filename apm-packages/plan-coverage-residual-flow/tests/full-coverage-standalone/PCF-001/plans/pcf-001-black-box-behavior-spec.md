# PCF-001 Black-Box Behavior Specification

| Case | Preconditions | Action | Observable postcondition | Coverage |
|---|---|---|---|---|
| `CASE-001` | producer state can be restored | invoke `src/StartupFlow.ps1` | `snapshot_state=Active`, consumer is `Accepting`, push is `Accepted` | `FR-001`, `FR-002`, `AC-001`, `XC-001` |
| `CASE-002` | consumer state is not accepting | invoke consumer push | operation rejects with `Consumer is not accepting items.` | `FR-002`, `AC-002` |
