# Copilot CLI real-scenario qualification record

- Date: 2026-08-05 (Asia/Tokyo)
- Copilot CLI: `1.0.78`
- APM: `0.26.0`
- Package: `token-aware-full-coverage-3layer` `0.6.1`
- Remote source: `suusanex/coding_agent_plan_and_verify_process#8d7527cbf5c0172148346463fd6c61f25fb33e24`
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
full-SHA installation. Missing durable execution artifacts caused the
positive-path scenarios to stop fail-closed; those scenarios are not claimed
as completed.

| Scenario | Status | Real evidence |
| --- | --- | --- |
| Compact Slice Record v2 two-slice | `UNOBSERVABLE` | Session `9c2e7a49-563d-4a57-9f19-a76b963d1cd8`; missing Parent State, ledger, Slice Records, and authorization returned `BlockedByArtifactLayoutMismatch`. |
| Parent authorization and independent verification | `UNOBSERVABLE` | Session `bd5c5973-ec8f-4f7d-b6b4-40cf88da6355`; required artifacts were absent, so authorization/delegation/verification were not observed. |
| Final Record through residual decision | `UNOBSERVABLE` | Session `940dc751-fec1-488c-b96e-ba7210673dcf`; Final Record and upstream artifacts were absent. |
| New-session Parent State resume | `UNOBSERVABLE` | Session `3b83102d-336c-41bf-8bcc-3dfabb138852`; no durable Parent State or route/layout metadata existed. |
| Stale or incomplete layout failure | `PASS` | Session `669dc742-0b1b-4648-93f2-1076206a2cc1`; missing, mixed, contradictory, or stale layout returned `BlockedByArtifactLayoutMismatch` and stopped. |
| Design Pair E2E | `BLOCKED` | Issue #69 canonical Copilot support is not merged. |

Remaining work is a real positive-path two-slice execution with durable Parent
State, independent verification, Final Record, cross-slice verification, and
residual decision evidence. Design Pair remains blocked by #69.
