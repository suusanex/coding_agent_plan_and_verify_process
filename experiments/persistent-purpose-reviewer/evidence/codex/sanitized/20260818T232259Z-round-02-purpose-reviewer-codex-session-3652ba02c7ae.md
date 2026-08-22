BEGIN_PURPOSE_REVIEW
prior_finding_resolution: FAIL
reopened_or_persistent_finding:
  id: PUR-1
  status: active
  statement: unknown legacy 値を保留または明示エラーにせず、元値を失った default v2 値へ丸めて成功扱いにする finding が残っている。
  evidence: `var safeFallback = V2Settings.CreateDefault();` および `return MigrationResult.Success(safeFallback);`
unknown_handling_assertion: FAIL
data_preservation_assertion: FAIL
visible_failure_assertion: FAIL
mapping_assertion: FAIL
mvp_boundary_assertion: PASS
priority_assertion: FAIL
production_changes: NO
production_change_assertion: PASS
END_PURPOSE_REVIEW
