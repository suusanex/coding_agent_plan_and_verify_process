BEGIN_PURPOSE_REVIEW
purpose_restatement: legacy 設定値を明示的に移行し、利用者が手入力や作り直しをせず安全に使い続けられるようにする。unknown legacy 値は隠さず保留または明示エラーとして扱う。
purpose_assertion: FAIL
rejected_approach:
  proposal: 旧値を黙って default v2 値へ置換する方式
  reason: データ消失と利用者の意図喪失を招くため
rejected_approach_assertion: FAIL
formal_but_goal_failure_assertion: FAIL
findings:
  - id: PUR-1
    status: active
    severity: blocker
    statement: unknown な通知モードを明示的な失敗や保留にせず、"steady" に置換して成功扱いにしている。
    evidence: `: v2Mode ? v2Mode : "steady";` および `return MigrationResult.Success(result);`
  - id: PUR-2
    status: active
    severity: high
    statement: 判定用入力の unknown legacy 値 `extension_value` を保持も記録もせず、移行対象から黙って欠落させている。
    evidence: `V2Settings` には `NotificationMode` と `QuietHours` だけを設定し、`extension_value` の処理がない。
mapping_assertion: FAIL
unknown_handling_assertion: FAIL
mvp_boundary_assertion: PASS
priority_assertion: FAIL
production_changes: NO
production_change_assertion: PASS
END_PURPOSE_REVIEW
