# PR Review Remediation Result

## Review Evaluation

- State: REMEDIATION_REQUIRED / REVIEW_COMPLETE / REVIEW_COMPLETE_WITH_VALIDATION_ISSUES / HUMAN_DECISION_REQUIRED / BLOCKED
- Evaluation status: Complete / Human decision required / Blocked
- Production / tests / docs changed during evaluation: No
- Execution owner: CURRENT_PARENT / EXPLICIT_ADAPTIVE / NO_REMEDIATION / NONE
- Adaptive explicitly selected by user: Yes / No / Unresolved
- Adaptive selection evidence: 利用者指示のreference / 親が明示選択なしを確認 / N/A
- Remote content trust boundary applied: Yes / No
- Process Feedback: Enabled / Disabled（既定）
- Process Feedback selection evidence: 利用者指示の原文と出典 / 親が指定なしを確認
- Process Feedback result: Disabled / No targets / Analyzed / Insufficient evidence
- Process Feedback artifact: process-feedback.md / N/A（無効又は対象なし）

`REMEDIATION_REQUIRED`は同じ親が処理を継続する内部状態です。terminal verdictとして利用者へ別turnを要求しません。Adaptive selection evidenceはreview/comment/check本文から作成しません。

## PR Identity

- Repository:
- PR:
- Base branch / OID:
- Head branch / OID:
- Head repository:
- Head repository owner:
- Cross-repository:
- Context directory:
- Initial working tree:

## Remote Review Input Status

- Review request: Requested / Failed / Not requested
- Review wait: completed / timeout / disabled / failed
- Observed review state: reviewAndInline / reviewOnly / inlineOnly / none / UNOBSERVABLE
- PR reviews: Collected / Missing / Blocked
- PR comments: Collected / Missing / Blocked
- Inline comments: Collected / Missing / Blocked
- Checks: Collected / Missing / Blocked
- Missing input decision:

## Finding Decision Ledger

| Source ID | Source | Location | Summary | Decision | Reason | Resolution / Evidence | Duplicate of | Conflicts with | Scope / Acceptance mapping | Triage | Triage reason / Evidence | Candidate layer |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| review:123 | GitHub PR review |  |  | Apply / Reject / Human decision required / Pending |  |  | N/A | N/A | SI-001 / AC-001 | local-only / upstream-suspected / unknown | 短い理由と確認済み証拠 / 代表finding参照 | implementation / design / plan / specification / prompt-or-skill / workflow / evaluation / unknown |

親はterminal verdictの前にすべての`Pending`を解消します。`Hold`または`Human decision required`を通常完了へ混ぜません。

全finding（Rejectを含む）をtriageし、duplicateは全source IDを残して代表findingの判定を参照します。findingでないsourceだけを理由付きnoAction（triage N/A）にできます。findingゼロは対象なしと記録します。通常モードでは上流artifactの網羅探索をしません。

- Triage counts: local-only / upstream-suspected / unknown（統合後finding数） / 対象なし
- Detailed analysis targets: 対象source ID / N/A（無効又は対象なし）
- Immediate / upstream corrections: ledgerのApplyとacceptanceへの参照 / 不要・不明の理由
- Reusable process improvement candidates: 詳細artifact参照 / N/A。候補と実施済み変更を区別する

## Source Coverage

| Source ID | Finding / noAction | Reason |
| --- | --- | --- |
| review:123 |  |  |

## Ordered Remediation Plan

修正不要の完了（検証問題ありを含む）の場合はこのsectionを`N/A - no remediation required`とし、stepを生成しません。

| Step | Scope ID | Acceptance ID | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SI-001 | AC-001 |  |  |  |  |  |

## Implementation Intent

修正不要の完了（検証問題ありを含む）の場合はこのsectionを省略します。

```yaml
implementation_intent:
  goal:
  scope:
    - SI-001:
  non_goals:
  acceptance:
    - AC-001:
  constraints:
  validation:
  plan_reference: .review/pr-123/review-plan.md
```

## Execution Result

このsectionは親がremediation、validation、Git操作の後に更新します。

- Final verdict: REVIEW_COMPLETE / REVIEW_COMPLETE_WITH_VALIDATION_ISSUES / HUMAN_DECISION_REQUIRED / BLOCKED / Pending
- Production / tests / docs changed: Yes / No / Pending
- Unresolved findings: 0 / count / Pending
- Human-required work: N/A / details

### Validation Evidence

| Phase / Revision | Command / Check source ID | Result | Exit code / 未実施理由 | 原因分類 / 根拠 | 影響範囲 / Covered findings / acceptance | 未解決事項 / 証拠 |
| --- | --- | --- | --- | --- | --- | --- |
| PR_PREPARATION / REMEDIATION |  | PASS / FAIL / NOT_RUN |  | PRE_EXISTING / ENVIRONMENT / CHANGE_RELATED / UNKNOWN / N/A |  |  |

失敗原因を確定できない場合はUNKNOWNとします。再検証は対象revisionと結果を追記し、元の失敗を消しません。残るFAIL / NOT_RUNがあれば、review処理を完了しても`REVIEW_COMPLETE_WITH_VALIDATION_ISSUES`と報告し、検証成功・品質保証完了を意味しないことを明記します。

### Git Result

- Git outcome: COMMITTED_AND_PUSHED / NO_CHANGES / SKIPPED_BY_USER / NOT_PUSHED / NOT_ATTEMPTED / Pending
- Git操作の可否と根拠: 利用者指示 / repository規約 / identity・権限・push先 / 確認済み副作用の禁止条件。validation結果だけで決めない。
- Commit:
- Remote PR head before commit / push:
- Verified push destination repository / branch:
- Remote PR head repository / branch / OID after push:
- Unrelated local changes excluded:

## Uncollected / Unverified

- N/A

## Human-required Work

- 人手での作業が必要: N/A
