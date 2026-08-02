# Codex Local Inbox

Codex Local Inbox is a packaged WinUI 3 application that displays completed
`spool-item-v1` files from the Local Spool producer.

## Prerequisites and build

Install the WinUI MVVM template and Windows App SDK prerequisites, then use the
repository WinUI workflow:

```powershell
.\BuildAndRun.ps1 apps\CodexLocalInbox\CodexLocalInbox.csproj
```

The project targets x64, ARM64, and x86 packaged MSIX builds. Do not run the
packaged executable directly; use `BuildAndRun.ps1` or `winapp run`.

## Usage

The default spool folder is:

```text
%LOCALAPPDATA%\CodexNotificationRuntime\spool
```

Set `CODEX_NOTIFICATION_SPOOL_HOME` to an absolute path to override it. The
Inbox reads only final `.json` files, validates the exact ten-field
`spool-item-v1` contract, and preserves malformed or unsafe files as removable
error entries.

Use Resume, Open result, and Delete on each card. Delete is immediate and has
no Undo. Closing the window hides it in the notification area. Use Show Inbox
to restore it or Exit to stop monitoring and terminate the app.

The application intentionally has no database, service, autostart, search,
filter, retention policy, toast delivery, forwarding, or multi-window mode.
