# Example: Existing AGENTS Layering

## Scenario

The target repository already has `AGENTS.md`.

## Expected behavior

- Treat the Codex-first profile and repo guidance as layered instructions.
- Keep repo-local build/test/security rules authoritative.
- Do not replace the repo `AGENTS.md`.
- Detect `AGENTS.override.md` when present.
- If instruction size or conflicts may hide important guidance, produce a bootstrap / dry-run merge report.
- Stop with `NeedsHumanDecision` instead of applying ambiguous changes.
