# Design Pair real-model smoke result

- Status: NOT RUN
- Operator:
- Started at:
- Completed at:
- Process repository revision:
- Design Pair package version:
- Adaptive package version:
- Fixture baseline revision:
- Disposable repository root:
- Plan reference: plans/retry-after-plan.md
- Execution surface: Codex CLI / GitHub Copilot CLI / other
- CLI version:
- Configured model:
- Configured reasoning effort:
- Effective model: Unknown unless independently verified
- Agent selection flags:
- Tracked handoff path:
- Unsupported capability notes:
- Input origin: Human-operated / Scripted scenario (not human confirmation)
- Comparison baseline / candidate revisions:
- Same-task / model / reasoning / permission comparability:

## Turn sequence

| Turn | User message / turn reference | Expected stage | Observed repository root | Observed verdict / stage | Production or test diff | Adaptive started? | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | | target-selection | NOT RUN | NOT RUN | NOT RUN | NOT RUN | |
| 2 | | disposition-confirmation | NOT RUN | NOT RUN | NOT RUN | NOT RUN | |
| 3 | | complete | NOT RUN | NOT RUN | NOT RUN | NOT RUN | |

Add rows for any optional question-and-answer turns during `disposition-confirmation`. Record the exact human message and do not synthesize missing input in the smoke harness.

## Artifact evidence

- Target Map presentation evidence:
- Target selection request evidence:
- Selected Target IDs:
- Delegated-to-Adaptive Target IDs:
- No-Change Target IDs:
- Upstream-Decision-Required Target IDs:
- Pending human-owned Target IDs:
- Target Map / summary set reconciliation evidence:
- Selected Target Discussion Evidence:
- Material sections / versions / presentation turns:
- Finalization status and final reconciliation:
- Target Disposition Evidence:
- Upstream Binding Constraints:
- Upstream User Initial Positions:
- Locked Decision IDs:
- Locked Decision confirmation evidence:
- Confirmation occurred after Target Map presentation:

## Verdict sequence

```text
NOT RUN
```

## Validation

- Turn 1 stopped before READY: NOT RUN
- 初回資料の問い・判断材料・因果関係・具体的根拠と会話の判断入口: NOT RUN
- Every turn executed in the disposable repository root: NOT RUN
- Turn 1 production/tests unchanged: NOT RUN
- Turn 1 Adaptive not started: NOT RUN
- Upstream proposal not converted to Locked Decision: NOT RUN
- Turn 2 trade-off response observed: NOT RUN
- Target-only selection advanced to disposition-confirmation without requiring an initial position or repeating selection: NOT RUN
- 既知の根拠の再利用と必要な差分だけの回答・記録: NOT RUN
- Turn 2 stopped for final disposition: NOT RUN
- Final post-map confirmation evidence valid: NOT RUN
- Every Locked / Discussed-Unlocked / Adaptive-Owned Target has matching post-map disposition evidence: NOT RUN
- Explicit multi-Target delegation has one disposition evidence row per Target: NOT RUN
- Adaptive started only after READY: NOT RUN
- Resume waiting behavior, if exercised: NOT RUN
- New CLI session resume used tracked handoff as authority, if exercised: NOT RUN
- Ordinary Plan route exercised: NOT RUN
- Explicit Plan Coverage route exercised: NOT RUN
- ID選択なしの直接質問・反論・明示的確定: NOT RUN
- 部分・残件・全件skipとNo-Changeの区別: NOT RUN
- 新案・code変更時の局所追加調査と資料版更新: NOT RUN
- 待機中Pendingからの再開と完了時の全集合・証拠照合: NOT RUN
- 無効READYをAdaptiveが編集前に拒否: NOT RUN

## 初回から最終dispositionまでのコスト

| Variant / turn | Input tokens | Output tokens | Reasoning tokens | Cached tokens | Elapsed | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| Baseline / NOT RUN | Unknown | Unknown | Unknown | Unknown | Unknown | |
| Candidate / NOT RUN | Unknown | Unknown | Unknown | Unknown | Unknown | |
| Baseline total | Unknown | Unknown | Unknown | Unknown | Unknown | |
| Candidate total | Unknown | Unknown | Unknown | Unknown | Unknown | |

- Token包含関係と二重計上防止:
- 説明不足解消だけの往復数（baseline / candidate）:
- 不要な根拠再読・既出説明再掲・handoff全面更新（baseline / candidate）:
- 必要な追加調査とその理由:
- 全行程完了・比較上の制限:
- 観測できた差分（未計測の改善効果は断定しない）:

## Final result

- Runtime verdict: NOT RUN
- Adaptive Implementation result: NOT RUN
- Final code review status: NOT RUN
- Remaining work:
- Human-required work:
