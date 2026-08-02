# Codex completion notification manual verification

## Environment

- Windows: Windows 11 Pro build 26200
- Codex CLI: 0.145.0
- Codex Desktop: 26.721.4979.0
- Provider: Local Spool (`spool-item-v1` JSON); Windows App provider is legacy rollback reference only

## Automated verification

- Status: 検証済み（2026-07-29）
- Command: `pwsh -NoProfile -File scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`
- Coverage: markerless generic event、optional enrichment / invalid fallback、callback identity、stable 10-field spool schema、same-ID replay / parallel、distinct IDs、atomic publish、single-provider fail-open、installer install/check/rollback、File-based apps publish

## Live callback verification

永続的なuser-level `config.toml`は変更せず、one-off `codex exec -c notify=...`で確認する。

| Check | Status | Evidence |
|---|---|---|
| 通常の`agent-turn-complete` callback受信 | 要再検証 | marker、Decorator、envelopeなしの親turnでcallbackとgeneric通知を確認する |
| invalid envelope fallback | 要再検証 | 不正envelopeでもgeneric通知とtask復帰導線が残ることを確認する |
| production Spool folder / JSON | ManualOnly | installed callbackが`%LOCALAPPDATA%\CodexNotificationRuntime\spool`にUTC-first JSONを1件作り、通常のeditorで10-field JSONを読めることを確認する |
| `result_uri`と`resume_uri`の保存 | 更新後要再検証 | installed itemのJSONにresult/resume導線が保存されることを確認する |
| parent + reviewer subagent通知件数 / target | ManualOnly | real parentからreviewer subagentを起動し、user-visible通知がparent中心でspamにならないことを記録する。公開callbackにないhierarchy fieldからfilterを推測しない |
| provider failure時のturn非影響 | 自動検証済み | Local Spool provider failure / timeoutでもruntime callbackはexit code 0を維持する |

### Codex実行証跡（2026-08-02）

- 実ユーザー環境へのLocal Spool runtime導入後、installer `--check` はPASSした。既存の`notify` chainは保持された。
- `codex exec --ephemeral --sandbox read-only` によるone-off turnはexit code 0で完了した。
- production Spool pathは`%LOCALAPPDATA%\CodexNotificationRuntime\spool`。実行前0件、実行後2件のfinal JSONを確認した。親turnとone-off turnが同じ実行窓で完了したため、one-offのcallback identityに一致するfinalは1件だった。
- one-offに一致するfinalはUTC-first filenameで、temp / partial fileは0件だった。
- 実行後に得られたfinal JSON 2件すべてが`spool-item-v1` schemaに適合し、10 fieldsかつ`notification_status`なしだった。one-off itemは`observed_status: TURN_ENDED`、`resume_uri`は`codex` scheme、`result_uri`はJSON `null`だった。
- 通常のeditorでfolderを開いてJSONを読む目視確認は、ユーザー確認によりPASS（2026-08-02）。

one-off `codex exec`は外側のCodex Desktop taskとは別の発火元threadを作る。そのthreadをDesktopでまだ開いていない場合、deep link後は新しいtaskが開いたように見えるが、表示された入力と応答がone-off実行と一致することを発火元thread遷移の根拠とする。通常運用ではcallback payload自身の`thread-id`から`resume_uri`を作るため、通知を発火したtaskが遷移先になる。`result_uri`がある場合も`resume_uri`を置き換えず、両ボタンを同じ通知へ表示する。

thread ID、turn ID、input message、assistant message、credentialはこの記録へ保存しない。

## Goal Context same-parent end-to-end procedure

人手での作業が必要: 次のbutton操作とuser-visible notification件数を実機で確認する。

1. Decoratorやnotification envelopeを指定しない通常のCodex turnを完了し、generic Windows通知が表示されることを確認する。
2. 「このタスクを開く」を押し、その通常turnの発火元taskがCodex Appで開くことを確認する。
3. disposable Ready PRとfree-form Goal Contextを使い、元の実装taskで`$goal-context-pr-review`をterminalまで完了する。
4. terminal assistant message末尾に`completion-notification.txt`のfenced blockがverbatimで一度だけ含まれることと、Windows通知が表示されることを確認する。
5. 同じ通知の「このタスクを開く」が元の実装taskを開き、「結果を開く」が対象PRを開くことを確認する。
6. reviewer subagent実行中のuser-visible通知件数とtargetを記録し、親のterminal通知を見失うspamがないかを判定する。callbackにないhierarchy fieldを仮定してfilterしない。
