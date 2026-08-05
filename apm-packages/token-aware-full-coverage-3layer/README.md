# Token-aware Full-coverage 3-layer

Plan Coverageで`full-coverage`と判定され、Architecture Slice Readiness Gateとslice decompositionを通過した変更を、parentが整合を保持したままbounded slicesとして実行するadvanced APM processです。通常のPlan CoverageやAdaptive Implementationの代わりに直接選ぶ標準入口ではありません。

## Use only when

- currentなbounded parent Planとchange-risk-triageがある
- `architecture-slice-readiness`が`ReadyForSliceDecomposition`または`ArchitectureNotRequired`を返している
- 必要な場合はcurrentなSlice Architectureとslice decompositionがある
- 複数sliceのownership、authorization、cross-slice verificationをparentが管理する必要がある

要求展開が不足している場合はPlanへ戻します。shared semanticsが未確定の場合はArchitecture Slice Readiness Gateへ戻し、このprocessで推測しません。

## Current route

fresh workは`compact-slice-record-v2`を使います。

```text
Parent Orchestration State
  -> Slice Preparation Delta
  -> Parent Authorization
  -> Adaptive Implementation
  -> independent Slice Verification
  -> optional bounded FixNow
  -> Full-coverage Final Record
       -> cross-slice verification
       -> residual decision
       -> close decision
```

sliceはapproved parent authorityを継承し、parent Plan Coverage chainへ再入場しません。各sliceのimplementationとverification evidenceは一つのliving Slice Recordへ記録し、full tableはcanonical Coverage Ledgerが所有します。legacy split artifactsは既存workのresumeとexplicit compatibilityに限り、自動migrationしません。

## Three layers

1. parent agentがParent State、slice queue、authorization、cross-slice blockersを管理する。
2. `slice-prep`がslice-local deltaを調査し、shared semanticsを変えずParent Authorizationへ渡す。
3. authorizedな非自明sliceをAdaptive Implementationへ委譲し、独立verifierが同じSlice Recordへ結果を記録する。

`DELEGATED_IMPLEMENTATION`ではparentがproduction codeやtestsを直接編集しません。非自明なREADY sliceは`high-implementation-starter`から開始し、valid handoff後だけ`standard-implementation-completer`へ直列委譲します。構造判断が再発したらHIGH_MODELへ戻します。

`PREP_ONLY`は「準備まで」「reviewまで」「実装しない」と利用者が明示した場合だけ使います。

## APM and workspace responsibilities

APM packageはprocess instructions、Skill、`slice-prep`、canonical Adaptive agentsへのdependency、Parent State / Slice Record / Final Record templatesを配布します。

workspace側には`.codex/config.toml`などの実行境界が残ります。このrepositoryでは並列度と再帰深さを制限し、packageが定義する作業手順を安全に実行するために使います。APM packageとworkspace configは代替関係ではありません。

既存repositoryへAPM packageとCodex agent profilesを導入する場合は、repository rootの`scripts/provision-work-repo-agents.cs`を使います。Full-coverage packageのprovisioningはこのcanonical helperから開始します。

## Records and closure

- Parent Stateはsessionをまたぐmandatory resume entrypointです。
- Slice Recordはimmutable baseline、preparation、authorization、implementation、verification、bounded fixes、current handoffを保持します。
- Final Recordはcross-slice runtime postconditions、forbidden states、residual decision、close decisionを保持します。
- source-structure test、interfaceの存在、CI greenだけで`CROSS_SLICE_VERIFIED`にしません。
- stateful contractではproducer stateとconsumer gateの両方を検証します。

## GitHub Copilot CLI

APM 0.26.0の`copilot,agent-skills` targetで、Skill、shared instruction、
`slice-prep`、canonical agentsをGitHub Copilot CLIが読むrepository-local
pathsへ導入できます。実測された導入先、install / update / rollback /
check / use / resume、model capabilityの制約、real CLI evidenceは
[Copilot CLI qualification](tests/copilot-cli/README.md)を参照してください。

fresh runの`compact-slice-record-v2`、Parent State resume、独立verification、
Final Record、residual decisionの意味はこのpackageのcanonical Skillと
referencesが所有します。Copilot向け文書は同じ契約を複製しません。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer#<full-commit-sha> --target copilot,agent-skills --https
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer --dry-run
apm install --frozen
apm audit --ci
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer#<known-good-commit-sha> --target copilot,agent-skills --https
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer --dry-run
```

`copilot skill list`で導入を確認し、fresh workでは`compact-slice-record-v2`
と`implementation_route: adaptive` / `implementation_route_source: default`
を使います。新sessionは`copilot --resume=<session-id>`で会話を続けられますが、
必ずParent Orchestration Stateを再開入口として読みます。legacy split、
stale baseline、mixed layout、欠落route metadataは推測・migrationせず
fail closedにします。per-agent model lockがCLIで観測できない場合は
requested / observed modelを分け、unsupportedまたは`ManualOnly`として記録します。

Parent Stateのartifact-authoritativeなnew-session resumeは、fresh
`copilot -p` sessionとnegative fail-closed runを含むtracked evidence bundle
により`PROVEN`です。bundleの`hashes.sha256`は自身のhash行を含まない安定
manifestで、`evidence_bundle_sha256`はそのmanifestのSHA-256です。正式な
qualificationは他の未解決scenarioが残るため`REAL_SCENARIO_INCOMPLETE`のままです。

Troubleshooting: Skillが表示されない場合は`.agents/skills`と
`.github/instructions`、`.github/agents`、lockfileの整合を確認し、
`apm install --frozen`と`apm audit --ci`を再実行します。同名agentのcollisionは
ownershipを確認するまで`--force`で上書きしません。

Final-head package installation is checked independently from the canonical
Full Coverage validator:

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-copilot-full-package-install.ps1 `
  -PackageName token-aware-full-coverage-3layer `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <full-commit-sha>
```

## Documentation and validation

- [Full-coverage decomposition policy](../../docs/token-aware-full-coverage-decomposition-flow.md)
- [Plan Coverage package](../plan-coverage-residual-flow/README.md)
- [Adaptive Implementation package](../adaptive-implementation-execution/README.md)
- [Historical 3-layer fixes](../../docs/codex-full-coverage-3layer-fixes.md)

```powershell
./scripts/validate-full-coverage-slice-flow.ps1
./scripts/validate-architecture-slice-readiness.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1
```
