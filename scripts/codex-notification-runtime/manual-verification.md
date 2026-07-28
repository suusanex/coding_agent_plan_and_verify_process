# Codex completion notification manual verification

## Environment

- Windows: Windows 11 Pro build 26200
- Codex CLI: 0.145.0
- Codex Desktop: 26.721.4979.0
- Provider: Windows App SDK `AppNotificationManager`

## Automated verification

- Status: 検証済み（2026-07-26）
- Command: `pwsh -NoProfile -File scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`
- Coverage: event/schema、status保持、terminal-envelope gating、dedup、provider failure/timeout/retry、既存notify転送、installer install/check/reinstall/rollback、TOML table挿入、File-based apps publish

## Live callback verification

永続的なuser-level `config.toml`は変更せず、one-off `codex exec -c notify=...`で確認する。

| Check | Status | Evidence |
|---|---|---|
| `agent-turn-complete` callback受信 | 要再検証 | marker-only中間callbackとterminal envelope callbackの連続受信を確認する |
| Windows通知表示 | 要再検証 | marker-onlyでは表示されず、terminal envelopeで1件だけ表示されることを確認する |
| `result_uri`からPR #57を開く | 検証済み（2026-07-26） | 「結果を開く」から対象PRが直接開いた |
| `resume_uri`から発火元threadを開く | 検証済み（2026-07-26） | terminal notificationの「Codexを開く」から検証用threadを直接開いた |
| provider failure時のturn非影響 | 検証済み（2026-07-26 11:12 JST） | 存在しないproviderを指定してruntimeは`FAILED`を記録し、`codex exec`はexit code 0で回答を保持 |

one-off `codex exec`は外側のCodex Desktop taskとは別の発火元threadを作る。そのthreadをDesktopでまだ開いていない場合、deep link後は新しいtaskが開いたように見えるが、表示された入力と応答がone-off実行と一致することを発火元thread遷移の根拠とする。通常運用ではcallback payload自身の`thread-id`から`resume_uri`を作るため、通知を発火したtaskが遷移先になる。

thread ID、turn ID、input message、assistant message、credentialはこの記録へ保存しない。
