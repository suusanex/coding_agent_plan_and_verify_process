# Persistence-control v2 fixture design evidence

作成日: 2026-08-19
対象 root: `experiments\persistent-purpose-reviewer`

## v1 の保存と invalid/inconclusive 条件

既存 v1 (`fixtures\persistence-control\`、`prompts\persistence-control\`) は変更しない。v1 Round 2/3 prompt の「前回までの理解に照らす」と「この入力だけを使い、入力にない具体的な前提を補わない」は、persistent state の使用と current-input-only 制約を同時に要求する矛盾である。

v1 試行は、persistent reviewer の state を使えなかった場合、fresh reviewer と persistent reviewer を同じ条件で採点した場合、fresh reviewer の `unknown`/`insufficient` を不合格扱いした場合、または Round 2/3 に full context/previous output を再送した場合に invalid/inconclusive とする。Round 2 persistent/fresh の prompt+candidate byte equality を証明していない試行も invalid/inconclusive とする。

これは結果に合わせた修正ではなく、user 要求の persistent purpose contract を prompt に正しく実装するための設計不備の分離訂正である。

### v1 preservation baseline

v1 の次の bytes/hash を作成前に記録し、v2 作成後も同一であることを確認した。

| path | bytes | SHA-256 |
| --- | ---: | --- |
| `fixtures\persistence-control\README.md` | 2270 | `1b317798a69cb5c963c567433ee155ac67171b04a67bbbc3d6bc05b574aa24e8` |
| `fixtures\persistence-control\round-1-context.md` | 990 | `f7effe92a77fae0a9d41fec04683180ca00033e29c81b2c697bfc85ba011512e` |
| `fixtures\persistence-control\round-1-candidate.md` | 389 | `3213d66f6f3480f0e2066b08f592306dc3e05ba0a190f4c689dd5a45c91e664c` |
| `fixtures\persistence-control\round-2-candidate.md` | 166 | `3a278bdee809a04d05e2a95c3ce213982b94f0f62a549679961fd3c9f601ac29` |
| `fixtures\persistence-control\round-3-candidate.md` | 167 | `33b2a14015eebca9e386b258a8678a3e434288fdd1366039efb0c5e529273493` |
| `prompts\persistence-control\README.md` | 885 | `c2285c6d4436d87122be5561245c98d5c425349f0d69f5fc5ebcde54db906139` |
| `prompts\persistence-control\round-1.md` | 1079 | `d9d9e86527da43f8c248f02453c55520baa9762491425cd06922ba6953bcb77f` |
| `prompts\persistence-control\round-2.md` | 903 | `bf976acc0762393c40f946edb0e90cdd48ae2a8a2df1c096171a5f91385c5082` |
| `prompts\persistence-control\round-3.md` | 925 | `1c7ddafb1158e885f78e72a2a8c9f2c002519494b45914e03f8df59448d7b426` |
| `evidence\persistence-control\fixture-design.md` | 3250 | `e897f88743840664535c20a5a4cd50f714bff5a8215c4060c43bc28aeae4dbc2` |

## v2 decision source と state contract

- `fixtures\persistence-control-v2\round-1-context.md` だけが decision source である。
- `lantern-pulse` の固定 token は `quick-check`、`focus-mode` は旧 consumer wire token のため棄却済みである。
- R1 candidate は `PPR-001` を発生させる。
- R2 candidate は説明なしに同じ契約違反を保つ。
- R3 candidate は固定 token を復元する。
- Persistent R2 は R1 state と own finding を使い `PPR-001` active、Persistent R3 は R1 decision/R2 finding を使い resolved と判定する。
- Fresh R2/R3 は state を持たず、current input だけで contract を確認できない場合に `unknown`/`insufficient` とする。

## 外部送信 input boundary

| 実行 | 外部へ渡す files | 継続 state |
| --- | --- | --- |
| Persistent R1 | `prompts\persistence-control-v2\round-1.md` + `fixtures\persistence-control-v2\round-1-context.md` + `fixtures\persistence-control-v2\round-1-candidate.md` | なし |
| Persistent R2 | `prompts\persistence-control-v2\round-2.md` + `fixtures\persistence-control-v2\round-2-candidate.md` | R1 purpose/decision/own finding |
| Persistent R3 | `prompts\persistence-control-v2\round-3.md` + `fixtures\persistence-control-v2\round-3-candidate.md` | R1 decision/R2 finding |
| Fresh R2 | `prompts\persistence-control-v2\round-2.md` + `fixtures\persistence-control-v2\round-2-candidate.md` | なし |
| Fresh R3 | `prompts\persistence-control-v2\round-3.md` + `fixtures\persistence-control-v2\round-3-candidate.md` | なし |

R2/R3 persistent の state は、Round 1 context や previous output 全文を外部入力へ再送することとは別の継続状態である。fresh にはその state を渡さない。外部モデル・ネットワークはこの準備作業では実行しない。

## Round 2 byte equality contract

Persistent R2 と Fresh R2 は、同じ exact path の prompt/candidate bytes を使う。composition は「prompt file の全 bytes に続けて candidate file の全 bytes」を区切りなしで連結し、SHA-256 を計算する。path、bytes、個別 SHA-256、composition SHA-256 が一致しなければ比較を invalid とする。

| item | exact path | bytes | SHA-256 |
| --- | --- | ---: | --- |
| R2 prompt | `prompts\persistence-control-v2\round-2.md` | 1605 | `6760d25b1a22bbe2cbefe00e2a1ae3546ff0c34a01590af599344d0ad17917e6` |
| R2 candidate | `fixtures\persistence-control-v2\round-2-candidate.md` | 166 | `3a278bdee809a04d05e2a95c3ce213982b94f0f62a549679961fd3c9f601ac29` |
| R2 persistent composition | 上記 prompt bytes + candidate bytes | 1771 | `0c5be9a59873938331d8a0b96e2842174837b145d676d6023489d9a53079e357` |
| R2 fresh composition | 上記と同一 bytes | 1771 | `0c5be9a59873938331d8a0b96e2842174837b145d676d6023489d9a53079e357` |

## v2 file hashes

SHA-256 は作成後の file bytes に対して PowerShell `Get-FileHash -Algorithm SHA256` で計算した。fixture-design 自身の hash は自己参照を避けるため表に含めない。

| path | bytes | SHA-256 |
| --- | ---: | --- |
| `fixtures\persistence-control-v2\README.md` | 4043 | `537238acb75e6b8edd74ee9e5203a5f5679d848bbd1c46f3b4347fcd1b98221c` |
| `fixtures\persistence-control-v2\round-1-context.md` | 990 | `f7effe92a77fae0a9d41fec04683180ca00033e29c81b2c697bfc85ba011512e` |
| `fixtures\persistence-control-v2\round-1-candidate.md` | 389 | `3213d66f6f3480f0e2066b08f592306dc3e05ba0a190f4c689dd5a45c91e664c` |
| `fixtures\persistence-control-v2\round-2-candidate.md` | 166 | `3a278bdee809a04d05e2a95c3ce213982b94f0f62a549679961fd3c9f601ac29` |
| `fixtures\persistence-control-v2\round-3-candidate.md` | 167 | `33b2a14015eebca9e386b258a8678a3e434288fdd1366039efb0c5e529273493` |
| `prompts\persistence-control-v2\README.md` | 1167 | `9f67c050c81902d6aa5db9bb23b96d00af7d5cf055b81e7523c2876740f01bb2` |
| `prompts\persistence-control-v2\round-1.md` | 1113 | `3fea063ac1df232d9af69891f0baae4bfcebe75509acaa768a35317efbdfb8e7` |
| `prompts\persistence-control-v2\round-2.md` | 1605 | `6760d25b1a22bbe2cbefe00e2a1ae3546ff0c34a01590af599344d0ad17917e6` |
| `prompts\persistence-control-v2\round-3.md` | 1650 | `7c8a93aa62aeab1e856e0d3a9dd4bcd3c800eca45e109c6043e5d833fdbfafd7` |
