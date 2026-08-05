# GitHub Copilot CLI qualification result

- Date: 2026-08-05 (Asia/Tokyo)
- Copilot CLI: `1.0.78`
- APM: `0.26.0`
- Remote boundary source: `suusanex/coding_agent_plan_and_verify_process#3e427582051facda51f38997b1ce4a05921bd5f2`
- Remote package version: `0.9.0`
- Final working-tree manifest version: `0.9.1`
- Working-tree source: `3e427582051facda51f38997b1ce4a05921bd5f2-dirty`
- Working-tree mode: `local-skill-only`

## Observed install boundary

| Observation | Status | Evidence |
| --- | --- | --- |
| Remote APM package install with `--target copilot,agent-skills --https` | PASS | Pinned remote install completed in a disposable repository |
| Copilot Skill discovery | PASS | `copilot skill list` listed `plan-coverage-residual-flow` |
| Installed Skill path | PASS | `.agents/skills/plan-coverage-residual-flow/SKILL.md` |
| Shared instruction path | PASS | `.github/instructions/plan-coverage-shared.instructions.md` |
| Portable agent path | PASS | `.github/agents/*.agent.md` |
| Working-tree Skill discovery | PASS | Local Skill-only install listed `plan-coverage-residual-flow` |
| Per-agent model locking | ManualOnly | Requested and observed models require separate CLI evidence |

Installed Skill hashes:

- Remote boundary: `8814975edb2cc8ec48dc369c117d6e1cb9ca07ca59c0468151347841d873db3a`
- Working tree: `3e055494361a233c13b0e404d0630e919f9a3915c134d22e6fa6890a39f4c754`

## Scenario status

| Scenario | Status | Evidence |
| --- | --- | --- |
| Install and Skill discovery | PASS | Remote package and working-tree Skill probes |
| Explicit `lite` / `standard` | NOT RUN | Requires a real model run |
| Unauthorized generic / question / comparison / negation | NOT RUN | Requires a real model run |
| Durable authorization and new-session resume | NOT RUN | Requires a real model run |
| Adaptive and HIGH → STANDARD → HIGH scenarios | NOT RUN | Requires a real model run |
| Architecture, compact v2, verification, and residual scenarios | NOT RUN | Requires a real model run |
| Design Pair E2E | BLOCKED | Issue #69 canonical Copilot support is not merged |

The local package-directory full install limitation is recorded by the harness:
APM 0.26.0 rejects a root manifest that uses `git: parent`; a local Skill-only
probe is not presented as full dependency-graph evidence.

The remote boundary record uses the last published `main` revision. The
working-tree Skill discovery covers the final local Skill content; rerun the
remote package scenario after publishing the final commit SHA.
