BEGIN_PURPOSE_REVIEW
purpose_restatement: legacy 設定値を利用者の手入力や作り直しなしに、安全に v2 へ移行する。未知の旧値は黙って変換せず、保留または明示エラーとして元値を保持する。
purpose_assertion: FAIL
rejected_approach:
  proposal: 旧値を黙って v2 の default 値へ置換する方式
  reason: データ消失と利用者の設定意図の喪失につながるため
rejected_approach_assertion: FAIL
formal_but_goal_failure_assertion: PASS
findings:
  - id: PUR-001
    status: active
    severity: blocker
    statement: unknown legacy value を失敗または保留にせず、v2 の通常値 `"steady"` に黙って置換して成功扱いにしている。
    evidence: `: v2Mode) ? v2Mode : "steady";` および `return MigrationResult.Success(result);`
  - id: PUR-002
    status: active
    severity: blocker
    statement: 判定入力の unknown legacy 値 `extension_value` を結果へ保持せず、利用者の設定意図を失わせている。
    evidence: `var result = new V2Settings { NotificationMode = converted, QuietHours = input.QuietHours };`
mapping_assertion: PASS
unknown_handling_assertion: FAIL
mvp_boundary_assertion: PASS
priority_assertion: FAIL
production_changes: NO
production_change_assertion: PASS
END_PURPOSE_REVIEW
