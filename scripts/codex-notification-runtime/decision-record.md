# Codex completion notification runtime MVP decision record

## Decision

production providerはLocal Spoolの独立processとする。core runtimeはnormalized event JSONをstdin送信し、providerはstable 10-field `spool-item-v1` JSONを同一directory temp、disk flush、atomic moveで公開する。

installerはruntimeを設定し、callback deliveryにはLocal Spoolだけを設定する。既存notify metadataはrollback参照として保持するがcallbackから転送しない。

配布のsource of truthはruntime、installer、Local Spool providerの3本の`.cs` File-based appsと`spool-item-v1.schema.json`とする。installerは導入時にsourceからstaging directoryへpublishし、repository内の`artifacts/`生成物は配布契約に含めない。

旧Windows providerのソースはrollback参照としてのみ保持する。production callbackはLocal Spool provider一つへ固定し、Windows App SDKのprobe・toast配送・dual-button処理はこのスコープで実行しない。

## Observed environment

- Windows 11 Pro build 26200
- Codex CLI 0.145.0
- Codex Desktop 26.721.4979.0
- 既存のuser-level `notify` metadataは更新・rollbackのために保持するが、production callbackから別providerへchainしない。

## Contract

- Codex callback: `agent-turn-complete`、`thread-id`、`turn-id`、`cwd`、`input-messages`、`last-assistant-message`。
- resume URI: `codex://threads/<thread-id>`をruntimeで生成する。
- result URI: userinfoなしのHTTPSかつ具体的resource pathを持つものだけを許可する。host rootとGitHubのトップ・ownerトップ・repositoryトップは拒否する。有効なresult URIがある場合も、spool itemへ`result_uri`とcallback由来の`resume_uri`を保存するだけで、表示actionは後続consumerの責務とする。
- every valid `agent-turn-complete` callbackはmarker、Skill token、envelopeの有無にかかわらずgeneric candidateになる。generic eventは`primary_process: codex`、`observed_status: TURN_ENDED`を使い、repositoryはcallbackの`cwd`から解決する。
- `completion-notification` fenced blockのJSONはoptional authoring envelopeであり、fully validな場合だけprocess、status、title、repository、resultをenrichする。unknown field、unsafe text、unsafe/coarse result URIを含むinvalid envelopeは全体を無視してgeneric fallbackにする。
- `thread-id`、`turn-id`、`resume_uri`、`source_event_id`はcallbackだけをauthorityとし、envelopeから上書きしない。`target_markers`とinstallerの`--target-marker`は既存runtime configとの読み取り互換性だけのために残し、通知対象判定には使わない。

## Safety and rollback

- callback modeは常にexit code 0で終了する。provider、log、dedupの失敗は主process verdictを変えない。
- installerは初回導入時だけ`config.toml.codex-notification-runtime.bak`を作成し、更新時には上書きしない。rollbackはCodexを終了し、そのbackupから元configを復元してから`%LOCALAPPDATA%\CodexNotificationRuntime`を削除する。
- installerは最初のTOML tableより前にtop-level `notify`を配置し、staging検証後にbin、runtime config、user configの順で切り替える。途中失敗時は直前のbinとruntime configへ戻す。
- runtime logはevent hashと状態だけを保持し、assistant message、input message、完全URIを保存しない。

## Human verification required

one-off `codex exec`でproduction callbackからLocal Spoolへfinal JSONが生成され、通常のeditorで読めることを実機確認する。toast、dual-button、Inbox、consumer state、parent/subagentの通知件数は後続スコープとする。

実施状況は`manual-verification.md`へ、message本文・完全URI・識別子を含めずに記録する。
