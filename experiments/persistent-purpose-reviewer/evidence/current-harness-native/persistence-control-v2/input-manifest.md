# current harness native child: persistence-control v2 input manifest

保存基準時刻: 2026-08-19T18:08:16.047+09:00（指定された current_datetime）
保存対象: experiments\persistent-purpose-reviewer\evidence\current-harness-native\persistence-control-v2\

## 実行・権限境界

- task agent type: general-purpose（全 child 共通）
- model: GPT-5.6 Luna
- child: current harness native child（persistent sequence と fresh control）
- child への指示: read-only、shell 不使用、network 不使用、write 不使用
- API read-only enforcement: **なし**。prompt instruction だけであり、permission/sandbox の独立保証ではない。
- この証跡保存処理での外部モデル・ネットワーク: **不使用**
- v1 の prompt 矛盾は v2 fixture に分離して修正済み。v1 source bytes は変更していない。

## 入力境界

| 実行 | 実際に読む prompt/fixture | context replay | previous output replay | 備考 |
| --- | --- | --- | --- | --- |
| Persistent R1 | prompts\persistence-control-v2\round-1.md; fixtures\persistence-control-v2\round-1-context.md; fixtures\persistence-control-v2\round-1-candidate.md | あり（R1 の context/candidate のみ） | なし | decision source は R1 context のみ |
| Persistent R2 | prompts\persistence-control-v2\round-2.md; fixtures\persistence-control-v2\round-2-candidate.md | なし | なし | R2 task message は Fresh R2 と完全同一 |
| Fresh R2 | prompts\persistence-control-v2\round-2.md; fixtures\persistence-control-v2\round-2-candidate.md | なし | なし | Persistent R2 と同一 prompt/candidate bytes |
| Persistent R3 | prompts\persistence-control-v2\round-3.md; fixtures\persistence-control-v2\round-3-candidate.md | なし | なし | previous state のみ継続 |
| Fresh R3 | 実行/raw supplied なし | n/a | n/a | この保存対象には含めない |

Round 1 context は Persistent R1 にだけ渡された。R2/R3/Fresh R2 に context 全文、previous output 全文、decision mapping、finding 本文の replay はない。

## R2 task message and payload equality

Persistent R2 の write_agent message と Fresh R2 の task prompt は、variant 内で次の完全同一 message bytes である（UTF-8 no-BOM、改行なし）。


D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\prompts\persistence-control-v2\round-2.md と D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\fixtures\persistence-control-v2\round-2-candidate.md だけを実際に読んでその指示に従ってください。他ファイル、shell、ネットワーク、書込みを使わず、production/実験artifactを変更しないでください。


- message bytes: 475
- message SHA-256: 5ef11bf41f3f2d069039e6fb3b50456bd8db2b3195f3f77528f9c45896e09387
- R2 prompt bytes/hash: 1605 / 6760d25b1a22bbe2cbefe00e2a1ae3546ff0c34a01590af599344d0ad17917e6
- R2 candidate bytes/hash: 166 / 3a278bdee809a04d05e2a95c3ce213982b94f0f62a549679961fd3c9f601ac29
- Persistent R2 composition: 1771 / 0c5be9a59873938331d8a0b96e2842174837b145d676d6023489d9a53079e357
- Fresh R2 composition: 1771 / 0c5be9a59873938331d8a0b96e2842174837b145d676d6023489d9a53079e357
- 判定: **byte-equal**。composition は prompt bytes + candidate bytes を区切りなしで連結。

## Fixture/prompt hashes（fixture-design.md からコピー）

| path | bytes | SHA-256 |
| --- | ---: | --- |
| fixtures\persistence-control-v2\README.md | 4043 | 537238acb75e6b8edd74ee9e5203a5f5679d848bbd1c46f3b4347fcd1b98221c |
| fixtures\persistence-control-v2\round-1-context.md | 990 | f7effe92a77fae0a9d41fec04683180ca00033e29c81b2c697bfc85ba011512e |
| fixtures\persistence-control-v2\round-1-candidate.md | 389 | 3213d66f6f3480f0e2066b08f592306dc3e05ba0a190f4c689dd5a45c91e664c |
| fixtures\persistence-control-v2\round-2-candidate.md | 166 | 3a278bdee809a04d05e2a95c3ce213982b94f0f62a549679961fd3c9f601ac29 |
| fixtures\persistence-control-v2\round-3-candidate.md | 167 | 33b2a14015eebca9e386b258a8678a3e434288fdd1366039efb0c5e529273493 |
| prompts\persistence-control-v2\README.md | 1167 | 9f67c050c81902d6aa5db9bb23b96d00af7d5cf055b81e7523c2876740f01bb2 |
| prompts\persistence-control-v2\round-1.md | 1113 | 3fea063ac1df232d9af69891f0baae4bfcebe75509acaa768a35317efbdfb8e7 |
| prompts\persistence-control-v2\round-2.md | 1605 | 6760d25b1a22bbe2cbefe00e2a1ae3546ff0c34a01590af599344d0ad17917e6 |
| prompts\persistence-control-v2\round-3.md | 1650 | 7c8a93aa62aeab1e856e0d3a9dd4bcd3c800eca45e109c6043e5d833fdbfafd7 |

## Raw 保存 hash

| raw path | bytes | SHA-256 |
| --- | ---: | --- |
| persistent\round-1.raw.md | 449 | 5f06e832d258c610c5c32d425af993169836fe63c551e0feb06283374bd1a518 |
| persistent\round-2.raw.md | 392 | d7bf8c8524fcd3c920ad107a8f3a97487506883759152b3d753be884c57caa62 |
| fresh\round-2.raw.md | 218 | f5566410498360bd6ab3e881275b43d7ee53af3a4ac8263fbf34b438c788cda9 |
| persistent\round-3.raw.md | 418 | e6fc1991d5cf5926f7e03a5515cfa6cd68582aefac2d9cd001ad254888061cdc |

## Semantic result

- Round 2 discrimination: **PASS**（persistent R2 は active/fail、fresh R2 は unknown/insufficient）。
- Round 3 decision contract: **PASS**（decision_contract_assertion=pass, finding_id=none）。
- Round 3 schema-status qualification: prior_finding_status=active のままであり、finding none/contract pass と status assertion に不整合がある。したがって「修正判定」は pass だが、「prior finding が resolved/closed になった」という schema-status assertion は pass としない。