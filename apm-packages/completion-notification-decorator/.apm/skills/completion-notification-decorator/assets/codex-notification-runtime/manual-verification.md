# Codex completion notification manual verification

## Environment

- Windows: Windows 11 Pro build 26200
- Codex CLI: 0.145.0
- Codex Desktop: 26.721.4979.0
- Provider: Windows App SDK `AppNotificationManager`

## Automated verification

- Status: 検証済み（2026-07-29）
- Command: `pwsh -NoProfile -File scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`
- Coverage: markerless generic event、optional enrichment / invalid fallback、callback identity、event/schema、dedup、provider / chain failure、timeout/retry、結果／現在taskのdual-button contract、既存notify転送、installer install/check/reinstall/rollback/self-wrap、TOML table挿入、File-based apps publish

## Live callback verification

永続的なuser-level `config.toml`は変更せず、one-off `codex exec -c notify=...`で確認する。

| Check | Status | Evidence |
|---|---|---|
| 通常の`agent-turn-complete` callback受信 | 要再検証 | marker、Decorator、envelopeなしの親turnでcallbackとgeneric通知を確認する |
| invalid envelope fallback | 要再検証 | 不正envelopeでもgeneric通知とtask復帰導線が残ることを確認する |
| `result_uri`から対象PRを開く | 更新後要再検証 | terminal notificationの「結果を開く」からsame-parent runの対象PRが直接開くことを確認する |
| `resume_uri`から発火元threadを開く | 更新後要再検証 | 同じterminal notificationの「このタスクを開く」から検証用threadを直接開くことを確認する |
| parent + reviewer subagent通知件数 / target | ManualOnly | real parentからreviewer subagentを起動し、user-visible通知がparent中心でspamにならないことを記録する。公開callbackにないhierarchy fieldからfilterを推測しない |
| provider failure時のturn非影響 | 検証済み（2026-07-26 11:12 JST） | 存在しないproviderを指定してruntimeは`FAILED`を記録し、`codex exec`はexit code 0で回答を保持 |

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
