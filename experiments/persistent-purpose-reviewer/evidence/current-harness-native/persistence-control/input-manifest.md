# current harness native child: persistence-control v1 input manifest

保存基準時刻: 2026-08-19T18:08:16.047+09:00（指定された current_datetime）
保存対象: experiments\persistent-purpose-reviewer\evidence\current-harness-native\persistence-control\

## 実行・権限境界

- task agent type: general-purpose（全 child 共通）
- model: GPT-5.6 Luna
- child: current harness native child（persistent sequence と fresh control）
- child への指示: read-only、shell 不使用、network 不使用、write 不使用
- API read-only enforcement: **なし**。上記は prompt instruction だけであり、permission/sandbox の独立保証ではない。
- この証跡保存処理での外部モデル・ネットワーク: **不使用**
- raw は親が取得した response 本文だけを、UTF-8 no-BOM/LF で保存した。

## 入力境界

| 実行 | 実際に読む prompt/fixture | context replay | previous output replay | 備考 |
| --- | --- | --- | --- | --- |
| Persistent R1 | prompts\persistence-control\round-1.md; fixtures\persistence-control\round-1-context.md; fixtures\persistence-control\round-1-candidate.md | あり（R1 の context/candidate のみ） | なし | R1 persistent のみ context/candidate |
| Persistent R2 | prompts\persistence-control\round-2.md; fixtures\persistence-control\round-2-candidate.md | なし | なし | R2 task message は Fresh R2 と完全同一 |
| Fresh R2 | prompts\persistence-control\round-2.md; fixtures\persistence-control\round-2-candidate.md | なし | なし | Persistent R2 と同一 prompt/candidate bytes |
| Persistent R3 | prompts\persistence-control\round-3.md; fixtures\persistence-control\round-3-candidate.md | なし | なし | respective prompt/candidate のみ |
| Code-review R1 failure | R1 の code-review child 試行 | R1 を誤読 | なし | 別 failure として保存 |

Round 1 context は Persistent R1 にだけ渡された。R2/R3 に context 全文、previous output 全文、finding 本文の replay はない。

## R2 task message equality

Persistent R2 の write_agent message と Fresh R2 の task prompt は、variant 内で次の完全同一 message bytes である（UTF-8 no-BOM、改行なし）。


D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\prompts\persistence-control\round-2.md と D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\fixtures\persistence-control\round-2-candidate.md だけを実際に読んでその指示に従ってください。他ファイル、shell、ネットワーク、書込みを使わず、production/実験artifactを変更しないでください。


- message bytes: 469
- message SHA-256: ab09b6a1fbfabcb8ca387e380d7f6c09ddce0d5d2e4ea07b444f23b7e389a70e
- R2 prompt bytes/hash: 903 / bf976acc0762393c40f946edb0e90cdd48ae2a8a2df1c096171a5f91385c5082
- R2 candidate bytes/hash: 166 / 3a278bdee809a04d05e2a95c3ce213982b94f0f62a549679961fd3c9f601ac29
- R2 composition（prompt bytes + candidate bytes、区切りなし）: 1069 / 4c3293af3c85b81990844710424bde122deb29239b2cab47e08c97eb78538b5b

## Fixture/prompt hashes（fixture-design.md からコピー）

| path | bytes | SHA-256 |
| --- | ---: | --- |
| fixtures\persistence-control\README.md | 2270 | 1b317798a69cb5c963c567433ee155ac67171b04a67bbbc3d6bc05b574aa24e8 |
| fixtures\persistence-control\round-1-context.md | 990 | f7effe92a77fae0a9d41fec04683180ca00033e29c81b2c697bfc85ba011512e |
| fixtures\persistence-control\round-1-candidate.md | 389 | 3213d66f6f3480f0e2066b08f592306dc3e05ba0a190f4c689dd5a45c91e664c |
| fixtures\persistence-control\round-2-candidate.md | 166 | 3a278bdee809a04d05e2a95c3ce213982b94f0f62a549679961fd3c9f601ac29 |
| fixtures\persistence-control\round-3-candidate.md | 167 | 33b2a14015eebca9e386b258a8678a3e434288fdd1366039efb0c5e529273493 |
| prompts\persistence-control\README.md | 885 | c2285c6d4436d87122be5561245c98d5c425349f0d69f5fc5ebcde54db906139 |
| prompts\persistence-control\round-1.md | 1079 | d9d9e86527da43f8c248f02453c55520baa9762491425cd06922ba6953bcb77f |
| prompts\persistence-control\round-2.md | 903 | bf976acc0762393c40f946edb0e90cdd48ae2a8a2df1c096171a5f91385c5082 |
| prompts\persistence-control\round-3.md | 925 | 1c7ddafb1158e885f78e72a2a8c9f2c002519494b45914e03f8df59448d7b426 |

## Raw 保存 hash

| raw path | bytes | SHA-256 |
| --- | ---: | --- |
| persistent\round-1.raw.md | 381 | 1156492e787cf64410cb2eae0062c2e842969672aa572f90b1c53393ff61eb22 |
| persistent\round-2.raw.md | 347 | ef39c90247c65531c25ea3e7ed714e438b2eb3de4a40c7a00aa2ffcb22d42eef |
| fresh\round-2.raw.md | 194 | 80814268f34a2ddbbe75f77c2e2b332db19c993723d46db36b08890b1235131b |
| persistent\round-3.raw.md | 194 | 80814268f34a2ddbbe75f77c2e2b332db19c993723d46db36b08890b1235131b |
| failures\code-review-round-1.raw.md | 445 | 59fca9015e508faaa399ca07096cf543c553b904131480ca2bfef80e3134d62d |

Code-review failure raw は別 failure として保存し、v1 の semantic conclusion に混ぜない。