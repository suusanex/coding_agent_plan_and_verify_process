# Codex Notification Runtime

このdirectoryには、Completion Notification Decoratorと一緒に導入されたCodex Notification Runtime assetsがあります。Codex turn終了時の`agent-turn-complete` callbackをLocal Spoolへ保存するalways-on producerを導入し、valid callbackごとに、editorで読める`spool-item-v1` JSONを1 event 1 fileでappend-onlyに発行します。

production providerは一つの`local-spool` providerだけです。既存user-level `notify` metadataはsafe updateとrollbackのためにだけ保持し、Windows toast、Inbox、consumer、retention、forwarding、cloud serviceへ配信しません。

## Install

導入先repository rootから、installed Skill内のassetを使ってdry-run、install、checkの順で実行します。

```powershell
$runtimeAssetRoot = ".\.agents\skills\completion-notification-decorator\assets\codex-notification-runtime"
dotnet run --file "$runtimeAssetRoot\install-codex-notification-runtime-local.cs" -- --dry-run
dotnet run --file "$runtimeAssetRoot\install-codex-notification-runtime-local.cs" -- install
dotnet run --file "$runtimeAssetRoot\install-codex-notification-runtime-local.cs" -- --check
```

通常導入では`%LOCALAPPDATA%\CodexNotificationRuntime`をinstall rootに使います。一時環境で検証する場合は`--codex-home <path> --install-root <path>`を指定します。

既定のSpool folderは`%LOCALAPPDATA%\CodexNotificationRuntime\spool`です。`CODEX_NOTIFICATION_SPOOL_HOME`だけが、絶対pathによるSpool folder overrideを行えます。

installerはasset directoryにある3本の`.cs` sourceからtemporary areaへpublishします。`artifacts/`の生成物は追跡・配布しません。

## Event behavior

通常通知にenvelopeは不要です。runtimeはcallbackの`thread-id`と`turn-id`をidentity authorityとし、`codex://threads/<thread-id>`へのresume URIを生成します。enrichmentがない場合はgeneric `TURN_ENDED` itemを保存します。

process、status、title、repository、resultを表示したい場合だけ、primary processの最終応答にversion 1 envelopeを追加できます。

````markdown
```completion-notification
{"schema_version":1,"primary_process":"adaptive-implementation-execution","observed_status":"COMPLETED","title":"implementation completed","repository":"owner/repository","result_uri":"https://github.com/owner/repository/pull/123"}
```
````

`result_uri`は具体的な結果を指すuserinfoなしのHTTPS URLだけを受理します。host root、GitHub top、owner top、repository topのような粗いlinkは破棄します。envelope、field、URIが不正な場合はenrichment全体を無視し、generic itemを保存します。runtimeまたはproviderの失敗はprimary Codex turnを失敗にしません。

optional enrichmentの使い方は、同じinstalled Skillの`SKILL.md`を参照してください。

## Producer and consumer boundary

producer / consumer I/F、`spool-item-v1` fields、file naming、atomic publication、consumer-owned retentionは[local-spool-interface.md](local-spool-interface.md)で定義します。Codex Local InboxはこのSpoolを読む独立したconsumerであり、このAPM packageには含まれません。

rollbackとprovider選択のdecisionは[decision-record.md](decision-record.md)、実機確認済み範囲とManualOnly項目は[manual-verification.md](manual-verification.md)を参照してください。

## Validate the installed runtime

```powershell
$runtimeAssetRoot = ".\.agents\skills\completion-notification-decorator\assets\codex-notification-runtime"
dotnet run --file "$runtimeAssetRoot\install-codex-notification-runtime-local.cs" -- --check
```

source repositoryのmaintainer向けvalidatorはinstalled Skillへ配布されません。package sourceを変更する場合は、source repositoryにあるCompletion Notification Decoratorとcanonical runtimeのvalidatorを実行してください。
