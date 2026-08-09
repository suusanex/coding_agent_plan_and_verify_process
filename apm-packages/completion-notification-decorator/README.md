# Completion Notification Decorator

`completion-notification-decorator` distributes the always-on Codex completion Local Spool runtime and provides an optional observational Skill for richer process/result metadata. Once installed, every valid `agent-turn-complete` callback produces one editor-readable JSON spool item without requiring this Skill, a marker, or an envelope.

The package contains no custom agent or generic process runner. It includes checked mirrors of the canonical File-based apps, schemas, and runtime documentation under the installed Skill's `assets/codex-notification-runtime/` directory. The producer/consumer boundary is documented in [local-spool-interface.md](.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/local-spool-interface.md).

## Install or update

To install into a work repository, run the following from the target root and point `$sourceRoot` at this repository checkout. The package smoke validates this local package path from a separate consumer repository.

```powershell
$sourceRoot = "C:\path\to\coding_agent_plan_and_verify_process"
apm install "$sourceRoot\apm-packages\completion-notification-decorator" --target codex,agent-skills
dotnet run --file .\.agents\skills\completion-notification-decorator\assets\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --dry-run
dotnet run --file .\.agents\skills\completion-notification-decorator\assets\codex-notification-runtime\install-codex-notification-runtime-local.cs -- install
dotnet run --file .\.agents\skills\completion-notification-decorator\assets\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --check
```

The runtime installer configures exactly one Local Spool provider for the current OS user. Its default folder is `%LOCALAPPDATA%\CodexNotificationRuntime\spool`; `CODEX_NOTIFICATION_SPOOL_HOME` can supply an absolute override. Run it once for each OS user who uses Codex, and restart Codex after changing that user's configuration.

## Ordinary notifications

After installation, use Codex normally. A valid callback without notification-specific text or metadata produces a generic `TURN_ENDED` spool item. The item always keeps `codex://threads/<thread-id>` derived from the callback. Missing or invalid enrichment cannot suppress this path.

## Optional enrichment

Select the decorator and exactly one primary process only when the notification should also show that process's status/title or a concrete HTTPS result action:

```text
$completion-notification-decorator
$adaptive-implementation-execution

このPlanを実装してください。
```

The primary process runs under its existing contract. The decorator copies its terminal status into a version 1 envelope at the end of the final response. The callback thread/turn identity remains authoritative. Missing or invalid envelope data falls back to a generic Local Spool item, and persistence failure does not change the process status.

The Local Spool JSON keeps both `result_uri` and the callback-derived `resume_uri` when available. The decorator does not select or start another review or implementation task. The package does not add a consumer, Inbox, toast, retention, forwarding, or cloud sync.

See [usage guide](docs/usage-guide.md) and [integration validation](docs/examples/integration-validation.md).

## Validate

```powershell
./apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator-contract.ps1
./apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1
./apm-packages/completion-notification-decorator/scripts/test-apm-package-install.ps1
dotnet publish ./scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs
git diff --check
```
