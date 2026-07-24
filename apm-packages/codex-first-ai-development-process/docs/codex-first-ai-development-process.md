# Codex-first AI Development Process

この document は、Codex を第一優先にした cost-aware development process の全体像をまとめる。
既存の `plan-coverage-residual-flow`、`full-autonomous-plan-first-flow`、full-coverage 3層運用はそのまま利用可能だが、この package の標準ルートではない。
標準ルートの中核は `codex-first-cost-router` であり、利用者に process 名、agent 名、model tier、full-coverage 分岐を選ばせない。
実装経路は `adaptive` を既定とし、利用者が明示的に `design-pair` を選んだ場合だけ、実装開始前に Design Pair pre-stage を挿入する。

## Goal

詳しくない開発者が短い依頼から始めても、Codex 側が工程を分け、難しさとリスクに応じて model tier / agent / subagent を割り当てる状態を作る。

- ordinary natural-language intake
- cost-aware routing
- Plan / risk / scan / contract / implementation / verification / close gate
- state artifact based resume
- audit artifact based delegation evidence
- READY 判定
- delegated bounded implementation
- residual decision
- Agent Usage Ledger / DelegationCompliance
- execution mode and model-observability metadata
- human / higher-model stop

## Non-goals

- すべてを上位モデルで処理すること
- すべての課題を full-coverage 3層運用へ送ること
- 利用者に process 名や agent 名を覚えさせること
- 実名モデルを固定すること
- GitHub Copilot fallback を主経路にすること
- secret、課金、本番環境、外部サービス設定を AI が自動操作すること

## Standard route: cost-aware routing

| Gate | Main output | Default tier |
| --- | --- | --- |
| Intake | source of truth, current state, allowed-to-edit | `STANDARD_MODEL` |
| Plan | bounded Plan or equivalent artifact、behavior expansion decision、Case-to-Plan mapping、Plan readiness | `HIGH_MODEL` |
| Risk | `ReadyForRiskTriage` 後の risk class、advanced-route boundary、`plans/<slug>-change-risk-triage.md` | `STANDARD_MODEL` / `HIGH_MODEL` |
| Scan | summarized repo evidence | `CHEAP_MODEL` |
| Contract | implementation approach and human decisions | `HIGH_MODEL` |
| Implementation handoff review | parent authorization artifact, Parent Plan Coverage Ledger, and Behavior Case Coverage Ledger when required | `HIGH_MODEL` / `STANDARD_MODEL` |
| Design Pair pre-stage | explicit user selection に基づく Target Map、対話、Locked Decisions、tracked handoff。production / test edit は行わない | `HIGH_MODEL` |
| Implementation start / re-entry | non-trivial READY scope edits delegated to `high-implementation-starter` | `HIGH_MODEL` |
| Bounded completion | valid handoff の decision-free remainder delegated to `standard-implementation-completer` | `STANDARD_MODEL` |
| Verification | evidence and manual-only checks delegated to `standard-verifier` | `STANDARD_MODEL` |
| Close | residual and close decision | `STANDARD_MODEL` / `HIGH_MODEL` |

`CHEAP_MODEL` workers handle delegated read-heavy scan, docs consistency, or artifact formatting when the Routing Plan requires it.
They do not own final implementation permission or close decisions.

write-heavy parallel editing is not the default. That is separate from delegation: READY implementation is serial delegated work that begins with `high-implementation-starter`; `standard-implementation-completer` owns edits only after a valid handoff, and re-entry returns ownership to HIGH_MODEL. The parent does not implement it directly unless a recorded `ParentDirectExecutionException` has explicit human approval.
If the parent directly performs work that was expected to be delegated, the state records `PARENT_DIRECT_WORK` or `TRIVIAL_PARENT_FIX` and does not count it as cost-saving delegation.
Before normal READY implementation, the Risk gate must create `plans/<slug>-change-risk-triage.md` and set `risk_triage_artifact_status = Complete`. Then `implementation-handoff-review` or an explicitly equivalent pre-implementation gate must create the parent authorization artifact. When behavior expansion is required, the state must record `behavior_case_coverage_ledger_status = Complete` before `high-implementation-starter` can start.
`implementation_route = design-pair` is valid only when `implementation_route_source = explicit-user-selection` is recorded. The router must not infer or recommend it. A selected Design Pair pre-stage must complete `plans/<slug>-design-pair-implementation-handoff.md` before the HIGH implementation owner begins edits; all other work continues directly through the Adaptive implementation contract.

## Documentation level

`documentation_level` records how much planning and verification structure is needed for the current bounded work.
It is selected by Codex-first routing, not by the user.

| Level | Use when | Required guardrail |
| --- | --- | --- |
| `lite` | Work is small, bounded, local, and has clear FR / AC and verification evidence | A Lite artifact or equivalent section keeps source of truth, FR / AC coverage, Inline Ready Gate, Implementation Self-Map, Verification Summary, and residual / close decision together |
| `standard` | Work has compatibility risk, behavior expansion, implementation-realization risk, repeated coverage ledger needs, or non-trivial verification | Separate or canonical artifacts preserve Plan readiness, risk, coverage ledger / delta, implementation contract, handoff / readiness, verification, and residual decision |

`strict` is not a documentation level.
`full-coverage` is an advanced `selected_process` / route, not a documentation level.
If the task is broad enough for full-coverage decomposition, the documentation level remains `standard` while the selected process moves to `advanced-full-coverage`.

Lite may replace a separate `implementation-handoff-review` artifact only when the Inline Ready Gate is explicitly equivalent and complete.
If behavior expansion, human decision, manual verification, or implementation-realization ambiguity remains, the route must use `standard` or stop before implementation.

## Close rules

Close してよいのは、次が満たされるときだけ。

- Plan の acceptance conditions に対応する evidence がある。
- behavior expansion が必要な場合、Case IDs が Plan FR / AC または explicit disposition に mapping 済みである。
- production implementation と wiring が確認済み、または manual-only として明示済み。
- `ManualVerificationRequired` を残す場合は close ではなく human review 待ちにする。
- `NeedsHumanDecision` と `NeedsHigherModelReview` は未解決のまま完了扱いしない。
- `DelegationRequired = Yes` の gate に observed run または accepted exception がある。
- `DelegationCompliance = PASS`、または explicit human decision 付き `EXCEPTION_ACCEPTED` である。
- cost-saving delegation として数える run には、委譲実行の evidence があり、`delegation_violation` がない。
- residual work がある場合は、FixNow / Deferred / Manual / HigherModel のいずれかに分類されている。

## State and audit artifacts

通常は次の state artifact を使う。

```text
plans/<slug>/codex-first-state.md
```

この artifact は、`task_weight`、`documentation_level`、`selected_process`、`implementation_route`、`implementation_route_source`、`design_pair_handoff`、`design_pair_status`、`design_pair_locked_decision_ids`、`design_pair_conflict`、`current_gate`、`next_gate`、`recommended_model_tier`、`model_tier_recommendation`、`execution_mode`、`risk_triage_artifact`、`risk_triage_artifact_status`、`behavior_case_coverage_ledger_artifact`、`behavior_case_coverage_ledger_status`、`shape_handoff_status`、`remaining_design_uncertainty`、`completion_scope`、`shape_reentry_reason`、Routing Plan、Agent / Subagent Plan、Edit Permission、`delegation_required`、`required_artifacts`、Stop / Ready Gate、`audit_artifact`、DelegationCompliance summary、`stop_reason`、`human_required_items`、`unresolved_residuals`、`next_action` を持つ。
ユーザーが「続きやって」と依頼したら、まずこの artifact を読む。

委譲証跡、model 観測詳細、route 履歴、close audit は次の audit artifact に分ける。

```text
plans/<slug>/codex-first-audit.md
```

Agent Usage Ledger では `configured_model`、`hook_model`、`reported_model`、`effective_model` を混ぜない。
close 可否が委譲証跡や DelegationCompliance に依存する場合は、state と audit の両方を読む。

## Executable profile templates

この package は `profiles/codex-first/` に、Codex が読める profile / custom agent file の最小例を持つ。
`profiles/codex-first/agents/*.toml` には `model` と `model_reasoning_effort` の初期値があり、そのまま検証に使うことも、組織の契約や利用枠に合わせて変更することもできる。

抽象 tier は文書上の安定語彙であり、実名モデルへの対応は profile 側で管理する。

## Advanced route

full-coverage 3層運用は advanced route である。
`ReadyForRiskTriage` の Plan の scope が広すぎる、cross-slice contract が強い、標準 cost-router では安全に bounded 化できない、または熟練 operator が明示的に選ぶ場合だけ使う。
要求展開不足、Case-to-Plan mapping 不足、期待動作の未決は full-coverage ではなく Plan gate の `NeedsPlanBehaviorExpansion` / `NeedsHumanDecision` として扱う。

標準 user guide では full-coverage のプロンプト例を示さない。
詳細は `advanced-full-coverage-3layer.md` に分離する。

## Compatibility with existing packages

- `plan-coverage-residual-flow`: cost-router が内部で参照する既存 kernel 群。
- `full-autonomous-plan-first-flow`: broad autonomous flow を明示的に選ぶ場合の既存資産。
- `token-aware-full-coverage-3layer`: advanced route の既存資産。
- `adaptive-implementation-execution`: 標準 route と full-coverage slice route で共有する implementation-internal ownership contract。
- `design-pair-implementation-execution`: 利用者が明示的に選んだ場合だけ Adaptive implementation の直前に入る対話型 design pre-stage。Locked Decisions だけを拘束力のある入力として Adaptive HIGH owner へ渡す。

この package は既存資産を複製せず、初心者向けの入口、state、model tier routing、stop vocabulary を上に重ねる。
