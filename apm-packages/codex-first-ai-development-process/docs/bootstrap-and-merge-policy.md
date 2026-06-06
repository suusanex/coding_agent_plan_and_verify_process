# Bootstrap And Merge Policy

Team profile layering is the preferred installation path.
Bootstrap / merge support is only for repositories where layering is insufficient.

## Detect before changing

Inspect:

- `AGENTS.md`
- `AGENTS.override.md`
- `.codex`
- existing scripts
- existing skills or APM package files
- build/test/security instructions
- approximate instruction size and duplication risk

## Dry-run first

Bootstrap must produce a dry-run report before changing repo files.
The report should include:

- detected files
- instruction layering risk
- `AGENTS.override.md` impact
- likely size-limit risk
- proposed additions
- conflicts with repo-local rules
- files that would be changed

## Merge rules

- Do not replace repo-local rules.
- Do not weaken build/test/security requirements.
- Do not remove existing `AGENTS.md` content.
- Do not modify production, secret, billing, or external service settings.
- Apply changes only after user approval.
- Stop when automatic merge would be ambiguous.

## Stop reasons

Use:

- `NeedsHumanDecision` for rule conflicts or unclear ownership.
- `ManualVerificationRequired` for repo behavior that must be tested by a human.
- `Blocked` when required files are unreadable or the repo state is inconsistent.
