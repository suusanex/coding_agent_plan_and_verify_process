# Decision-Surface Re-entry Handoff

隔離runtime試験の注入payload。自然発生した子の検出結果ではない。

- Verdict: NEEDS_DECISION_SURFACE_REENTRY
- trigger: dependency-return-contract-changed
- reentry_count: 1
- previous_reentry_trigger: N/A
- implementation_route: adaptive
- implementation_route_source: default
- Design Pair handoff: N/A
- Original Implementation Intent: plans/report.md
- Bounded Residual Implementation Handoff: plans/report-bounded-residual-implementation-handoff.md
- Structure review version: 1
- Work completed before stop: formatter本体と7件の検証（既存turn3の実結果）
- Evidence that opened the decision surface: fixtureがItemStore.Readの境界型をIReadOnlyList<Item>からIEnumerable<Item>へ変更。ReportService.Runからformatterへ渡す型が整合しなくなった。
- New decision required: store/formatter間のデータ受渡し契約と適応場所。元の機能・cache/retryなしの制約は変更しない。
- Worktree state: 既存の子実装は保持、store signatureのみ外的変化を注入
- Locked Decision IDs preserved: 手元の元handoffどおり
