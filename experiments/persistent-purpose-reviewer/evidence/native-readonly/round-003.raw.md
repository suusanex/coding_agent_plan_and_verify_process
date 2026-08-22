BEGIN_PURPOSE_REVIEW
prior_finding_resolution: PASS
reopened_or_persistent_finding:
  id: PUR-001
  status: resolved
  statement: unknown legacy 値を default に置換せず、元値を保持した Pending として明示的に扱っている。
  evidence: unknown 分岐が `MigrationResult.Pending` を返し、`originalV1Value`、明示的な code、利用者向け message を設定している。
unknown_handling_assertion: PASS
production_changes: NO
production_change_assertion: PASS
END_PURPOSE_REVIEW
