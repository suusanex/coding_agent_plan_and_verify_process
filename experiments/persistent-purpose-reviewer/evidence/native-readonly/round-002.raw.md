BEGIN_PURPOSE_REVIEW
prior_finding_resolution: FAIL
reopened_or_persistent_finding:
  id: PUR-001
  status: active
  statement: unknown legacy 値を `CreateDefault()` の default 値へ置換し、warning のみで成功扱いにしているため、前回の問題が解消されず再発している。
  evidence: unknown 分岐で元値を保持せず `V2Settings.CreateDefault()` を使用し、保留状態や明示 error なしに `MigrationResult.Success` を返している。
unknown_handling_assertion: FAIL
production_changes: NO
production_change_assertion: PASS
END_PURPOSE_REVIEW
