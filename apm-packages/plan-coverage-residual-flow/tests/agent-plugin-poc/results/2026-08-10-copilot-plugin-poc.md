# Plan Coverage Agent Plugins direct-load PoC (#107)

- date: 2026-08-10
- decision.verdict: HOLD
- package_version: 0.13.0
- canonical_fingerprint: 98a49a9a3efa807363d3f4411f01f15992642fd1f4224fa8d8a57de2aa0e4ffb
- fingerprint_match: true
- bundle.status: PASS
- copilot_direct_load.status: PARTIAL
- plugin_discovery: PASS
- plugin_install: PASS
- authorization: PASS
- standard_slice: FAIL
- full_coverage: NOT_RUN
- adaptive_connection: FAIL
- codex_direct_load: UNSUPPORTED_CURRENT_CLIENT
- source_run_id: plan-coverage-plugin-poc-e17250eb67c348d19631e2ccde0eef80

## Capability gaps

- Adaptive HIGH/STANDARD agents not present in plugin bundle; STD handoff documents driving-session HIGH substitute
- Shared instruction not materialized to .github/instructions (plugin agents still executed)
- FULL-001 not completed in this PoC evidence set
- adaptive_connection.connection_satisfied=false under #106 Adaptive observation rules (HIGH agent not in bundle)

## Scenarios

| id | kind | status | agents_observed | stop_reason |
| --- | --- | --- | --- | --- |
| A | authorization-negative | PASS |  |  |
| B | authorization-negative | PASS |  |  |
| C | authorization-negative | PASS |  |  |
| D | authorization-positive | PASS | plan-kernel | authorized-progress |
| E | authorization-negative | PASS |  |  |
| F | authorization-positive | PASS |  | intake-stop-or-authorization-only |
| G | authorization-negative | PASS |  |  |
| H | authorization-negative | PASS |  |  |
| STD-001 | standard-slice-e2e | FAIL | plan-kernel, change-risk-triage, verification-kernel | residual-decision-gate |

## Decision rationale

- Strict Agent Plugins v1 bundle generated from canonical .apm via apm pack without duplicate process source
- Copilot direct plugin install/discovery PASS (plugin-dir + plugin install local path)
- Authorization A-H PASS under direct plugin load — explicit-invocation-only maintained
- STD-001 evaluation status=FAIL; external oracle STD_001_VERIFIED; plugin agents plan-kernel/change-risk-triage/verification-kernel observed
- FULL-001 NOT_RUN (time/cost); not claimed PASS
- Adaptive transitive agents absent from apm pack output — APM projection or separate Adaptive plugin required for strict Adaptive parity
- Codex direct local bundle: UNSUPPORTED_CURRENT_CLIENT (marketplace snapshot only)
- Baseline #106 fingerprint matches; full semantic parity not claimed due to FULL/Adaptive gaps

## Next steps

- Compose Adaptive via APM materialization or a separate Agent Plugins bundle + Copilot adapter
- Re-run FULL-001 after Adaptive composition path exists
- Keep APM as multi-target projection + dependency materialization layer
- Treat Agent Plugins as portable Skill packaging contract (+ Copilot agents/ extension)
- No package version bump for PoC-only packaging

## Notes

- #106 APM baseline evidence was not modified.
- Fixture repos did not receive `apm install` of Plan Coverage.
- Shared instruction was not hand-copied into fixtures.
- Plugin agents observed as `plan-coverage-residual-flow:<agent>`.
- STD-001 external oracle returned `STD_001_VERIFIED` on kept worktree.
- FULL-001 not run; recorded NOT_RUN (not PASS).