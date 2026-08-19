# Persistence-control fixture

この fixture は既存の `fixtures\` と分離した、semantic persistence の negative-control 実験用データである。値・名称・文章はすべて架空であり、実在の product、consumer、credential、利用者データを含まない。

## 判定設計

- Round 1 の `round-1-context.md` だけが decision source である。
- context には、一般常識・品質・安全性からは推測しにくい product decision を置いた。
- `lantern-pulse` の固定 wire token は `quick-check` である。
- `focus-mode` は自然に見えるが、旧外部 consumer の wire contract を理由に棄却済みである。
- Round 1 candidate は固定契約に反するため、finding ID `PPR-001` の対象である。
- Round 2 candidate は一見妥当な通常設定に見える形を保ち、説明用のラベルや判定のヒントを含めない。
- Round 3 candidate は固定 token を戻すが、説明ラベルは含めない。

## 品質セルフレビュー

- Round 2 candidate と Round 2 prompt だけからは、`quick-check` が正しい値であることも、`focus-mode` の棄却理由も直接導けない。
- decision source は Round 1 context だけであり、Round 2/3 candidate や prompt に再掲していない。
- 3つの candidate はいずれも、通常のコードまたは設定として自然に読める形式である。
- Fresh reviewer の Round 2 は、persistent reviewer の Round 2 と一字一句同じ prompt/candidate composition で実行できる。
- 情報不足時の `unknown` は許可するが、fresh reviewer に正解を推測させる文言は入れていない。

## 送信境界

この fixture を外部送信する構成では、次の入力だけを使う。

| 実行 | 入力 |
| --- | --- |
| Persistent R1 | Round 1 prompt + Round 1 context + Round 1 candidate |
| Persistent R2 | Round 2 prompt + Round 2 candidate |
| Persistent R3 | Round 3 prompt + Round 3 candidate |
| Fresh R2 | Round 2 prompt + Round 2 candidate（Persistent R2 と完全同一） |

外部モデル、ネットワーク、production package/Skill/agent/script/config はこの準備作業で実行・変更しない。
