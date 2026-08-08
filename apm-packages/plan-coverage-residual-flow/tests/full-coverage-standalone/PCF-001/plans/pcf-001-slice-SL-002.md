# PCF-001 Slice SL-002 Bounded Plan

- Goal: derive consumer acceptance, reject non-accepting states, and bind the production startup path.
- Non-goals: producer restoration internals and residual policy changes.
- Coverage: `FR-002`, `AC-001`, `AC-002`, `CASE-001`, `CASE-002`, `XC-001`.
- Dependency: `SL-001` must be `SLICE_VERIFIED`.
- Production bindings: `src/ConsumerGate.ps1`, `src/StartupFlow.ps1`.
- Required sequence: runtime contract, test design, handoff `Match`, Adaptive Implementation, independent verification.
