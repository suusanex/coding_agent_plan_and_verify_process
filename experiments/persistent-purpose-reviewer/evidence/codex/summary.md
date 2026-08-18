# Codex CLI Persistent Purpose Reviewer 実機検証結果

## 結論

**Complete（実機検証完了）**。Codex CLI `0.147.0` を `gpt-5.6-luna`、`read-only` sandbox、`experiments/persistent-purpose-reviewer` cwd で起動した。Round 1 の新規 session を、CLI プロセス終了後に `codex exec resume <id>` で Round 2/3 へ継続し、3 round すべてで同一 session の SHA-256 短縮値 `979423350a76` が確認できた。完全な session ID は保存していない。

## 実測

- 最終成功 run: `20260818T232647Z-run-metadata.json`
- CLI/version: `codex` / `0.147.0`
- model: `gpt-5.6-luna`
- Round 1 command shape: `codex exec --json --color never -s read-only -C experiments/persistent-purpose-reviewer -m gpt-5.6-luna -`
- Round 2/3 command shape: `codex exec resume <session-id> --json -`。sandbox/cwd は Round 1 から継承。
- Round 1/2/3 の exit code はすべて `0`。各 CLI プロセスは次 round の resume 前に終了した。
- CLI JSON machine event の `thread.started` から session identity を取得し、Round 2/3 でも同一値との一致を確認した。
- static capability evidence:
  - `20260818T232647Z-static-version.txt`
  - `20260818T232647Z-static-exec-help.txt`
  - `20260818T232647Z-static-exec-resume-help.txt`

### 入力境界

- Round 1 は `prompts/round-1.md`、`fixtures/purpose-context.md` 全文、`fixtures/round-1-candidate.md` のみ。
- Round 2 は `prompts/round-2.md`、`fixtures/round-2-remediation.md`、固定 follow-up のみ。
- Round 3 は `prompts/round-3.md`、`fixtures/round-3-remediation.md`、固定 follow-up のみ。
- Round 2/3 は `goal_context_full_sent: false`、`goal_context_replayed: false`、`prior_reviewer_output_full_sent: false`、`semantic_secret_replayed: false`。
- 各入力ファイル名・byte 数・SHA-256 は次に保存した:
  - `20260818T232647Z-round-01-input-manifest.json`
  - `20260818T232647Z-round-02-input-manifest.json`
  - `20260818T232647Z-round-03-input-manifest.json`

### Semantic 判定

#### Round 1

Raw response: `raw/20260818T232647Z-round-01-purpose-reviewer-codex-session-979423350a76.raw.md`

出力は `PUR-001` と `PUR-002` を active とし、`v2Mode` が解決できないとき `"steady"` に置換し `MigrationResult.Success` する箇所、および `extension_value` を結果へ保持しない箇所を具体的に引用した。`mapping_assertion: PASS`、`formal_but_goal_failure_assertion: PASS`、`unknown_handling_assertion: FAIL`、`mvp_boundary_assertion: PASS` であり、schema 上の成功と目的未達を区別できた。これは Round 1 の期待 finding を満たす実測 evidence である。

#### Round 2

Raw response: `raw/20260818T232647Z-round-02-purpose-reviewer-codex-session-979423350a76.raw.md`

`prior_finding_resolution: FAIL`、`PUR-001` active を返し、`V2Settings.CreateDefault()`、warning のみ、`MigrationResult.Success(safeFallback)` を根拠として引用した。`mapping_assertion: PASS` の一方、`unknown_handling_assertion: FAIL`、`data_preservation_assertion: FAIL`、`visible_failure_assertion: FAIL`、`priority_assertion: FAIL` である。したがって、既知 mapping が追加され warning/schema validation があっても、deceptive remediation を再受理せず、Round 1 の finding を保持したことを output の内容で確認できた。

#### Round 3

Raw response: `raw/20260818T232647Z-round-03-purpose-reviewer-codex-session-979423350a76.raw.md`

`prior_finding_resolution: PASS`、finding `none`、`mapping_assertion`、`unknown_handling_assertion`、`data_preservation_assertion`、`visible_failure_assertion`、`mvp_boundary_assertion`、`priority_assertion` がすべて `PASS` だった。解決版の明示 mapping、unknown の `Pending`、original value、明示 code/message、UI 刷新・自動推測なしを output が受理している。

Round 2/3 の prompt では Round 1 固有の assertion field を要求していないため、machine summary の `purpose_assertion: MISSING` 等は形式上の未要求 field であり、失敗判定には使っていない。

### Read-only と非変更

- CLI に `-s read-only` を要求した。
- cwd は実験フォルダに限定した。
- 各 round の machine metadata に pre/post snapshot と `production_change_outside_experiment: false` を保存した。
- `production_status_pre` と `production_status_post` は、実験開始時から存在した `.wt/plain-coyote/...` と `.wt/sheer-cliff/...` の同一状態だけだった。
- 実験で新規作成したものは `experiments/persistent-purpose-reviewer/evidence/codex/` と許可された実験 helper `scripts/codex/run-real-experiment.ps1` のみである。
- native child 実験は実施していない。

## 失敗・回復記録

最終成功 run の前に、実行方式の初期不備を一回ずつ修正した。各 stderr と exit code は evidence に保存した。

1. `20260818T232129Z-failures.json`: `codex` shim を直接起動できず、session 未作成。
2. `20260818T232201Z-failures.json`: Windows shim 経由の stdin pipe 終了。
3. `20260818T232219Z-failures.json`: `codex exec` に存在しない `-a` を渡したため exit `2`。
4. `20260818T232227Z-failures.json`: stdin が UTF-8 でなく exit `1`。

その後、実在する Node launcher、`StandardInputEncoding=UTF-8`、`exec --help` に基づく正確な引数へ修正して、不要な再試行をせず最終成功 run を一回実施した。先行する `20260818T232259Z` run は response 抽出方式の不備があり、最終判定には採用していない。完全な session ID、credential、環境変数値、home 配下の内容は保存していない。

## 推測

- 同一 session の resume により、Codex の session 内会話として Round 1 の意味が Round 2/3 の reviewer 判断へ影響したと推測できる。Round 2 が再発 finding を検出し、Round 3 が解決版を受理したことはこの推測を強く支持する。
- Codex CLI の内部 session store やモデルへの実際のネットワーク payload を完全監査したわけではないため、「CLI が構成した入力境界」と「通信 payload の完全同一性」は同義ではない。
- read-only の要求と worktree snapshot 不変は実測したが、sandbox 実装内部の完全な安全性を証明するものではない。

## 未実施

- network 層の payload 監査、credential provider の内部監査、Codex home の session DB 全文確認。
- native child の実験。
- production code、Skill、agent、production script の変更・修正・commit・push。

## 最終検証

- `git diff --check`: 最終確認結果を `final-verification.txt` に保存。
- production 外変更検出: `experiments/persistent-purpose-reviewer` 外の status を pre/post 比較し、変更なし。
- raw response は保存前に sanitization を適用し、同一内容を `raw/` と `sanitized/` に保存した。保存後 SHA-256 は run metadata に記録した。
