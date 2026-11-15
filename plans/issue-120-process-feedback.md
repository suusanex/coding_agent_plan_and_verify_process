# Issue #120: 現行PRレビューへの上流原因分析の統合

## 目的と設計判断

[Issue #120](https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/120)の目的は、人間の直観に依存せず全findingの上流原因を一度検討し、任意の詳細分析で再発防止へ還元することである。ユーザーは旧reviewer / round構成の前提失効を示し、現行構成への実装を依頼した。

現行の親所有の評価・review-plan・collectorを再利用する。通常は全findingの軽量triage、利用者がProcess Feedbackを明示選択した場合だけ疑い・unknownの証拠を逆追跡する。詳細分析は任意artifactに分け、通常モードの探索を増やさない。共通プロセス改善は候補提示と変更権限を分離する。既存のsource coverage、採否、validation、Git安全性を維持する。

新しいレビューエージェント、旧round構造、他Skillの自動起動、独自分析runtimeは不要。既存自然言語契約の拡張であり、BCL / framework / NuGetによる実行機構は追加しない。検証は既存package validatorを拡張する。

## 受入条件

- Apply / Rejectを含む全findingにtriageと短い根拠があり、duplicateのsource IDとnoActionの理由が失われない。
- Process Feedbackは利用者の明示選択だけで有効化し、通常モード・対象なしでは詳細artifactを生成しない。
- Goal Context / Planのある場合は証拠を逆追跡し、不在の場合は既存証拠と不明を記録する。
- 今回のPR修正・今回の上流artifact修正・再利用プロセス改善候補を区別し、一般化根拠のない共通変更やscope拡大をしない。
- 分析の証拠不足と、今回のacceptanceの未決定を区別する。既存の完了・Git・未取得source保護を維持する。
- 配布されるSkill/templateと利用文書を揃え、静的contract / fixture検証とReady PRのremote reviewを行う。静的検証を実modelの原因分析精度の保証と扱わない。

## Purpose Review

- Input: [issue-120-purpose-review-input.json](issue-120-purpose-review-input.json)
- Runner: 0.6.0 / protocol 4（ユーザーが指定した導入済みSkillの互換条件）
- Run: `4e608694-644d-41cc-af10-4dc07968a961`
- 結果: `COMPLETE`、findingなし。round 1 / reviewRounds 1 / durableSubmissions 1。
- 設計責任者の応答: findingなしのため修正応答なし。提案の実装を進める。
- 未確認: 実装適合、実model挙動、運用上の再発防止効果はこのreviewでは検証されない。COMPLETEはユーザー承認や実装完了を意味しない。

自然言語契約と統合レビューは親、テスト変更と実行はユーザー指定のGPT-6 Lunaが担当する。

## 検証記録

- package validator（collector publish / help、静的契約、scenarioと負例）: PASS。
- README navigation、Agent Plugin qualification recordの検証: PASS。
- ローカルAPM 0.33.0でのAgent Plugin package検証: FAIL。既存builderのlocal bundle installがCLIに拒否された。原因はENVIRONMENT（CI指定は0.26.0）であり、変更したSkillの分析結果ではない。
- CIと同じAPM 0.26.0を一時venvへ導入し、`validate-agent-plugin-package.ps1 -Package pr-review-remediation -ApmExecutable <一時venvのapm.exe>`で再検証: PASS。global環境は変更していない。0.33.0との互換性はこの変更では修正していない。
- 静的fixtureは期待する記録の整合を検査する。実modelによる分析精度、共通改善の有効性、配布後runtimeは未評価。

## PR Review Remediation

[PR #177](https://github.com/suusanex/coding_agent_plan_and_verify_process/pull/177)のhead `220bae1`に対するCopilot reviewをcollectorで取得し、親がremote patchと契約を照合した。2件ともApply、Rejectなし。

- `inline-comment:4580578802`: candidateLayerの記録漏れをfixture validatorが見逃す。定義済み値の検査と欠落・空・不正値の負例を追加。
- `inline-comment:4580578835`: fixture validatorが任意のPlan / Goal Contextを必須化していた。finding traceと各行の形式を検査し、Plan / Goal Contextなしで分析する肯定例を追加。

両件とも既存契約へ検証コードを合わせる局所修正で、設計・共通SKILL欠陥の根拠はない。詳細Process Feedbackは今回のレビューでは未選択。修正をGPT-6 Lunaへ委譲し、親が統合確認した。修正後のpackage validator（collector publish / help、fixture負例含む）とdiff checkはPASS。初回headのCIは全14 check成功。採否・source coverage・Git結果の詳細は作業ローカルの`.review/pr-177/review-plan.md`に保持する。
