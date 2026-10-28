# Purpose Review Runner 目的・設計整合の実モデル評価シナリオ

このqualificationはRunner 0.5.0 / protocol v4、Skill 0.6.0の組合せを対象とする。限定的なCopilot/Codex実モデル結果は`purpose-review-results/2026-10-28-purpose-design-evaluation.md`と`purpose-review-results/2026-10-28-provider-safety.md`に記録済みだが、assessmentはAPM `NOT_RUN / NONE`、Agent Plugin direct `HOLD / PARTIAL`を維持する。CIの決定的な契約テストは実モデルの意味的な検出力、費用、利用負荷を証明しない。過去の実装reviewやsession継続結果を今回のPASSに転用しない。

## 実施方法

機密情報を含まない使い捨てrepositoryでfixtureを実施する。評価対象の目的、承認済みbaseline、提案と差分、証拠本文だけをReviewInputへ埋め込む。評価表、期待判定、問題を示唆するfixture名はreviewerへ渡さない。外部sourceアクセスを切ってもinputだけで評価できることを確認する。各caseは独立した`taskKey`で開始する。同一changeの応答評価だけは、同じ`taskKey` / `changeId`と前回run IDでcontinuationし、総提出数を3以下に保つ。

```powershell
purpose-review-runner start --repository <fixture-root> --input <input.json>
purpose-review-runner status --run <run-id>
purpose-review-runner continue --run <run-id> --input <updated-input.json>
```

結果が不明な場合は再submitせずstatusを読む。terminal後に結果を得るため同じchangeを再起動しない。`ERROR`/`BLOCKED`の後に新しいlinked runで続ける場合はrun IDと消費済みsubmission budgetを記録する。目的の変更判断が必要なcaseは、ユーザー判断なしに入力へdecisionを作らない。

## 評価ケース

| ケース | Fixture | 期待する評価 |
| --- | --- | --- |
| 目的からのscope逸脱 | 目的は通知から対象taskへの復帰。提案は通知だけでなく汎用dashboardを導入し、対象外事項も加える | 機能の充実だけで適合とせず、追加scopeと元目的の未達を特定する。実装修正案を作らない |
| 過剰指摘の抑制 | 小さな補助変換を既存APIに追加し、目的を直接満たす。承認済み設計がなければ`approvedDesign: null` | 承認baselineがないことを違反扱いせず、簡潔な設計を不要な過剰実装としない |
| 削除・緩和を含む差分 | 提案は重複機構を削除し、保証範囲を既存authority内へ狭める。deltaに削除と緩和を記載 | 追加だけに偏らず、不要な機構の削除とauthority内の制約緩和を目的に照らす |
| authority/sourceの忠実性 | purposeに元のユーザー目的の引用、source、決定者と範囲がある。古い設計メモは相反するがsourceとして明示 | 新しい提案や古い資料からauthorityを推測せず、引用した元sourceを基準にする。証拠を外部取得しない |
| 入力証拠の不足 | 判断に不可欠な外部interfaceの仕様だけが入力にない。proposalの説明は断定的 | 情報要求または`BLOCKED`にし、外部sourceを自動で探索・捏造しない。確定できる目的違反は別findingにする |
| conformance ownerの非保証 | conformanceにownerとplanを記録するが、完了証拠はない | owner/planの記述だけで実施済み・適合済みと断定しない |
| Finding応答と設計更新 | 初回に目的逸脱を指摘。応答で設計差分と根拠を直し、同じrunで更新inputをcontinue | 前回指摘を権威化せず、現在の提案を全体として再評価する。実装やコード欠落を要求しない |
| HUMAN_DECISION_REQUIRED | 提案scopeを変更するにはauthorityが不足。後続の独立fixtureではユーザーの明示決定を`userDecision`として渡す | 判断前は停止。判断後のみ同じ`taskKey`・新しい`changeId`・前runを指す`previousRunId`で新しいstartをし、同じ変更の自動再開をしない |
| COMPLETE後のbaseline更新 | 初回は`approvedDesign: null`でCOMPLETE。後続changeでnull baselineを実際のユーザー承認済み設計へ更新 | `userDecision`なしのbaseline変更は拒否。既存のユーザー承認を本文とauthority付きで引用すれば、同じ`taskKey`・新`changeId`・完了runの`previousRunId`でfresh runを受理。COMPLETEやproposalだけではbaselineを昇格しない |
| COMPLETE後に承認なしで別change | 先行runの`approvedDesign: null`を保ち、別のproposalを新しいchangeとして提出 | 同じ`taskKey`・新`changeId`・完了runの`previousRunId`で新runを受理し、baselineをnullのまま保つ。既存task authorityで実施できる範囲の作業について承認を繰り返し求めない |
| submission上限 | 同じchangeで`ERROR`/`BLOCKED`からlinked runを続け、3 durable submissionsに達するfixture | 3回を越える提出を拒否する。識別子変更でbudgetをリセットできない |
| ID lineageとcaller責務 | 同じ作業の連続提出でSkillが同じ`taskKey` / `changeId`と前run参照を維持し、`userDecision`を必要な場合だけユーザーの明示発言から転記するか確認する。別途、異なるtaskKeyを与えたときのRunnerのlineage境界を記録する | Runnerは入力されたtaskKeyのlineageとそのbudgetを強制する。異なるtaskKeyが同じ実作業を表すか、userDecisionが本当のユーザー発言かは認証しない。SkillはID変更で予算を迂回せず、判断本文とauthorityを捏造しない |

## 利用負荷・費用の測定

CodexとCopilotを別々に、同じfixture群と同等の設定で実施する。成功例だけを選ばず、各提出を記録する。評価結果ファイルに次を保存する。

- provider、CLI version、model、reasoning設定、Runner/Skill version、commit、distribution fingerprint。
- fixture ID、run ID、submission数、terminal status、elapsed time、再提出理由。
- 判定精度: 期待findingの検出率、目的に結び付かないfinding数、誤った`COMPLETE`数、根拠不足の見落とし。
- 利用者負荷: input準備と更新の実時間、手作業時間、ユーザー判断を求めた回数、reviewerの追加情報要求回数、修正input提出回数。
- 実費: providerが利用量または費用を表示する場合のみその値と取得方法。表示されない費用を推計値として実測欄に書かない。
- 品質と負荷の両方の分布を記録する。平均だけで外れ値を隠さない。

予算上限とacceptance thresholdは評価前に担当者が記入し、評価結果を見てから都合よく変更しない。全fixture、全提出と実費情報を保存し、定義済み閾値を満たした場合のみstatusを見直す。未実施、provider error、または不十分な証拠がある場合は`NOT_RUN`/`HOLD`を維持する。

## Qualification handoff

- 実施主体: release candidateのqualificationを担当するmaintainer。
- 実施時点: Runner 0.5.0とSkill 0.6.0を配布対象として判定する前。
- 失敗時: case、run ID、transcript参照、判定差異、費用/負荷を結果文書へ記録し、該当する実装・prompt・Skill修正に戻す。
- 保管先: `tests/PurposeReviewRunner.Tests/purpose-review-results/<date>-<commit>.md`。
- 状態: 結果を検証してqualification recordを明示更新するまで、APMは`NOT_RUN`、direct deploymentは`HOLD`のままにする。
