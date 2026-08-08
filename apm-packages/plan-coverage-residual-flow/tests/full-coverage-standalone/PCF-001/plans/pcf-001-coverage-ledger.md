# PCF-001 Canonical Coverage Ledger

| ID | Type | Owning slice | Implementation evidence | Verification evidence | Status |
|---|---|---|---|---|---|
| `FR-001` | requirement | `SL-001` | `src/ProducerState.ps1` | `verify-sl-001.ps1`, cross-slice verifier | implemented-and-verified |
| `FR-002` | requirement | `SL-002` | `src/ConsumerGate.ps1`, `src/StartupFlow.ps1` | `verify-sl-002.ps1`, cross-slice verifier | implemented-and-verified |
| `AC-001` | acceptance | `SL-002` | production startup path | cross-slice verifier | implemented-and-verified |
| `AC-002` | acceptance | `SL-002` | consumer rejection branch | `verify-sl-002.ps1`, cross-slice verifier | implemented-and-verified |
| `CASE-001` | case | `SL-001`, `SL-002` | accepted startup path | all three verifiers | implemented-and-verified |
| `CASE-002` | case | `SL-002` | rejection path | `verify-sl-002.ps1`, cross-slice verifier | implemented-and-verified |
| `XC-001` | cross-cutting | `SL-001`, `SL-002` | field continuity through `src/StartupFlow.ps1` | cross-slice verifier | implemented-and-verified |

- Fake-only evidence: none.
- Unclassified items: none.
- Blocking residuals: none.
