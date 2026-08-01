# Slice Architecture

## Requirement baseline and source artifacts

```yaml
baseline:
  repository_ref: goal-context-type2
  source_repository_commit: 774d6da78ed67be8478b4b5169121805daec79e6
  tracked_sources:
    - { role: goal_context, path: "docs/goal-context-multi-project-ai-development-notification-and-handoff-reduction.md", revision_type: content_sha256, revision: "60ed6a99eb76aa0e5bd029cf656de83210d98d7cb59324a6dd1e5ea492dbca38" }
    - { role: parent_plan, path: "plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-plan.md", revision_type: content_sha256, revision: "4f40d8e528f51133fec03e3848fdda61285ed8a9d0e4d8064ec0c7e58df20ed7" }
    - { role: behavior_spec, path: "plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md", revision_type: content_sha256, revision: "81ec89b032a9f0d31b093d8930271f231de65a004007c8d5ba04b4df69202ddb" }
    - { role: change_risk_triage, path: "plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-change-risk-triage.md", revision_type: content_sha256, revision: "d1c882c08b2a1dbf39faa3a2ca44dab35471b5f8a2382f3677c1709077405738" }
  watch_paths:
    - "scripts/codex-notification-runtime/"
    - "apm-packages/completion-notification-decorator/"
    - "apm-packages/pr-review-remediation/"
    - ".github/agents/local-reviewer.agent.md"
    - ".github/agents/purpose-reviewer.agent.md"
    - ".github/agents/review-planner.agent.md"
    - "README.md"
    - ".github/workflows/validate-completion-notification-decorator.yml"
  artifact_revision: 1
  generated_at: 2026-07-29T23:18:00+09:00
```

```yaml
elaboration_trigger:
  readiness_path: "plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-architecture-slice-readiness.md"
  readiness_revision: "readiness-r1"
  blocking_residual_ids: ["AR-001", "AR-002", "AR-003", "AR-004", "AR-005", "AR-006"]
  decision_sources:
    - "docs/goal-context-multi-project-ai-development-notification-and-handoff-reduction.md"
    - "plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-plan.md"
    - "plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md"
    - "plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-change-risk-triage.md"
    - "current Codex Manual: Notifications and Subagents"
  freshness_dependency: false
```

- Parent Plan: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-plan.md`
- Black-box Behavior Spec: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- Change Risk Triage: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-change-risk-triage.md`
- Architecture Slice Readiness: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-architecture-slice-readiness.md` R1
- Existing architecture sources: `scripts/codex-notification-runtime/decision-record.md`、現行notification event / envelope schema、current review Skills / reviewer profiles / collector。

## Runtime participants and responsibilities

| Participant | Responsibility | Owned state | Allowed writes | Forbidden writes | Evidence mode | Source / production evidence address |
| --- | --- | --- | --- | --- | --- | --- |
| Codex host | 親またはagent turn終了時にdocumented callback payloadをuser-level `notify`へ渡す。 | `thread-id`、`turn-id`、`cwd`、入力と最終応答。 | user configに従うcallback invocation。 | runtime内部state、review artifact、repository sourceの変更。 | ExistingProductionBinding | current Codex Manual Notifications、`CodexPayload`。 |
| Notification installer | runtime/providerをpublishし、user-level configへ一度配線し、既存notifyをchainする。 | installed binary / runtime-config / backupの導入状態。 | staging、install root、user configのtop-level `notify`。 | 既存notifyの黙示破棄、自己再帰、作業ごとのprompt。 | ExistingProductionBinding + GreenfieldDesignDecision | `install-codex-notification-runtime-local.cs`。常時targetingへの変更はgreenfield。 |
| Notification runtime | valid `agent-turn-complete`をgeneric eventへ変換し、optional envelopeで安全にenrichし、dedup後providerへ配送する。 | `.claim` / `.delivered`とprivacy-safe runtime log。 | runtime home state / log、provider stdin、chained notify argv。 | 親turnのverdict変更、repository source、user-visible review state。 | ExistingProductionBinding + GreenfieldDesignDecision | `codex-notification-runtime.cs`。generic fallbackはnew decision。 |
| Notification provider | eventをWindows notificationとして表示し、thread / optional result actionを開ける形にする。 | なし。 | Windows notification side effect。 | runtime state、Codex / repository state。 | ExistingProductionBinding | `windows-app-notification-provider.cs`。 |
| Same-parent review orchestrator | current parent thread内でintake、round、subagent起動、finding統合、修正可否、terminal verdictを制御する。 | current run summary、round number、active finding IDs、review artifact index。 | `.review/pr-<n>/same-thread/<run-id>/`のreview artifacts、terminal response metadata。 | reviewer生出力の改変、production codeの独立review判定、別top-level taskの作成強制。 | GreenfieldDesignDecision | Goal Context、`REV-001`〜`REV-013`。canonical entryは`goal-context-pr-review` Skillを更新する。 |
| GitHub context collector | current Ready PR identity、remote patch、Copilot review/comments/checksを収集し、head driftを拒否する。 | 収集時点のderived snapshot。 | orchestrator指定run rootのcontext / patch。 | GitHub state変更、review verdict、source edits。 | ExistingProductionBinding | `collect-pr-review-context.cs`の`TargetIdentity` / wait / output。 |
| Local code reviewer subagent | round 1のcurrent remote PR diffを独立code reviewする。 | 自身のraw resultのみ。 | parentへ返すresult、指定raw output artifact。 | production code / tests / GitHub / orchestration state。 | ExistingProductionBinding | `local-reviewer.toml`、`.github/agents/local-reviewer.agent.md`。 |
| Purpose reviewer subagent | Goal Contextに照らしてround 1またはcurrent corrected PR diffを独立purpose reviewする。 | 自身のraw resultとstable `PUR-*` finding IDs。 | parentへ返すresult、指定raw output artifact。 | production code / tests / GitHub /round state、IssueでGoal Contextを代替。 | ExistingProductionBinding + GreenfieldDesignDecision | `purpose-reviewer.toml`、`.github/agents/purpose-reviewer.agent.md`。fixed thread / Adaptive reference依存は除去する。 |
| Parent implementation agent | reviewer結果を統合し、許可されたfindingだけを同じ実装contextで修正・検証し、PR headを更新する。 | working tree、commit / PR head、current remediation evidence。 | production source / tests / docs、git commit / push（呼出し時の権限範囲内）、run summary。 | reviewer raw outputの偽造、未決product semanticsの推測、reviewer権限でのwrite。 | GreenfieldDesignDecision | Goal Context「修正実装は親agent」。 |
| APM package / sync helper | runtime install assets、same-parent Skill、reviewer profilesを導入・checkする。 | installed package / profile layout。 | APM targetと`.codex/agents`のpackage-owned files。 | `AGENTS.md`の黙示変更、user promptごとのDecorator強制。 | ExistingProductionBinding + GreenfieldDesignDecision | current APM manifests / `sync-pr-review-remediation-local.cs`。 |

## Source-of-truth matrix

| Concept | Owner / canonical source | Readers | Precedence | Conflict handling | Evidence mode | Source / production evidence address |
| --- | --- | --- | --- | --- | --- | --- |
| callback identity | Codex callback `thread-id` + `turn-id` | notification runtime | callback payloadがenvelopeやassistant textより上位。 | missing / invalidなら通知候補を破棄し、chained notifyだけ継続する。 | ExistingProductionBinding | current `CodexPayload` validation。 |
| resume URI | notification runtimeがcallback `thread-id`から導出 | provider | envelopeは上書き不可。 | invalid thread IDならeventを生成しない。 | ExistingProductionBinding | `CreateCandidate`。 |
| generic notification fields | runtime fixed defaults + `cwd`から解決したrepository | provider | valid optional envelopeがprocess/status/title/resultだけをenrichする。callback identity / resumeは上書き不可。 | envelope missing / invalidでもgeneric notificationへfallbackする。 | GreenfieldDesignDecision | `NTF-001`〜`NTF-004`。 |
| result URI | valid optional envelopeの具体的HTTPS resource URI | runtime / provider | URI allowlist validation後だけgeneric eventへ追加する。 | invalid / coarse URIは無視し、thread actionだけ残す。 | ExistingProductionBinding + GreenfieldDesignDecision | `IsAllowedResultUri`、provider validation。 |
| notification delivery identity | `source_event_id = codex:<thread-id>:<turn-id>` | runtime state | delivered markerがclaimより上位。 | duplicateは配送せず、stale claimだけbounded cleanupする。 | ExistingProductionBinding | runtime state files。 |
| PR identity / reviewed patch | collectorがGitHubから取得したrepository、PR、base/head OID、remote patch | reviewers / parent | current collector snapshotがconversation memoryや旧artifactより上位。 | head drift / Draft / missingはroundをblockedにする。 | ExistingProductionBinding | collector `ReadAndValidateIdentity` / `EnsureIdentityUnchanged`。 |
| Goal Context selection | 呼出しで明示されたrepository-relative path、なければPR / repoから一意に解決したcurrent document | purpose reviewer / parent | explicit valid path > unique discovered candidate。Issue本文は代替不可。 | missing / ambiguous / unreadableはblocked。hashを利用者へ要求しない。 | GreenfieldDesignDecision | Goal Context、`REV-009`。 |
| reviewer finding | individual reviewer raw output | parent / next purpose reviewer | reviewerのown finding ID / evidenceがparent summaryより上位。 | contradictory / missing mandatory sourceはround completionを拒否する。 | GreenfieldDesignDecision | `REV-002`, `REV-010`, `INV-005`。 |
| current run state | auto-created `run-summary.md` projection + active parent thread context | parent / purpose reviewer | current PR headとraw artifactsがsummaryやconversation memoryより上位。 | contradiction時はcurrent remote evidenceからsummaryをrefreshし、推測できなければblocked。 | GreenfieldDesignDecision | `REV-011`, `REV-012`。 |
| terminal review verdict | parent orchestratorがmandatory reviewer coverage、active findings、round countから導出 | notification enrichment / user | raw reviewer coverage + current head > run summary > terminal envelope projection。 | mandatory source欠落や矛盾は`BLOCKED`、product decisionは`HUMAN_DECISION_REQUIRED`。 | GreenfieldDesignDecision | state decision table below。 |
| terminal notification envelope | same-parent Skillまたはcompatible Skillのterminal projection | notification runtime | review verdict authorityではなくenrichment projection。 | invalid projectionはgeneric notificationへfallbackし、review resultは変更しない。 | GreenfieldDesignDecision | `RC-005`、`NTF-004`。 |

## Canonical state model

| State domain | Canonical states | Owner | Durable / derived | Meaning |
| --- | --- | --- | --- | --- |
| Notification candidate | `IgnoredInvalidCallback`, `GenericCandidate`, `EnrichedCandidate` | notification runtime | Derived | valid callbackはenvelopeなしでもcandidate。valid envelopeだけenrichする。 |
| Notification delivery | `Unclaimed`, `Claimed`, `Delivered`, `Failed`, `Duplicate` | notification runtime | Durable claim / delivered、他はderived/log | provider side effectのidempotencyとretry可否。 |
| Review run | `Preparing`, `Round1Reviewing`, `Remediating`, `PurposeReviewing`, `Complete`, `HumanDecisionRequired`, `Blocked` | same-parent orchestrator | Minimal durable projection in `run-summary.md` | 利用者が操作するstate machineではなくagent監査・resume用。 |
| Review round | `1`, `2`, `3` | same-parent orchestrator | Durable projection + raw round directory | round 1はfull review、round 2/3はpurpose-only。review評価回数を数える。 |
| Finding | `Active`, `Resolved`, `NeedsHumanDecision` | reviewer raw outputを根拠にparentがprojection | Durable projection、evidenceはraw output | text similarityで黙示的に解消しない。 |
| PR head | `Current`, `Stale`, `Unavailable` | GitHub collector | Derived from remote | reviewer inputsとparent remediationのidentity gate。 |
| Return Gate | `ThreadOnly`, `ThreadAndResult` | notification runtime | Derived | result URIの有効性でbutton集合を決める。 |

## State transition and decision table

| Input state tuple / event | Classification | Lane / capacity | Eligibility | Permitted effect | Next state | Rejection / fail-closed behavior |
| --- | --- | --- | --- | --- | --- | --- |
| valid callback + no envelope | Generic terminal attention | notification single-delivery lane | thread / turn IDsあり | generic event生成、chain、dedup、provider配送 | `GenericCandidate`→delivery state | invalid callbackはprovider配送しない。 |
| valid callback + valid envelope | Enriched terminal attention | notification single-delivery lane | safe text、valid optional result URI | generic identityを保持してfieldsをenrich | `EnrichedCandidate`→delivery state | invalid field / envelopeはgeneric fallback。 |
| claimed event + provider success | Delivered | same source event capacity 1 | 未delivery | delivered marker作成 | `Delivered` | duplicateは配送しない。 |
| claimed event + provider failure / timeout | Retryable notification failure | same source event capacity 1 | claim owner | claim解放、privacy-safe log | `Failed` | 親turn verdictを変更しない。 |
| Skill start + Ready PR + valid Goal Context | Review activation | parent write lane 1、review lanes read-only | current parent thread、inputs auto-resolved | run root / summary作成、Copilot wait / context collect | `Round1Reviewing` | missing / ambiguousは`Blocked`。 |
| round 1 context ready | Independent full review | reviewer read lanes | current base/head一致 | local reviewerとpurpose reviewerを独立実行し、GitHub Copilot sourcesを保存 | `Round1Reviewing` | mandatory reviewer / source欠落は`Blocked`。 |
| round result + no actionable finding | Close | parent lane | mandatory sources complete | summaryをComplete、terminal enrichmentを出す | `Complete` | reviewer coverage不足ならclose禁止。 |
| round result + auto-fixable active finding + round < 3 | Remediation | parent write lane 1 | product decision不要、source authority十分 | parentが修正、test、commit / pushしcurrent remote headを確立 | `Remediating`→`PurposeReviewing` | push / verification不能は`Blocked`、権限判断が必要なら停止。 |
| remediation complete + round < 3 | Purpose-only review | reviewer read lane | new current remote head | collectorをCopilot waitなしでrefreshし、purpose reviewerだけ実行 | next round | local reviewer / Copilot waitを再実行しない。 |
| active finding + round = 3 | Bounded human stop | parent lane | mandatory purpose review complete | summaryとterminal enrichmentにreason / PR resultを保持 | `HumanDecisionRequired` | round 4を自動開始しない。 |
| finding requires product / policy decision | Human decision stop | parent lane | sourceで自動確定不可 | reasonとevidenceを保持し停止・通知 | `HumanDecisionRequired` | 推測によるfix / close禁止。 |
| head drift / missing Goal Context / mandatory reviewer failure | Operational stop | parent lane | safe continuation不能 |具体的blockerを保持し停止・通知 | `Blocked` | 空結果でreview / remediationへ進まない。 |

## Major sequences

### 1. 一度のnotification activation

1. 利用者はAPMからnotification assetsを導入し、installerを`--dry-run`、`install`、`--check`の順で実行する。
2. installerはsourceからruntime / providerをstaging publishし、既存top-level `notify`をruntime configへchainとして保存する。
3. configのtop-level `notify`をruntimeへ切り替え、新しく開始したCodex turnからすべてのvalid callbackを対象にする。
4. install / update失敗時は直前binary / configへrollbackする。作業ごとのDecorator / marker指定はない。

### 2. Generic / enriched notification delivery

1. Codex hostが`agent-turn-complete` payloadをruntimeへ渡す。
2. runtimeは既存notifyへ元payloadをforwardし、callback identityを検証する。
3. envelopeなしまたはinvalidならgeneric event、validなら同じidentityのenriched eventを作る。
4. `thread-id` / `turn-id`でclaimし、providerへbounded timeoutでeventを渡す。
5. providerはthread actionを必ず持ち、valid resultがある場合だけresult actionも追加する。
6. failureはclaimを解放してlogへ記録し、親turnへ非zeroを返さない。duplicateは再表示しない。

### 3. Same-parent round 1

1. 利用者は初回実装parent threadで`goal-context-pr-review`を一度起動する。必要ならGoal Context pathだけを短く添える。
2. parent orchestratorはcurrent repository / Ready PR / base-headとGoal Contextを自動解決し、run rootを自動生成する。
3. collectorがcurrent remote patchとGitHub Copilot review / comments / checksをbounded waitで収集する。
4. parentは同じconfirmed contextを、別々のread-only local reviewer / purpose reviewer subagentへ渡す。
5. raw outputsをround 1へ保存し、mandatory source coverageを確認する。
6. findingなしならComplete。actionableならparent remediation。human decisionまたはoperational failureならterminal stop。

### 4. Parent remediation and purpose-only rerun

1. parentはreviewer evidenceからactive findingを列挙し、Goal Context外のscopeを追加しない。
2. 同じparent contextでproduction source / tests / docsを修正し、関連checksを実行する。
3. current workflowの権限内でcommit / pushし、remote PR headをcurrentにする。できない場合はblockedとして停止する。
4. collectorをCopilot waitなしでrefreshしてcurrent patchを固定する。
5. previous purpose findingsとnew patchを、新しいread-only purpose reviewerへ渡す。
6. round 2または3のraw outputとactive / resolved projectionを保存し、decision tableへ戻る。

### 5. Terminal / Return Gate

1. Complete、HumanDecisionRequired、Blockedのいずれかでrun summaryを確定する。
2. parent final responseは人間向けsummaryに加え、Skill-owned optional notification envelopeを一つだけ出す。`result_uri`はcurrent PRの具体的HTTPS URL。
3. user-level runtimeはenvelopeをenrichmentとして読み、callback由来のparent thread actionとPR result actionを同じ通知へ表示する。
4. 利用者は通知から同じparent threadへ戻り、必要ならPRまたはhuman decisionを確認する。

### 6. Retry / replay / cleanup

- notification callback replayはsource event IDでdedupする。failed provider eventはclaim解放により次callback replayで再試行可能。
- review collectorのtimeoutはno-findingsへ変換せずBlocked。利用者が同じparent threadで再開するとcurrent remote stateから新runまたは明示resumeを行う。
- current run artifactsは自動生成pathに保持し、利用者へhash / pathの転記を要求しない。長期・複雑なresumeはMVP外として手動判断する。

## Cross-boundary contracts

| ID | Producer | Consumer | Mechanism | Fields / state | Identity continuity | Timeout / retry / recovery |
| --- | --- | --- | --- | --- | --- | --- |
| `ARC-RC-001` | Codex host | notification runtime | argv JSON callback | type、thread-id、turn-id、cwd、input-messages、last-assistant-message | thread + turnがsource event identity | invalidはignore、chainは継続。 |
| `ARC-RC-002` | same-parent Skill / generic task | notification runtime | optional fenced envelope in last response | schema version、primary process、observed status、title、optional result URI | callback thread / turnが上位でenvelopeはidentityを持たない | invalid / missingはgeneric fallback。 |
| `ARC-RC-003` | notification runtime | provider | event JSON stdin | source、process、status、title、repository、resume、optional result、source event | source event IDをdedup | provider timeoutはfail-open、claim release。 |
| `ARC-RC-004` | installer | Codex host / runtime | TOML notify argv + runtime-config | runtime argv、providers、chained notify | installed absolute path、self-wrap拒否 | staging check、rollback、`--check`。 |
| `ARC-RC-005` | GitHub / collector | reviewers / parent | review-context JSON / Markdown + remote patch | repo、PR、base/head OIDs、review sources、checks、wait status | current remote head OID | bounded wait、head drift / timeoutはBlocked。 |
| `ARC-RC-006` | parent orchestrator | local reviewer / purpose reviewer | subagent task with read-only profile | confirmed identity、patch、Goal Context、prior findings where applicable | run ID + round + head OID | missing/contradictory inputはreviewer BLOCKED。 |
| `ARC-RC-007` | reviewer subagents | parent orchestrator | raw Markdown result + stable finding IDs | verdict、finding ID、evidence、risk、suggested outcome、Production code changed: No | run ID + round + reviewed head | mandatory result missing / write evidenceはround reject。 |
| `ARC-RC-008` | parent remediation | next purpose review | pushed current PR head + prior finding projection | changed head OID、tests、active/resolved IDs | same PR、new current head | push / identity failureはBlocked、round maxはHumanDecisionRequired。 |
| `ARC-RC-009` | parent terminal decision | notification runtime | optional envelope + Codex callback | terminal status、short title、PR result URI | callback supplies parent thread identity | invalid enrichmentはgeneric fallback。 |

## Resource coordination

| Resource | Lane / lock / reservation / capacity semantics | Acquire | Retain | Release / cleanup | Owner |
| --- | --- | --- | --- | --- | --- |
| Notification source event | capacity 1 per `thread-id` + `turn-id` | atomic claim file create | provider invocation中 | delivered markerへmove、failureでclaim delete、stale claim cleanup | notification runtime |
| Production worktree / PR head | single writer: parent agentのみ | review findingがauto-fixableでcurrent head確認済み | edit / test / commit / push中 | new current remote head確立またはterminal stop | parent implementation agent |
| Reviewer execution | read-only lanes。round 1のlocal / purposeは独立に実行可能 | confirmed immutable contextを渡す | reviewer run中 | raw result返却後にrelease | parent orchestrator |
| GitHub Copilot wait | external bounded observation lane | collector start | stable samplesまたはtimeoutまで | context snapshot保存後release | collector |
| Review run artifacts | auto-generated run root、利用者管理不要 | intake成功時 | run terminalまで | terminal summary後保持。cleanupはMVP外 | parent orchestrator |

## Invariants and forbidden states

| ID | Invariant / forbidden state | Source FR / AC / Case | Enforcement owner | Verification oracle |
| --- | --- | --- | --- | --- |
| `ARCH-INV-001` | valid ordinary callbackをmarker / envelope不足で無通知にしてはいけない。 | `FR-001`, `AC-001`, `NTF-001` | notification runtime | generic callback fixture + installed smoke |
| `ARCH-INV-002` | result actionがthread actionを置換してはいけない。 | `FR-002`, `AC-002`, `NTF-003` | runtime / provider | provider dual-button test + manual click |
| `ARCH-INV-003` | invalid optional envelopeでgeneric notificationを失ってはいけない。 | `NTF-004` | notification runtime | invalid-envelope fallback fixture |
| `ARCH-INV-004` | notification failureでmain Codex turnを失敗にしてはいけない。 | `FR-003`, `AC-003`, `NTF-007` | notification runtime | failing provider / chain fixture |
| `ARCH-INV-005` | subagent数に比例するuser-visible notification spamをclose-compatibleにしてはいけない。 | `FR-004`, `AC-005`, `NTF-005` | verification gate | real parent + subagent callback smoke |
| `ARCH-INV-006` | normal review pathへ別top-level task、thread ID、plan path、hash、JSON転記を要求してはいけない。 | `FR-005`, `FR-011`, `AC-006`, `REV-001`, `REV-012` | goal-context Skill / docs validator | canonical invocation / forbidden term checks + smoke |
| `ARCH-INV-007` | reviewer subagentがproduction writeを行ってはいけない。 | `FR-010`, `AC-010`, `REV-003` | read-only profile / parent | profile validation + reviewer output + diff ownership evidence |
| `ARCH-INV-008` | round 2以降にGitHub Copilot waitまたはlocal code reviewを再実行してはいけない。 | `FR-007`, `AC-008`, `REV-005` | parent orchestrator | round artifact source coverage / agent invocation evidence |
| `ARCH-INV-009` | round 3のactive finding、human decision、mandatory source欠落を黙示closeしてはいけない。 | `FR-008`, `AC-009`, `REV-007`〜`REV-010` | parent orchestrator | state decision fixture / raw outputs |
| `ARCH-INV-010` | terminal review通知はparent threadとvalid PR resultの両導線を保持する。 | `FR-009`, `AC-011`, `REV-013` | Skill + runtime / provider | end-to-end callback event + manual buttons |
| `ARCH-INV-011` | Plugin移行、timeline、Adaptive executorを今回のclose条件へ入れてはいけない。 | Parent non-goals、`SCP-002`, `SCP-003` | parent orchestration | coverage ledger disposition |

## Production entrypoints and wiring

| Entrypoint | Production participant | Wiring / provider | Required state / config | Failure behavior | Evidence mode | Production evidence address |
| --- | --- | --- | --- | --- | --- | --- |
| notification installer `--dry-run/install/--check` | Notification installer | APM-distributed File-based Appsからruntime / providerをpublish | writable Codex home / install root、parseable top-level notify | fail closed before unsafe config change、rollback | ExistingProductionBinding + GreenfieldDesignDecision | current installer。package distribution pathを実装sliceで固定。 |
| user-level Codex `notify` | Codex host → notification runtime | top-level argv | runtime installed、runtime-config present | runtime不在はinstaller check失敗。callback runtime自体はfail-open | ExistingProductionBinding | config replacement code。 |
| `$goal-context-pr-review` in initial implementation parent thread | Same-parent review orchestrator | APM-installed Skill + reviewer profiles | current repo、Ready PR、Goal Context、GitHub auth | missing / ambiguousはBlocked terminal notification | GreenfieldDesignDecision | existing Skill pathをcanonical same-parent entryへ更新。 |
| reviewer subagent profiles | Local / purpose reviewer | `.codex/agents/*.toml` with `sandbox_mode = read-only` | canonical agent prompts installed | profile missing / wrong permissionはround start拒否 | ExistingProductionBinding | current TOMLs / sync helper。 |
| GitHub context collector | Collector | `gh pr view` / `gh api` / `gh pr diff` | authenticated gh、current PR identity | timeout / head drift / DraftはBlocked | ExistingProductionBinding | collector source。 |
| terminal notification enrichment | Parent final response → runtime | Skill-owned optional envelope | terminal verdict、PR URL | invalid metadataはgeneric notificationへfallback | GreenfieldDesignDecision | notification schema v1 + updated Goal Context Skill。 |

## Cross-slice verification postconditions

| Parent AC / Case | Producer action | Production path | Consumer observable | Forbidden state to deny | Required evidence strength |
| --- | --- | --- | --- | --- | --- |
| `AC-001`, `NTF-001` | ordinary parent turn completes without marker | installed user-level notify → runtime → provider | one thread-link notification | `not-targeted` suppression | deterministic fixture + installed real callback smoke |
| `AC-002`, `NTF-003`, `NTF-004` | generic or enriched event delivered | runtime → Windows provider | thread-only or dual-button notification | unsafe result / missing thread action | automated provider test + manual click |
| `AC-003`, `NTF-006`, `NTF-007` | callback replays or provider fails | runtime state / timeout path | no duplicate; main result preserved | provider failure changes Codex verdict | deterministic failure / replay fixture |
| `AC-005`, `NTF-005` | parent spawns reviewer subagents | real Codex callback path | parent-centric user-visible notification count | subagent notification spam | real-environment manual evidence only |
| `AC-006`, `REV-001`, `REV-012` | user starts Skill once in original parent | installed Goal Context Skill | no manual top-level handoff or ID/path/hash/JSON copy | fixed two-task normal path | static contract + real-model smoke |
| `AC-007`, `REV-002`〜`REV-004` | round 1 runs and parent applies fixes | collector + read-only subagents + parent write lane | raw 3-source review and parent-authored diff | self-review replacement / reviewer write | deterministic artifact check + real-model smoke |
| `AC-008`, `REV-005` | corrected head reviewed | purpose-only path | only purpose reviewer on rounds 2/3 | repeat Copilot wait / local reviewer | invocation ledger / artifact source check |
| `AC-009`, `REV-006`〜`REV-011` | round decision evaluates findings | parent state decision | Complete / HumanDecisionRequired / Blocked | silent residual close / auto round 4 | deterministic transition fixture + reviewer evidence |
| `AC-010`, `REV-003` | reviewers execute | read-only profiles | `Production code changed: No`; parent owns diff | reviewer source modification | profile validator + git diff ownership evidence |
| `AC-011`, `REV-013` | terminal review response emits enrichment | parent callback → runtime → provider | same parent thread and current PR direct actions | result replaces thread / wrong task | integration fixture + manual click |
| `AC-012`, `AC-013` | packages installed and validators run | APM install / sync / README commands | documented reproducible setup and checks | fake-only close or decorator-required usage | package smoke + publish + docs validator + manual evidence ledger |

## Architecture residual classification

| ID | Classification | Topic | Source / evidence | Owner | Blocking? | Next action |
| --- | --- | --- | --- | --- | --- | --- |
| `AR-001` | SliceLocalContract | generic/enriched event field defaultsとschema compatibility | `ARC-RC-001`〜`ARC-RC-003` | notification slice | No | runtime-contract-kernelでfield / fallbackを固定する。 |
| `AR-002` | SliceLocalContract | real Codexがsubagent callbackをuser notifyへ渡す範囲 | official manualにhierarchy fieldなし | notification verification | No | static filterを推測せずmanual smokeをclose gateにする。 |
| `AR-003` | SliceLocalContract | auto-generatedrun root / summaryの最小field | canonical state model | review orchestration slice | No | implementation-contract-kernelでaddressとrequired fieldsを固定する。 |
| `AR-004` | SliceLocalContract | parent remediation時のcommit / push / check command | parent single-writer decision | remediation slice | No | repository rulesとcurrent PR workflowからslice-localに決める。 |
| `AR-005` | ImplementationDetail | generic title text、run ID naming、finding aggregationの内部表現 | parent AC | implementation owners | No | user-visible semanticsを変えない範囲で決める。 |
| `AR-006` | OutOfScopeWithSource | notification timeline、additional provider、Adaptive executor、generic multi-thread recovery | Parent non-goals | future work | No | 今回実装しない。 |

ArchitectureCritical residual count: 0

NeedsHumanDecision residual count: 0

## Files inspected

| File / address | Why inspected | Architecture decisions supported |
| --- | --- | --- |
| Goal Context、parent Plan、Behavior Spec、triage、R1 readiness | requirement / risk / blocking architecture source | 全GreenfieldDesignDecision、invariants、state / sequence |
| `scripts/codex-notification-runtime/codex-notification-runtime.cs` | callback authority、envelope gating、dedup、fail-open | runtime participant、source precedence、notification state |
| `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs` | production config wiring、chain、rollback | installer responsibility / entrypoint |
| `scripts/codex-notification-runtime/windows-app-notification-provider.cs` | thread / result actions | Return Gate、provider contract |
| notification schemas / decision record / manual verification | current public eventとmanual evidence | schema compatibility、verification strength |
| Goal Context / base review Skills | current separate-turn authority | same-parent replacement boundary |
| `collect-pr-review-context.cs` selected symbols | current PR identity / Copilot wait / artifact contract | GitHub boundary、head continuity |
| `manage-review-cycle.cs` selected symbols | old fixed role thread / round / verdict authority | legacy normal-path removal decision |
| reviewer agent prompts and TOMLs | reviewer responsibility / permissions | read-only lanes、raw output authority |
| package manifests / sync helper selected symbols | APM wiring / installed profiles | production entrypoint、distribution boundary |
| current Codex Manual Notifications / Subagents | documented callback fields and subagent thread behavior | no hierarchy-field assumption、subagent separation |

## Files intentionally not inspected

| File / area | Why not required | Revisit trigger |
| --- | --- | --- |
| unrelated APM packages and agents | selected architecture boundaries外 | decompositionでconcrete dependencyが追加された場合 |
| full validator / fixture bodies | architecture semanticsではなくtest implementation | test-design / implementation sliceで更新範囲を確定するとき |
| historical `plans/**` | current source of truthではない | migration validatorがhistorical artifactを誤ってauthorityにする場合 |
| live GitHub PR / review state | architectureは特定PRに依存しない | manual / real-model verification時 |
| Windows App SDK method reference details | provider architectureは既存bindingを維持 | provider implementation変更が必要になった場合 |

## Freshness rule

このartifactはtracked sourceのrevision / content hashが変わる、`source_repository_commit`以後のdiffがwatch pathまたはinspected production evidence addressへ影響する、human decision sourceが変わる、または明示的`artifact_revision`が変わる場合に`stale`となる。readiness / architecture artifactだけの追加・更新はbaseline semanticsを変更しない限りself-invalidationを起こさない。path一致だけではfreshnessを証明しない。

## Readiness handoff

- Architecture baseline status: ReadyForReadinessRerun
- ArchitectureCritical residual count: 0
- NeedsHumanDecision residual count: 0
- Immediate next agent: `architecture-slice-readiness.agent.md`
- Implementation allowed now: No
- Decomposition allowed now: No。R2 verdictを待つ。
