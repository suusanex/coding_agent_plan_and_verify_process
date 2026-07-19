---
name: fix-selected-residual
description: Fix only selected residual IDs after Copilot fallback verification.
agent: high-implementation-starter
model: GPT-5.6 Terra (copilot)
tools: ['codebase', 'editFiles', 'runCommands']
---

Fix only the selected residual IDs or selected scope.

Selected residuals:

`${input:residualIds:RES-001}`

Rules:

- Do not expand scope beyond the selected residuals.
- Read the state artifact and verification result first.
- Update implementation evidence after the fix.
- Start with HIGH_MODEL; use `standard-implementation-completer` only if this run creates a valid decision-free completion handoff.
- Return to verification after edits.
