# Plan Slice Decomposition

## 親 Plan の要約

通常のCodex作業を一度のuser-level導入で常時リンク付き通知へ接続し、初回実装を行った同じ親threadから一操作で独立review、親agentによる修正、purpose-only再reviewを最大3roundまで実行する。Decorator指定、別top-level Review Thread、thread ID / path / hash / JSON転記をnormal-pathから除く。

## full-coverage 判定の理由

notification callback / provider / user configと、GitHub collector / read-only reviewer subagents / parent-only write / review round / terminal notificationが別production boundaryにあり、単一passではruntime identity、state ownership、fake-only evidenceを安全に扱えない。一方、file単位へ細分化する必要はなく、独立価値とverification routeを持つ二つのminimum useful sliceへ統合できる。

## Architecture Slice Readiness

- Readiness artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-architecture-slice-readiness.md`
- Verdict: ReadyForSliceDecomposition
- Architecture artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-slice-architecture.md`
- Blocking architecture residuals: 0
- Architecture identity: source commit `774d6da78ed67be8478b4b5169121805daec79e6`、architecture `artifact_revision: 1`、external SHA-256 `1e791e99a059428996355d38012ea155204b073c0e6a7a77c8ed25c7b02437de`、readiness R2 SHA-256 `e415b8ecb1369979dbb5190dd628271c332306be0fea44572e4433d623185208`。

## 分割方針

- notification callback、runtime、provider、installer、APM distributionは同じproduction wiringとverification routeを共有するため`SL-001`へ統合する。
- review intake、round 1 independent review、parent remediation、round 2/3 purpose-only review、legacy normal-path removalは同じSkill / parent ownership / state transitionを共有するため`SL-002`へ統合する。
- `SL-002`のterminal status / PR URLを`SL-001`がoptional enrichmentとして消費する境界を`XC-001`とする。
- `SL-002`がsubagentを実行したときのactual callback / notification countを`SL-001`と共同で実機確認する境界を`XC-002`とする。
- APM package、README、validatorだけを独立sliceにしない。各production ownerのsliceにcoalesceする。

## Slice 一覧

| Slice ID | Name | Goal | Recommended profile | Immediate next agent | Depends on | Can run in parallel? |
| --- | --- | --- | --- | --- | --- | --- |
| `SL-001` | Always-on Codex completion notification | marker / Decoratorなしの全valid親turnをthread-link通知へ接続し、一度のAPM導入でproduction wiringを成立させる。 | standard-slice | `implementation-contract-kernel.agent.md` | なし | Architecture上はYes。ただしroot docs / integration validator競合を避けるため実装は先行する。 |
| `SL-002` | Same-parent independent review and bounded remediation | 同じ親thread内でround 1 full review、親修正、round 2/3 purpose-only review、terminal stop / notification enrichmentを成立させる。 | standard-slice | `implementation-contract-kernel.agent.md` | `SL-001`の`XC-001` consumer contract。review本体は独立実装可能。 | Source上はYes、最終verificationはNo。 |

## Slice granularity review

| Slice ID | Too small? | Coalesce target | Reason to keep separate | Decision |
| --- | --- | --- | --- | --- |
| `SL-001` | No | N/A | 独立したinstall / callback / provider production path、rollback、automated + manual notification verificationを持ち、`SL-002`を通知へ接続するproducer/consumer boundaryをunblockする。 | executable |
| `SL-002` | No | N/A | GitHub / subagent / parent-write state transitionという別owner / permission / verification routeを持つ。 | executable |
| `CAND-DIST` | Yes | `SL-001` / `SL-002` | APM manifest / docsだけでは独立runtime valueがない。 | coalesce-with-SL-001 / SL-002 |
| `CAND-RERUN` | Yes | `SL-002` | purpose-only再reviewはsame Skill state machineから分けるとowner / finding continuityを壊す。 | coalesce-with-SL-002 |

## Slice 詳細

### SL-001: Always-on Codex completion notification

- Goal: user-level Codex `notify`を一度導入した後、marker / Decorator / envelopeなしのvalid turn callbackをgeneric thread-link notificationへ変換し、safe optional metadataがある場合だけresult actionを追加する。
- Non-goals: notification timeline、additional provider、Codex private API、subagent hierarchyのunsupported heuristic、review orchestration本体。
- Parent requirements covered: `FR-001`〜`FR-004`、`FR-009`のconsumer側、`FR-012`のnotification distribution。
- Parent acceptance conditions covered: `AC-001`〜`AC-005`、`AC-011`のconsumer側、`AC-012`、`AC-013`のnotification docs。
- Affected components / modules: `scripts/codex-notification-runtime/`、`apm-packages/completion-notification-decorator/`、notification workflow / validator、root README notification sections。
- Expected implementation scope: generic fallback、optional enrichment precedence、dedup / fail-open維持、installerのalways-on config、runtime assetsのAPM distribution、legacy Decoratorをoptional compatibilityへ降格、schemas / fixtures / docs / manual evidence更新。
- Internal high-risk boundary candidates: `ARC-RC-001`〜`ARC-RC-004`、Windows provider production binding、user config rollback。
- Cross-slice dependencies: `XC-001`で`SL-002`のterminal enrichmentを消費する。`XC-002`はcross-slice manual verification。
- Related Cross-slice Contract IDs: `XC-001`, `XC-002`
- Architecture readiness verdict: ReadyForSliceDecomposition
- Architecture baseline: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-slice-architecture.md`
- Architecture baseline identity: commit `774d6da...`、artifact revision `1`、hash `1e791e...`、watch pathsはnotification / completion package / README / workflow。
- Architecture source IDs / sections: `ARC-RC-001`〜`ARC-RC-004`, `ARC-RC-009`, `ARCH-INV-001`〜`ARCH-INV-005`, `ARCH-INV-010`。
- Shared invariants consumed: generic delivery、thread action retention、invalid envelope fallback、fail-open、parent-centric notification。
- Architecture residuals assigned to this slice: `AR-001`, `AR-002`, `AR-005`のnotification部分。
- Black-box behavior coverage:
  - Parent behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
  - Expansion required: Yes
  - Slice Plan readiness: ReadyForRiskTriage
  - Assigned Behavior Case IDs: `NTF-001`〜`NTF-008`, `REV-013`のconsumer側、`SCP-003`
- Case-to-Slice mapping:
  - `NTF-001`, `NTF-002`, `NTF-004`, `NTF-006`, `NTF-007`, `NTF-008`: slice内部。`FR-001`〜`FR-003`, `FR-012` / `AC-001`〜`AC-004`, `AC-012`, `AC-013`へ接続。
  - `NTF-003`, `REV-013`: `XC-001`を通るCrossSliceVerification。`FR-002`, `FR-009` / `AC-002`, `AC-011`。
  - `NTF-005`: `XC-002`を通るCrossSliceVerification。`FR-004` / `AC-005`。
  - `SCP-003`: APM継続 / Plugin移行除外としてOutOfScopeWithSourceとproduction distributionへ反映。
- Cross-slice contract excerpt:
  - XC ID: `XC-001`
  - Architecture source: `ARC-RC-002`, `ARC-RC-009`, `ARCH-INV-010`
  - This slice role: Consumer
  - Mechanism: Codex callback `last-assistant-message`内のoptional `completion-notification` envelope
  - Required fields / state / identifiers: schema version、primary process、observed status、safe title、optional concrete HTTPS PR URI。thread / turn identityはcallback自身から取得。
  - Owned by this slice: parse / validation / generic fallback / result URI safety / provider actions。
  - Consumed by this slice: `SL-002`のterminal projection。
  - Deferred / unresolved fields: なし。invalid fieldsはfabricateせずgeneric fallback。
  - XC ID: `XC-002`
  - Architecture source: `ARCH-INV-005`、Cross-slice postcondition `AC-005`
  - This slice role: Consumer / verification owner
  - Mechanism: real Codex parent + reviewer subagent execution時のuser-level callback observation
  - Required fields / state / identifiers: parent task、reviewer subagent count、user-visible notification count / targets。identifier本文はevidenceへ保存しない。
  - Owned by this slice: runtime / provider delivery observation。
  - Consumed by this slice: `SL-002`のsubagent orchestration。
  - Deferred / unresolved fields: official callbackにhierarchy fieldはない。manual observationまで`ManualOnly`。
- Small slice justification: N/A。
- Implementation-realization risks: existing marker-only gatingへのnearest-neighbor回帰、runtime assetsがAPM package外、TOML wiring / chain / rollback、schema compatibility、real subagent callback scope。
- Recommended process profile: standard-slice
- Immediate next agent: `implementation-contract-kernel.agent.md`
- Required inputs for next agent: parent Plan、behavior spec、triage、R2 readiness、Slice Architecture、本decomposition、SL-001 artifact、notification production files / package / validator。
- Stop condition for this slice: generic/enriched runtime、installation / distribution、automated evidenceがcompleteし、manual-only `XC-002`を明示してslice verificationを終える。cross-slice closeはまだ行わない。

### SL-002: Same-parent independent review and bounded remediation

- Goal: 初回実装parent threadで一度起動すると、current Ready PRとGoal Contextを自動解決し、round 1の三系統review、parent-owned fixes、round 2/3 purpose-only review、terminal decisionを同じparent thread内で完結する。
- Non-goals: separate top-level Review / Implementation tasks、Adaptive executor、round 4自動継続、Goal Context多段承認、base review Skill全体の不要な再設計。
- Parent requirements covered: `FR-005`〜`FR-012`。
- Parent acceptance conditions covered: `AC-006`〜`AC-013`。
- Affected components / modules: Goal Context review Skill / references / templates / scripts、collector、reviewer prompts / profiles、sync helper、APM manifest、package / root README、PRR fixtures / validators / manual smoke。
- Expected implementation scope: same-parent orchestration contract、auto intake、auto run root / summary、round 1 local + purpose subagentsとCopilot source、parent-only remediation、purpose-only round 2/3、terminal verdict / optional enrichment、fixed two-task cycle managerのnormal-path removal、docs / validators。
- Internal high-risk boundary candidates: `ARC-RC-005`〜`ARC-RC-009`、GitHub auth / head drift、read-only profiles、single-writer parent、round state / finding continuity。
- Cross-slice dependencies: terminal notificationは`XC-001`で`SL-001`へ渡す。subagent notification behaviorは`XC-002`で共同確認する。
- Related Cross-slice Contract IDs: `XC-001`, `XC-002`
- Architecture readiness verdict: ReadyForSliceDecomposition
- Architecture baseline: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-slice-architecture.md`
- Architecture baseline identity: commit `774d6da...`、artifact revision `1`、hash `1e791e...`、watch pathsはPR package / reviewer agents / README。
- Architecture source IDs / sections: `ARC-RC-005`〜`ARC-RC-009`, `ARCH-INV-006`〜`ARCH-INV-011`、review state / decision table。
- Shared invariants consumed: no manual messenger、reviewer read-only / parent write、code review round 1 only、3round stop、terminal thread / PR Return Gate。
- Architecture residuals assigned to this slice: `AR-003`, `AR-004`, `AR-005`のreview部分。
- Black-box behavior coverage:
  - Parent behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
  - Expansion required: Yes
  - Slice Plan readiness: ReadyForRiskTriage
  - Assigned Behavior Case IDs: `REV-001`〜`REV-013`, `NTF-003`, `NTF-005`, `SCP-001`〜`SCP-003`
- Case-to-Slice mapping:
  - `REV-001`〜`REV-012`: slice内部。`FR-005`〜`FR-011` / `AC-006`〜`AC-010`, `AC-012`, `AC-013`。
  - `REV-013`, `NTF-003`: `XC-001`のproducerとしてCrossSliceVerification。`FR-009` / `AC-011`。
  - `NTF-005`: `XC-002`のproducerとしてCrossSliceVerification。`FR-004` / `AC-005`。
  - `SCP-001`: complex multi-top-level / long resumeをOutOfScopeWithSource。
  - `SCP-002`: timeline / Adaptive executorをDeferredWithSource。
  - `SCP-003`: Plugin移行をOutOfScopeWithSource、APM manifestを更新。
- Cross-slice contract excerpt:
  - XC ID: `XC-001`
  - Architecture source: `ARC-RC-009`, `ARCH-INV-010`
  - This slice role: Producer
  - Mechanism: terminal final responseのoptional envelope
  - Required fields / state / identifiers: schema version、canonical terminal verdict projection、safe title、current concrete PR URL。parent thread identityは生成しない。
  - Owned by this slice: terminal verdictとPR result URI projection。
  - Consumed by this slice: N/A。`SL-001`runtimeがconsumer。
  - Deferred / unresolved fields: なし。thread IDをenvelopeへfabricateしない。
  - XC ID: `XC-002`
  - Architecture source: `ARCH-INV-005`
  - This slice role: Producer
  - Mechanism: real Codex parentからread-only reviewer subagentsを起動する。
  - Required fields / state / identifiers: reviewer count / roles、parent terminal completion、user-visible notification observation。
  - Owned by this slice: subagent orchestration evidence。
  - Consumed by this slice: `SL-001`manual runtime observation結果。
  - Deferred / unresolved fields: callback hierarchyはsourceからfabricateしない。
- Small slice justification: N/A。
- Implementation-realization risks: current Skill / manager / plannerがfixed two-taskをauthorityとする、reviewer promptsにAdaptive / Review Thread契約が残る、collectorはexplicit repo / PRを要求する、run summary schemaとsource write owner addressが未実装。
- Recommended process profile: standard-slice
- Immediate next agent: `implementation-contract-kernel.agent.md`
- Required inputs for next agent: parent / slice artifacts、current Goal Context / base review Skills、collector、manager surface、reviewer prompts / profiles、manifest / sync helper、validators / fixtures。
- Stop condition for this slice: deterministic contract / package validationがpassし、real-model same-parent smokeがmanual evidenceとして分類され、`XC-001` / `XC-002`をcross-slice verificationへ渡す。

## Cross-slice contracts

| Cross-slice Contract ID | Producer slice | Consumer slice | Runtime participants | Mechanism | Required fields / state / identifiers | Error / retry / recovery expectation | Verification requirement | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `XC-001` | `SL-002` | `SL-001` | same-parent orchestrator、Codex host、notification runtime、provider | optional terminal envelope + callback | schema version、primary process、terminal status、safe title、current PR URI。thread / turnはcallback authority。 | invalid / missing envelopeはgeneric notification。review verdictは変えない。 | fixtureでprojection / parser / dual actions、実機でparent thread / PR click。 | Deferred |
| `XC-002` | `SL-002` | `SL-001` + cross-slice verification | parent agent、reviewer subagents、Codex host、runtime / provider | real subagent executionに伴うcallback delivery | reviewer roles / count、parent terminal、user-visible notification count / targets。private IDsは保存しない。 | unsupported hierarchyをheuristicで補わない。spamが観測されたらclose blocker。 | real Codex manual smokeのみ。 | ManualOnly |

### Architecture traceability

| XC / Slice / Invariant | Architecture source | Projected semantics | Drift allowed? |
| --- | --- | --- | --- |
| `SL-001` | notification participants、`ARC-RC-001`〜`004`、`ARCH-INV-001`〜`005` | generic always-on callback / safe enrichment / fail-open / installation | No |
| `SL-002` | review participants / state / decisions、`ARC-RC-005`〜`009`、`ARCH-INV-006`〜`011` | same-parent review、single writer、purpose-only rerun、terminal stop | No |
| `XC-001` | `ARC-RC-002`, `ARC-RC-009`, `ARCH-INV-010` | enrichment cannot override callback identity; generic fallback | No |
| `XC-002` | `ARCH-INV-005`, cross-slice postcondition `AC-005` | parent-centric notification is manual close gate | No |

## Cross-slice field continuity

| Field / state / identifier | Required by | Source artifact / owner | Producer XC | Intermediate storage / artifact | Consumer XC | Fabrication allowed? | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `thread-id` | resume action | Codex callback | N/A | runtime event only | `XC-001` consumer path | No | Deferred | `SL-002`は生成・上書きしない。runtime binding後にverify。 |
| `turn-id` | dedup identity | Codex callback | N/A | claim / delivered key | `XC-001` consumer path | No | Deferred | envelope外。 |
| terminal status | enriched notification | `SL-002` decision table | `XC-001` | terminal envelope / run summary | `XC-001` | No | Deferred | mandatory source coverageから導出。 |
| current PR URL | result action | GitHub collector / current PR | `XC-001` | terminal envelope | `XC-001` | No | Deferred | concrete HTTPS resourceのみ。 |
| primary process / title | notification display | `SL-002` Skill terminal projection | `XC-001` | terminal envelope | `XC-001` | No | Deferred | safe text validation。 |
| parent / subagent role observation | notification noise gate | real Codex execution | `XC-002` | privacy-safe manual evidence | `XC-002` | No | ManualOnly | official callback payloadからfabricateしない。 |
| reviewed head OID | purpose rerun | GitHub collector | internal `SL-002` | round raw context / summary | internal `SL-002` | No | Deferred | stale headを拒否。 |
| Goal Context path | purpose reviewer | explicit valid pathまたはunique discovery | internal `SL-002` | run summary / reviewer task | internal `SL-002` | No | Deferred | hash転記をuserへ要求しない。 |
| active finding IDs | next remediation / purpose review | reviewer raw outputs | internal `SL-002` | run summary + raw output | internal `SL-002` | No | Deferred | text similarityで代替しない。 |

## Parent contract mapping

| Parent Contract ID | Disposition | Slice ID | Cross-slice Contract ID | Notes |
| --- | --- | --- | --- | --- |
| `RC-001` | InternalToSlice | `SL-001` | `XC-002` | callback / providerは内部、subagent noiseはcross verification。 |
| `RC-002` | InternalToSlice | `SL-001` | N/A | installer / APM distribution。 |
| `RC-003` | InternalToSlice | `SL-002` | `XC-002` | round 1 reviewは内部、actual notification observationがcross。 |
| `RC-004` | InternalToSlice | `SL-002` | N/A | remediation / purpose-only bounded state。 |
| `RC-005` | CrossSlice | `SL-002`→`SL-001` | `XC-001` | terminal result enrichment。 |

## Behavior Case mapping

| Case ID | Parent FR / AC | Disposition | Slice ID | Cross-slice Contract ID | Evidence route | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `NTF-001` | `FR-001`, `FR-002` / `AC-001` | InternalToSlice | `SL-001` | N/A | runtime fixture + installed callback | generic notification。 |
| `NTF-002` | `FR-001`, `FR-002` / `AC-001`, `AC-005` | InternalToSlice | `SL-001` | N/A | generic / enriched stop fixture | stopも対象。 |
| `NTF-003` | `FR-002` / `AC-002` | CrossSliceVerification | `SL-001`,`SL-002` | `XC-001` | integration + manual buttons | dual actions。 |
| `NTF-004` | `FR-002` / `AC-002` | InternalToSlice | `SL-001` | N/A | invalid URI / envelope fixture | thread fallback。 |
| `NTF-005` | `FR-004` / `AC-005` | CrossSliceVerification | `SL-001`,`SL-002` | `XC-002` | real Codex smoke | parent-centric。 |
| `NTF-006` | `FR-003` / `AC-003` | InternalToSlice | `SL-001` | N/A | replay fixture | dedup。 |
| `NTF-007` | `FR-003` / `AC-003` | InternalToSlice | `SL-001` | N/A | provider / chain failure | fail-open。 |
| `NTF-008` | `FR-001`,`FR-012` / `AC-004`,`AC-013` | InternalToSlice | `SL-001` | N/A | package install smoke | one-time install。 |
| `REV-001`〜`REV-012` | `FR-005`〜`FR-011` / `AC-006`〜`AC-010`,`AC-012`,`AC-013` | InternalToSlice | `SL-002` | N/A | static + deterministic + real-model smoke | same-parent review/remediation。 |
| `REV-013` | `FR-009` / `AC-011` | CrossSliceVerification | `SL-002`,`SL-001` | `XC-001` | terminal integration + manual link | parent / PR Return Gate。 |
| `SCP-001` | Parent non-goals | OutOfScopeWithSource | `SL-002` | N/A | docs / coverage disposition | complex multi-thread / long resume。 |
| `SCP-002` | Parent non-goals | DeferredWithSource | N/A | N/A | residual ledger | timeline / Adaptive executor。 |
| `SCP-003` | `FR-012` / `AC-004`,`AC-012` | OutOfScopeWithSource | `SL-001`,`SL-002` | N/A | APM manifests | Plugin migrationなし。 |

## Execution order

1. `SL-001`を先行し、generic callback / optional enrichment consumer / production installationを成立させる。
2. `SL-001`のslice verification後、`SL-002`でsame-parent review / remediationと`XC-001` producerを実装する。
3. source上のparallel implementationは可能だが、root README、package validation、manual smokeが交差するため本worktreeではserial write ownerを維持する。
4. 両slice後に`cross-slice-verification-kernel.agent.md`で`XC-001`, `XC-002`とParent ACを確認する。
5. producer / consumer片側だけで`XC-001`をDoneにせず、`thread-id` / `turn-id` / PR URL / terminal statusをfabricateしない。

## Final cross-slice verification requirements

- Parent AC: `AC-002`, `AC-005`, `AC-006`, `AC-010`, `AC-011`, `AC-012`, `AC-013`。
- Contracts: `XC-001`, `XC-002`。
- Field continuity: callback `thread-id` / `turn-id`、terminal status、current PR URL、safe display fields、parent/subagent notification observation。
- Cases / negative expectations: `NTF-003`, `NTF-005`, `REV-001`〜`REV-005`, `REV-013`。Decorator不要、別top-level task不要、reviewer write禁止、round 2以降code review禁止。
- Production binding: APM-installed runtime / profiles、user-level config、real Windows provider、Ready PR collector、read-only subagents、parent write path。
- Manual-only: actual Windows buttons、real callback、real parent + subagent notification count、real-model reviewer independence / same-parent remediation。
- Block PASS: invalid / stale architecture、generic callback suppression、subagent notification spam、manual messenger requirement、reviewer write、mandatory reviewer不足、unverified production wiring、fake-only evidence。

## Human decisions required

なし。

## 今回の decomposition の対象外

- notification timeline、additional provider、Plugin migration、Adaptive executor、generic multi-thread recovery。
- implementation class / method / helper分割、full integration test design、live external verificationの実行。

## Handoff Packet

- Profile used: plan-slice-decomposition
- Parent Plan artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-plan.md`
- Change Risk Triage artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-change-risk-triage.md`
- Slice Decomposition artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-slice-decomposition.md`
- Slice artifacts: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-slice-SL-001.md`、`plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-slice-SL-002.md`
- Slice IDs: `SL-001`, `SL-002`
- Cross-slice Contract IDs: `XC-001`, `XC-002`
- Cross-slice field continuity items: thread / turn identity、terminal status、PR URL、display fields、parent/subagent observation、review head、Goal Context path、finding IDs。
- Slice granularity review: distributionとpurpose rerun候補はrespective owner sliceへcoalesce。executableは2 slices。
- Behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- Behavior Case IDs: `NTF-001`〜`NTF-008`、`REV-001`〜`REV-013`、`SCP-001`〜`SCP-003`
- Source artifacts: parent Plan、behavior spec、triage、R2 readiness、Slice Architecture。
- Files inspected: upstream artifactsとarchitectureで選択済みのbounded production surfaces。
- Files intentionally not inspected: unrelated packages、implementation details、full fixture bodies、live external state。
- Decisions made: 2 minimum useful slices、serial write order、`XC-001` terminal enrichment、`XC-002` manual notification-noise gate。
- Do not redo unless new evidence appears: notification / reviewをさらにfile単位へ分けず、distribution / rerunを独立small sliceにしない。
- Remaining work: 各sliceのimplementation contract、runtime contract、test design、handoff review、Adaptive implementation、slice verification、cross-slice verification、residual decision。
- Recommended next step: `SL-001`をAdvanced full-coverage routeへ渡し、implementation-realization riskがPresentのため`implementation-contract-kernel.agent.md`から準備する。
- Required downstream guardrails: 各sliceはparent Plan、decomposition、own slice artifactを読む。Parent `RC-*`とslice / `XC-*` mapping、Behavior Case mapping、Slice Architecture / R2をauthorityとする。shared semanticsをslice-prepで変更しない。selected runtime contractでparticipant / boundary、test point、stub usage、production binding、production wiring、explicit unresolved statusを保持する。`XC-*`をslice内で勝手にDoneにせずcross-slice verificationへ渡す。fieldをfallback / 空文字 /推測で補わない。production bindingがsliceをまたぐ場合はcross-slice verificationまでDeferred / PartiallyDone。coalesce候補をexecutable sliceへ戻さない。
