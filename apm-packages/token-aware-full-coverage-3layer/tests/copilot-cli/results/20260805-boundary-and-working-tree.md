# GitHub Copilot CLI qualification result

- Date: 2026-08-05 (Asia/Tokyo)
- Copilot CLI: `1.0.78`
- APM: `0.26.0`
- Remote boundary source: `suusanex/coding_agent_plan_and_verify_process#3e427582051facda51f38997b1ce4a05921bd5f2`
- Remote package version: `0.6.0`
- Final working-tree manifest version: `0.6.1`
- Working-tree source: `3e427582051facda51f38997b1ce4a05921bd5f2-dirty`
- Working-tree mode: `local-skill-only`

## Observed install boundary

| Observation | Status | Evidence |
| --- | --- | --- |
| Remote APM package install with `--target copilot,agent-skills --https` | PASS | Pinned remote install completed in a disposable repository |
| Copilot Skill discovery | PASS | `copilot skill list` listed `token-aware-full-coverage-3layer` |
| Installed Skill path | PASS | `.agents/skills/token-aware-full-coverage-3layer/SKILL.md` |
| Full-coverage instruction path | PASS | `.github/instructions/token-aware-full-coverage-3layer.instructions.md` |
| Shared instruction path | PASS | `.github/instructions/plan-coverage-shared.instructions.md` |
| Portable agent path | PASS | `.github/agents/*.agent.md` including `slice-prep.agent.md` |
| Working-tree Skill discovery | PASS | Local Skill-only install listed `token-aware-full-coverage-3layer` |
| Per-agent model locking | ManualOnly | Requested and observed models require separate CLI evidence |

Installed Skill hashes:

- Remote boundary: `717c91f6b65e3eab4003ba4938f99ec4abb01982f212ecbd2dc254208e9c9c91`
- Working tree: `caaaf28ad088eba4b90e6e3cf71901d1ce86d156871cd95810621fba11b5a4f2`

## Scenario status

| Scenario | Status | Evidence |
| --- | --- | --- |
| Compact Slice Record v2 two-slice run | NOT RUN | Requires a real model run |
| Parent authorization and independent verification | NOT RUN | Requires a real model run |
| Final Record through residual decision | NOT RUN | Requires a real model run |
| New-session Parent State resume | NOT RUN | Requires a real model run |
| Stale or incomplete layout failure | NOT RUN | Requires a real model run |
| Design Pair E2E | BLOCKED | Issue #69 canonical Copilot support is not merged |

The local package-directory full install limitation is recorded by the harness:
APM 0.26.0 rejects a root manifest that uses `git: parent`; a local Skill-only
probe is not presented as full dependency-graph evidence.

The remote boundary record uses the last published `main` revision. The
working-tree Skill discovery covers the final local Skill content; rerun the
remote package scenario after publishing the final commit SHA.
