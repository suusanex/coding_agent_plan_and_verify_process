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
- result URI: userinfoなしのHTTPSかつ具体的resource pathを持つものだけを許可する。host rootとGitHubのトップ・ownerトップ・repositoryトップは拒否する。有効なresult URIがある場合、Windows providerは「結果を開く」と「このタスクを開く」の両ボタンを表示し、resume URIを置き換えない。
- every valid `agent-turn-complete` callbackはmarker、Skill token、envelopeの有無にかかわらずgeneric candidateになる。generic eventは`primary_process: codex`、`observed_status: TURN_ENDED`を使い、repositoryはcallbackの`cwd`から解決する。
- `completion-notification` fenced blockのJSONはoptional authoring envelopeであり、fully validな場合だけprocess、status、title、repository、resultをenrichする。unknown field、unsafe text、unsafe/coarse result URIを含むinvalid envelopeは全体を無視してgeneric fallbackにする。
- `thread-id`、`turn-id`、`resume_uri`、`source_event_id`はcallbackだけをauthorityとし、envelopeから上書きしない。`target_markers`とinstallerの`--target-marker`は既存runtime configとの読み取り互換性だけのために残し、通知対象判定には使わない。

## Safety and rollback

- callback modeは常にexit code 0で終了する。provider、log、dedup、chainの失敗は主process verdictを変えない。
- installerは初回導入時だけ`config.toml.codex-notification-runtime.bak`を作成し、更新時には上書きしない。rollbackはCodexを終了し、そのbackupから元configを復元してから`%LOCALAPPDATA%\CodexNotificationRuntime`を削除する。
- installerは最初のTOML tableより前にtop-level `notify`を配置し、staging検証後にbin、runtime config、user configの順で切り替える。途中失敗時は直前のbinとruntime configへ戻す。
- runtime logはevent hashと状態だけを保持し、assistant message、input message、完全URIを保存しない。

## Human verification required

one-off `codex exec -c notify=...`でterminal notificationを表示し、`result_uri`ボタンが対象PRを、`resume_uri`ボタンがcallback発火元のCodex threadを直接開くことを2026-07-26に実機確認した。always-on generic callback、両ボタンの同時表示、invalid envelope fallback、real parent/subagent通知件数は更新後のmanual smokeで再確認する。

実施状況は`manual-verification.md`へ、message本文・完全URI・識別子を含めずに記録する。
