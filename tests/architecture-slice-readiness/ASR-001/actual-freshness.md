# ASR-001 Actual Freshness Re-evaluation

## Positive path: R1 → A1 → R2

- R1 revision: `readiness-r1`
- A1 revision: `arch-1`
- R2 revision: `readiness-r2`, written to the same logical readiness path
- R1 role in A1: `elaboration_trigger`, `freshness_dependency: false`
- A1 tracked source changes after R2: none
- A1 current after readiness rerun: `Yes`
- R2 tracks A1 external content hash: `Yes`
- Decomposition allowed: `Yes`

## Negative path: Parent Plan changes after R2

- Changed tracked source: `input-plan.md`
- Recorded revision: `fixture-plan-v1`
- Recomputed revision: `fixture-plan-v2`
- A1 stale: `Yes`
- R2 stale: `Yes`
- Decomposition allowed: `No`

## Negative path: production watch path changes after R2

- Synthetic watch path: `src/activation/**`
- Diff: production activation wiring changed
- A1 stale: `Yes`
- R2 stale: `Yes`
- Decomposition allowed: `No`
