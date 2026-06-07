# Install Guide

## Dry-run first

対象 repository へ入れる前に dry-run を実行してください。

```powershell
dotnet run --file .\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs -- <target-repo-path> --dry-run
```

dry-run は追加予定ファイル、既存 `.github` customization、衝突、manual merge が必要な項目を表示します。

## Apply

衝突がない場合は `--dry-run` を外して適用します。

```powershell
dotnet run --file .\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs -- <target-repo-path>
```

既存同名ファイルと内容が異なる場合、既定では停止します。template を上書きする必要がある場合だけ `--force` を使います。

```powershell
dotnet run --file .\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs -- <target-repo-path> --force
```

`.github/copilot-instructions.md` は marker 管理された block だけを差し替えます。既存 instructions 全体を自動で破壊的に置き換えません。

## Verify in VS Code

- custom agents に `copilot-cost-router` が見える
- prompt files に `/cost-route`、`/resume-state`、`/verify-and-close` が見える
- 「この issue を進めて」で実装に直行しない
- `plans/<slug>/codex-first-state.md` が作られる
- close blocker が残る場合に完了扱いしない

