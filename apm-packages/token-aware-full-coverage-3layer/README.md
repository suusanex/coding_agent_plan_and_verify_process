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

既存repositoryへAPM packageとCodex agent profilesを導入する場合は、repository rootの`scripts/provision-work-repo-agents.cs`を使います。Codex-firstのbootstrapにはこのhelperを使いません。

## Records and closure

- Parent Stateはsessionをまたぐmandatory resume entrypointです。
- Slice Recordはimmutable baseline、preparation、authorization、implementation、verification、bounded fixes、current handoffを保持します。
- Final Recordはcross-slice runtime postconditions、forbidden states、residual decision、close decisionを保持します。
- source-structure test、interfaceの存在、CI greenだけで`CROSS_SLICE_VERIFIED`にしません。
- stateful contractではproducer stateとconsumer gateの両方を検証します。

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
