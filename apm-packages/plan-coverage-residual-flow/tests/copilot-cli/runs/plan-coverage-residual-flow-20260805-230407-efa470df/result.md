# GitHub Copilot CLI qualification result

- Date: 2026-08-05T23:04:21.2059793+09:00
- Operator: automated repository-local harness
- Copilot CLI version: GitHub Copilot CLI 1.0.78.
Run 'copilot update' to check for updates.
- APM version: Agent Package Manager (APM) CLI version 0.26.0
- Package: plan-coverage-residual-flow
- Package version in lock: 0.9.1
- Package source and full commit: suusanex/coding_agent_plan_and_verify_process#8d7527cbf5c0172148346463fd6c61f25fb33e24
- Source repository revision: 8d7527cbf5c0172148346463fd6c61f25fb33e24-dirty
- Install mode: remote-package
- Working repository: C:\Users\suusa\.codex\worktrees\bd38\coding_agent_plan_and_verify_process\apm-packages\plan-coverage-residual-flow\tests\copilot-cli\runs\plan-coverage-residual-flow-20260805-230407-efa470df\workspace
- Installed Skill path: C:\Users\suusa\.codex\worktrees\bd38\coding_agent_plan_and_verify_process\apm-packages\plan-coverage-residual-flow\tests\copilot-cli\runs\plan-coverage-residual-flow-20260805-230407-efa470df\workspace\.agents\skills\plan-coverage-residual-flow\SKILL.md
- Installed Skill SHA-256: 8814975edb2cc8ec48dc369c117d6e1cb9ca07ca59c0468151347841d873db3a
- Required full-package assets: PASS
- Install boundary status: PASS
- Skill discovery status: PASS
- Local-only status: NOT APPLICABLE
- Real-scenario status: INCOMPLETE
- Qualification status: REAL_SCENARIO_INCOMPLETE
- Model capability observation: requested and observed model values require separate evidence; this harness does not infer per-agent model locking.

| Scenario | Status | Observable evidence | Validation | Requested model | Observed model |
| --- | --- | --- | --- | --- | --- |
| install-and-skill-discovery | PASS | Remote full-SHA install with --target copilot,agent-skills --https exited 0; deployed Skill and copilot skill list were observed. | validate-copilot-full-package-install.ps1; session 2026-08-05 | not supplied | not supplied |
| explicit-lite | PASS | Real Copilot JSONL assistant.message reported plan-coverage-residual-flow, explicit authorization, documentation_level lite, and adaptive/default metadata; exit 0; no files changed. | session bfb9052d-4b77-4bb5-a0a4-14018080a460; observed model gpt-5.6-luna | not supplied | not supplied |
| explicit-standard | PASS | Real Copilot JSONL assistant.message reported plan-coverage-residual-flow, explicit authorization, documentation_level standard, and adaptive/default metadata; exit 0; no files changed. | session e46dd15f-3171-470b-bbb1-5a21468ee1e5; observed model gpt-5.6-luna | not supplied | not supplied |
| unauthorized-generic | PASS | Generic implementation prompt returned no activation of plan-coverage-residual-flow or custom agents; exit 0; no files changed. | session 78f2e696-94fa-40a3-bc32-a7d49449e8ff; observed model gpt-5.6-luna | not supplied | not supplied |
| unauthorized-question-comparison-negation | PASS | Question, comparison, and negation prompt returned no Skill or custom-agent activation; exit 0; no files changed. | session 3f2ad865-dabc-40c2-8329-62d9ec2c4f72; observed model gpt-5.6-luna | not supplied | not supplied |
| durable-authorized-resume | PASS | Copilot read a complete durable process_route/process_route_source/user_selection_evidence tuple and accepted artifact resume with adaptive/default metadata; exit 0. | session 325c9c28-61a4-45a4-8369-3fccf55fe652; no phase completion claimed | not supplied | not supplied |
| default-adaptive-route | PASS | Fresh-intake prompt returned adaptive/default, Design Pair handoff N/A, reentry_count 0, previous trigger N/A; exit 0; no files changed. | session b4fc1784-d99f-4a71-b26d-bbacd971799f; observed model gpt-5.6-luna | not supplied | not supplied |
| high-to-standard-completion | UNOBSERVABLE | Requested gpt-5.6-terra and observed gpt-5.6-terra, but Copilot rejected the supplied incomplete handoff and did not expose an actual HIGH-to-STANDARD phase transition. | session 25e023a4-1ab4-4d45-a6a0-31bb55922697; no files changed | not supplied | not supplied |
| high-reentry | UNOBSERVABLE | Real prompt recognized NEEDS_HIGH_MODEL_REENTRY and reported requested gpt-5.6-luna/observed gpt-5.6-luna, but no actual STANDARD-to-HIGH phase transition was exposed. | session 1335e1cb-c56c-4d0e-b970-273218af85a6; no files changed | not supplied | not supplied |
| blocked-human-decision-replan | PASS | Real Copilot returned HUMAN_DECISION_REQUIRED for a BLOCKED_BY_HUMAN_DECISION artifact and stopped without implementation or verification. | session 93031f62-5eb7-4317-b8c5-bddf79fe0c37; observed model gpt-5.6-luna | not supplied | not supplied |
| architecture-slice-readiness | UNOBSERVABLE | Copilot stopped at missing upstream Plan/risk authority with NeedsHumanDecision; architecture-slice-readiness agent selection and readiness execution were not observable. | session d9cd0b1c-5e06-4aee-890c-10d10799c1f7; no files changed | not supplied | not supplied |
| two-slice-v2 | UNOBSERVABLE | Copilot returned BlockedByArtifactLayoutMismatch because Parent State, Coverage Ledger, Slice Records, and same-digest authorization were absent; no two-slice execution occurred. | session 01ac7bc4-2236-4180-ad31-666f0ebfccc6; no files changed | not supplied | not supplied |
| independent-verification | UNOBSERVABLE | Copilot returned BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE because Plan, contracts, ledger, and production-binding evidence were absent; verification-kernel execution was not observable. | session 06ea905c-8086-4e37-945d-58307c349bac; no files changed | not supplied | not supplied |
| final-record-residual-decision | UNOBSERVABLE | Copilot found no Final Record, Parent State, Slice Records, or Coverage Ledger and stopped; cross-slice verification and residual decision phases were not observable. | session 31ad0566-0b12-4faf-afe3-7b680a04423f; no files changed | not supplied | not supplied |
| new-session-resume | PASS | A separate Copilot process using --resume=325c9c28-61a4-45a4-8369-3fccf55fe652 read the durable tuple and accepted artifact resume with adaptive/default metadata; conversation phase state remained unobservable. | session 325c9c28-61a4-45a4-8369-3fccf55fe652; exit 0; no files changed | not supplied | not supplied |
| stale-incomplete-artifact-failure | PASS | Real Copilot returned BLOCKED_BY_ARTIFACT_MISMATCH for missing/incomplete freshness and artifact metadata and did not continue to implementation. | session aed962e2-93b9-446a-9e55-dbeee70bbee9; observed model gpt-5.6-luna | not supplied | not supplied |
| design-pair-e2e | BLOCKED | No local Design Pair implementation or Adaptive fallback was attempted. | not supplied | not supplied | not supplied |

## Notes and limitations

- local-skill-only proves CLI Skill discovery for the working-tree Skill but is never qualification evidence.
- Static validators and Skill discovery do not prove real model routing, production mutation, durable process completion, or per-agent model locking.
- A qualification pass requires every non-blocked fixture scenario to be PASS and every required full-package asset and lock identity to be observed.
- Design Pair E2E remains blocked by Issue #69.
