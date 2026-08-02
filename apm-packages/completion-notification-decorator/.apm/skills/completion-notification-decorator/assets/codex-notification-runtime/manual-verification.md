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

永続的なuser-level `config.toml`は変更せず、one-off `codex exec --ephemeral --sandbox read-only`で確認する。

| Check | Status | Evidence |
|---|---|---|
| 通常の`agent-turn-complete` callback受信 | PASS | one-off callbackがLocal Spoolへfinal JSONを保存した |
| invalid envelope fallback | 自動検証済み | 不正envelopeはgeneric spool itemへfallbackした |
| production Spool folder / JSON | PASS（2026-08-02） | installed callbackが`%LOCALAPPDATA%\CodexNotificationRuntime\spool`にUTC-first JSONを作り、通常のeditorで10-field JSONを読めた |
| `result_uri`と`resume_uri`の保存 | PASS（2026-08-02） | installed itemのJSONに両フィールドを保存した。表示actionは後続consumerの責務とする |
| parent + reviewer subagent通知件数 / target | DeferredWithSource | user-visible通知件数、toast、consumer filteringは後続スコープ |
| provider failure時のturn非影響 | 自動検証済み | Local Spool provider failure / timeoutでもruntime callbackはexit code 0を維持する |

### Codex実行証跡（2026-08-02）

- 実ユーザー環境へのLocal Spool runtime導入後、installer `--check` はPASSした。既存の`notify` metadataは更新・rollback用に保持された。
- `codex exec --ephemeral --sandbox read-only` によるone-off turnはexit code 0で完了した。
- production Spool pathは`%LOCALAPPDATA%\CodexNotificationRuntime\spool`。実行前0件、実行後2件のfinal JSONを確認した。親turnとone-off turnが同じ実行窓で完了したため、one-offのcallback identityに一致するfinalは1件だった。
- one-offに一致するfinalはUTC-first filenameで、temp / partial fileは0件だった。
- 実行後に得られたfinal JSON 2件すべてが`spool-item-v1` schemaに適合し、10 fieldsかつ`notification_status`なしだった。one-off itemは`observed_status: TURN_ENDED`、`resume_uri`は`codex` scheme、`result_uri`はJSON `null`だった。
- 通常のeditorでfolderを開いてJSONを読む目視確認は、ユーザー確認によりPASS（2026-08-02）。

one-off `codex exec`のcallback identityはspool itemの`source_event_id`と`resume_uri`へ保存される。consumer、deep link、button操作はこのproducer scopeに含めない。

thread ID、turn ID、input message、assistant message、credentialはこの記録へ保存しない。

## Deferred consumer verification

Inbox、consumer state、toast、button action、forwarding、retention、parent/subagent通知件数は後続スコープとする。今回のmanual evidenceはproduction Spool folderとJSONを通常のeditorで閲覧できることまでを対象とする。
