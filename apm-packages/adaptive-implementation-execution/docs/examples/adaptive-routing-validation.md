# Adaptive routing検証

schema v5のrouting-scenarios.jsonは、親構造→提示/turn終了→post-presentation実応答→readiness→子→完了/再引受けの状態遷移を検査する。既存比較evidenceとacceptance / Work Package双方向mappingを再利用する。

正例: 承認後子完了、提示停止、承認なしresume、既存再利用、構造再レビュー、Design Pair Locked Decision保持。

負例: 無応答、同turn応答、AI応答、旧版承認、code drift、親直接完了、別上位起動、build失敗、親詳細実装、turn継続、readiness不成立、mapping不足、旧schema、応答quote欠落、Locked Decision drift、再引受け旧承認、未解消trigger。

これは合成fixtureをvalidatorに通した証拠であり、modelが実際に停止する保証ではない。runtime確認はcopilot-manual-smoke.mdに従い別途記録する。子の内部test設計等はDeferred to childとし、旧全decision Resolved条件を検証しない。
