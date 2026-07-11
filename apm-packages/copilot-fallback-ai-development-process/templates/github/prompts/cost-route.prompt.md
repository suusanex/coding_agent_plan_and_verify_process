---
name: cost-route
description: Route an ordinary development request through the Copilot fallback cost-aware process.
agent: copilot-cost-router
model: GPT-5.6 Terra (copilot)
tools: ['codebase', 'editFiles', 'runCommands']
---

Route this request through the GitHub Copilot fallback AI Development Process.

- Read repo-local instructions and existing artifacts.
- Read or create `plans/<slug>/codex-first-state.md`.
- Choose the next gate and `COPILOT_*` model tier.
- Do not implement before READY.
- Do not close with unresolved `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`.
- Use handoff to the appropriate Copilot fallback agent when needed.

User request:

`${input:request:この issue を進めて}`
