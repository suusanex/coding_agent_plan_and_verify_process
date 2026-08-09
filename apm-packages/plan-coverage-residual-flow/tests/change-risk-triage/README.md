# Change Risk Triage profile stability smoke

This suite separates deterministic contract validation from external-model observations.

`scenarios.json` is the CI authority for `CRT-001` through `CRT-003`, and `result.schema.json` constrains each fresh-session observation. CI checks both schemas, the expected execution-model classifications, the selected profile, the escalation result, and the Change Risk Triage agent hash pinned in `agent.sha256`. Update that pin only when the reviewed agent contract changes. CI does not invoke an external model and must not present fixture expectations as model observations.

## Manual procedure

Run every scenario in a fresh session three times. Give the session only the current `change-risk-triage.agent.md`, the scenario text, and the instruction to produce a normal-mode triage artifact. Do not carry an earlier result into the next run.

For every run, record:

- the agent SHA-256;
- all bounded runtime sequences;
- every execution-model classification;
- the recommended profile;
- `Why standard-slice is insufficient` and the escalation gate result;
- recommendation confidence and the evidence that would lower or raise the profile.

The three runs for a scenario pass only when the execution-model set, recommended profile, and required section presence are identical. For `CRT-003`, all five source-backed escalation evidence fields and `Escalation gate result: Satisfied` must also be identical in meaning.

Use `result-template.md` for the observation record. `NOT RUN` and `UNOBSERVABLE` do not count as passes. This manual smoke is the only evidence that can claim external-model profile stability.

The current nine-run observation and raw schema-constrained outputs are stored under `results/`, with `results/2026-08-09.md` as the summary.
