# Adaptive Routing Validation

この文書は `adaptive-implementation-execution` の routing contract を検証するシナリオです。各 scenario は、input、observed evidence、expected route、禁止事項を記録できる形にします。

## Common evidence

実行 validation では次を保存します。

- source Plan / Implementation Intent
- agent verdict sequence
- implementation owner by phase
- files changed by each agent
- validation commands and results
- acceptance status and evidence for every in-scope item
- handoff persistence
- re-entry handoff, if any
- final review status

## VAL-001: Early delegation

Input:

- external behavior is small
- existing implementation pattern is clear
- HIGH_MODEL edits a representative production case and runs a focused test
- only same-pattern cases and tests remain

Expected:

```text
READY_FOR_STANDARD_COMPLETION -> COMPLETED
```

Checks:

- HIGH_MODEL edited production code or tests before delegation
- handoff names files, symbols, expected behavior, and allowed surface
- handoff records acceptance status and applicability evidence, including reasons for any N/A concern
- every Incomplete acceptance item and Remaining work row has a bidirectional Work ID mapping, no Blocked item exists, and every Complete item has evidence
- STANDARD_MODEL makes no structural change

## VAL-002: Mid-implementation delegation

Input:

- class responsibility, DI, representative production path, and test seam require decisions
- HIGH_MODEL implements those decisions and passes build / smoke test
- validation branches and test cases remain

Expected:

```text
READY_FOR_STANDARD_COMPLETION -> COMPLETED
```

Checks:

- locked decisions include responsibility, wiring, signature, and test seam
- STANDARD_MODEL handles only remaining branches and tests

## VAL-003: HIGH_MODEL completes

Input:

- state ownership, error handling, and API shape decisions continue through implementation
- no natural delegation point exists

Expected:

```text
COMPLETED_BY_HIGH_MODEL
```

Checks:

- no artificial skeleton or broken intermediate state is created for delegation
- HIGH_MODEL records completed scope and checks
- every in-scope acceptance item is Complete with implementation or validation evidence
- `COMPLETED_BY_HIGH_MODEL` includes unchanged `implementation_route`, `implementation_route_source`, and the Design Pair handoff path or `N/A`

## VAL-004: Re-entry from STANDARD_MODEL

Input:

- HIGH_MODEL initially delegates through a handoff that has passed authorization
- STANDARD_MODEL discovers that test seam or production wiring must change

Expected:

```text
READY_FOR_STANDARD_COMPLETION
  -> NEEDS_HIGH_MODEL_REENTRY
  -> high-implementation-starter resumes
```

Checks:

- STANDARD_MODEL does not redesign the seam or wiring
- `NEEDS_HIGH_MODEL_REENTRY` is emitted only for the structural decision discovered after valid authorization, never to repair invalid route metadata
- High-model Re-entry Handoff contains invalidating evidence, worktree state, unchanged route pair, and Design Pair handoff path or `N/A`
- STANDARD_MODEL increments incoming reentry_count and preserves incoming previous_reentry_trigger
- parent passes both the original Implementation Completion Handoff and the High-model Re-entry Handoff back to HIGH_MODEL and rejects route identity mismatch
- HIGH_MODEL preserves the incremented count and copies the returned Trigger to previous_reentry_trigger only when a strictly smaller handoff is safe
- agents run serially
- HIGH_MODEL owns completion after the first re-entry unless Remaining work and Allowed edit surface both strictly shrink and the same trigger has not recurred

## VAL-005: Insufficient Plan

Input:

- Plan contains a goal but scope or acceptance cannot be determined

Expected:

```text
REPLAN_REQUIRED or HUMAN_DECISION_REQUIRED
```

Checks:

- no production code or tests are edited
- missing product / scope / acceptance decision is explicit

## VAL-006: Plan Coverage independence

Input:

- ordinary Plan exists
- no change-risk-triage, runtime-contract, test-design, handoff-review, coverage-ledger, or residual-decision artifact exists

Expected:

- skill starts from the ordinary Plan
- missing Plan Coverage artifacts are not blockers

Manifest check:

- package has no dependency on `plan-coverage-residual-flow`, `token-aware-full-coverage-3layer`, or `codex-first-ai-development-process`

## VAL-007: No write-heavy parallelism

Input:

- a valid HIGH_MODEL handoff exists

Expected:

- STANDARD_MODEL starts only after HIGH_MODEL run and handoff validation complete
- re-entry starts only after STANDARD_MODEL stops and returns its handoff

Checks:

- no overlap between HIGH_MODEL and STANDARD_MODEL write ownership
- parent / router does not edit production code or tests

## VAL-008: Installation

Steps:

1. Install the package with APM for `codex,agent-skills`.
2. Confirm skill and both reference templates are deployed.
3. Confirm both portable agents are available to Codex.
4. If APM leaves model-less custom agent TOMLs, complete their settings with `install-adaptive-implementation-local.cs`.
5. Run installer `--check`.
6. Confirm Codex can select the skill and both custom agents.
7. Confirm the installer does not access an existing `AGENTS.md`, and review collision behavior with same-name TOML.
8. Dry-run APM uninstall, custom agent configuration removal, and orphan prune before rollback.

Expected:

- skill, refs, portable agents, both TOML sources, and docs are present in the package
- installed skill refs are available under `.agents/skills/adaptive-implementation-execution/refs`
- concrete agent TOMLs contain model, reasoning effort, and workspace-write sandbox fields
- HIGH_MODEL and STANDARD_MODEL use different custom agent names and different model mappings
- the installer does not create, read, update, or remove `AGENTS.md`
- APM-generated model-less stubs with matching package metadata are completed without `--force`
- other same-name TOML collisions fail closed unless `--force` is explicit

## VAL-009: Explicit Design Pair handoff

Input:

- user explicitly selected Design Pair
- tracked Design Pair handoff has one explicit Locked Decision and one Adaptive-Owned target

Expected:

- HIGH_MODEL preserves the Design Pair Decision ID and binds only the Locked Decision
- Target Map and Affected files / symbols are not treated as the Allowed edit surface
- HIGH_MODEL decides the Adaptive-Owned target from actual code and verification evidence
- a valid Completion Handoff consolidates Design Pair and HIGH_MODEL decisions with Origin and Decision ID
- STANDARD_MODEL receives Design Pair Decision IDs through the Completion Handoff
- a Locked Decision conflict returns evidence and a stop verdict without automatic Design Pair re-entry

## VAL-010: Resume a pre-Design-Pair Adaptive handoff

Input:

- `legacy-adaptive-handoff.md`, matching the tracked handoff schema from before Design Pair fields were introduced
- no Design Pair selection, Decision ID, Target Map, or handoff path evidence

Expected:

- the resume is not rejected solely because Design Pair fields and Origin / Decision ID columns are absent
- the parent records `implementation_route: adaptive`, `implementation_route_source: default`, and `route_metadata_normalization: legacy-adaptive-handoff`
- `Design Pair handoff` and `Design Pair Decision compliance` normalize to explicit `N/A`
- legacy Locked decisions receive deterministic `LEGACY-HIGH-D01`-style IDs with `Origin: HIGH_MODEL`
- the normalized affected-file value does not become the Allowed edit surface
- partial new-schema handoffs, incomplete old-schema handoffs, and any handoff with Design Pair evidence fail closed

## VAL-011: Preserve route metadata in a tracked completion handoff

Input:

- a current-schema Adaptive or Design Pair run reaches `READY_FOR_STANDARD_COMPLETION`
- a session, thread, model, or worker boundary requires a tracked `Implementation Completion Handoff`

Expected:

- fresh `adaptive / default` intake initializes `design_pair_handoff: N/A` with both route fields
- parent supplies `implementation_route`, `implementation_route_source`, and the Design Pair Implementation Handoff path or explicit `N/A` in every initial HIGH_MODEL payload
- HIGH_MODEL writes both `implementation_route` and `implementation_route_source` into the handoff header without changing their incoming values
- STANDARD_MODEL requires both fields before editing and rejects a missing or contradictory pair
- a High-model Re-entry Handoff preserves both route fields and the Design Pair handoff path or `N/A`
- HIGH_MODEL and STANDARD_MODEL return both route fields and the Design Pair handoff path or `N/A` on every non-invalid result, including normal completion
- parent validates every non-invalid HIGH_MODEL and STANDARD_MODEL result against the incoming route identity before accepting completion, continuation, delegation, or re-entry
- a partial current-schema handoff does not use `Legacy Adaptive handoff normalization`
- a missing, contradictory, or evidence-inconsistent current-schema handoff returns `BLOCKED` with `BlockedByInvalidCompletionHandoff` and does not emit `NEEDS_HIGH_MODEL_REENTRY`
- invalid-artifact `BLOCKED` returns raw observed values or `<missing>` for each identity field plus repair evidence; parent accepts this stop result without requiring a complete pair
- external-blocker `BLOCKED` still returns the complete unchanged route identity
- a later resume restores the selected route without defaulting to Adaptive

## VAL-012: Portable agent route validation

Input:

- a launcher or APM target uses the packaged HIGH and STANDARD TOMLs without repository-local `.github/agents`

Expected:

- both portable agents accept only `adaptive / default` with an explicit `N/A` path or `design-pair / explicit-user-selection` with the current tracked path
- either missing field, a contradictory pair, or Design Pair evidence mismatch returns `BLOCKED` with `BlockedByInvalidCompletionHandoff` before editing
- `design-pair` requires the current Design Pair Implementation Handoff path and never falls back to Adaptive
- STANDARD_MODEL preserves the route pair and Design Pair handoff path in every High-model Re-entry Handoff
- both agents return the complete route identity on every non-invalid result
- invalid-artifact `BLOCKED` returns raw observed values or `<missing>` plus repair evidence instead of fabricating a complete identity
- STANDARD_MODEL reserves `NEEDS_HIGH_MODEL_REENTRY` for structural decisions found after a valid handoff passes authorization

## VAL-013: Manual-only Codex invocation

Scenarios:

1. The user says `この小さな修正を実装してください。`
2. The user says `$adaptive-implementation-execution を使って実装してください。`
3. An installed skill or higher-level workflow explicitly selects `adaptive-implementation-execution` and delegates an authorized implementation intent.

Expected:

- scenario 1 does not select `adaptive-implementation-execution` and does not start HIGH_MODEL or STANDARD_MODEL implementation subagents from this skill
- scenario 2 can start the existing Adaptive Implementation flow
- scenario 3 can start the existing Adaptive Implementation flow because `allow_implicit_invocation: false` does not prohibit explicit delegation
- merely installing the package does not make a generic implementation request eligible for this skill
- APM deploys `agents/openai.yaml` under `.agents/skills/adaptive-implementation-execution/agents` with `allow_implicit_invocation: false`

## Issue #44 integration validation matrix

次のシナリオは standalone Adaptive package だけでなく、Plan Coverage、full-coverage slice、Codex-first、Copilot fallback の routing surface を同じ contract で検証します。`trivial-local` は対象外です。

| ID | Scenario | Expected verdict sequence | Expected implementation owner sequence | Required state / audit evidence |
| --- | --- | --- | --- | --- |
| `INT-001` | 新規 service + DI + tests | `READY_FOR_STANDARD_COMPLETION -> COMPLETED -> verification` | HIGH が service responsibility、DI、代表 test seam を固定し、STANDARD が Work-ID-mapped remainder だけを完了 | HIGH start、valid handoff、serial owner、production wiring evidence |
| `INT-002` | 大きな class からの責務分離 | `COMPLETED_BY_HIGH_MODEL -> verification` | `high-implementation-starter` が責務境界と移動を完了 | `shape_handoff_status = NotRequired`、STANDARD run は N/A、抽出後の behavior evidence |
| `INT-003` | async + retry + cancellation | `COMPLETED_BY_HIGH_MODEL -> verification` | HIGH が state ownership、retry、cancellation、error semantics を完了 | HIGH owner、runtime postcondition、forbidden-state evidence、STANDARD run は N/A |
| `INT-004` | 既存 pattern が明確な早期 STANDARD 委譲 | `READY_FOR_STANDARD_COMPLETION -> COMPLETED -> verification` | HIGH が representative production case と focused check を実行後、STANDARD が同型 remainder を完了 | `Pending -> Ready -> Consumed`、complete handoff、no write-owner overlap |
| `INT-005` | STANDARD 中の構造判断再発と HIGH re-entry | `READY_FOR_STANDARD_COMPLETION -> NEEDS_HIGH_MODEL_REENTRY -> COMPLETED_BY_HIGH_MODEL -> verification` | HIGH -> STANDARD -> HIGH | `Ready -> Invalidated -> NotRequired`、`shape_reentry_reason`、incremented re-entry count、HIGH return evidence |

### Surface expectations

| Surface | Start / completion / verification owner | Result and state evidence |
| --- | --- | --- |
| Plan Coverage | `high-implementation-starter` -> conditional `standard-implementation-completer` -> `verification-kernel` | `plans/<slug>-implementation-execution.md` に phase owner、verdict、Implementation Self-Map、checks、acceptance evidence、Remaining Work。Completion Handoff は通常 inline |
| full-coverage | 各非自明な READY slice ごとに HIGH -> conditional STANDARD -> HIGH re-entry、slice-local verification | slice 間は既存の非重複条件でのみ並列化し、各 slice 内 owner は直列。parent audit に HIGH-first、valid handoff、re-entry、owner non-overlap |
| Codex-first | `high-implementation-starter` -> conditional `standard-implementation-completer` -> `standard-verifier` | state の `current_status`、`selected_agent_name`、`recommended_model_tier`、`edit_owner` と4つの Adaptive fields、audit の observed-run evidence |
| Copilot fallback | `high-implementation-starter` -> conditional `standard-implementation-completer` -> `copilot-standard-verifier` | Codex-first 互換 state、Copilot frontmatter model/handoff、HIGH -> STANDARD -> HIGH discovery と serial ownership evidence |

### State transition oracle

| Phase | shape_handoff_status | selected_agent_name | recommended_model_tier | edit_owner | stop_reason |
| --- | --- | --- | --- | --- | --- |
| Authorized start | `NotStarted` / `Pending` | `high-implementation-starter` | `HIGH_MODEL` | `high-implementation-starter` | `ReadyForHighImplementationStart` |
| Valid bounded handoff | `Ready` | `standard-implementation-completer` | `STANDARD_MODEL` | `standard-implementation-completer` | `ReadyForStandardCompletion` |
| Handoff consumed | `Consumed` | `standard-implementation-completer` or verifier after completion | `STANDARD_MODEL` | current serial owner | next verification gate |
| Structural re-entry | `Invalidated` | `high-implementation-starter` | `HIGH_MODEL` | `high-implementation-starter` | `NeedsHighModelReentry` |
| Invalid handoff | `Blocked` | none / parent router | N/A | none | `BlockedByInvalidCompletionHandoff` |

`current_status` には各 phase の実 verdict をそのまま記録します。HIGH start と STANDARD completion はともに `DelegationRequired = Yes` です。`ParentDirectExecutionException` は明示承認付き互換例外として残しますが、cost-saving delegation 成功には数えません。

### 実モデル比較 runbook

1. 同じ source Plan、repository revision、acceptance criteria、検証環境を固定する。
2. 旧 single-pass route と Adaptive route で `INT-001` から `INT-005` を個別に実行する。
3. agent ごとの configured / observed model、input / output token、wall time、handoff verdict、re-entry count、changed files、checks を記録する。
4. 同じ human reviewer が、acceptance miss、production wiring miss、unnecessary structural change、review finding count を記録する。
5. 品質差、token cost、re-entry 回数、人間レビュー指摘数をシナリオ別と合計で比較する。静的 contract 合格だけから品質改善を推論しない。

| Run | Quality / acceptance | Token cost | Re-entry count | Human review findings | Status |
| --- | --- | --- | --- | --- | --- |
| Legacy single-pass baseline | 未計測 | 未計測 | 未計測 | 未計測 | `NOT RUN` |
| Adaptive HIGH -> STANDARD -> HIGH | 未計測 | 未計測 | 未計測 | 未計測 | `NOT RUN` |

実モデル比較は `NOT RUN` です。CI と static validation は routing contract を検証しますが、実証済みの品質改善や token cost 削減を宣言しません。

人手での作業が必要: 同一の Plan、revision、環境を固定して legacy / Adaptive の両 route を実モデルで実行し、同じ reviewer が品質、token cost、re-entry、review finding を記録してください。この実モデル比較は repository static contract の merge gate ではなく、品質改善を実証済みと宣言する前の運用 evidence gate です。

## Repository static validation

```powershell
./scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./scripts/install-adaptive-implementation-local.cs
git diff --check
```

The static validator checks the package layout and Windows path budget, standalone dependency avoidance, Plan Coverage independence, verdict contracts, custom agent fields and APM stub compatibility, manual-only Codex invocation policy, absence of package-owned repository-wide `AGENTS.md` guidance, integrated package versions and dependencies, Codex-first profile synchronization, state and audit transitions, Copilot handoffs, legacy compatibility notices, workflow path filters, root README entry, and presence of VAL-001 through VAL-013 and INT-001 through INT-005.

## Local validation result

Originally validated on 2026-07-13 with APM CLI 0.18.0 and a .NET 11 preview SDK targeting `net10.0`; Windows path, APM-generated stub, TOML-only installer, and `AGENTS.md` non-access regression checks were updated on 2026-07-16:

| Check | Result | Evidence |
| --- | --- | --- |
| Static package contract | PASS | `validate-adaptive-implementation-execution.ps1` |
| Static validator CI wiring | PASS | `validate-adaptive-implementation-execution.yml` invokes the package validator for relevant agent, package, workflow, and README changes |
| Full package local-path dry-run | PASS | APM accepted the package manifest and listed the local package install plan |
| File-based app publish | PASS | `dotnet publish install-adaptive-implementation-local.cs` |
| Skill local install | PASS | APM deployed `SKILL.md` and both `refs/*.md` files under `.agents/skills/adaptive-implementation-execution` |
| Custom agent dry-run / install / check | PASS | installer completed both `.codex/agents/*.toml` files without accessing `AGENTS.md`, then `--check` returned OK |
| APM-generated stub completion | PASS | fresh APM 0.18.0 Codex TOMLs containing only `name`, `description`, and `developer_instructions` were completed without `--force`; both model mappings were written and `--check` returned OK |
| Authored TOML collision | PASS | changing an installed model mapping preserved the authored value and made a no-force install fail without changing files |
| Distinct mapping negative check | PASS | changing the installed STANDARD_MODEL mapping to the HIGH_MODEL mapping made `--check` fail with `must use distinct model mappings`; restoring the package TOML returned OK |
| Custom agent remove dry-run / remove / remove-check | PASS | package-owned TOMLs were removed, then `--remove --check` returned OK |
| Remote branch package install | PASS | APM resolved the virtual package and both `git: parent` portable agents from `#codex/issue-45` at `66e1234b`, then deployed the skill, references, and both Codex agents |
| Remote rollback | PASS | `apm uninstall` removed the direct package and skill, custom agent removal deleted package-owned TOMLs, and `apm prune` removed both orphaned portable agent packages; no integrated skill, agent, or package files remained |
| Agent discovery contract | PASS | remote install created both named `.codex/agents` entries and the static validator confirmed that the skill routes to those names |
| Runtime multi-agent orchestration | NOT RUN | installation validation does not execute the skill and both implementation agents; this remains a separate Codex runtime validation |
| Full package local-path install | NOT APPLICABLE | APM 0.18.0 cannot inherit `git: parent` from a local path dependency; the supported remote repository route is validated separately above |

The full-package local-path limitation does not change the package manifest. The remote branch validation confirms that the `git: parent` convention resolves the root portable agents when APM installs the repository subdirectory package.
