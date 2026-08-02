# Codex Local Inbox

Codex Local Inbox is a packaged WinUI 3 application that displays completed
`spool-item-v1` files from the Local Spool producer.

## Prerequisites and build

Install a .NET 11 preview SDK and the Windows App SDK prerequisites. From the
repository root, build, register, and launch the packaged app with:

```powershell
dotnet run --project .\apps\CodexLocalInbox\CodexLocalInbox.csproj
```

The project targets x64, ARM64, and x86 packaged MSIX builds. Do not run the
packaged executable directly; use `dotnet run` or `winapp run` so that the app
has package identity.

Run the automated checks from the repository root with:

```powershell
dotnet test .\tests\CodexLocalInbox.Tests\CodexLocalInbox.Tests.csproj
dotnet build .\apps\CodexLocalInbox\CodexLocalInbox.csproj
```

## Usage

The default spool folder is:

```text
%LOCALAPPDATA%\CodexNotificationRuntime\spool
```

Set `CODEX_NOTIFICATION_SPOOL_HOME` to an absolute path to override it. The
Inbox reads only final `.json` files, validates the exact ten-field
`spool-item-v1` contract, and preserves malformed or unsafe files as removable
error entries.

`source_event_id` is the logical event identity. If multiple valid files have
the same identity, the absolute path that sorts first is shown as the normal
card and the remaining files are shown as removable duplicate-file errors.

Use Resume, Open result, and Delete on each card. Delete is immediate and has
no Undo. Closing the window hides it in the notification area. Use Show Inbox
to restore it or Exit to stop monitoring and terminate the app.

The app is single-instanced. Launching it again redirects activation to the
existing process and restores its window instead of creating another watcher
or notification-area icon.

Packaged access to the producer's real Local Spool, notification-area behavior,
URI activation, and second-launch restoration require a manual Windows smoke
test; the unit tests and CI build do not claim that runtime evidence.

The application intentionally has no database, service, autostart, search,
filter, retention policy, toast delivery, forwarding, or multi-window mode.
