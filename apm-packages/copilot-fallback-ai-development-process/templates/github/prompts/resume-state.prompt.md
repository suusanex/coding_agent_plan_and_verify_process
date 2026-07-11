---
name: resume-state
description: Resume Copilot fallback work from the compatible codex-first state artifact.
agent: copilot-cost-router
model: GPT-5.6 Terra (copilot)
tools: ['codebase', 'editFiles', 'runCommands']
---

Resume from `plans/<slug>/codex-first-state.md`.

- Locate the relevant state artifact.
- Read `current_gate`, `next_gate`, Routing Plan, Edit Permission, `stop_reason`, `unresolved_residuals`, and `next_action`.
- Execute only the next gate.
- Confirm whether edits are allowed before implementation.
- Update the state artifact before stopping.
