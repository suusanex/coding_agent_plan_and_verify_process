# Plan Coverage Agent Plugins direct-load PoC (#107)

- date: 2026-08-11
- decision.verdict: HOLD
- candidate_commit: e3928cd95aa7afc3830fc75d37715f61d1e69722 (clean)
- canonical_fingerprint: 98a49a9a3efa807363d3f4411f01f15992642fd1f4224fa8d8a57de2aa0e4ffb
- fingerprint_match: true
- bundle.status: PASS
- plugin_json: pack-stage synthesis only (not checked into package root)
- copilot_direct_load.status: PARTIAL
- plugin_discovery/install: PASS
- authorization: PASS
- standard_slice: FAIL
- full_coverage: NOT_RUN
- adaptive_connection: FAIL
- codex_direct_load: UNCONFIRMED_NO_LOCAL_DIRECT_LOAD_OBSERVED
- adaptive_attestation_lock_sha256: 3944e241668efd7b801c192c456293c91137ffc7b513f0148db1ebb07795d4ce

## Capability gaps

- Adaptive Skill/HIGH/STANDARD attested in source-install lock deployed_files/hashes but not inlined by apm pack of Plan Coverage (path-dep pack refused; Adaptive packs standalone)
- Shared instruction not materialized to .github/instructions under direct plugin fixture
- FULL-001 NOT_RUN (time/cost; skipped by flag)
- STD residual-decision-gate incomplete vs #106 close criteria (session time-bound; oracle STD_001_VERIFIED)
- adaptive_connection.connection_satisfied=false under #106 Adaptive observation rules (HIGH/STANDARD not in Plan Coverage plugin bundle)

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

- Strict Agent Plugins v1 bundle synthesized at pack stage (no checked-in package-root plugin.json); APM local-source install semantics preserved
- Adaptive Skill/HIGH/STANDARD attested in source-install lock deployed_files/hashes; apm pack refuses path deps; Plan Coverage pack does not inline Adaptive; Adaptive standalone pack succeeds
- Copilot direct plugin install/discovery PASS on clean commit
- Authorization A-H PASS (explicit-invocation-only)
- STD-001 status=FAIL (oracle STD_001_VERIFIED; residual close incomplete vs #106)
- FULL-001 NOT_RUN
- Codex: UNCONFIRMED_NO_LOCAL_DIRECT_LOAD_OBSERVED (local path probe rejected)
- Fingerprint matches #106 baseline; semantic_parity_claimed=false

## Notes

- #106 baseline unmodified; fingerprint match; semantic_parity_claimed=false.
- No package-root plugin.json; APM local-source install smoke still PASS.
- Adaptive attested in install lock; not in Plan Coverage plugin bundle; standalone Adaptive pack OK.