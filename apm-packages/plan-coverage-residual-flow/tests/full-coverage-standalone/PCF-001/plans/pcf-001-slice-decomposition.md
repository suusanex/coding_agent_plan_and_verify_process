# PCF-001 Plan Slice Decomposition

Readiness input: `ReadyForSliceDecomposition`

| Order | Slice | Depends on | Goal | Coverage | Field continuity | Recommended profile | Next agent |
|---|---|---|---|---|---|---|---|
| 1 | `SL-001` | none | restore producer snapshot | `FR-001`, `CASE-001`, `XC-001` | emits `snapshot_state`, `correlation_id` | `contract-kernel` | standard Plan Coverage chain |
| 2 | `SL-002` | `SL-001` | gate consumer and bind production entrypoint | `FR-002`, `AC-001`, `AC-002`, `CASE-001`, `CASE-002`, `XC-001` | consumes unchanged fields | `standard-slice` | standard Plan Coverage chain |

Cross-slice guardrail: do not run cross-slice verification until both slice verdicts are `SLICE_VERIFIED`.
