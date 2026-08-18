BEGIN_PURPOSE_REVIEW
purpose_restatement: legacy設定値を明示的に安全移行し、利用者が手入力や作り直しをせず使い続けられるようにする。
purpose_assertion: FAIL
rejected_approach:
  proposal: unknown legacy値をv2のdefault値に黙って置換する。
  reason: データと利用者の設定意図を失わせ、変換失敗を隠すため。
rejected_approach_assertion: FAIL
formal_but_goal_failure_assertion: PASS
findings:
  - id: PUR-001
    status: active
    severity: blocker
    statement: candidateはunknown値を「steady」に置換して成功扱いにするため、利用者の意図を保持せず、移行目的を未達にする。
    evidence: mappingにない値をTryGetValue失敗時に「steady」へ丸め、ValidateV2Schema成功後にMigrationResult.Successを返している。
mapping_assertion: PASS
unknown_handling_assertion: FAIL
mvp_boundary_assertion: PASS
priority_assertion: FAIL
production_changes: NO
production_change_assertion: PASS
END_PURPOSE_REVIEW
