# Full-Coverage Close Record

Use `plans/<slug>-full-coverage-close.md` after every required Slice Living Record has an independent verification verdict and no pending slice ledger delta.

The Plan Coverage parent/router is the only repository writer. `cross-slice-verification-kernel` and `residual-decision-gate` remain separate semantic owners and return deltas in that order; they must not be merged into one agent or one verdict.

```md
# Full-Coverage Close Record

## Record Metadata

- Parent Plan:
- artifact_mode: slice-living-record
- documentation_level: standard
- Canonical Coverage Ledger:
- Required Slice Living Records:
- Pending Coverage Ledger Delta count:

## Cross-Slice Verification

- Formal cross-slice-verification-kernel verdict:
- Required slices independently verified:
- Parent acceptance condition evidence:
- XC / field continuity evidence:
- Production binding / wiring evidence:
- Behavior Case evidence:
- Remaining gaps:

## FixNow Repair Loop

- Trigger verdict:
- Selected gap selectors:
- Target Slice Living Records:
- Repair verdicts:
- Slice re-verification verdicts:
- Cross-slice rerun verdict:

## Coverage Ledger Delta

| Delta ID | Source phase | Plan item / Case ID / Residual ID | Previous status | New status | Evidence / reason | Applied to canonical ledger? |
| --- | --- | --- | --- | --- | --- | --- |

## Residual Decision

- Formal residual-decision-gate verdict:
- Cross-slice verdict consumed:
- Residual decisions:
- Human decisions:
- Remaining blockers:

## Close Readiness

- Pending Coverage Ledger Delta count:
- Canonical ledger consistency:
- No fake-only completion:
- Production wiring verified:
- Close-ready verdict:
```

Required order:

```text
all required slices independently verified
-> no pending slice ledger delta
-> cross-slice-verification-kernel section delta
-> if CROSS_SLICE_PARTIAL_WITH_FIX_CANDIDATES: target-slice triage delta
-> one bounded gap-resolution pass and Gap Repair Evidence delta
-> affected slice verification rerun
-> cross-slice-verification-kernel rerun
-> apply CROSS ledger delta
-> residual-decision-gate section delta
-> apply residual ledger delta
-> no pending ledger delta
-> close readiness
```

`CROSS_SLICE_PARTIAL_WITH_FIX_CANDIDATES` must not flow directly to Residual Decision. The Plan Coverage parent records repair-loop history in this close record, while triage, repair, and slice re-verification details are applied to the affected Slice Living Records. The close record does not authorize implementation and does not introduce Parent Authorization, Parent Orchestration State, a scheduler, or a parallel orchestration layer.
