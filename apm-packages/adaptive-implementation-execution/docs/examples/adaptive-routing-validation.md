# Adaptive Routing Validation

この文書は `adaptive-implementation-execution` の routing contract を検証するシナリオです。各 scenario は、input、observed evidence、expected route、禁止事項を記録できる形にします。

## Common evidence

実行 validation では次を保存します。

- source Plan / Implementation Intent
- original Implementation Intent artifact path or durable snapshot
- agent verdict sequence
- implementation owner by phase
- files changed by each agent
- validation commands and results
- acceptance status and evidence for every in-scope item
- handoff persistence
- requested / observed model for Copilot runs
- re-entry handoff, if any
- final review status

## VAL-001: Early delegation

Input:

- code、wiring、signatures、call sites、testsから非局所decisionを閉じられる
- HIGH_MODELのproduction/test editは不要
- production implementation、wiring、testsを含むmeaningfulなWork Packageが残る

Expected:

```text
READY_FOR_STANDARD_COMPLETION -> COMPLETED
```

Checks:

- handoff records `HIGH_MODEL code changes: No` and `Delegation basis: non-local-decisions-closed`
- every Decision closure concern is `Locked` or evidence-backed `N/A`
- Work Packages name responsibility, authorized surface, expected behavior, locked boundaries, local freedom, and completion check
- Allowed edit surface contains every Work Package surface as an envelope
- every Incomplete acceptance item and Remaining work row has a bidirectional Work ID mapping, no Blocked item exists, and every Complete item has evidence
- STANDARD_MODEL owns production implementation, tests, and validation without changing locked boundaries

## VAL-002: Mid-implementation delegation

Input:

- class responsibility、signature、DI strategy/location/lifetime、state/error/cancellation/retry semantics、test architecture require decisions
- HIGH_MODEL locks those decisions from actual code evidence
- class/interface files、method bodies、DI registration、tests remain

Expected:

```text
READY_FOR_STANDARD_COMPLETION -> COMPLETED
```

Checks:

- locked decisions include responsibility, wiring, signature, and test seam
- STANDARD_MODEL creates the locked class/interface, implements wiring and behavior, and writes tests

## VAL-003: HIGH_MODEL completes

Input:

- state ownership, error handling, and API shape decisions continue through implementation
- implementation itself is required to close those non-local decisions

Expected:

```text
COMPLETED_BY_HIGH_MODEL
```

Checks:

- no artificial skeleton or broken intermediate state is created for delegation
- HIGH_MODEL records completed scope and checks
- `Direct completion reason: design-implementation-inseparable` and concrete evidence are present
- every in-scope acceptance item is Complete with implementation or validation evidence
- `COMPLETED_BY_HIGH_MODEL` includes unchanged `implementation_route`, `implementation_route_source`, and the Design Pair handoff path or `N/A`

## VAL-004: Re-entry from STANDARD_MODEL

Input:

- HIGH_MODEL initially delegates through a handoff that has passed authorization
- STANDARD_MODEL discovers that the locked signature, wiring architecture, semantics, or test architecture must change

Expected:

```text
READY_FOR_STANDARD_COMPLETION
  -> NEEDS_HIGH_MODEL_REENTRY
  -> high-implementation-starter resumes
```

Checks:

- STANDARD_MODEL implements locked class/interface/wiring without re-entry and does not redesign locked boundaries
- `NEEDS_HIGH_MODEL_REENTRY` is emitted only when a locked non-local decision must change after valid authorization, never for an edit type or invalid route metadata
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

- package has no dependency on Plan Coverage, full-coverage, or other process packages

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

1. Install the package with APM 0.26.0 for `copilot,codex,agent-skills`.
2. Confirm skill and both reference templates are deployed.
3. Confirm both portable agents are available to Codex and GitHub Copilot Chat in VS Code.
4. If APM leaves model-less custom agent TOMLs, complete their settings with `install-adaptive-implementation-local.cs`.
5. Run installer `--check`.
6. Confirm Codex can select the skill and both custom agents; confirm Copilot agent frontmatter requests Terra for HIGH / re-entry and Luna for STANDARD.
7. Confirm the installer does not access an existing `AGENTS.md`, and review collision behavior with same-name TOML.
8. Dry-run APM uninstall, custom agent configuration removal, and orphan prune before rollback.

Expected:

- skill, refs, portable agents, both TOML sources, and docs are present in the package
- installed skill refs are available under `.agents/skills/adaptive-implementation-execution/refs`
- concrete agent TOMLs contain model, reasoning effort, and workspace-write sandbox fields
- HIGH_MODEL and STANDARD_MODEL use different custom agent names and different model mappings
- the local installer sources only the two package `codex-agents/*.toml` files and writes only target `.codex/agents/*.toml` files
- the local installer does not copy or update root `.github/agents/*.agent.md` files or the Skill
- the installer does not create, read, update, or remove `AGENTS.md`
- APM-generated model-less stubs with matching package metadata are completed without `--force`
- other same-name TOML collisions fail closed unless `--force` is explicit
- pre-existing unmanaged `.github/agents` customization is preserved without `--force`
- a frozen reinstall leaves package-managed skill and agent content unchanged

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

- Codex CLI or an APM target uses the packaged HIGH and STANDARD TOMLs without repository-local `.github/agents`

Expected:

- both portable agents accept only `adaptive / default` with an explicit `N/A` path or `design-pair / explicit-user-selection` with the current tracked path
- either missing field, a contradictory pair, or Design Pair evidence mismatch returns `BLOCKED` with `BlockedByInvalidCompletionHandoff` before editing
- `design-pair` requires the current Design Pair Implementation Handoff path and never falls back to Adaptive
- STANDARD_MODEL preserves the route pair and Design Pair handoff path in every High-model Re-entry Handoff
- both agents return the complete route identity on every non-invalid result
- invalid-artifact `BLOCKED` returns raw observed values or `<missing>` plus repair evidence instead of fabricating a complete identity
- STANDARD_MODEL reserves `NEEDS_HIGH_MODEL_REENTRY` for evidence that a locked non-local decision must change after a valid handoff passes authorization

## VAL-013: GitHub Copilot VS Code package configuration

Input:

- APM 0.26.0 installs the package for `copilot,codex,agent-skills` from a full commit SHA
- VS Code loads both repository-local custom agents

Expected:

- `high-implementation-starter` omits `tools` so Copilot uses its default tool set and APM does not produce a lossy Codex agent compilation; it has `model: GPT-5.6 Terra (copilot)`, `target: vscode`, `disable-model-invocation: true`, and a single bounded-completion handoff to `standard-implementation-completer`
- `standard-implementation-completer` omits `tools` for the same reason; it has `model: GPT-5.6 Luna (copilot)`, `target: vscode`, `disable-model-invocation: true`, and a single structural re-entry handoff to `high-implementation-starter` using Terra
- both agents remain user-invocable in the picker but are unavailable for model-decided subagent invocation
- STANDARD direct start is rejected without a valid tracked `READY_FOR_STANDARD_COMPLETION`
- `COMPLETED_BY_HIGH_MODEL` and stop verdicts do not route to another agent
- Copilot model / agent transitions use tracked completion and re-entry artifacts containing original Implementation Intent, unchanged route identity, Locked Decisions, Design Pair Decision IDs when present, and current worktree state
- the local installer sources the two package `codex-agents/*.toml` files and writes only target `.codex/agents/*.toml` files; APM installs the Skill and root `.github/agents` files
- executable scenarios A-J in `tests/routing-scenarios.json` are interpreted by `tests/validate-routing-scenarios.ps1`; negative mutations reject invalid HIGH completion, incomplete handoff acceptance, ambiguous or missing reference handoffs, unknown Decision closure concerns, unsupported acceptance status, asymmetric acceptance / Work ID edges, edit-type-only re-entry with otherwise valid tracked state, incomplete re-entry state, repeated delegation without surface reduction, implicit route defaulting, and locked Design Pair decision changes
- GitHub Copilot CLI real-model execution is `PASS` for Terra direct completion, Terra-to-Luna bounded completion, Luna-to-Terra structural re-entry, invalid handoff rejection, selected agent / model evidence, files, checks, terminal verdicts, and absence of unexpected automatic transitions; see `copilot-cli-real-model-e2e-2026-07-31.md`
- VS Code-specific `target` filtering and handoff-button behavior remain `NOT RUN` and use the manual smoke template

## Standalone Adaptive integration validation matrix

次のシナリオは standalone Adaptive package の implementation-only routing surface を検証します。`trivial-local` は対象外です。final verification は caller の別工程であり、この matrix の owner または expected sequence に含めません。

| ID | Scenario | Expected verdict sequence | Expected implementation owner sequence | Required state / audit evidence |
| --- | --- | --- | --- | --- |
| `INT-001` | 新規 service + DI + tests | `READY_FOR_STANDARD_COMPLETION -> COMPLETED` | HIGHがservice contract、DI strategy/location/lifetime、test seam strategyをlockし、STANDARDがclass/interface、wiring、testsを実装 | zero/minimal HIGH LOC、Decision closure、Work Packages、STANDARD implementation share |
| `INT-002` | 大きな class からの責務分離 | `READY_FOR_STANDARD_COMPLETION -> COMPLETED` | HIGHがextraction boundary、ownership、contractをlockし、STANDARDがcode moveとtestsを実装 | boundary evidence、serial owner、locked contract compliance |
| `INT-003` | async + retry + cancellation | `READY_FOR_STANDARD_COMPLETION -> COMPLETED` | HIGHがstate ownership、retry、cancellation、error semanticsをlockし、STANDARDがimplementationとtestsを担当 | runtime postconditions、forbidden-state evidence、locked semantics compliance |
| `INT-004` | 既存 pattern が明確な早期 STANDARD 委譲 | `READY_FOR_STANDARD_COMPLETION -> COMPLETED` | HIGHがcode inspectionだけでdecision closureし、STANDARDがproduction/test実装を主体的に完了 | `HIGH_MODEL code changes: No`、local freedom evidence、no write-owner overlap |
| `INT-005` | locked non-local decisionの無効化と HIGH re-entry | `READY_FOR_STANDARD_COMPLETION -> NEEDS_HIGH_MODEL_REENTRY -> COMPLETED_BY_HIGH_MODEL` | HIGH -> STANDARD -> HIGH | invalidating evidence、incremented re-entry count、`post-reentry-high-ownership` evidence |

### Surface expectations

| Surface | Start / completion owner | Result and state evidence |
| --- | --- | --- |
| Standalone Adaptive | `high-implementation-starter` -> conditional `standard-implementation-completer` -> optional HIGH re-entry | route identity、Completion / Re-entry Handoff、serial owner、production wiring evidence。completion後のfinal review / independent verification は caller が別工程で扱う |

### State transition oracle

| Phase | canonical route identity | handoff / verdict evidence | serial owner | stop_reason |
| --- | --- | --- | --- | --- |
| Authorized start | incoming `implementation_route` / `implementation_route_source` / Design Pair handoff path unchanged | Parent Authorization and Implementation Intent | `high-implementation-starter` | `ReadyForHighImplementationStart` |
| Valid bounded handoff | unchanged incoming identity | `READY_FOR_STANDARD_COMPLETION` with tracked Completion Handoff | `standard-implementation-completer` | `ReadyForStandardCompletion` |
| Handoff consumed | unchanged incoming identity | consumed Completion Handoff and implementation result returned to the caller | current serial owner | ImplementationCompleted |
| Structural re-entry | unchanged incoming identity | `NEEDS_HIGH_MODEL_REENTRY` with tracked Re-entry Handoff | `high-implementation-starter` | `NeedsHighModelReentry` |
| Invalid handoff | raw observed identity or `<missing>` | `BLOCKED` with artifact repair evidence | parent router | `BlockedByInvalidCompletionHandoff` |

各 phase の verdict と route identity は Completion / Re-entry Handoff にそのまま記録します。HIGH start、STANDARD completion、re-entry は同じ Adaptive route identity を保持し、owner は常に serial に進みます。implementation completion 後は caller に戻り、この flow は final verification を所有しません。

### 実モデル比較 runbook

1. 同じ source Plan、repository revision、acceptance criteria、検証環境を固定する。
2. standalone Adaptive route で `INT-001` から `INT-005` を個別に実行する。
3. agentごとのconfigured / observed model、input / output token、wall time、handoff verdict、re-entry count/category、changed files/LOC/test LOC、checksを記録する。clientがtokenを公開しない場合は`Unavailable`と理由を記録する。
4. 同じ human reviewer が、acceptance miss、production wiring miss、unnecessary structural change、review finding count を記録する。
5. 品質、token cost、re-entry 回数、人間レビュー指摘数を記録する。静的 contract 合格だけから品質改善を推論しない。

| Run | Eligible / STANDARD started | HIGH / STANDARD LOC share | Direct completion reason | Quality / acceptance | Token cost | Re-entry count / category | Human review findings | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Standalone Adaptive HIGH -> STANDARD -> HIGH | 未計測 | 未計測 | 未計測 | 未計測 | 未計測 | 未計測 | 未計測 | `NOT RUN` |

初期観測目安は、中規模以上のeligible taskでSTANDARD start rate 50–70%以上、delegated taskでSTANDARD changed LOC share 50%以上、re-entry 20%以下、quality baseline非劣性です。使用率そのものは品質指標またはmerge gateにしません。

実モデル run は `NOT RUN` です。CI と static validation は routing contract を検証しますが、実証済みの品質改善や token cost 削減を宣言しません。

人手での作業が必要: 同一の Plan、revision、環境を固定して standalone Adaptive route を実モデルで実行し、同じ reviewer が品質、token cost、re-entry、review finding を記録してください。この実モデル run は repository static contract の merge gate ではなく、品質改善を実証済みと宣言する前の運用 evidence gate です。

## Repository static validation

```powershell
./scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./scripts/install-adaptive-implementation-local.cs
git diff --check
```

The static validator checks the package layout and Windows path budget, standalone dependency avoidance, Plan Coverage independence, verdict contracts, custom agent fields and APM stub compatibility, absence of package-owned repository-wide `AGENTS.md` guidance, integrated package versions and dependencies, portable Codex configuration synchronization, route identity and handoff transitions, Copilot configuration and handoffs, legacy compatibility notices, workflow path filters, root README entry, and presence of VAL-001 through VAL-008 and INT-001 through INT-005.

## Local validation result

The historical Codex checks below were first recorded with APM 0.18.0. The Copilot package configuration work targets APM 0.26.0; current results must be recorded from the commands in this document rather than inferred from the historical rows.

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
| Copilot frontmatter and executable scenarios | PASS | the validator checks canonical agents, tracked projections, and the package local installer, then executes the schema-v3 A-J state machine and negative mutations |
| APM 0.26.0 local package-configuration install | PASS | a temporary dependency composed from the root agents and packaged Skill deployed Copilot agents, Codex stubs, and the shared Skill; frozen reinstall preserved hashes, the Codex helper completed and checked both model mappings, and an unmanaged same-name Copilot agent was preserved without `--force` |
| APM 0.26.0 pinned remote install smoke | PASS | the disposable Copilot CLI E2E installed the package from full commit `816268eea12ae4e61a40f045de9448d180ef4a2c`; CI also runs `validate-adaptive-implementation-apm-smoke.ps1` |
| Historical GitHub Copilot CLI real-model orchestration for 0.4.0 | PASS | `copilot-cli-real-model-e2e-2026-07-31.md` records the former representative-path-first contract and remains historical evidence only |
| GitHub Copilot CLI real-model orchestration for 0.5.0 | NOT RUN | `copilot-cli-real-model-e2e-2026-08-09.md` requires a candidate remote ref and must observe zero/minimal HIGH implementation, STANDARD implementation ownership, local autonomy, and locked-boundary re-entry |
| GitHub Copilot Chat in VS Code UI smoke | NOT RUN | follow `copilot-manual-smoke.md` only for VS Code-specific agent picker, `target` filter, and handoff-button coverage; real-model routing itself is covered by the CLI E2E |
| Runtime multi-agent orchestration for 0.5.0 | NOT RUN | the 2026-07-31 record must not be reused as evidence for the new semantics |
| Full package local-path install | NOT APPLICABLE | APM 0.26.0 cannot inherit `git: parent` from a local path dependency; the supported remote repository route is validated separately above |

The local package-configuration smoke validates current transformation and collision behavior but does not replace the pinned remote smoke for the real `git: parent` dependency graph. The full-package local-path limitation does not change the package manifest. The remote branch validation confirms that the `git: parent` convention resolves the root portable agents when APM installs the repository subdirectory package.
