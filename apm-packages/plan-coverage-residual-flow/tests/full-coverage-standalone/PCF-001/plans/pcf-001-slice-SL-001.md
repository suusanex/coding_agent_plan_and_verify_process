# PCF-001 Slice SL-001 Bounded Plan

- Goal: restore the producer snapshot to `Active` and preserve `correlation_id`.
- Non-goals: consumer acceptance, production entrypoint binding, and residual decision.
- Coverage: `FR-001`, `CASE-001`, `XC-001`.
- Dependency: none.
- Production binding: `src/ProducerState.ps1`.
- Required sequence: runtime contract, test design, handoff `Match`, Adaptive Implementation, independent verification.
