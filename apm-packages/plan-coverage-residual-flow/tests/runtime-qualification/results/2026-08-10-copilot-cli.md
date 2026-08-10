# Plan Coverage GitHub Copilot CLI runtime qualification

- date: 2026-08-10
- overall_status: FAIL
- client_version: GitHub Copilot CLI 1.0.78.
Run 'copilot update' to check for updates.
- model_requested: null
- model_observed: client-selected-or-unobserved
- apm_version: Agent Package Manager (APM) CLI version 0.26.0
- candidate_commit: 2a4075dc39bee365ece0b82ba5377005715e8270-dirty
- plan_coverage_package_version: 0.13.0
- canonical_fingerprint: 98a49a9a3efa807363d3f4411f01f15992642fd1f4224fa8d8a57de2aa0e4ffb
- install_targets: copilot,codex,agent-skills
- distribution_smoke: PASS
- platform: Win32NT
- temporary_evidence: C:\WindowsTemp\plan-coverage-rq-79fb991df32847878c8777c4e0a5dc08

## Scenarios

| id | kind | status | agents_observed | stop_reason |
| --- | --- | --- | --- | --- |
| A | authorization-negative | PASS |  |  |
| B | authorization-negative | PASS |  |  |
| C | authorization-negative | PASS |  |  |
| D | authorization-positive | FAIL |  |  |
| E | authorization-negative | PASS |  |  |
| F | authorization-positive | FAIL |  |  |
| G | authorization-negative | PASS |  |  |
| H | authorization-negative | PASS |  |  |
| STD-001 | standard-slice-e2e | FAIL |  | tests/verify-std-001.ps1,plan-kernel,change-risk-triage,high-before-or-with-standard,standard-after-handoff,verification-kernel,residual-decision-gate,plan-artifacts-present |
| FULL-001 | full-coverage-e2e | FAIL |  | tests/verify-sl-001.ps1,tests/verify-sl-002.ps1,tests/verify-full-001.ps1,architecture-slice-readiness,plan-slice-decomposition,living-records,cross-slice-verification,residual-decision-gate,adaptive-connection,plan-created |

## Notes

- skill_observation is UNOBSERVABLE unless Copilot CLI emits a dedicated skill-load event.
- Authorization negatives require no Plan Coverage agents, no Plan Coverage artifact writes, and no route recommendation.
- STD-001 / FULL-001 use external oracles hash-checked by the harness.
- Personal COPILOT_HOME customizations were isolated via temporary COPILOT_HOME.