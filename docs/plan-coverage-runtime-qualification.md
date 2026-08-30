# Plan Coverage runtime qualification matrix

この文書は、canonical Plan Coverage semantics、distribution projection、runtime evidence、現行runtimeのsupport assessmentを分離して記録する。Plan Coverage process semantics自体は変更しない。

## 用語と責務

| 用語 | 意味 |
| --- | --- |
| evidence validity | evidenceがschema、scenario invariant、`source_run`、取得時fingerprint・package version・candidate commit・client/runtime metadataと内部整合していること。current checkoutとの差異とは独立して判定する |
| evidence verdict | `overall_status`。そのrunが取得時snapshotについてfull qualificationを満たしたかを示す。`QUALIFIED`を別snapshotへ移植しない |
| snapshot relation | evidence取得時snapshotとcurrent checkoutの関係。validatorは`CURRENT_SNAPSHOT`、`HISTORICAL_BASELINE`、`DIFFERENT_SNAPSHOT`として表示するが、通常モードでは差異だけをfailureにしない |
| support assessment | validなhistorical baseline、targeted delta evidence、deterministic checks、変更のruntime regression riskを基に、現行package/runtimeを引き続きsupportedと扱えるかを判断するpolicy。evidence verdictを書き換えない |
| qualification input fingerprint | Plan Coverage canonical/manifest、Adaptive Implementation canonical/manifest/profile overlay、Codex profile finalizer manifest/runtime scriptをordinal path順でhashしたidentity。親repositoryの無関係な変更を含めず、runtime-relevant dependencyの変更をstrict gateへ反映する |

Canonical authorityは`apm-packages/plan-coverage-residual-flow/.apm/`、package manifestは`apm-packages/plan-coverage-residual-flow/apm.yml`である。canonical fingerprintはLF正規化した`.apm/**`のpathとcontentをordinal path順でSHA-256化し、証拠取得snapshotを一意に結び付ける。またcanonical sourceの変化をdeterministicに検出する。ただし、fingerprintまたはpackage versionの変化だけをexternal-model qualificationの再実行理由にはしない。

`apm_lock_sha256`は実行時install resolutionのprovenanceとして保持するが、parent refやruntime非関連のresolution差分まで含み得るためcurrent strict identityには流用しない。Strict gateでは、無関係なparent repository変更を除外しつつAdaptive/profile projection変更を含めるpurpose-builtなqualification input fingerprintを使う。

`overall_status`はevidence verdict専用であり、current support stateを兼用しない。historical `QUALIFIED`は取得時snapshotについてのvalidなbaselineとして保持できるが、current snapshotで取得した証拠とは主張しない。`PENDING`はtargeted runや未完了runをfull qualificationへ昇格させないために使い、`UNOBSERVABLE`や`NOT_RUN`をPASSへ昇格させない。

## Distribution projection

| Target | deterministic verification |
| --- | --- |
| `copilot` | `validate-plan-coverage-residual-flow-apm-smoke.ps1` |
| `codex` | 同じfresh APM smokeとchecked-in Codex projection drift check |
| `agent-skills` | 同じfresh APM smoke |

Fresh install smokeはtransitive Adaptive Implementation assetsと、remote ref使用時のinstalled full-coverage deterministic E2Eも検査する。通常pull request CIは外部modelを呼ばない。

## Runtime evidenceと現行support assessment

Evidence directoryは`apm-packages/plan-coverage-residual-flow/tests/runtime-qualification/results/`、schemaは`result.schema.json`である。qualified client surfaceはGitHub Copilot CLIだけであり、VS Code Agent mode等の別surfaceはseparate runtime qualification未実施である。

| Evidence | 取得時identity | evidence verdict | 役割 |
| --- | --- | --- | --- |
| `2026-08-10-copilot-cli.json` | package 0.13.0 / fingerprint `98a49a…`; qualification input identityは当時未記録 | `QUALIFIED`; A-H、STD-001、FULL-001、Adaptive connectionを含むfull PASS | immutable historical baseline。未記録identityをcurrent値で補完しない |
| `2026-08-11-copilot-cli-pending.json` | package 0.14.0 / fingerprint `c12b3a…`; qualification input identityは当時未記録 | `PENDING`; DO-001〜DO-003はPASS、無関係なscenarioはこのrunでは未実行 | Decision Ownershipのtargeted delta evidence。未記録identityをcurrent値で補完しない |

現行0.14.0のDecision Ownership変更は`targeted runtime risk`として評価する。変更対象に対応するDO-001〜DO-003がtargeted external-model runでPASSし、0.13.0のfull baselineと通常のdeterministic checksを併用できるため、GitHub Copilot CLI support assessmentは`CARRY_FORWARD_WITH_TARGETED_DELTA`とする。0.13.0 evidenceを0.14.0へre-bindせず、0.14.0 targeted resultをfull `QUALIFIED`へ昇格せず、A-H、STD-001、FULL-001の全面再実行も要求しない。

このassessmentはAgent Plugins direct deploymentのGO/HOLD、APM supported installation path、他runtime surfaceのqualificationを変更しない。

## Runtime regression riskと再実行policy

### Low / normal

Documentation、wording、metadata、behaviorへ影響しないcanonical整理、またはisolatedでdeterministic validationが十分な変更を対象とする。変更したownerのdeterministic CIを実行し、distribution inputを変更した場合だけ該当closureのinstall smokeを実行する。external-model regressionは原則実行せず、次回実運用でruntime behaviorを観測する。

### Targeted runtime risk

特定agent behavior、decision rule、bounded contract、新しい限定runtime behaviorを対象とする。Adaptive接続では、compatibleなhandoff field変更、Adaptive側の内部ownership semantics変更、またはPlan Coverage側の限定connection behaviorだけに影響する変更を含む。deterministic CIに加え、必要に応じて変更したconnection scenarioだけをtargeted runtime smokeとして実行する。影響根拠のないauthorization、STD、FULL等は再実行しない。

### Full runtime risk

次の境界を変更する場合はfull runtime qualificationを要求または強く推奨する。

- invocation authorization / explicit-invocation-only境界
- route selection、route orchestration、standard/full route全体のshared semantics
- runtime adapter / projection、Skill・agent discovery、materializationの根幹
- Plan Coverage全routeに共通するAdaptive invocation protocol、route identity、materialization、shared orchestration semantics
- runtime/client compatibility boundary
- 新runtimeを正式supported runtimeへ昇格するpromotion review
- historical baselineを合理的にcarry forwardできない広範なsemantics変更

Adaptiveというdependency名やconnection fileの変更だけではFullにしない。分類根拠は変更内容とruntime regression riskであり、`.apm/**`変更、package version bump、fingerprint mismatchそのものではない。full risk以外ではtargeted evidenceを優先し、無関係なfull suiteを要求しない。

## Validator mode

通常CIは次を実行する。

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-runtime-qualification.ps1
```

通常モードは全committed resultのschema shape、fingerprint形式、全verdict共通のduplicate scenario禁止、targeted `PENDING`の全recorded scenario PASS、`source_run` frozen identity、top-level metadataとの一致、forged/re-bound evidenceをfail-closedで検査する。`distribution_smoke`はrationaleを含む全fieldをfrozen identityとして扱う。historical `QUALIFIED`とcurrent identityの差異は`HISTORICAL_BASELINE`として表示するが、それだけではfailureにしない。

Promotion review等でcurrent snapshotのfull qualificationを明示的に要求する場合だけstrict gateを使う。

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-runtime-qualification.ps1 -RequireQualified
```

Strict gateはcurrent canonical fingerprint、package version、`apm.yml` hash、runtime-relevant qualification input fingerprintに一致し、A-H、DO-001〜DO-003、STD-001、FULL-001、distribution smoke、Adaptive connectionがfull PASSの`QUALIFIED` evidenceを要求する。Adaptiveやprofile projectionだけが変化した場合も古いfull evidenceをcurrentとは判定しない。Baseline carry-forwardやqualification input identity未記録のhistorical evidenceをcurrent full evidenceの代用にはしない。

## Runnerとre-evaluation

Live runはtemporary run rootの`run-metadata.json`へcandidate commit、canonical fingerprint、qualification input fingerprint、package version、lock hash、client/runtime identityを凍結する。`-ReevaluateFromRunRoot`はそのidentityを必ず保持し、current checkout値へre-bindしない。再評価結果は同じ`source_run_id`の既存JSON/Markdown pathを置換し、日をまたいでもduplicate resultを作らない。再評価後の`overall_status`はsource snapshot自身のscenario evidenceから決め、current checkoutとの差異はinformationalなsnapshot relationとして出力する。

Targeted scopeの全recorded scenarioがPASSした場合、evidence verdictはfull suite未実行を示す`PENDING`のまま、runner commandは成功終了する。Scenario failureを含む`FAIL`だけをcommand failureとする。

External-model invocationはManualOnlyであり、通常CIには含めない。

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1 `
  -ConfirmExternalModelPayload `
  -Model <available-copilot-model>
```

## Evidence integrity invariants

- historical evidenceのfingerprint、package version、candidate commit、client/runtime identityを書き換えない。
- `result.*`と`source_run.*`のidentity不整合、top-level fingerprintだけのre-bind、metadata矛盾をfail-closedで拒否する。
- `distribution_smoke`のstatus、command、rationaleをtop-levelと`source_run`で一致させる。
- `PENDING` targeted evidenceにFAIL、NOT_RUN、UNOBSERVABLE、duplicate scenarioを混入させない。
- historical runをcurrent qualificationとして扱わず、targeted evidenceをfull evidenceとして扱わない。
- raw transcriptやhook logを捏造せず、`UNOBSERVABLE` / `NOT_RUN`をPASSにしない。
- Agent Plugins PoC evidenceは別experimentとして保持し、APM runtime evidenceへ移植しない。direct-load parity claim自体がsnapshot比較を目的とする場合はfingerprint一致を引き続き要求する。
