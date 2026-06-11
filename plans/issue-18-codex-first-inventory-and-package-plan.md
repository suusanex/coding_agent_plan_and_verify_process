# Issue 18: Codex-first process pack inventory and package plan

## Source

- GitHub Issue: https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/18
- Related GitHub Issue: https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/19
- source_workitem: `workitems/running/codex-first-ai-development-process-pack-repo-inventory-and-package-plan-01.yaml`
- management_repo: `suusanex/personal-project-driver`
- project_id: `codex-first-ai-development-process-pack`

## Goal

`coding_agent_plan_and_verify_process` の既存資産を棚卸しし、Codex-first process pack として何を再利用し、何を追加し、どの順序で実装するかを明確にする。

この Plan は Issue #19 の `codex-first-cost-router` MVP を実装・補強するための前提 artifact として扱う。

## Non-goals

- Hook 監査の本体実装
- Skill / `AGENTS.md` / agent instructions による強制力アップの本格実装
- plugin trust / 社内配布の最終決定
- GitHub Copilot fallback 版の追加実装
- 社内モデル実名対応表の決定
- 外部サービス、課金、GitHub 設定、secret、社内環境設定の変更

## Existing Asset Inventory

| Area | Current assets | Reuse decision |
| --- | --- | --- |
| Repository overview | `README.md` | Codex-first の入口、package 選択、READY / close gate、model tier、導入スクリプト説明を再利用する。Issue #19 では不足分だけ補う。 |
| Root Codex config | `.codex/config.toml` | この repository 自身の Codex 実行境界として再利用する。package 配布物ではなく repo-local default として扱う。 |
| Existing kernel agents | `.github/agents/*.agent.md` | Plan網羅チェック・残件判定フロー、full-coverage decomposition、verification / residual gate の source of truth として再利用する。Codex-first package に本文コピーしない。 |
| Codex-first package | `apm-packages/codex-first-ai-development-process/` | Codex-first process pack の主対象。Issue #19 MVP の入口、docs、templates、profiles、installer をここへ集約する。 |
| Codex-first skill | `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md` | MVP 入口として再利用する。task weight / route decision の文書側補強をこの skill と整合させる。 |
| Codex-first package instructions | `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md` | repository-local `AGENTS.md` と組み合わせる導入指示として再利用する。 |
| Codex-first state template | `apm-packages/codex-first-ai-development-process/templates/codex-first-state.md` | state artifact の expected shape として再利用する。Issue #19 の required fields をすでに多く満たしている。 |
| Stop report template | `apm-packages/codex-first-ai-development-process/templates/stop-report.md` | READY 前停止、人間判断待ち、higher-model stop の報告形式として再利用する。 |
| Model tier mapping example | `apm-packages/codex-first-ai-development-process/templates/model-tier-mapping.example.md` | HIGH / STANDARD / CHEAP の抽象 label と実名 model 対応の分離例として再利用する。 |
| Codex profile templates | `apm-packages/codex-first-ai-development-process/profiles/codex-first/` | Codex-readable `config.toml` と custom agent TOML の配布元として再利用する。 |
| Local installer | `apm-packages/codex-first-ai-development-process/scripts/install-codex-first-local.cs` | repo-local bootstrap 手段として再利用する。APM 実行を前提にしない MVP 導入経路にする。 |
| Temporary launcher | `apm-packages/codex-first-ai-development-process/scripts/codex-first-start.ps1` | 一時的な `CODEX_HOME` 切替用として維持するが、標準導入は local installer を優先する。 |
| Codex-first docs | `apm-packages/codex-first-ai-development-process/docs/*.md` | user guide / maintainer guide / advanced route / bootstrap policy を再利用する。Issue #19 の task weight と sample routing を補強する。 |
| Codex-first examples | `apm-packages/codex-first-ai-development-process/docs/examples/*.md` | 初心者向け利用例の土台として再利用する。軽量サンプル入力と期待 Routing Plan 例を追加する。 |
| Full-coverage 3 layer package | `apm-packages/token-aware-full-coverage-3layer/` | advanced route の既存実装として再利用する。Codex-first 標準ルートへ昇格しない。 |
| Plan coverage package | `apm-packages/token-aware-guardrail-kernel-flow/` | standard route 内で必要に応じて参照する kernel flow として再利用する。 |
| Full autonomous package | `apm-packages/full-autonomous-plan-first-flow/` | compatibility / 熟練 operator 向けの既存資産として維持する。Codex-first MVP の標準ルートにはしない。 |
| Copilot fallback package | `apm-packages/copilot-fallback-ai-development-process/` | 後続展開用の比較対象として維持する。Issue #19 では変更しない。 |
| Hook-related guidance | `README.md`, `docs/codex-full-coverage-3layer-fixes.md`, Codex-first maintainer guide | 補助証跡の設計メモとして再利用する。Hook監査の本体実装は後続 WorkItem に分離する。 |

## Reusable Concepts and Vocabulary

| Concept | Reuse source | Decision |
| --- | --- | --- |
| Parent Plan coverage | Plan網羅チェック・残件判定フロー | Codex-first route の Plan / verification / close で維持する。 |
| Guardrail Focus | Plan網羅チェック・残件判定フロー | deep-check subset として扱い、implementation scope の縮小には使わない。 |
| Residual Decision Gate | Plan網羅チェック・残件判定フロー | close 前に unresolved residual を explicit decision へ分離する語彙として再利用する。 |
| full-coverage 3 layer | `token-aware-full-coverage-3layer` | standard route ではなく advanced route として再利用する。 |
| Routing Plan | Codex-first state | task weight、model tier、delegation owner、READY / stop を表す中心 table として再利用する。 |
| Edit Permission | Codex-first state | READY 前停止と edit owner 明示に使う。 |
| Agent Usage Ledger | Codex-first state | expected / observed delegation と model observability の主証跡にする。 |
| DelegationCompliance | Codex-first state | implementation / verification delegation evidence の close gate にする。 |
| HIGH_MODEL / STANDARD_MODEL / CHEAP_MODEL | Codex-first docs / profile | 抽象 label として維持し、実名 model は mapping file / profile で差し替える。 |
| ParentDirectExecutionException | Codex-first docs / skill | required delegation を親が直接実行する例外として維持する。explicit human approval が必要。 |

## New or Reinforced Assets

| Asset | Issue | Action |
| --- | --- | --- |
| `plans/issue-18-codex-first-inventory-and-package-plan.md` | #18 | 追加する。棚卸し、実装順、責務分担、MVP境界、人間判断項目を記録する。 |
| `apm-packages/codex-first-ai-development-process/docs/cost-router-goals.md` | #19 | task weight classification と route decision conditions を明文化する。 |
| `apm-packages/codex-first-ai-development-process/docs/examples/routing-mvp-sample.md` | #19 | 軽量サンプル入力と期待 Routing Plan / state excerpt を追加する。 |
| `apm-packages/codex-first-ai-development-process/docs/user-guide.md` | #19 | MVP sample への導線を追加する。 |

## Recommended Implementation Order

1. Inventory and package plan
   - Create the Issue #18 artifact under `plans/`.
   - Confirm package ownership and source-of-truth boundaries.
   - Separate MVP scope from later enforcement, hook audit, plugin, and Copilot fallback work.

2. Codex-first cost-router MVP
   - Reuse the existing `codex-first-cost-router` skill, state template, profile agents, installer, and user guide.
   - Add explicit task weight classification and routing branch conditions.
   - Add sample input and expected Routing Plan output.

3. Manual validation
   - Run text consistency checks.
   - Run installer `--dry-run` or `--check-only` when .NET SDK availability permits.
   - Confirm no root package ownership drift is introduced.

4. Enforcement hardening
   - Strengthen `AGENTS.md`, package instructions, and agent docs so ordinary requests enter Codex-first routing automatically.
   - Keep this separate from the MVP so the route can be tested before stronger enforcement.

5. Hook audit
   - Implement optional `SubagentStart` / `SubagentStop` logging.
   - Add write-heavy edit detection before READY.
   - Treat hook logs as supplemental evidence; keep Agent Usage Ledger as the primary repo-tracked evidence.

6. Plugin / APM distribution hardening
   - Finalize packaged metadata, install/update path, trust boundary, and release checklist.
   - Do not mix this with MVP behavior changes.

7. GitHub Copilot fallback follow-up
   - Reuse shared state vocabulary and gate policy.
   - Keep Copilot-specific model labels and VS Code `.github/` layout separate.

## Skill / AGENTS / Agent Instructions / Hook Responsibility Split

| Layer | Responsibility | Not responsible for |
| --- | --- | --- |
| `codex-first-cost-router` skill | Intake, source-of-truth detection, task weight, selected process, model tier recommendation, edit permission, state artifact, stop reason, next action | Hard blocking at runtime, external service operations, real model mapping decisions |
| Package `AGENTS.md` / profile `AGENTS.md` | Default behavior and prohibition wording for Codex-first route | Repo-specific build/test/security rules |
| Repo-local `AGENTS.md` in target repository | Local rules, safety constraints, and managed Codex-first section | Replacing package docs or hiding local rules |
| `.codex/agents/*.toml` profile | Configured execution defaults for high / standard / cheap agent roles | Proof that the effective runtime or billing model matched the configured value |
| `templates/codex-first-state.md` | Stable state artifact shape and ledger columns | Real-time hook collection |
| Hook audit | Supplemental observation of subagent start/stop, model payload, changed files, and ready-before-edit anomalies | Primary close decision, accepted residual decisions, or model tier policy |
| Maintainer docs | Release checklist, mapping review, package ownership, and rollout notes | Runtime enforcement |

## MVP Scope

MVP includes:

- Manual `$codex-first-cost-router` entrypoint.
- Task weight and route decision rules.
- Routing Plan and state artifact expected shape.
- READY-before-implementation stop behavior.
- Edit owner and DelegationRequired output.
- Agent Usage Ledger placeholder.
- Abstract HIGH / STANDARD / CHEAP model tier labels.
- Beginner-facing usage guidance.
- Lightweight sample input and expected Routing Plan example.
- Clear separation of advanced full-coverage route.

MVP does not include:

- Hook-based blocking.
- Automatic prevention of parent-direct edits.
- Mandatory plugin trust or install flow.
- Organization-specific real model mapping.
- Copilot fallback implementation changes.
- Production, billing, secret, external service, or GitHub settings changes.

## Follow-up WorkItem Candidates

| Candidate | Purpose | Suggested status |
| --- | --- | --- |
| sample-validation | Run the MVP sample against a real target repo and capture expected state artifact output. | ready after MVP merge |
| enforcement-hardening | Strengthen `AGENTS.md`, package instructions, and agent prompts so Codex-first routing is harder to bypass. | proposed |
| hook-audit | Add optional hook logging and READY-before-write-heavy detection. | proposed / human-required for block scope |
| plugin-package | Finalize package metadata, install/update flow, trust boundary, and release checklist. | proposed / human-required for trust |
| copilot-fallback-sync | Align fallback docs and prompt files after Codex-first MVP stabilizes. | proposed |

## Human-required Items

| Item | Why human-required | MVP substitute |
| --- | --- | --- |
| First internal rollout repository | It depends on management repo priority and team readiness. | Use public/sample validation only. |
| HIGH_MODEL / STANDARD_MODEL / CHEAP_MODEL real mapping | It depends on contract, pricing, availability, and quality policy. | Keep abstract labels and example mapping. |
| Hook block scope | Blocking edits can interrupt legitimate work and needs operator policy. | Document hook as supplemental evidence only. |
| Plugin trust / distribution | It affects local execution trust and install/update semantics. | Keep package files and local installer path. |
| Copilot fallback conditions | It depends on team environment and Codex availability policy. | Keep fallback package separate. |

## Issue 19 Sequencing Decision

Issue #18 and Issue #19 should be implemented in one continuous branch because Issue #19 depends on the inventory result, and the current repository already contains most MVP assets.

The safe sequence is:

1. Land this Issue #18 inventory artifact.
2. Patch the existing Codex-first MVP docs with task weight and route decision details.
3. Add one concrete MVP sample artifact.
4. Validate text and package consistency.

If later validation finds that the MVP entrypoint must move or be renamed, update the package and docs together before closing Issue #19.

## Result Reporting for Management Repo

suggested_management_status: `ready_for_review`

remaining_work:

- Validate the MVP sample in a real target repository after merge.
- Decide whether enforcement hardening should be a mandatory default or an optional managed section.
- Decide hook block scope before implementing runtime audit / block behavior.
- Decide plugin trust and distribution path before packaging for broader rollout.
- Decide internal model mapping outside this repository.

human_required_items:

- First internal rollout repository.
- Real model mapping for HIGH_MODEL / STANDARD_MODEL / CHEAP_MODEL.
- Hook blocking policy.
- Plugin trust / distribution policy.
- Copilot fallback activation conditions.
