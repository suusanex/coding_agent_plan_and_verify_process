# Implementation Contract Kernel: SL-002

## スコープ

`SL2-RC-001`〜`SL2-RC-003`について、same-parent review/remediation normal pathの実装判断を固定する。通知runtime consumerは実装せず、`XC-001` / `XC-002`はcross-slice verificationまでDeferredとする。

## Plan が要求する実装要件

| Requirement | Expected by Plan | Evidence found | Status |
| --- | --- | --- | --- |
| one-operation intake | 親threadからrepository、Ready PR、Goal Contextを解決し、欠落・曖昧なら具体的にBlocked。 | Goal Context selectorはexact/unique selectionを検証し、collectorはReady PR identityを検証する。 | Confirmed |
| round 1 independent review | Copilot、local、purposeのraw outputをcurrent headへ結び付ける。 | collector、read-only reviewer profiles、review-plannerの契約が存在する。 | Confirmed |
| parent-only remediation | reviewerはread-onlyで、親が修正・検証・current head更新を担う。 | reviewer agent/TOMLはread-only。architectureがparent single writerを定義する。 | Confirmed |
| rounds 2/3 purpose-only | local reviewとCopilot waitを再実行せず、active/resolved IDsをcurrent `PUR-*` evidenceで遷移する。 | manager/planner contractにpurpose-only validationがある。 | Confirmed |
| normal-path migration | fixed two-task/manual handoffをnormal Goal Context pathから外し、APM/docs/validators/fixturesを同期する。 | 現在Skill/README/managerは固定二taskをauthorityとしており、変更対象が確認できる。 | Confirmed |
| terminal enrichment | status/title/current PR URIだけをoptional projectionへ渡し、thread identityを含めない。 | architecture `ARC-RC-009` / `XC-001`がfield authorityを定義する。 | Confirmed |

## Dependency と API surface の確認結果

| Dependency / API / symbol | Expected source | Found location | Status | Notes |
| --- | --- | --- | --- | --- |
| canonical Goal Context selection | selected validated document, no Issue substitute | `goal-context-pr-review/scripts/select-goal-context.cs` and Skill | Confirmed | missing/ambiguous/unreadable selection is Blocked. |
| Ready PR / current patch authority | `TargetIdentity`, remote patch, head drift rejection | `collect-pr-review-context.cs` | Confirmed | auto-resolution must occur before invoking the collector. |
| read-only reviewers | local/purpose reviewer agent contracts and TOMLs | `.github/agents/*reviewer.agent.md`, `codex-agents/*.toml` | Confirmed | sandbox must remain `read-only`. |
| purpose-only round validation | round mode, source coverage, tracking IDs | `manage-review-cycle.cs`, review-planner contract | Confirmed | existing fixed role-task binding is not reusable as normal-path authority. |
| auto-created same-parent run root / `run-summary.md` | architecture `AR-003` | no concrete production implementation address found | MissingButRequired | implementation must establish a package-owned address under the orchestrator run root. |
| parent remediation commit/push/check command | architecture `AR-004` | repository rules and current PR workflow, not a package API | ApiSurfaceUnknown | implementation owner must select commands under target-repository rules without changing single-writer semantics. |
| terminal envelope projection | compatible Skill terminal projection | existing decorator envelope is an adjacent compatibility path | RejectedSubstitute | Decorator must not become required; normal path needs its own optional safe projection. |

## 選択した実装アプローチ

1. `goal-context-pr-review`をcanonical same-parent entryへ更新し、短い起動からrepository、Ready PR、Goal Contextを解決してpackage-owned run rootを作成する。
2. collectorはcurrent remote PR identity/patch authority、selectorはGoal Context identity authority、reviewer raw outputsはfinding evidence authorityとして再利用する。
3. round 1はcollectorのCopilot collectionとlocal/purpose read-only reviewersを独立に起動する。round 2/3はcollectorの`--no-wait-for-copilot`とpurpose reviewerだけに限定する。
4. parentのみがauthorized findingsを修正・検証・PR head更新する。new headを確認できなければpurpose rerunしない。
5. run summaryはround、reviewed head OID、Goal Context path、raw artifact index、active/resolved/NeedsHumanDecision finding IDs、mandatory-source coverage、terminal verdictを保持する。raw evidenceがsummaryより優先する。
6. terminal projectionは`schema_version`、terminal status、安全なtitle、current PR HTTPS URIだけを生成する。callback identityは生成・受領・上書きしない。

## 必要なコード変更

| Surface | Required change | Verification hook |
| --- | --- | --- |
| `goal-context-pr-review/SKILL.md` and usage/design references | same-parent one-operation canonical flow、round limits、Blocked/HumanDecision terminal handling、non-goalsを記述する。 | canonical invocation and forbidden fixed-handoff assertions. |
| same-parent orchestration / run-summary implementation | auto-resolution、raw artifact paths、round/finding state、parent-only remediation transition、terminal projectionを実装する。 | deterministic state fixtures and current-head rejection. |
| `collect-pr-review-context.cs` integration boundary | explicit repo/PR remains collector API; caller resolves them automatically and binds declared remote patch. | Ready/Draft/head-drift fixtures. |
| reviewer prompts/profiles and sync helper | read-only profiles、round-2 purpose-only input、raw output contractを維持する。 | TOML/profile sync and reviewer ownership validation. |
| `apm.yml`, package/root docs, validators, fixtures | normal path and installed profile/package contractを同期し、fixed two-task materialをlegacy-onlyへ縮退する。 | package validator, APM smoke, deterministic fixtures, publish. |

## 禁止される代替実装

| Similar existing path | Why it is not sufficient | Allowed reuse, if any |
| --- | --- | --- |
| fixed Review/Implementation Thread `manage-review-cycle` path | user must supply/preserve two role task IDs and separately resume them; this violates `REV-001` / `REV-012`. | round mode, source coverage, artifact-role, head-drift, and finding-transition rules only. |
| `$completion-notification-decorator` required input | parent Plan forbids making decorator selection a prerequisite for normal notification. | compatible optional envelope shape only, if it preserves `XC-001` authority. |
| baseline `$pr-review-remediation` on Goal Context failure | it omits independent purpose review and cannot substitute for selected Goal Context. | collector/templates only when Goal Context boundary remains enforced. |
| text-similarity finding reconciliation | architecture requires explicit raw-evidence tracking IDs. | none. |

## 検証フック

- static Skill/profile/manifest/README validator for one-operation, read-only, purpose-only, no round 4, and no mandatory Decorator/fixed-task contract.
- deterministic fixture/replay for current head, mandatory source coverage, finding transitions, blocked/human/complete decisions, and safe terminal projection.
- package install/profile sync/APM smoke and File-based App publish.
- manual real-model smoke for independent reviewer execution and manual cross-slice notification observation.

## 未解決の実装実現性項目

| Item | Status | Handling |
| --- | --- | --- |
| package-owned concrete same-parent orchestration/run-summary source address | MissingButRequired | resolve in implementation before code write; do not rebrand two-task manager as this address. |
| target-repository remediation commit/push/check command | ApiSurfaceUnknown | choose under repository rules during authorized implementation; preserve parent single writer. |
| real reviewer/subagent callback hierarchy and notification count | ManualOnly | defer as `XC-002`; no static hierarchy filter may be claimed. |
| terminal projection consumer behavior | Deferred | `XC-001` consumer is owned by SL-001 and verified cross-slice. |

## Self-check / Readiness verdict

READY_FOR_RUNTIME_CONTRACT

## Self-check evidence

| Checkpoint | Evidence | Status | Notes |
| --- | --- | --- | --- |
| Parent/slice boundaries preserved | SL-002 bounded Plan and decomposition | Done | no notification consumer or cross-slice close claimed. |
| Required path identified | Skill, collector, manager, profiles, package surfaces | Done | same-parent orchestrator implementation address remains deliberately explicit. |
| Nearby substitutions classified | two-task manager, Decorator, baseline Skill | Done | all unsafe normal-path substitutions rejected. |
| Production wiring identified | APM manifest, sync helper, docs/validators | Done | binding requires downstream verification. |
| Shared semantics | Slice Architecture revision 1 | Done | no new owner, state, identity, or precedence introduced. |

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: parent Plan, behavior spec, parent triage, readiness R2, Slice Architecture, decomposition, SL-002, SL-002 triage.
- Selected contracts / IDs: `SL2-RC-001`, `SL2-RC-002`, `SL2-RC-003`; `XC-001` / `XC-002` Deferred.
- Files inspected: Goal Context/base Skills, collector, manager, reviewer contracts/profiles, manifest, sync helper, package validators and docs.
- Files intentionally not inspected: unrelated code/packages, full fixture bodies, live external services.
- Decisions made: same-parent caller owns auto-resolution and run summary; collector/selector/raw evidence retain their specified authority; parent is sole writer.
- Do not redo unless new evidence appears: do not restore fixed two-task or Decorator-required normal path; do not make purpose-only rounds full review.
- Remaining work: runtime participant/field/error contract and test design; concrete implementation address must be chosen without changing architecture semantics.
- Recommended next step: `runtime-contract-kernel.agent.md` for `SL2-RC-001`〜`SL2-RC-003`.
