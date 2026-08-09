# Plan Coverage Check and Residual Decision Flow

bounded Planを実装・検証のsource of truthとして維持し、通常可能な作業を進めながら、manual-only、blocked、ambiguous、high-costな残件を明示判断へ渡すAPM processです。日本語では「Plan網羅チェック・残件判定フロー」と呼び、起動名は`plan-coverage-residual-flow`です。

広いruntime evidenceとintegration test designを含めて自走させる場合は[Full Autonomous Plan-first Flow](../full-autonomous-plan-first-flow/README.md)、既にあるPlanを実装するだけなら[Adaptive Implementation Execution](../adaptive-implementation-execution/README.md)を使います。

## Use when

- Plan-firstを維持したいが、full autonomous flowは重すぎる
- parent Plan全体のcoverageを落とさず、riskの高いruntime / production-binding surfaceだけを深く確認したい
- stub、fake、mockを使ったtestがあり、production implementationやwiringの欠落を防ぎたい
- 1回のbounded passで無理に完了させず、残件をexplicit decisionへ渡したい
- requirementが広くslice decompositionを必要とする可能性がある

## Core model

このprocessが守るchainは次のとおりです。

```text
Source requirement
  -> Black-box behavior cases
  -> Plan FR / AC
  -> Guardrail Focus runtime contract
  -> Guardrail Focus test point
  -> stub/fake usage
  -> production implementation
  -> production wiring / entrypoint
  -> Parent Plan Coverage Ledger
  -> Residual Decision Ledger
```

Guardrail Focusはdeep-check subsetであり、implementation scopeではありません。focus外のparent Plan itemもcoverage ledgerで分類します。Plan readinessが不足している場合はrisk triageへ進まず、behavior expansionまたはhuman decisionへ戻します。

## Start

このrouteはexplicit-invocation-onlyです。利用者が直接選ぶか、上流processが同じ選択のdurable evidenceを持つ場合だけ開始します。

```text
$plan-coverage-residual-flow を使って、この issue を進めてください。
```

Planから個別に始める場合:

```text
plan-kernel.agent.md を使って bounded Plan を作成してください。
実装は行わず、Goal、Non-goals、Functional requirements、Acceptance conditions、
Black-box behavior coverage、Affected components、Residual policy、
Guardrail Focus candidates、Plan readiness、次gateへのhandoffを記録してください。
```

## Standard flow

1. `plan-kernel`がbounded PlanとPlan readinessを作る。
2. behavior expansionが必要なら`black-box-behavior-spec-kernel`でCase IDsを作り、`plan-kernel`へ戻してFR / ACへmappingする。
3. `change-risk-triage`がparent Plan全体を分類し、Guardrail Focusとprocess profileを選ぶ。
4. `full-coverage`の場合は`architecture-slice-readiness`を通す。必要なら`architecture-elaboration`後に再判定し、許可された場合だけ`plan-slice-decomposition`へ進む。
5. 必要なimplementation contract、runtime contract、test design、implementation handoff reviewを作る。
6. 非自明な実装は`high-implementation-starter`から開始し、valid handoff後だけ`standard-implementation-completer`へ直列委譲する。
7. human reviewの重点を整理する場合は、任意で`code-review-focus-kernel`を実行する。
8. `verification-kernel`がparent Plan coverageとproduction bindingを検証する。full-coverageでは`cross-slice-verification-kernel`も実行する。
9. 未解決項目を`coverage-gap-triage`と`residual-decision-gate`へ渡す。explicit FixNow selectorだけを`coverage-gap-resolution-slice`で修正する。

各agentは1回のbounded passで停止し、未解決項目をartifactへ残します。

## Common prompt patterns

behavior expansionが必要な場合:

```text
plans/<slug>.md の Plan readiness が NeedsPlanBehaviorExpansion です。
black-box-behavior-spec-kernel.agent.md を使い、source requirementsをstable Case IDs、
negative expectations、derived invariants、excluded combinations、
unresolved requirement-elaboration itemsへ展開してください。
Plan FR / AC、runtime contract、test design、implementationは変更しないでください。
```

risk triageを行う場合:

```text
plans/<slug>.md を入力として change-risk-triage.agent.md を実行してください。
ReadyForRiskTriageの場合だけparent Plan全体のrisk inventory、Guardrail Focus、
implementation-realization risk、residual candidates、recommended process pathを出してください。
implementation scopeは縮小しないでください。
```

implementation前のgateを行う場合:

```text
implementation-handoff-review.agent.md を使って、Parent Plan Coverage Ledgerと、
Plan -> Guardrail Focus RC -> TP -> production binding requirementの接続を確認してください。
source codeとartifactは変更せず、READYまたはBLOCKED verdictを出してください。
```

Adaptive Implementationへ渡す場合:

```text
high-implementation-starter.agent.md を使って非自明な実装をHIGH_MODELから開始してください。
completeなREADY_FOR_STANDARD_COMPLETION handoffがある場合だけ
standard-implementation-completer.agent.mdへ直列委譲し、
NEEDS_HIGH_MODEL_REENTRYはHIGH_MODELへ戻してください。
bounded Planをsource of truthとし、Guardrail Focusをimplementation scopeにしないでください。
```

verificationを行う場合:

```text
verification-kernel.agent.md を実行し、Parent Plan Coverage Ledgerを更新してください。
Guardrail Focus RC / TPはproduction implementation、wiring、entrypoint、
contract representationを深く確認し、focus外のparent Plan itemも分類してください。
修正は行わず、parent Plan verdictと未解決項目を出してください。
```

human reviewの重点を整理する場合:

```text
code-review-focus-kernel.agent.mdを使い、bounded Plan、change-risk-triage、
implementation contract、runtime contract、実装差分を対応付けてください。
human reviewerが確認する順序、重点surface、parent Plan item、Guardrail Focus、
未解決riskをplans/<slug>-code-review-focus-kernel.mdへ記録してください。
実装の承認、修正、書き換えは行わないでください。
```

residual decisionを行う場合:

```text
residual-decision-gate.agent.md を実行し、Residual Decision Ledgerを作成してください。
explicit human decisionがある項目だけAcceptedResidual、ManualVerificationDelegated、
DeferredWithOwner、AbortedWithReasonとして扱い、未決項目は停止してください。
```

FixNowを実行する場合:

```text
verification、gap triage、またはresidual gateのexplicit FixNow selectorだけを対象に、
coverage-gap-resolution-slice.agent.mdを実行してください。
selector外へ広げず、修正後はverificationとresidual decisionへ戻してください。
```

## Full-coverage route

`full-coverage`は要求不足の代用ではありません。Plan readinessが成立した広い変更について、Architecture Slice Readiness Gateがshared semanticsをslice可能な精度か判定します。

```text
full-coverage
  -> architecture-slice-readiness
     -> architecture-elaboration -> readiness rerun, when required
     -> plan-slice-decomposition, when authorized
  -> each Slice Living Record
     -> slice-local risk and required kernel section deltas
     -> architecture baseline compatibility: Match
     -> Adaptive Implementation
     -> independent verification
  -> Full-Coverage Close Record
     -> cross-slice-verification
     -> residual-decision-gate
```

新規full-coverage runは`documentation_level: standard`と`artifact_mode: slice-living-record`を別々に記録します。`plan-slice-decomposition`が作る各`plans/<slug>-slice-SL-xxx.md`はbounded Slice Planを兼ねるcanonical Living Recordです。risk、implementation contract、runtime contract、test design、Inline Ready Gate、Adaptive evidence、independent verification、coverage delta、residual handoffを同じrecordから追跡できます。

agent semanticsとverdict vocabularyは維持されますが、各agentはowned section deltaだけを返し、Plan Coverage parent/routerだけがLiving Recordとcanonical Coverage Ledgerをrepositoryへ書きます。current architecture baselineとのcompatibilityが`Match`の場合だけAdaptive Implementationへ進み、`Drift`はArchitecture Slice Readiness / Elaborationへ戻し、`Unclear`はfail closedしてreadinessを再実行します。`ArchitectureNotRequired`でもLightweight architecture baselineとの比較を省略しません。全sliceのindependent verificationとpending ledger delta 0の後、`plans/<slug>-full-coverage-close.md`へCross-Slice Verification、Residual Decisionの順で別agent semanticsを適用します。

base artifact budgetはparent control-plane 5件、sliceごとにLiving Record 1件、final close 1件です。Black-box Behavior Spec、Slice Architecture、Design Pair handoffは条件付きで別集計します。別artifactはArtifact Creation Gateの`cross-thread-handoff`、`parallel-write-isolation`、`human-approval-wait`、`external-audit-evidence`、`record-size-limit`のいずれかを先にLiving Recordへ記録した場合だけ作成できます。pre-redesign runはexplicit legacy/separate modeのままresumeでき、silent migrationや同一run内のmode混在は行いません。

## Agent reference

| Agent | Responsibility |
| --- | --- |
| `plan-kernel` | bounded Plan、FR / AC、behavior coverage、residual policy、readinessを作る |
| `black-box-behavior-spec-kernel` | source requirementをexternal black-box casesへ展開する |
| `change-risk-triage` | Plan readiness、risk inventory、Guardrail Focus、recommended profileを判定する |
| `architecture-slice-readiness` | shared architecture semanticsがslice可能か判定する |
| `architecture-elaboration` | requirementを変えずshared architectureを確定する |
| `plan-slice-decomposition` | approved architectureをbounded execution slicesへ射影する |
| `implementation-contract-kernel` | dependency、API、provider、実現方式と未解決項目を整理する |
| `runtime-contract-kernel` | Guardrail Focusのruntime contractを固定する |
| `test-design-kernel` | Guardrail Focusのtest pointsとproduction binding checkを設計する |
| `implementation-handoff-review` | implementation前のPlan coverageとauthorizationを確認する |
| `high-implementation-starter` | 非自明な実装をHIGH_MODELで開始する |
| `standard-implementation-completer` | complete handoff後のbounded remainderだけを完了する |
| `code-review-focus-kernel` | human review用の差分と重点surfaceを整理する |
| `verification-kernel` | parent Plan coverage、behavior evidence、production bindingを検証する |
| `cross-slice-verification-kernel` | cross-slice contracts、runtime postconditions、forbidden statesを統合検証する |
| `coverage-gap-triage` | unresolved gapをFixNow、manual decision、residual candidateへ分類する |
| `residual-decision-gate` | explicit human decisionだけをaccepted residualへ変換する |
| `coverage-gap-resolution-slice` | explicit FixNow selectorだけをboundedに修正する |

`implementation-contract-review-kernel`と`implementation-execution`はexplicit compatibility useに限ります。

## Artifacts

通常のartifact名は次のとおりです。

| Artifact | Purpose |
| --- | --- |
| `plans/<slug>.md` | bounded Plan。実装のsource of truth |
| `plans/<slug>-black-box-behavior-spec.md` | Case IDs、negative expectation、derived invariants |
| `plans/<slug>-change-risk-triage.md` | risk inventoryとprocess recommendation |
| `plans/<slug>-implementation-contract-kernel.md` | implementation realization decisionsと未解決項目 |
| `plans/<slug>-runtime-contract-kernel.md` | Guardrail Focus runtime contract |
| `plans/<slug>-test-design-kernel.md` | Guardrail Focus test pointsとbinding requirements |
| `plans/<slug>-coverage-ledger.md` | canonical Parent Plan / Behavior Case / Residual ledgers |
| `plans/<slug>-implementation-handoff-review.md` | implementation authorization |
| `plans/<slug>-implementation-execution.md` | implementation evidence、checks、remaining work |
| `plans/<slug>-code-review-focus-kernel.md` | 任意のhuman review重点、確認順序、未解決risk |
| `plans/<slug>-verification-kernel.md` | parent Plan verification result |
| `plans/<slug>-coverage-gap-triage.md` | unresolved gap classification |
| `plans/<slug>-residual-decision-gate.md` | residual decisionsとnext verdict |

full-coverageではcanonical Coverage Ledger、parent control-plane artifacts、各Slice Living Record、final close recordを使います。通常のnon-full-coverage routeは上表のartifact名を維持します。Living Record modeでは通常の`*-runtime-contract-kernel.md`、`*-test-design-kernel.md`、`*-implementation-handoff-review.md`、`*-implementation-execution.md`、`*-verification-kernel.md`をsliceごとに作成しません。

Living Recordとclose recordのcanonical shapeは次を参照してください。

- `.agents/skills/plan-coverage-residual-flow/references/full-coverage-slice-living-record.md`
- `.agents/skills/plan-coverage-residual-flow/references/full-coverage-close.md`

## Verdicts and residual policy

implementation handoffは次のverdictを返します。

- `READY_FOR_BOUNDED_PARENT_PLAN_PASS`
- `READY_FOR_BOUNDED_PARENT_PLAN_PASS_WITH_DECLARED_RESIDUAL_RISKS`
- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
- `BLOCKED_BY_ARTIFACT_MISMATCH`
- `BLOCKED_BY_HUMAN_DECISION`
- `BLOCKED`

verificationは次のparent Plan verdictを返します。

- `PARENT_PLAN_VERIFIED`
- `PARENT_PLAN_VERIFIED_WITH_ACCEPTED_RESIDUALS`
- `PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES`
- `PARENT_PLAN_NEEDS_RESIDUAL_DECISION`
- `BLOCKED_BY_PRODUCTION_BINDING_GAP`
- `BLOCKED_BY_CONTRACT_MISMATCH`
- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
- `BLOCKED_BY_HUMAN_DECISION`

residual decisionのclose verdictは次を含みます。

- `READY_TO_CLOSE_WITH_NO_RESIDUALS`
- `READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS`
- `READY_FOR_NEXT_BOUNDED_FIX_PASS`
- `READY_FOR_MANUAL_VERIFICATION_HANDOFF`
- `NEEDS_HUMAN_RESIDUAL_DECISION`
- `REPLAN_REQUIRED`
- `ABORT_RECOMMENDED`

`ManualVerificationRequired`はclose不可のcandidate statusです。owner、method、required evidenceを持つexplicit human decision後だけ`ManualVerificationDelegated`にできます。`AcceptedResidual`、`DeferredWithOwner`、`AbortedWithReason`もexplicit decisionなしには使用しません。

## Operating principles

- Plan作成とPlan readinessを省略しない
- requirement-elaboration gapをfull-coverageやslice decompositionで隠さない
- parent Planをagentが縮小しない
- Guardrail Focusをimplementation scopeとして扱わない
- fake、stub、mock-only successをproduction completionとして扱わない
- source-structure testやCI greenだけでruntime postconditionをcloseしない
- previous gapを同等または弱いevidenceでcloseしない
- canonical Coverage LedgerとResidual Decision Ledgerを維持する
- explicit decisionなしにresidualをaccepted扱いしない

## Documentation and validation

- [Purpose and policy](../../docs/plan-coverage-purpose.md)
- [Detailed process and agent requirements](../../docs/plan-coverage-process-and-agents.md)
- [Full-coverage decomposition policy](../../docs/token-aware-full-coverage-decomposition-flow.md)
- [Architecture Slice Readiness validation](../../docs/architecture-slice-readiness-validation.md)
- [Standalone full-coverage E2E fixture](tests/full-coverage-standalone/PCF-001/README.md)
- [Manual model smoke](tests/manual-model-smoke/README.md)

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-full-coverage-e2e.ps1
```

standalone full-coverage E2Eは、currentまたはinstalled Living Record / close reference authorityからrequired sectionとtableを導出し、2-slice fixtureのowner境界、artifact budget、negative cases、ledger delta適用、production bindingを確認します。そのうえで2つのslice payloadを依存順に適用し、slice-local verification、production entrypoint経由のcross-slice verification、residual decisionまでをdeterministicに検証します。外部modelは実行しないため、CodexやCopilot等がlifecycleを自律実行した証拠ではありません。

remote APM install smokeはpackageの変更をremote refで検証するときだけ実行します。
