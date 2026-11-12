# Issue #161 実装計画

対象: https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/161

## 目的と範囲

Adaptiveを親自身によるビルド可能な構造コード、人の実応答を待つ停止、承認後の子による詳細実装へ変更する。通常PlanとDesign Pair handoffの両入口を扱い、Design Pairの対話やPlan Coverage全体は再設計しない。

## 既存方式との比較

- 既存Skillは上位を別起動し、テスト等で全decision surfaceを解消して直接完了も許す。固定成果物境界と衝突するため置換する。
- 既存handoffのroute identity、Work Package、Allowed edit surface、Locked Decisions、比較evidence、re-entry lineageは再利用する。全decision解消assessmentは構造readinessへ置換し、テスト設計や内部制御は子へ残す。
- Design Pairの提示・実応答・durable handoffという既存パターンに従うが、Target Map等は複製せず、構造版・コードsnapshot・提示・応答を既存handoffへ追加する。
- finalizerのBCL / System.Text.Json / Tomlynと既存APM / plugin検証を再利用する。新しい状態管理基盤やOSS導入は不要であり、プロセス固有の停止条件だけを既存契約に記す。

## 実施

1. 親/子のcanonical契約、Skill、handoffとガイドを更新する。
2. 親model pinと上位別起動を除去し、finalizerと配布時検査を更新する。旧配布を黙って利用しない。
3. routing正負シナリオ、関連package境界、配布整合を検証する。
4. 隔離runtimeで実modelの停止・未承認再開・承認後委譲・再引受け・再利用を観測する。合成応答と実利用者承認を区別する。
5. commit / push / Ready PR作成後、pr-review-remediationでremote evidenceを取得し評価する。

## Purpose review

- Run: `2f1e48f8-5229-4e06-98ac-d1167ebaebf1`
- 初回 `PUR-001` を採用。旧handoffの全Resolved要求を残さず、構造判断と子の詳細判断を区分する。
- 入力・結果: `artifacts/purpose-review-runner/issue-161/`（ローカル証拠）。terminal COMPLETE、round=2、reviewRounds=2、durableSubmissions=2。未解決findingなし。利用者承認や実装保証ではない。

## 検証結果

Adaptive routing/contract、Design Pair、Plan Coverage、package境界、finalizerテスト、README navigation、APM 0.26.0でのAdaptive/Plan Coverage plugin生成・検証はPASS。runtimeはapm-packages/adaptive-implementation-execution/tests/runtime/issue-161/README.mdを参照。静的検証、runtime試験、実利用者による運用確認を区別する。
