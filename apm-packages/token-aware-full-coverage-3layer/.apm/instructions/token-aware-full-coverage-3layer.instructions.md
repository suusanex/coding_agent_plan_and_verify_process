---
description: Codex guidance for compact-slice-record-v2 full-coverage execution after approved decomposition.
---

# Full-coverage compact execution

Keep Plan readiness, parent risk triage, Architecture Slice Readiness, Architecture Elaboration, and decomposition unchanged. Fresh decomposition uses `full_coverage_artifact_layout: compact-slice-record-v2` with `full_coverage_artifact_layout_source: default-new-flow`; resumes with existing split artifacts use `legacy-split-v1` / `legacy-resume` and are not migrated.

The standard post-decomposition artifacts are the canonical coverage ledger, one Parent Orchestration State, one Slice Record per executable slice, and one Full-Coverage Final Record. A phase does not imply a separate artifact. A separate file requires an independent human/tool/model lifecycle plus Parent State Exception Register ownership and merge-back rule.

Each Slice Record has immutable baseline, Slice Preparation, Parent Authorization, Design Pair, Implementation, Slice Verification, Bounded Fix Passes, Current Handoff, and Coverage Ledger Delta sections. Parent authority is inherited without re-derivation; slice preparation writes only local deltas and an Inline Slice Ready Gate. Parent Authorization plus a passing same-digest gate is the v2 implementation-handoff-review equivalent.

Only authorized slices start Adaptive Implementation at `high-implementation-starter`; a decision-free remainder may use `standard-implementation-completer`. Both update the same record. Independent verification updates the Slice Verification section, does not repair gaps, preserves XC for final verification, and emits Direct FixNow only for simple bounded gaps. Selected repairs update Bounded Fix Passes and must return to verification.

`NEEDS_HIGH_MODEL_REENTRY` always returns to `high-implementation-starter`. `slice-impl` remains legacy compatibility only. fresh intakeだけ`implementation_route: adaptive` / `implementation_route_source: default`を初期化し、resumeでは`implementation_route`と`implementation_route_source`の両方が欠落または矛盾する場合、Adaptiveへ補完せず停止する。

Cross-slice verification writes Final Verification Snapshot and residual decision writes Residual Decision / Close Decision in `plans/<slug>-full-coverage-final.md`. Do not treat local verification, fake-only evidence, or an unapproved residual as close-ready. Canonical ledger owns full coverage; records carry deltas only.

Never silently mix v1 and v2, infer layout metadata, promote an old artifact to a v2 authorization source, or create generic per-slice risk, contract, handoff, implementation, verification, parent-review, execution-table, audit-ledger, cross-slice, or residual files for v2. Generic non-sliced and explicit legacy routes retain their existing paths.

Use this route only after the authorized parent Plan/triage/Architecture Slice Readiness/decomposition chain. In `PREP_ONLY`, the parent writes no production or test code. In `DELEGATED_IMPLEMENTATION`, the parent authorizes and audits but never edits production or tests; one serial Adaptive owner does. Parent State is the resume entrypoint and must verify source revision/watch-path freshness. Keep few-slice/coalescing rules and stop for shared-semantics drift, human decisions, or further decomposition; do not turn any of those into a recursive artifact chain.
