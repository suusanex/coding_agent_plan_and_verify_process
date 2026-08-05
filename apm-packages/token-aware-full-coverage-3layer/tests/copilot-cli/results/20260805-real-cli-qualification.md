# Copilot CLI real-scenario qualification record

- Date: 2026-08-06 (Asia/Tokyo)
- Copilot CLI: `1.0.78`
- APM: `0.26.0`
- Package: `token-aware-full-coverage-3layer` `0.6.1`
- Remote source: `suusanex/coding_agent_plan_and_verify_process#65286363e74b139188f8362e56edc969eef2946b`
- Install mode: `remote-package`
- Installed Skill SHA-256: `717c91f6b65e3eab4003ba4938f99ec4abb01982f212ecbd2dc254208e9c9c91`
- Full-package install: `PASS`
- Deployed `.agents/skills`, `.github/instructions`, `.github/agents`: `PASS`
- Lock source/ref/version/content hash/deployed Skill hash: `PASS`
- Unmanaged collision preservation: `PASS`
- Install boundary: `PASS`
- Skill discovery: `PASS`
- Local Skill-only evidence: not used for this record
- Real-scenario status: `INCOMPLETE`
- Qualification status: `REAL_SCENARIO_INCOMPLETE`

Route metadata remained:

```yaml
implementation_route: adaptive
implementation_route_source: default
design_pair_handoff: N/A
reentry_count: 0
previous_reentry_trigger: N/A
delegation_surface_reduced: N/A
```

All probes were executed through the real Copilot CLI after the remote
full-SHA installation. The new-session Parent State resume scenario is now
proven from a fresh session that reloaded the tracked compact v2 artifacts;
other required scenarios remain unresolved, so formal qualification is still
incomplete.

| Scenario | Status | Real evidence |
| --- | --- | --- |
| Compact Slice Record v2 two-slice | `UNOBSERVABLE` | Session `9c2e7a49-563d-4a57-9f19-a76b963d1cd8`; missing Parent State, ledger, Slice Records, and authorization returned `BlockedByArtifactLayoutMismatch`. |
| Parent authorization and independent verification | `UNOBSERVABLE` | Session `bd5c5973-ec8f-4f7d-b6b4-40cf88da6355`; required artifacts were absent. |
| Final Record through residual decision | `UNOBSERVABLE` | Session `940dc751-fec1-488c-b96e-ba7210673dcf`; Final Record and upstream artifacts were absent. |
| New-session Parent State resume | `PASS` | Fresh session `e155cba9-7448-480b-bf6b-7e2cdf652a0b` restored compact v2 state and created only the authorized output; negative session `2021bcad-29ca-4f10-9722-18f8a37e62ae` failed closed when `slice-2.md` was absent. |
| Stale or incomplete layout failure | `PASS` | Session `669dc742-0b1b-4648-93f2-1076206a2cc1`; missing, mixed, contradictory, or stale layout returned `BlockedByArtifactLayoutMismatch` and stopped. |
| Design Pair E2E | `BLOCKED` | Issue #69 canonical Copilot support is not merged. |

### New-session Parent State resume evidence declaration

- Artifact-authoritative process resume: `PROVEN`
- Positive session: `e155cba9-7448-480b-bf6b-7e2cdf652a0b`
- Negative session: `2021bcad-29ca-4f10-9722-18f8a37e62ae`
- Evidence bundle: `apm-packages/token-aware-full-coverage-3layer/tests/copilot-cli/evidence/20260806-new-session-parent-state-resume`
- `evidence_bundle_sha256`: `a3e3682b945f9dbd757e755d3c263776c00f1872e988834b0af091b234106a85`
- Stable manifest definition: `hashes.sha256` is tracked and excludes its own hash line; the declared bundle hash is the SHA-256 of that manifest.
- Artifact snapshots are under `artifact-snapshots/full-coverage/` and are referenced by `artifacts.txt`.
- The negative run remains required evidence: missing `slice-2.md` returned `BLOCKED / fail-closed` with no output file created or modified.

Remaining work is a real positive-path two-slice execution with Parent
Authorization, independent verification, Final Record, cross-slice
verification, and residual decision evidence. Design Pair remains blocked by
#69.
