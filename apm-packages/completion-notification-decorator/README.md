# Completion Notification Decorator

`completion-notification-decorator` is an explicitly selected observational Skill. It runs in the same Codex parent turn as one existing primary process and appends notification metadata without selecting that process, changing its verdict, or starting another workflow.

The package contains no custom agent or generic process runner. The canonical callback runtime remains in `scripts/codex-notification-runtime`; this package does not copy its source.

## Install or update

From this repository root, install the Skill into the target repository, then install or update the canonical user-level runtime:

```powershell
apm install .\apm-packages\completion-notification-decorator --target codex,agent-skills
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --dry-run
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- install
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --check
```

The runtime installer preserves and chains an existing user-level `notify` command. Restart Codex after changing the user-level runtime configuration.

## Use

Select the decorator and exactly one primary process in the same prompt:

```text
$completion-notification-decorator
$adaptive-implementation-execution

このPlanを実装してください。
```

The primary process runs under its existing contract. The decorator copies its terminal status into a version 1 envelope at the end of the final response. Notification delivery failure does not change that status.

See [usage guide](docs/usage-guide.md) and [integration validation](docs/examples/integration-validation.md).

## Validate

```powershell
./apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1
./apm-packages/completion-notification-decorator/scripts/test-apm-package-install.ps1
dotnet publish ./scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs
git diff --check
```
