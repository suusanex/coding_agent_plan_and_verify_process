# Persistence-control v2 prompts

この prompt 群は既存の `prompts\persistence-control\` と分離した v2 contract 用である。

## v1 の矛盾と v2 の修正

v1 は「前回までの理解に照らす」と「この入力だけを使い、入力にない前提を補わない」を同じ prompt に書き、persistent reviewer の内部 state を実質的に禁止していた。v2 は、persistent reviewer には保持 state を使わせ、fresh reviewer には state がないため current input だけで判断できないとき `unknown`/`insufficient` を返させる。

## 入力 contract

- R1 だけが full context を読む。
- Persistent R2/R3 は prompt と current candidate だけを外部入力として受け取り、state は同じ reviewer の継続状態として保持する。
- Fresh R2/R3 は同じ prompt/candidate bytes を受け取るが、reviewer state は持たない。
- Round 2 persistent/fresh の byte equality と composition hash は `evidence\persistence-control-v2\fixture-design.md` に保存する。
- prompt に具体的 mapping、棄却案、棄却理由、finding 本文は書かない。
