# Installed Codex notification runtime assets

This directory is installed with the APM package so the user-level runtime can be set up without a repository checkout. The canonical sources are mirrored from `scripts/codex-notification-runtime/` and checked byte-for-byte by the package validator.

From the installed Skill directory, run:

```powershell
dotnet run --file .\assets\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --dry-run
dotnet run --file .\assets\codex-notification-runtime\install-codex-notification-runtime-local.cs -- install
dotnet run --file .\assets\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --check
```

The installer publishes the adjacent runtime and Windows provider sources, preserves an existing user-level `notify` command as a bounded chain, and replaces only the top-level Codex `notify` entry. Ordinary valid `agent-turn-complete` callbacks are notified without a marker, decorator, or envelope. A valid version 1 envelope is optional enrichment.

Read `decision-record.md` for the runtime contract and `manual-verification.md` for automated and manual verification boundaries.
