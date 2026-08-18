BEGIN_PURPOSE_REVIEW
purpose_restatement: 利用者の手入力や設定の作り直しなしに、明示的な v1→v2 mapping で安全に移行し、未知値は保持して保留または明示エラーにする。
rejected_approach:
  proposal: unknown legacy 値を v2 の default 値へ黙って置換して成功扱いにする。
  reason: データ消失と利用者の意図喪失を招き、schema validation を通っても移行目的を満たさないため。
findings:
  - id: PUR-001
    status: active
    statement: unknown の `input.NotificationMode` を `"steady"` に置換して成功扱いにしており、未知値を可視化・保持・保留していない。
    evidence: `TryGetValue` が失敗した場合の fallback が `"steady"` で、`ValidateV2Schema` 後に常に `MigrationResult.Success` を返している。
unknown_handling_assertion: FAIL
production_changes: NO
production_change_assertion: PASS
END_PURPOSE_REVIEW
