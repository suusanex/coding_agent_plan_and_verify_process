# PCF-001 Black-Box Behavior Specification

| Case | Preconditions | Action | Observable postcondition | Coverage |
|---|---|---|---|---|
| `CASE-001` | producer recovery can publish generation 7 | invoke `src/StartupFlow.ps1`, then replay the durable snapshot | `snapshot_state=Active`, consumer is `Accepting`, push is `Accepted`, identity remains `pcf-001` plus generation 7, and replay is idempotent | `FR-001`, `FR-002`, `AC-001`, `XC-001` |
| `CASE-002` | consumer state is not accepting, the publication is incomplete, or the requested generation is stale | invoke consumer push or startup replay | operation rejects without accepting work | `FR-002`, `AC-002`, `XC-001` |
