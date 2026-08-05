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
- Install boundary status (`PASS` / `FAIL` / `LOCAL_SKILL_ONLY`):
- Skill discovery status (`PASS` / `FAIL` / `UNOBSERVABLE`):
- Local-only status (`LOCAL_SKILL_ONLY_NON_QUALIFYING` / `NOT APPLICABLE`):
- Real-scenario status (`PASS` / `INCOMPLETE`):
- Qualification status (`QUALIFICATION_PASS` / `REAL_SCENARIO_INCOMPLETE` / `LOCAL_SKILL_ONLY` / `INSTALL_BOUNDARY_FAILURE`):
- Route metadata:
  - `implementation_route`:
  - `implementation_route_source`:
  - `design_pair_handoff`:
  - `reentry_count`:
  - `previous_reentry_trigger`:
  - `delegation_surface_reduced`:

| Scenario | Status (`PASS` / `FAIL` / `NOT RUN` / `UNOBSERVABLE` / `BLOCKED`) | Prompt or fixture source | Observable CLI evidence | Evidence bundle path | Evidence bundle SHA-256 | Prompt / command / output references | Artifact paths + SHA-256 | Changed files | Verdict sequence | Requested / observed model | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Install and Skill discovery | NOT RUN | | | | | | | | | | |
| Explicit `lite` | NOT RUN | | | | | | | | | | |
| Explicit `standard` | NOT RUN | | | | | | | | | | |
| Unauthorized generic request | NOT RUN | | | | | | | | | | |
| Unauthorized question/comparison/negation | NOT RUN | | | | | | | | | | |
| Durable-authorized resume | NOT RUN | | | | | | | | | | |
| Default Adaptive route | NOT RUN | | | | | | | | | | |
| HIGH to STANDARD completion | NOT RUN | | | | | | | | | | |
| HIGH re-entry | NOT RUN | | | | | | | | | | |
| Blocked / human decision / replan | NOT RUN | | | | | | | | | | |
| Architecture Slice Readiness | NOT RUN | | | | | | | | | | |
| Compact Slice Record v2 two-slice run | NOT RUN | | | | | | | | | | |
| Independent verification | NOT RUN | | | | | | | | | | |
| Final Record through residual decision | NOT RUN | | | | | | | | | | |
| New-session resume | NOT RUN | | | | | | | | | | |
| Stale or incomplete artifact failure | NOT RUN | | | | | | | | | | |
| Design Pair E2E | BLOCKED | Issue #69 | | | | | | | | | |

## Notes and limitations

- Record unsupported or manually selected capabilities explicitly.
- Do not treat static validator success as real model evidence.
- A `PASS` for a new-session resume scenario requires an explicit
  `evidence_declaration` with `evidence_source: real-cli`,
  `artifact_authoritative_resume: PROVEN`, a tracked evidence bundle path and
  SHA-256, prompt/command/output references, artifact paths with SHA-256,
  changed files, and the observed verdict sequence.
- `evidence_bundle_sha256` identifies the SHA-256 of the tracked
  `hashes.sha256` manifest. The manifest must exclude its own hash line to
  avoid self-referential ambiguity, and `artifacts.txt` must use tracked
  artifact-snapshot paths.
- If only `copilot --resume=<session-id>` or `copilot --continue` was observed,
  record `artifact_authoritative_resume: NOT_PROVEN` and use `UNOBSERVABLE`;
  conversation history is not artifact-authoritative process state.
- `QUALIFICATION_PASS` is forbidden when any required non-blocked scenario is
  `NOT RUN`, `UNOBSERVABLE`, `FAIL`, or missing, or when full-package assets or
  lock identity are missing.
- Local Skill-only discovery is explicitly non-qualification evidence.
- Do not claim Design Pair support before Issue #69 is merged.

For JSON result files, use this qualification-only evidence shape on each
real scenario that needs a bundle:

```json
"evidence_declaration": {
  "evidence_source": "real-cli",
  "artifact_authoritative_resume": "NOT_PROVEN",
  "evidence_bundle_path": null,
  "evidence_bundle_sha256": null,
  "prompt_reference": "...",
  "command_reference": "...",
  "output_reference": null,
  "artifact_references": [
    { "path": "plans/<artifact>", "sha256": "<sha256>" }
  ],
  "changed_files": [],
  "verdict_sequence": []
}
```
