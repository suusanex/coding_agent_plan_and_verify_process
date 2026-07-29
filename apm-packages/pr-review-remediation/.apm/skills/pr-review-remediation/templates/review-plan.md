# PR Review Remediation Plan

## Phase 1 Verdict

- Verdict: READY_FOR_ADAPTIVE_IMPLEMENTATION / APPROVED_FOR_ADAPTIVE_IMPLEMENTATION (Goal Context multi-round approval only) / REVIEW_COMPLETE (Goal Context multi-round mode only) / HUMAN_DECISION_REQUIRED / BLOCKED
- Production code changed: No
- Process status: Review planning complete / Review complete / Human decision required / Blocked
- Review mode: Baseline / Goal Context
- Review round: N/A / round-NNN
- Previous round: N/A / round-NNN
- Previous Adaptive result: N/A

## PR Identity

- Repository:
- PR:
- Base branch / OID:
- Head branch / OID:
- Context directory:

## Review Input Status

- Local Codex review: Collected / Missing / Blocked
- Copilot wait status: completed / timeout / disabled
- Copilot observed review state: reviewAndInline / reviewOnly / inlineOnly / none
- PR comments: Collected / Missing
- Inline comments: Collected / Missing
- Checks: Collected / Missing
- Goal Context selection: N/A / SELECTED / Missing / Invalid / Ambiguous
- Purpose review: N/A / PURPOSE_REVIEWED / HUMAN_DECISION_REQUIRED / BLOCKED
- Missing input decision:

## Goal Context Boundary

- Selected Goal Context: N/A
- Goal Context SHA-256: N/A
- Original problem: N/A
- Desired outcome: N/A
- User scenarios: N/A
- MVP guardrails: N/A
- Non-goals: N/A
- Rejected alternatives: N/A
- Superficially compliant but wrong / negative conditions: N/A
- Open questions / human decisions: N/A

## Finding Decision Ledger

`PUR-*` rows are Goal Context mode only; omit them in Baseline mode.

| Source ID | Source | Location | Summary | Decision | Reason | Duplicate of | Conflicts with | Scope / Acceptance mapping |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LR-001 | Local Codex |  |  | Apply / Hold / Reject |  | N/A | N/A | SI-001 / AC-001 |
| PUR-001 | Purpose (Goal Context mode only) |  |  | Apply / Hold / Reject |  | N/A | N/A | SI-001 / AC-001 |

## Finding Delta (Goal Context multi-round mode only)

Omit this section in Baseline and single-round mode. Tracking IDs are stable across rounds and are not inferred from text similarity alone.

| Tracking ID | State | Current finding IDs | Source IDs | Prior evidence | Reason |
| --- | --- | --- | --- | --- | --- |
| TRK-001 | new / persistent / resolved / reopened |  |  | N/A / round-NNN |  |

## Ordered Remediation Plan

Goal Context multi-round modeでは、この実行可能planを`READY_FOR_ADAPTIVE_IMPLEMENTATION`の場合だけround artifactへ含めます。`HUMAN_DECISION_REQUIRED`ではこのtemplateを保存せず、Adaptive handoffも出しません。人間が継続を明示した後は`APPROVED_FOR_ADAPTIVE_IMPLEMENTATION`として`round-NNN/approved-review-plan.md`を参照し、cycle managerの`resolve`で承認情報とhashを記録します。

| Step | Scope ID | Acceptance ID | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SI-001 | AC-001 |  |  |  |  |  |

## Implementation Intent

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
  plan_reference: <multi-round READYではround-NNN/review-plan.md、人間承認後はround-NNN/approved-review-plan.md>
  goal_context_reference:
```

multi-round modeでは、`scope`の全項目を`SI-*`、`acceptance`の全項目を`AC-*`で始め、Ordered Remediation PlanのID集合と双方向に完全一致させます。intentだけへ追加作業を記載しません。

## Uncollected / Unverified

- N/A

## Human-required Work

- 人手での作業が必要:

## Explicit Implementation Turn Handoff

- Thread mode: single-round / role-thread-reuse / portable-handoff
- Target Implementation Thread ID: <Codex task UUID / N/A for single-round or portable-handoff>
- Target Implementation Thread URI: <codex://threads/... / N/A for single-round or portable-handoff>
- Return Review Thread ID: <Codex task UUID / N/A for single-round or portable-handoff>
- Return Review Thread URI: <codex://threads/... / N/A for single-round or portable-handoff>
- Plan SHA-256 source: <round manifest artifact binding / explicit single-round handoff record>

```text
$adaptive-implementation-execution を使って <review-plan-path> を、上記Implementation Threadの新しい明示ターンとして実装してください。
review-plan.md の implementation_intent を source of truth とし、既存 Adaptive Implementation の router、agents、verdict、handoff、validation contract を変更または複製しないでください。
既存会話の探索・設計コンテキストは利用できますが、scopeとacceptanceはartifactを正本としてください。完了後は上記Review Threadへ戻るためのURI、Adaptive result reference、変更後head OIDを報告してください。
```

基礎版のsingle-round利用ではrole thread bindingを要求せず、従来どおり別の明示ターンへartifactを渡します。`portable-handoff`の場合は、明示承認済みのartifact-only cold-startとしてtask identity欄を`N/A`にします。Phase 1の停止はレビュー反映プロセス全体の完了ではありません。Adaptive Implementationはこの親ターンから自動起動しません。
