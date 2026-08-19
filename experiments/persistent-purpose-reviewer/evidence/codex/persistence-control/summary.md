# Codex Persistent Purpose Reviewer 実験結果

## 結論

**Semantic persistence qualification: Partial（Yes ではない）**。

Codex の同一 session 継続自体は成立した。Persistent Round 2 は `focus-mode` の契約違反を `active` / `fail` として検出し、Fresh Round 2 は同一 payload で `unknown` / `insufficient` を返した。Persistent Round 3 は `quick-check` を `resolved` / `pass` として受理した。

ただし Persistent Round 2 の evidence は candidate の `focus-mode` のみで、期待値 `quick-check` と旧外部 consumer wire contract による棄却理由を明示していない。したがって、要求された「正確な wire-token 違反と rationale」の完全な検出とはせず、**Partial** と判定した。Fresh が正解を推測した事実はないため、fixture の再調整は行っていない。

## 実行方式と入力境界

- CLI: Codex `0.147.0`
- model: `gpt-5.6-luna`
- sandbox: `read-only`
- cwd: `experiments\persistent-purpose-reviewer`
- Round 1: 新規 `codex exec`。prompt、Round 1 context、Round 1 candidate の bytes のみ送信。
- Persistent Round 2/3: Round 1 プロセス終了後、同じ具体的 session ID を `codex exec resume` で指定。各 round の prompt と candidate の bytes のみ送信。
- Fresh Round 2: 新規 `codex exec`。Persistent Round 2 と payload SHA-256 が同一。
- 全 round で full context / previous output / semantic decision / mapping / finding の再送フラグは `false`（Round 1 の full context のみ `true`）。
- Persistent resume は Round 1 の system/bootstrap と異なり、Fresh Round 2 は新規 bootstrap である。この差は command shape に記録した。

Payload equality:

- Persistent R2: `7456fcac41dda767d74e3618eaafde38164fe683148e30992481dfe9084a6c86`
- Fresh R2: `7456fcac41dda767d74e3618eaafde38164fe683148e30992481dfe9084a6c86`

## Session と応答の検証

- Persistent R1/R2/R3 session hash: `f5777d93ac6b`（3 round 同一）
- Fresh R2 session hash: `0e54344aaaeb`（persistent と異なる）
- R1 プロセスは終了してから R2 resume を実行。
- 保存 exact bytes の raw response SHA-256 は `response-hash-verification.json` で直接再計算し、machine metadata と一致。
- sanitized response の SHA-256 も保存後 bytes を直接再計算し、raw と一致した。出力は fixture の架空値だけで、追加の秘密・session ID・環境値は保存していない。

## Semantic 結果

### Persistent Round 1

`PPR-001`, `active`, `fail`。`lantern-pulse` の wire token を `quick-check` に固定する context に対し、candidate の `focus-mode` が違反することを検出した。

### Persistent Round 2

`prior_finding_status: active`、`decision_contract_assertion: fail`。同じ `focus-mode` candidate を違反として保持した。これは Fresh より明確に強いが、`quick-check` と棄却理由を出力 evidence に明示しなかったため、exact violation/rationale の完全要件は未達とした。

### Fresh Control Round 2

`prior_finding_status: unknown`、`decision_contract_assertion: unknown`、`information_sufficiency: insufficient`、evidence は空。正解の token や rationale を推測していない。

### Persistent Round 3

`prior_finding_status: resolved`、`decision_contract_assertion: pass`。`quick-check` candidate を解決済みとして受理した。

## Architecture feasibility と security qualification

- **Architecture feasibility: 成立**。同一 session の R1→R2→R3 resume、Fresh の別 session、read-only sandbox、experiment cwd、payload equality を実測できた。
- **Security qualification: Partial**。Fresh negative control は成立したが、Persistent R2 の rationale 出力が exact 要件に届かなかった。
- network payload、credential provider、OS sandbox 内部の監査は本実験の範囲外である。これは architecture failure とは判定していない。

## Git と変更境界

`production_unchanged: true`。Codex 実行による production files / skills / production scripts / config の変更は検出しなかった。`git diff --check` は PASS。

実験中の pre/post status の差分には、別 provider の `evidence\grok\persistence-control\` 配下の並行・既存実験 artifacts が含まれていた。これは production 変更ではないが、Codex の許可 output scope 外として記録し、依頼どおり revert していない。Codex runner 自身の書込みは `evidence\codex\persistence-control\` と専用 runner script に限定した。

## 実行上の失敗

最終判定には使わない局所 runner の失敗が 2 件あった（実験 root の解決誤り、JSON event collection の型不一致）。いずれも修正後に新規 final run を実行し、失敗した応答を再利用していない。詳細は `runner-attempts.json` に保存した。

初回の root 解決誤りで runner 自身が誤った実験パスへ作成した静的 evidence は、final run 前にその作成物だけを削除した。既存の他変更は削除・revert していない。
