# Codex notification runtime assets

The canonical File-based apps in this directory install an always-on Local Spool producer. Each valid `agent-turn-complete` callback is persisted as one editor-readable `spool-item-v1` JSON file.

The production provider is exactly one `local-spool` provider. Existing user-level `notify` metadata is retained only for safe update and rollback handling; this runtime does not forward to a Windows toast provider, Inbox, consumer, or cloud service.

Use `install-codex-notification-runtime-local.cs` with `--dry-run`, `install`, and `--check`. The configured spool folder defaults to `%LOCALAPPDATA%\CodexNotificationRuntime\spool`; `CODEX_NOTIFICATION_SPOOL_HOME` may override only that folder with an absolute path.

The producer/consumer boundary, `spool-item-v1` fields, file naming, atomic publication, and consumer-owned retention responsibilities are defined in [local-spool-interface.md](local-spool-interface.md).
