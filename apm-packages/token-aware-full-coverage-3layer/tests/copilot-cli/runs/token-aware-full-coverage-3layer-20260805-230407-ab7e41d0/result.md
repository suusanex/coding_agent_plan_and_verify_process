# GitHub Copilot CLI qualification result

- Date: 2026-08-05T23:04:21.1183692+09:00
- Operator: automated repository-local harness
- Copilot CLI version: GitHub Copilot CLI 1.0.78.
Run 'copilot update' to check for updates.
- APM version: Agent Package Manager (APM) CLI version 0.26.0
- Package: token-aware-full-coverage-3layer
- Package version in lock: 0.6.1
- Package source and full commit: suusanex/coding_agent_plan_and_verify_process#8d7527cbf5c0172148346463fd6c61f25fb33e24
- Source repository revision: 8d7527cbf5c0172148346463fd6c61f25fb33e24-dirty
- Install mode: remote-package
- Working repository: C:\Users\suusa\.codex\worktrees\bd38\coding_agent_plan_and_verify_process\apm-packages\token-aware-full-coverage-3layer\tests\copilot-cli\runs\token-aware-full-coverage-3layer-20260805-230407-ab7e41d0\workspace
- Installed Skill path: C:\Users\suusa\.codex\worktrees\bd38\coding_agent_plan_and_verify_process\apm-packages\token-aware-full-coverage-3layer\tests\copilot-cli\runs\token-aware-full-coverage-3layer-20260805-230407-ab7e41d0\workspace\.agents\skills\token-aware-full-coverage-3layer\SKILL.md
- Installed Skill SHA-256: 717c91f6b65e3eab4003ba4938f99ec4abb01982f212ecbd2dc254208e9c9c91
- Required full-package assets: PASS
- Install boundary status: PASS
- Skill discovery status: PASS
- Local-only status: NOT APPLICABLE
- Real-scenario status: INCOMPLETE
- Qualification status: REAL_SCENARIO_INCOMPLETE
- Model capability observation: requested and observed model values require separate evidence; this harness does not infer per-agent model locking.

| Scenario | Status | Observable evidence | Validation | Requested model | Observed model |
| --- | --- | --- | --- | --- | --- |
| compact-v2-two-slice | UNOBSERVABLE | Real Copilot returned BlockedByArtifactLayoutMismatch because Parent State, Coverage Ledger, Slice Records, and same-digest authorization were absent; no two-slice execution occurred. | session 9c2e7a49-563d-4a57-9f19-a76b963d1cd8; observed model gpt-5.6-luna | not supplied | not supplied |
| parent-authorization-and-independent-verification | UNOBSERVABLE | Copilot described the required observation points but reported that executable Parent State and Slice Record artifacts were absent; actual authorization, Adaptive delegation, and independent verification were not observed. | session bd5c5973-ec8f-4f7d-b6b4-40cf88da6355; no files changed | not supplied | not supplied |
| final-record-through-residual-decision | UNOBSERVABLE | Copilot found no executable Parent State, Coverage Ledger, Slice Records, or Final Record; cross-slice verification, residual decision, and close decision were not observable. | session 940dc751-fec1-488c-b96e-ba7210673dcf; no files changed | not supplied | not supplied |
| new-session-parent-state-resume | UNOBSERVABLE | Copilot reported resume unavailable because no durable Parent Orchestration State or route/layout metadata existed; conversation resume cannot substitute for Parent State resume. | session 3b83102d-336c-41bf-8bcc-3dfabb138852; no files changed | not supplied | not supplied |
| stale-or-incomplete-layout-failure | PASS | Real Copilot returned BlockedByArtifactLayoutMismatch for missing, mixed, contradictory, or stale layout metadata and stopped before authorization or implementation. | session 669dc742-0b1b-4648-93f2-1076206a2cc1; observed model gpt-5.6-luna | not supplied | not supplied |
| design-pair-e2e | BLOCKED | No local Design Pair implementation or Adaptive fallback was attempted. | not supplied | not supplied | not supplied |

## Notes and limitations

- local-skill-only proves CLI Skill discovery for the working-tree Skill but is never qualification evidence.
- Static validators and Skill discovery do not prove real model routing, production mutation, durable process completion, or per-agent model locking.
- A qualification pass requires every non-blocked fixture scenario to be PASS and every required full-package asset and lock identity to be observed.
- Design Pair E2E remains blocked by Issue #69.
