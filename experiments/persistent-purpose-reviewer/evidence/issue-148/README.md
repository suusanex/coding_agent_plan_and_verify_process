# Issue #148 実測evidence

各directoryはrun IDで識別する。`measurement.json`はjobの時刻・設定・Lead sessionとprovider公開tokenの抜粋、`result.json`はRunnerの実出力。投入したpurposeと初期コードは[fixture](../../fixtures/lead-investigator/)を参照する。実行対象はfixtureをコピーした一時repositoryであり、本番のuser-level configは変更していない。

| run ID先頭 | 条件・結果 | 秒 | Lead total tokens | cached input |
| --- | --- | ---: | ---: | ---: |
| `2b1a6a88` | Lead-only。2欠陥を1 findingに統合して検出 | 34.33 | 67,889 | 56,448 |
| `3658e7a7` | Grokの進捗混在で不受理。Lead-onlyへ退避し2欠陥検出 | 160.23 | 59,923 | 51,072 |
| `7d0fe98f` | 試験設定の実行ファイル名誤り。退避し2欠陥検出 | 36.68 | 60,184 | 51,072 |
| `665f7cb0` | FakeProvider固有markerでexit 9。退避し2欠陥検出 | 37.32 | 60,164 | 51,200 |
| `d7ff2c46` | 候補ゼロreport。ただしFakeProviderの文字化けあり、正式な比較から除外 | 42.66 | 82,493 | 72,192 |
| `3eea5078` | Grokの進捗とbegin境界が改行なしで連結。不受理・退避し2欠陥検出 | 132.80 | 60,196 | 43,648 |
| `e1c661fe` | UTF-8の候補ゼロreportを受理。実Leadが未確認範囲を補い2欠陥検出 | 38.72 | 60,477 | 52,992 |
| `f57c2662` | Codex Lead + Grok Investigatorの正常handoff。2欠陥を原典照合して検出 | 150.38 | 63,546 | 50,816 |

各runのReview Lead provider invocationは1回。これはprovider内部のLLM model call数と異なる。Grokの最初の2試行の消費はそれぞれ95,126 / 97,709 total tokensで、`investigator-usage.json`に保存した。正常handoffのGrok消費は72,642 total tokens、Leadとの合計は136,188だった。退避した試行を正常分業の省資源性の証拠にはしない。

正常分業ではLead total tokensが基準より約6%少ない一方、cached inputも減り、総消費とwall-clockは増えた。利用枠消費の削減を実証したとは扱わず、この小規模対象ではLead-onlyを維持する。レビュー範囲が広い実案件への効果は未測定。

`2b1a6a88/round-2`と`f57c2662/round-2`には修正後の再review結果を保存した。両runとも同じLead sessionでCOMPLETE。Lead-onlyは24.75秒・58,216 tokens、分業は279.03秒・Lead 60,776 + Investigator 82,426 = 143,202 tokensだった。Round 2のLead tokenはsession累積値から保存済みRound 1累積値を引いて算出した。検証対象の変更はCanOrderの条件を`requested > 0 && !isSuspended && stock >= requested`へ置き換えた1行だけで、repository内の初期fixtureは再現用に保持している。

実測日はLead-onlyが2026-10-27、その他が2026-10-28（JST）。単一の小規模fixtureなので、tokenや所要時間の差をサービス利用枠削減や実案件全般の改善へ一般化しない。比較の前提と未検証事項は[検証記録](../../../../docs/issue-148-validation.md)を参照する。
