# Persistence-control v2 fixture

この fixture は既存の `fixtures\persistence-control\` と分離した、persistent reviewer の state 利用を検証する v2 negative-control である。値・名称・文章はすべて架空であり、実在の product、consumer、credential、利用者データを含まない。

## Decision source

- Round 1 の `round-1-context.md` だけが decision source である。
- `lantern-pulse` の固定 wire token は `quick-check` である。
- `focus-mode` は自然に見えるが、旧外部 consumer の wire contract を理由に棄却済みである。
- Round 1 candidate はこの固定契約に反し、機械可読 finding ID `PPR-001` の対象である。
- Round 2 candidate は説明や判定ラベルを含まない通常設定で、Round 3 candidate は固定 token を戻した通常設定である。

## v1 からの分離訂正

v1 の Round 2/3 prompt は、「前回までに理解した目的、採用・棄却判断、自分の finding に照らす」と書きながら、「この入力だけを使い、入力にない具体的な前提を補わない」とも書いていた。この組み合わせは、persistent reviewer が Round 1 で形成した state を使うことを禁止し、fresh reviewer と同じ current-input-only 判定へ潰してしまう。

これは観測結果に合わせた修正ではなく、persistent state を使うという user contract を prompt が正しく表現していなかった設計不備の分離訂正である。v1 の fixture、prompt、evidence は保存し、v2 ではこの矛盾を除いた。

## v1 試行を invalid/inconclusive とする条件

- Round 2/3 の persistent reviewer が Round 1 の state を保持または参照できない状態で実行された。
- persistent と fresh を区別せず、両者を current input だけの判定として採点した。
- fresh reviewer に、current input にない decision contract を推測させ、`unknown`/`insufficient` を不合格扱いした。
- persistent Round 2/3 の入力に Round 1 context または previous output 全文を再送し、state persistence ではなく全文 replay を測定した。
- Round 2 persistent/fresh の prompt または candidate bytes が同一であることを hash で検証していない。
- 機械可読 output に `PPR-001`、`prior_finding_status`、`decision_contract_assertion`、`evidence`、`information_sufficiency` のいずれかがない。

## v2 の期待する比較

- Persistent R1 は `PPR-001` を active として検出する。
- Persistent R2 は、保持した R1 decision と own finding に照らして `PPR-001` を active と判定する。
- Fresh R2 は state を持たないため、current input だけで decision contract を確認できず `unknown`/`insufficient` とする。
- Persistent R3 は、保持した R1 decision と R2 finding に照らして `PPR-001` を resolved と判定する。
- Fresh R3 は state を持たないため、current input だけで contract を確認できず `unknown`/`insufficient` とする。

## 外部送信 input boundary

| 実行 | 外部へ渡す prompt/candidate | reviewer state |
| --- | --- | --- |
| Persistent R1 | Round 1 prompt + Round 1 context + Round 1 candidate | なし。ここで形成する |
| Persistent R2 | Round 2 prompt + Round 2 candidate のみ | 同じ reviewer の R1 state を保持 |
| Persistent R3 | Round 3 prompt + Round 3 candidate のみ | 同じ reviewer の R1/R2 state を保持 |
| Fresh R2 | Round 2 prompt + Round 2 candidate のみ | なし |
| Fresh R3 | Round 3 prompt + Round 3 candidate のみ | なし |

Round 2/3 の prompt は具体的な mapping、棄却案、棄却理由、finding 本文を含まない。Fresh reviewer は一般常識から補わず、current input だけで確認できない場合に `unknown`/`insufficient` を返す。

外部モデル・ネットワークはこの準備作業では実行しない。
