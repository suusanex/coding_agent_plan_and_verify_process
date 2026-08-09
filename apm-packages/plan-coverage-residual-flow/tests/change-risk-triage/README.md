# Change Risk Triage profile stability smoke

This suite separates deterministic contract validation from external-model observations.

`inputs/CRT-001.md` through `inputs/CRT-003.md` contain change facts only. `oracles.json` is the CI-only authority for the expected execution-model classifications, selected profile, and escalation result. `result.schema.json` constrains each fresh-session observation, and `agent.sha256` pins the reviewed Change Risk Triage contract using UTF-8 bytes after normalizing CRLF and CR line endings to LF. Update that pin only when the reviewed agent contract changes. CI does not invoke an external model and must not present fixture expectations as model observations.

## Manual procedure

Run every input in a fresh session three times. Give the session only the current `change-risk-triage.agent.md`, exactly one `inputs/CRT-*.md` file, the observation schema, and the instruction to produce a normal-mode triage artifact. Never provide `oracles.json`, another run's output, an expected profile, an expected execution model, or an expected escalation result. Do not carry an earlier result into the next run.

For every run, record:

- the agent SHA-256;
- all bounded runtime sequences;
- every execution-model classification;
- the recommended profile;
- `Why standard-slice is insufficient` and the escalation gate result;
- recommendation confidence and the evidence that would lower or raise the profile.

The three runs for an input pass only when the execution-model set, recommended profile, and required section presence are identical and match the CI-only oracle. For `CRT-003`, all five source-backed escalation evidence fields and the escalation result must also be identical in meaning.

Use `result-template.md` for the observation record. `NOT RUN` and `UNOBSERVABLE` do not count as passes. This manual smoke is the only evidence that can claim external-model profile stability.

The current nine-run observation and raw schema-constrained outputs are stored under `results/`, with `results/2026-08-09.md` as the summary.
