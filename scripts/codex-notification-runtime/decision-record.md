# Codex completion notification runtime MVP decision record

## Decision

Windows 11上の初期providerは、Windows App SDKの`AppNotificationManager`を使う独立processとする。core runtimeはprovider commandへevent JSONをstdin送信するため、ntfy、Slack、Web UIを追加してもCodex callback解析と重複抑止は変更しない。

Codexのuser-level `notify`は一つのargvしか設定できないため、installerはruntimeを設定し、設定済みcommandを`runtime-config.json`の`chained_notify`として保持する。runtimeはすべてのcallbackで既存commandへ元JSONを最後の引数として転送する。

配布のsource of truthは3本の`.cs` File-based appsとする。installerは導入時にsourceからstaging directoryへpublishし、repository内の`artifacts/`生成物は配布契約に含めない。

Windows providerは副作用なしのself-testでWindows App SDKを初期化しない。support probeと通知配送時だけ明示的にbootstrapし、installerはprobeが5秒で終了しない場合にprocess treeを終了してstdout・stderrのEOFを回収する。CI jobにも15分の上限を設け、headless環境の停止がrunnerを無期限に占有しないようにする。

## Observed environment

- Windows 11 Pro build 26200
- Codex CLI 0.145.0
- Codex Desktop 26.721.4979.0
- 既存のuser-level `notify` commandあり。導入時に上書きせずchainする。

## Contract

- Codex callback: `agent-turn-complete`、`thread-id`、`turn-id`、`cwd`、`input-messages`、`last-assistant-message`。
- resume URI: `codex://threads/<thread-id>`をruntimeで生成する。
- result URI: userinfoなしのHTTPSかつ具体的resource pathを持つものだけを許可する。host rootとGitHubのトップ・ownerトップ・repositoryトップは拒否し、resume URIへfallbackする。
- `completion-notification` fenced blockのJSONはauthoring envelopeであり、runtime eventは`notification_status`を追加して配送する。
- input内のliteral marker `[completion-notification]`または明示Skill選択token `$completion-notification-decorator`はtarget declarationとして使う。ただしproviderへ配送するのは有効なterminal envelopeがあるcallbackだけとする。markerだけのcallbackは`awaiting-terminal-envelope`、不正なenvelopeは`invalid-envelope`としてlogへ記録し、`TURN_ENDED` fallbackは生成しない。installerの`--target-marker`を明示した場合は、指定したmarker群へ置き換える。

## Safety and rollback

- callback modeは常にexit code 0で終了する。provider、log、dedup、chainの失敗は主process verdictを変えない。
- installerは初回導入時だけ`config.toml.codex-notification-runtime.bak`を作成し、更新時には上書きしない。rollbackはCodexを終了し、そのbackupから元configを復元してから`%LOCALAPPDATA%\CodexNotificationRuntime`を削除する。
- installerは最初のTOML tableより前にtop-level `notify`を配置し、staging検証後にbin、runtime config、user configの順で切り替える。途中失敗時は直前のbinとruntime configへ戻す。
- runtime logはevent hashと状態だけを保持し、assistant message、input message、完全URIを保存しない。

## Human verification required

one-off `codex exec -c notify=...`でterminal notificationを表示し、`result_uri`ボタンが対象PRを、`resume_uri`ボタンがcallback発火元のCodex threadを直接開くことを2026-07-26に実機確認した。marker-only callbackの抑止とterminal envelope後の一意配送は更新後のmanual smokeで再確認する。

実施状況は`manual-verification.md`へ、message本文・完全URI・識別子を含めずに記録する。
