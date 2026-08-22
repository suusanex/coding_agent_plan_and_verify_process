# Codex CLI Persistent Purpose Reviewer v2 実験結果

## 判定

- 分類: **Yes**
- provider/model: codex / gpt-5.6-luna
- CLI version: 0.147.0
- sandbox: read-only
- cwd: experiments/persistent-purpose-reviewer

## 実行境界

- Persistent R1 は新規 session で実行し、プロセス終了後に同一 session hash へ codex exec resume で R2/R3 を継続した。
- Fresh R2 は新規 session で、Persistent R2 と同一の prompt/candidate bytes を送った。
- R2/R3/Fresh R2 へ R1 context、previous response、decision、mapping、finding の再送は行っていない。
- 入力 manifest、個別 bytes/SHA-256、no-replay flags は各 round に保存した。
- R2 composition equality: True、SHA-256: 0c5be9a59873938331d8a0b96e2842174837b145d676d6023489d9a53079e357。

## 意味判定出力

persistent-r1: finding_id=PPR-001; prior_finding_status=unknown; decision_contract_assertion=fail; information_sufficiency=sufficient; evidence=`lantern-pulse` の `mode` wire token は必ず `quick-check` とする契約だが、candidate は `focus-mode` を返している。 / `focus-mode` は過去の product decision で明示的に棄却されている。
persistent-r2: finding_id=PPR-001; prior_finding_status=active; decision_contract_assertion=fail; information_sufficiency=sufficient; evidence=保持 state では、`lantern-pulse` の `mode` wire token は `quick-check` 固定であり、`focus-mode` は明示的に棄却されている。 / current candidate は `integrationSource` が `lantern-pulse` であるにもかかわらず、`mode` が `focus-mode` のままである。
persistent-r3: finding_id=PPR-001; prior_finding_status=resolved; decision_contract_assertion=pass; information_sufficiency=sufficient; evidence=保持 state では、`lantern-pulse` の `mode` wire token は `quick-check` 固定である。 / current candidate は `integrationSource` が `lantern-pulse` で、`mode` が `quick-check` に修正されている。
fresh-r2: finding_id=none; prior_finding_status=unknown; decision_contract_assertion=unknown; information_sufficiency=insufficient; evidence=

- Persistent R2 の PPR-001 specific detection: True
- Persistent R3 の resolved 判定: True
- Fresh R2 の相対的に弱い判定: True

各 round の machine-metadata.json に、Codex output の実バイト SHA-256、保存時に sanitization 済みの response、semantic form、round label verification を保存した。session ID、secret、environment の raw value は保存していない。

## 非変更

- pre/post Git status を保存した。
- 実験フォルダ外の status 変化: 0 件。
- 実験フォルダ内で Codex v2 の許可 prefix 外に観測された既存・並行 status 変化: 9 件。これらは revert していない。
- production 非変更観測: PASS。
- git diff --check の結果は final-diff-check.txt に保存した。

## アーキテクチャ実現性とセキュリティ適格性

- アーキテクチャ実現性: PASS。resume の同一 session、fresh の別 session、R2 の完全 byte 一致、process exit、read-only/cwd boundary を別々に検証した。
- セキュリティ適格性: CONDITIONAL。raw session/secret/environment 値を保存せず production 非変更を観測したが、provider/network payload と sandbox 実装内部の独立監査は実施していない。

v1 は prompt 内の persistent state 使用禁止と state 継続要求が矛盾していたため、本判定根拠に使用していない。v2 fixture/prompt/design は変更していない。