---
applyTo: "**"
---

# Copilot Cost-Aware Routing

Use `copilot-cost-router` as the default route for ordinary development requests.

## Gates

| Gate | Goal | Tier |
| --- | --- | --- |
| Intake | identify request, repo rules, existing state, and edit permission | `COPILOT_STANDARD_MODEL` / `COPILOT_HIGH_MODEL` |
| Plan | create a bounded Plan or equivalent source of truth, including behavior expansion decision and Plan readiness | `COPILOT_HIGH_MODEL` |
| Risk | classify security/auth/DB/API/async/production/external SDK risk after `ReadyForRiskTriage` | `COPILOT_STANDARD_MODEL` / `COPILOT_HIGH_MODEL` |
| Scan | collect summarized read-heavy repo evidence | `COPILOT_CHEAP_MODEL` |
| Contract | decide implementation approach and unresolved human decisions | `COPILOT_HIGH_MODEL` |
| Implementation handoff review | create parent authorization and coverage ledgers before implementation | `COPILOT_HIGH_MODEL` / `COPILOT_STANDARD_MODEL` |
| Implementation | edit only READY scope | `COPILOT_STANDARD_MODEL` |
| Verification | map evidence to acceptance criteria and production wiring | `COPILOT_STANDARD_MODEL` |
| Close | decide residuals and close readiness | `COPILOT_STANDARD_MODEL` / `COPILOT_HIGH_MODEL` |

## Routing rules

- Record `current_gate`, `next_gate`, `recommended_model_tier`, `allowed_to_edit`, `stop_reason`, and `next_action` in `plans/<slug>/codex-first-state.md`.
- Use `copilot-cheap-repo-scanner` for read-heavy search and inventory.
- Use `copilot-high-planner` for ambiguous or broad planning.
- Use `copilot-risk-triage` for high-risk classification.
- If Plan readiness is `NeedsPlanBehaviorExpansion`, route to behavior expansion / Plan rerun and do not select full-coverage.
- Use `implementation-handoff-review` or an explicitly equivalent pre-implementation gate before `copilot-standard-implementer`.
- If `Expansion required = Yes`, use `copilot-standard-implementer` only after `behavior_case_coverage_ledger_status = Complete`.
- Use `copilot-standard-implementer` only after READY and pre-implementation handoff authorization.
- Use `copilot-standard-verifier` after implementation.
- Use `copilot-close-reviewer` before final close.
- Do not turn full-coverage 3層運用 into the standard route.
- Do not use full-coverage for missing behavior expansion, missing Case-to-Plan mapping, or undecided expected behavior.
