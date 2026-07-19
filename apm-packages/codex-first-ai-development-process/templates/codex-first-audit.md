# Codex First Audit

task_slug:
state_artifact: plans/<ticket-or-slug>/codex-first-state.md
source_of_truth:
audit_status: Active / Complete / N/A / Unknown
last_updated_summary:

This artifact holds delegation evidence, model-observability detail, route history, and close-time audit checks. Keep `codex-first-state.md` focused on resume-critical current state.

## Agent Usage Ledger

### Expected delegation

| Gate | Delegation required | Expected agent | Expected tier | Edit owner | Reason |
| --- | --- | --- | --- | --- | --- |

### Observed runs

| Run ID | Gate | Work item | Model tier | Agent name | Agent type | Configured model | Configured reasoning effort | Hook model | Reported model | Effective model | Delegation required | Edit owner | Delegation violation | Cost-saving delegation countable | Outcome | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Model field meanings

- model_tier: abstract routing label, one of HIGH_MODEL / STANDARD_MODEL / CHEAP_MODEL.
- configured_model: Codex custom agent file top-level `model`.
- configured_reasoning_effort: Codex custom agent file top-level `model_reasoning_effort`.
- hook_model: model observed from hook payload or hook log, otherwise unknown.
- reported_model: model self-reported by the agent; lower confidence than configured_model or hook_model.
- effective_model: billing or runtime-effective model only when independently verified, otherwise unknown.

## Delegation Compliance

| Check | Status | Evidence |
| --- | --- | --- |
| CHEAP work delegated when required | PASS / FAIL / N/A | |
| HIGH implementation started before any standard completion | PASS / FAIL / N/A | |
| STANDARD completion delegated only after valid handoff | PASS / FAIL / N/A | |
| NEEDS_HIGH_MODEL_REENTRY returned to HIGH implementation | PASS / FAIL / N/A | |
| HIGH and STANDARD write ownership did not overlap | PASS / FAIL / N/A | |
| STANDARD verification delegated | PASS / FAIL / N/A | |
| Parent direct execution exception documented | PASS / FAIL / N/A | |
| Delegation violation absent or accepted | PASS / FAIL / N/A | |
| Cost-saving delegation has observed delegated run evidence | PASS / FAIL / N/A | |

delegation_compliance: PASS / FAIL / EXCEPTION_ACCEPTED / N/A

## Route History

| Time / run | Gate | Decision | State fields changed | Evidence |
| --- | --- | --- | --- | --- |

## Parent Direct Exceptions

| Gate | Exception reason | Human approval evidence | Cost-saving countable? |
| --- | --- | --- | --- |

## Close Audit

- delegation_compliance:
- delegation_violation:
- cost_saving_delegation_countable:
- manual_verification_status:
- human_decision_status:
- higher_model_review_status:
- unresolved_residuals_summary:
- close_verdict:
