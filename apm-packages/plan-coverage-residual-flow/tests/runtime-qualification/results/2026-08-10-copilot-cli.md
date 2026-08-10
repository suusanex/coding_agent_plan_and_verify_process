# Plan Coverage GitHub Copilot CLI runtime qualification

- date: 2026-08-10
- overall_status: QUALIFIED
- reevaluation: kept-worktree-no-new-model-calls
- source_run_id: plan-coverage-rq-365b5a639d284262bedd05970227cd76
- source_run_root: C:\WindowsTemp\plan-coverage-rq-365b5a639d284262bedd05970227cd76
- client_version: GitHub Copilot CLI 1.0.78
- model_observed: client-selected-or-unobserved
- apm_version: Agent Package Manager (APM) CLI version 0.26.0
- candidate_commit: 2a4075dc39bee365ece0b82ba5377005715e8270-dirty
- plan_coverage_package_version: 0.13.0
- canonical_fingerprint: 98a49a9a3efa807363d3f4411f01f15992642fd1f4224fa8d8a57de2aa0e4ffb
- current_checkout_fingerprint: 98a49a9a3efa807363d3f4411f01f15992642fd1f4224fa8d8a57de2aa0e4ffb
- fingerprint_matches_current: True
- distribution_smoke: PASS
- adaptive_connection_satisfied: True
- high_to_standard_handoff_satisfied: False

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
| STD-001 | standard-slice-e2e | PASS | plan-kernel, change-risk-triage, implementation-execution, verification-kernel, residual-decision-gate | fixture-verified |
| FULL-001 | full-coverage-e2e | PASS | plan-kernel, change-risk-triage, architecture-slice-readiness, plan-slice-decomposition, implementation-contract-kernel, runtime-contract-kernel, test-design-kernel, implementation-handoff-review, verification-kernel, cross-slice-verification-kernel, residual-decision-gate | fixture-verified |