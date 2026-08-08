# Coverage Ledger

## Source of truth

| Field | Value |
| --- | --- |
| Parent Plan | `plans/pcf-001.md` |
| Documentation level | standard |
| implementation_route | adaptive |
| implementation_route_source | default |
| design_pair_handoff | N/A |
| design_pair_interaction_stage | N/A |
| design_pair_user_evidence | N/A |
| Selected process | advanced-full-coverage |
| Route note | full-coverage |
| Last full ledger update | `plans/pcf-001-cross-slice-verification-kernel.md` at deterministic-fixture |
| Last delta applied | `DELTA-CSV-001` |

## Parent Plan Coverage Ledger

| Plan item | Type | Implementation status | Verification status | Evidence | Residual status | Blocking? |
| --- | --- | --- | --- | --- | --- | --- |
| `FR-001` | Functional requirement | Implemented | Verified | `SL-001`, `RC-001`, `TP-001`, cross-slice oracle `ORACLE-001` | none | No |
| `FR-002` | Functional requirement | Implemented | Verified | `SL-002`, `RC-002`, `TP-002`, `TP-003`, `ORACLE-001`, `ORACLE-002` | none | No |
| `AC-001` | Acceptance condition | Implemented | Verified | production `src/StartupFlow.ps1`, `ORACLE-001` | none | No |
| `AC-002` | Acceptance condition | Implemented | Verified | production rejection branch, `ORACLE-002` | none | No |

## Behavior Case Coverage Ledger

| Case ID | Source IDs | FR / AC | Coverage route | Slice / RC / TP | Status | Residual / reason |
| --- | --- | --- | --- | --- | --- | --- |
| `CASE-001` | PCF-001 behavior spec | `FR-001`, `FR-002`, `AC-001`, `XC-001` | bounded verifiers plus production entrypoint oracle | `SL-001`, `SL-002` / `RC-001`, `RC-002` / `TP-001`, `TP-002` | Verified | none |
| `CASE-002` | PCF-001 behavior spec | `FR-002`, `AC-002` | bounded and cross-slice rejection oracle | `SL-002` / `RC-002` / `TP-003` | Verified | none |

## Residual Decision Ledger

| Residual ID | Source item | Residual type | Decision status | Human decision source | Owner / next step |
| --- | --- | --- | --- | --- | --- |
| none | canonical ledger and `CROSS_SLICE_VERIFIED` | no residual candidate | NoDecisionRequired | none | close-ready |

## Coverage Ledger Delta

| Delta ID | Source artifact | Plan item / Case ID / Residual ID | Previous status | New status | Evidence / reason | Blocking? |
| --- | --- | --- | --- | --- | --- | --- |
| `DELTA-V-SL1` | `pcf-001-slice-SL-001-verification-kernel.md` | `FR-001`, `CASE-001`, `XC-001` producer role | Implemented / ReadyForVerification | ImplementedAndVerified | direct production producer verifier passed | No |
| `DELTA-V-SL2` | `pcf-001-slice-SL-002-verification-kernel.md` | `FR-002`, `AC-002`, `CASE-001`, `CASE-002`, `XC-001` consumer role | Implemented / ReadyForVerification | ImplementedAndVerified | direct production consumer verifier passed both branches | No |
| `DELTA-CSV-001` | `pcf-001-cross-slice-verification-kernel.md` | `AC-001`, `AC-002`, `CASE-001`, `CASE-002`, `XC-001` | BoundedVerified / CrossSlicePending | Verified | production entrypoint positive and negative oracles passed | No |

## Close readiness summary

| Check | Status | Evidence |
| --- | --- | --- |
| All parent Plan FR / AC classified | PASS | four parent rows present |
| All implementation-required items implemented | PASS | both Adaptive evidence artifacts and production payloads |
| All verification-required items verified or explicitly dispositioned | PASS | both Verification Kernel artifacts and cross-slice result |
| Behavior Case coverage complete or N/A | PASS | `CASE-001`, `CASE-002` verified |
| Residual decisions explicit | PASS | no residual candidate; Residual Decision Gate confirms |
| No fake-only completion | PASS | all verifiers import production payload functions |
| No unclassified delta remains | PASS | all three deltas applied |
