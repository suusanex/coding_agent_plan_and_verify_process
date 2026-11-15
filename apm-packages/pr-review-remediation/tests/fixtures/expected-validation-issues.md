# 検証問題を残してreview処理を完了した例

これは実行記録ではなく、REMOTE-015の期待結果fixtureです。全source採否とApply実装は完了済み、Git安全条件は成立しています。

- Final verdict: REVIEW_COMPLETE_WITH_VALIDATION_ISSUES
- Execution owner: CURRENT_PARENT
- Git outcome: COMMITTED_AND_PUSHED
- 未実装Apply: 0
- 検証成功・品質保証完了ではない。merge可能とは判断しない。

## Process Feedback Triage Fixture

- Process Feedback: Disabled（既定）
- Triage counts: local-only 0 / upstream-suspected 0 / unknown 1（統合後finding数） / 対象なし No
- Finding triage reason / evidence: validation failureの分類はCHANGE_RELATEDだが、上流プロセス原因はこのfixtureだけでは判定できないためunknown
- Detailed artifact: N/A（未選択）

| Phase / Revision | Command / Check source ID | Result | Exit code / 未実施理由 | 原因分類 / 根拠 | 影響範囲 | 未解決事項 / 証拠 |
| --- | --- | --- | --- | --- | --- | --- |
| REMEDIATION / fixture-head | dotnet format --verify-no-changes | FAIL | 2 | CHANGE_RELATED / baseではPASS、変更行に診断あり | 変更ファイルの整形 | 診断が残る。fixtureの比較結果に基づく分類 |

scope内の修正と再検証後も残った失敗を報告した例であり、validationを省略する許可ではありません。commit / pushは利用者指示・repository規約に反せず、remote identity、push repository / branch、反映後OIDを照合したという前提です。失敗commandと残件はPR本文にも記録します。
