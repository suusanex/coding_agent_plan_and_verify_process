# Goal Context same-parent PR review design

## Canonical responsibility address

`scripts/manage-same-parent-review.cs` is the package-owned orchestration and minimal-state address. The APM-installed `$goal-context-pr-review` Skill invokes it from the original implementation parent task.

The utility resolves the current repository, prefers the current branch Ready PR, falls back to a unique repository-wide Ready PR, and selects an exact or conventionally discovered Goal Context. Goal Context content is arbitrary readable free-form text; authoring format and provenance are outside this flow. It creates `.review/pr-N/same-thread/<run-id>/` automatically and owns only these projections:

- `run-state.json`: round, current head, Goal Context identity, reviewer role/count ledger, finding projection, terminal state
- `run-summary.md`: human-readable projection; raw evidence has higher precedence
- `round-NNN/`: collector context/patch, Goal Context selection, reviewer raw outputs, parent assessment
- `terminal-projection.json` and `completion-notification.txt`: optional XC-001 producer fields

It does not spawn reviewers, edit production files, commit, push, or change GitHub state. Those actions remain with the Codex parent or read-only reviewer roles defined by the Skill.

## Authority and precedence

1. current collector-declared remote PR head and patch
2. exact selected Goal Context content identity
3. unmodified reviewer raw outputs
4. explicit current `PUR-*` prior assessment
5. `run-state.json`
6. `run-summary.md`
7. terminal notification projection

Issue text never replaces Goal Context. A missing heading or lifecycle marker never invalidates Goal Context. Text similarity never replaces stable finding IDs.

## Round model

- Round 1: GitHub Copilot sources, `local-reviewer`, `purpose-reviewer`
- Round 2/3: current-head collector refresh with no Copilot wait, then a new `purpose-reviewer` only
- Parent: sole production/tests/docs writer and validator
- Terminal: `Complete`, `HumanDecisionRequired`, or `Blocked`
- Maximum: 3; no automatic round 4

The state utility verifies exact mandatory-source sets. A purpose-only assessment containing local reviewer evidence, Copilot mandatory coverage, incomplete prior tracking assessment, or non-`PUR-*` actionable evidence is rejected.

## Historical compatibility boundary

`scripts/manage-review-cycle.cs` retains the schema and validations for historical fixed Review Thread / Implementation Thread evidence. It is not the canonical normal-path orchestrator and is not relabeled as same-parent behavior. Existing PRR-003 replay may continue to validate historical artifacts, but current Skill usage and docs do not require role task IDs or manual Adaptive handoffs.

## XC-001

The producer projection contains only:

- `schema_version`
- `primary_process`
- `observed_status`
- safe `title`
- current concrete HTTPS PR `result_uri`

It contains no thread or turn identity. The callback consumer remains authoritative for those fields. The parent appends `completion-notification.txt` verbatim to the terminal `last-assistant-message`; real callback and button operation remain manual verification.

## XC-002

The run state records executed reviewer roles/count and reviewed head after raw outputs are accepted. This enables later real same-parent smoke correlation. It does not infer callback hierarchy or prove user-visible notification counts.
