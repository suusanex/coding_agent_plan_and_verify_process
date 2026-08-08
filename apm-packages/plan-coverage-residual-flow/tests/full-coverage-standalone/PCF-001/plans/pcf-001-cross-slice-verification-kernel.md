# PCF-001 Cross-Slice Verification Kernel

- Preconditions: `SL-001=SLICE_VERIFIED`, `SL-002=SLICE_VERIFIED`.
- Production entrypoint: `src/StartupFlow.ps1`.
- Verifier: `tests/verify-cross-slice.ps1`.
- Accepted path observed: `Active -> Accepting -> Accepted`.
- Reject path observed: a non-accepting state rejects the push.
- Field continuity observed: `snapshot_state` and `correlation_id` remain bound across both slices.
- Coverage: `FR-001`, `FR-002`, `AC-001`, `AC-002`, `CASE-001`, `CASE-002`, `XC-001`.
- Final verdict: `CROSS_SLICE_VERIFIED`.
