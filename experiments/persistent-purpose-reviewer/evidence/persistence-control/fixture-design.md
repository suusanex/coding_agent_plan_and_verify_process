# Persistence-control fixture design evidence

作成日: 2026-08-19
対象 root: `experiments\persistent-purpose-reviewer`

## Decision source

Round 1 の `fixtures\persistence-control\round-1-context.md` だけが product decision source である。そこにだけ、`lantern-pulse` の mode wire token を `quick-check` に固定する契約と、自然に見える `focus-mode` を旧外部 consumer wire contract のため棄却した理由を記載した。

## Input composition contract

| 実行形態 | prompt | candidate/context | full context | previous output |
| --- | --- | --- | --- | --- |
| Persistent R1 | `prompts\persistence-control\round-1.md` | `fixtures\persistence-control\round-1-context.md` + `fixtures\persistence-control\round-1-candidate.md` | yes | no |
| Persistent R2 | `prompts\persistence-control\round-2.md` | `fixtures\persistence-control\round-2-candidate.md` | no | no |
| Persistent R3 | `prompts\persistence-control\round-3.md` | `fixtures\persistence-control\round-3-candidate.md` | no | no |
| Fresh R2 | `prompts\persistence-control\round-2.md` | `fixtures\persistence-control\round-2-candidate.md` | no | no |

Fresh R2 は Persistent R2 と prompt/candidate を一字一句同じにする。Round 2/3 の prompt に Round 1 context、具体的な mapping、棄却理由、previous finding 本文、semantic secret は含めない。情報不足時の `unknown` のみ共通に許可する。

## File hashes

SHA-256 は作成後のファイル bytes に対して PowerShell `Get-FileHash -Algorithm SHA256` で計算した。

| path | bytes | sha256 |
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

## Quality self-review

- Round 2 candidate/prompt だけから `quick-check` を導くことはできず、`focus-mode` の棄却理由も直接導けない。
- decision source は Round 1 context のみである。
- candidate はすべて正常なコードまたは設定として読め、説明ラベルで判定を誘導していない。
- fixture は架空データだけで構成され、外部モデル・ネットワークは実行していない。
