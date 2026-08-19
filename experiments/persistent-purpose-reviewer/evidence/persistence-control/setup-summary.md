# Persistent Purpose Reviewer 追加実験準備 summary

## 実施内容

- `fixtures\persistence-control\` と `prompts\persistence-control\` を既存 fixture/prompt から分離して作成した。
- Round 1 context だけに、`lantern-pulse` の固定 mapping `quick-check` と `focus-mode` の旧外部 consumer wire contract による棄却理由を置いた。
- Round 1 candidate は `PPR-001` 対象の違反、Round 2 candidate は説明なしの通常設定、Round 3 candidate は固定 mapping の復元とした。
- Round 2/3 prompt は context と previous output 全文を含めず、情報不足時の `unknown` だけを共通許可した。
- 全 fixture/prompt の SHA-256 と input composition contract を `evidence\persistence-control\fixture-design.md` に保存した。

## Codex 監査結果

- authority 候補 `evidence\codex\20260818T232647Z-run-metadata.json` を読み取り専用で監査した。
- 全 round で raw と sanitized の実測 SHA-256 は一致したが、metadata の `response_sha256` とは一致しなかった。
- 保存本文の形式は、metadata の exact path 順に **R1 initial finding → R2 prior FAIL → R3 prior PASS** である。
- 既存 report の循環主張は exact path の再監査では支持されず、先行監査の出力対応付け誤りだった。
- stored-byte SHA-256 は metadata response hash と一致しないが、末尾 CRLF を除いた保存前 text hash とは一致するため、問題は hash provenance/recording である。
- 詳細: `evidence\audits\codex-final-run-traceability.md` / `.json` / `codex-final-run-traceability-correction-20260819T1755.md`

## 境界と検証

- 外部モデル・ネットワークは実行していない。
- production package/Skill/agent/script/config は変更していない。
- 既存 evidence は上書き・削除していない。
- `git diff --check`: PASS
- 新規ファイルの trailing whitespace 検査: PASS
- audit JSON parse: PASS
- `git diff` / staged diff の tracked production changes: なし
- 作成物はすべて `experiments\persistent-purpose-reviewer\` 配下である。
