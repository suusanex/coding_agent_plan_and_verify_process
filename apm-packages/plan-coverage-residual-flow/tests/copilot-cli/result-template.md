# GitHub Copilot CLI qualification result

- Date:
- Operator:
- Copilot CLI version:
- APM version:
- Package:
- Package version:
- Package source and full commit:
- Install mode (`remote-package` / `local-skill-only`):
- Working repository:
- Installed Skill path:
- Installed instruction path:
- Installed agent path:
- `copilot skill list` evidence:
- Model capability observation:

| Scenario | Status (`PASS` / `FAIL` / `NOT RUN` / `UNOBSERVABLE` / `BLOCKED`) | Prompt or fixture source | Observable CLI evidence | Artifact paths | Requested / observed model | Validation |
| --- | --- | --- | --- | --- | --- | --- |
| Install and Skill discovery | NOT RUN | | | | | |
| Explicit `lite` | NOT RUN | | | | | |
| Explicit `standard` | NOT RUN | | | | | |
| Unauthorized generic request | NOT RUN | | | | | |
| Unauthorized question/comparison/negation | NOT RUN | | | | | |
| Durable-authorized resume | NOT RUN | | | | | |
| Default Adaptive route | NOT RUN | | | | | |
| HIGH to STANDARD completion | NOT RUN | | | | | |
| HIGH re-entry | NOT RUN | | | | | |
| Blocked / human decision / replan | NOT RUN | | | | | |
| Architecture Slice Readiness | NOT RUN | | | | | |
| Compact Slice Record v2 two-slice run | NOT RUN | | | | | |
| Independent verification | NOT RUN | | | | | |
| Final Record through residual decision | NOT RUN | | | | | |
| New-session resume | NOT RUN | | | | | |
| Stale or incomplete artifact failure | NOT RUN | | | | | |
| Design Pair E2E | BLOCKED | Issue #69 | | | | |

## Notes and limitations

- Record unsupported or manually selected capabilities explicitly.
- Do not treat static validator success as real model evidence.
- Do not claim Design Pair support before Issue #69 is merged.
