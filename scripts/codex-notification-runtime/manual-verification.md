# Codex completion notification manual verification

## Environment

- Windows: Windows 11 Pro build 26200
- Codex CLI: 0.145.0
- Codex Desktop: 26.721.4979.0
- Provider: Windows App SDK `AppNotificationManager`

## Automated verification

- Status: 検証済み（2026-07-26）
- Command: `pwsh -NoProfile -File scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`
- Coverage: event/schema、status保持、fallback、dedup、provider failure/timeout/retry、既存notify転送、installer install/check/reinstall/rollback、TOML table挿入、File-based apps publish

## Live callback verification

永続的なuser-level `config.toml`は変更せず、one-off `codex exec -c notify=...`で確認する。

| Check | Status | Evidence |
|---|---|---|
| `agent-turn-complete` callback受信 | 検証済み（2026-07-26 11:11-11:12 JST） | one-off overrideでresult envelopeとmarker fallbackの2 callbackを受信 |
| Windows通知表示 | 配送成功・目視未検証 | Windows providerが2 callbackともexit code 0を返した |
| `result_uri`からPR #57を開く | 人手での作業が必要 | 「結果を開く」をクリックして確認する |
| `resume_uri`から発火元threadを開く | 人手での作業が必要 | 「Codexを開く」をクリックして確認する |
| provider failure時のturn非影響 | 検証済み（2026-07-26 11:12 JST） | 存在しないproviderを指定してruntimeは`FAILED`を記録し、`codex exec`はexit code 0で回答を保持 |

thread ID、turn ID、input message、assistant message、credentialはこの記録へ保存しない。上記クリック確認が終わるまではIssue #52を実機検証済みとして扱わない。
