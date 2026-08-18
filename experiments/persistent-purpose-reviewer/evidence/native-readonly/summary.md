# native read-only reviewer 実験概要

## 結論

API で作成した同一の code-review child に対し、parent session 内で idle 後の follow-up を 2 回実行できた。Round 1、Round 2、Round 3 の応答から、`PUR-001` が Round 2 で持続し、Round 3 で解消されたことを確認した。同一 child の logical context が semantic に検証できた証跡として保存する。

## 実験条件

- agent type: `code-review`
- model: GPT-5.6 Luna
- child role label: `native-readonly-reviewer`
- child 作成: API で 1 回
- follow-up: 同じ handle に 2 回
- Round 1: `purpose-context` 全文と Round 1 candidate を入力
- Round 2/3: Goal Context 全文、previous output 全文、finding 本文を再送せず、candidate と最小 follow-up のみを入力
- handle の扱い: private session ID として保存せず、人間可読な role label として記録

## read-only の境界

`code-review` type は harness 定義上の read-only review type である。ただし、OS sandbox または permission の独立監査は未実施であり、これらの環境分離を技術的に保証する証跡ではない。read-only type の意味と、OS レベルの独立 enforcement を分けて記録する。

## Lifecycle と未実施事項

native task API で parent session 内の idle child に follow-up できることを実測した。same-child logical context は Round 1/2/3 の semantic finding 推移で検証できた。parent 終了後の recovery、session ID による復元、session ID/API durability は未実施である。

証跡保存作業では外部モデルおよびネットワークを使用していない。production、skills、scripts、config は変更していない。

## Git 検証

保存前の `git status --short` は `?? .wt/` と `?? experiments/` だった。保存対象は `experiments\persistent-purpose-reviewer\evidence\native-readonly\` のみである。保存前の `git diff --check` は出力なし、終了コード 0 だった。

最終 `git diff --check` も出力なし、終了コード 0 だった。最終 status で確認した新規ファイルは `native-readonly` 配下だけであり、他の変更は revert していない。
