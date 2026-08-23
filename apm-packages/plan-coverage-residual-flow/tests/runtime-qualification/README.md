# Plan Coverage runtime qualification

This directory holds GitHub Copilot CLI runtime qualification fixtures and committed evidence for the canonical Plan Coverage package.

## Boundaries

| Layer | Authority | What it proves |
| --- | --- | --- |
| Canonical semantics | `apm-packages/plan-coverage-residual-flow/.apm/` | Process contract (runtime-neutral) |
| Distribution projection | fresh APM install smoke (`validate-plan-coverage-residual-flow-apm-smoke.ps1`) | `copilot` / `codex` / `agent-skills` projection install |
| Runtime evidence | GitHub Copilot CLI only in this Issue | Live authorization + route behavior |

Do not treat VS Code Agent mode or other Copilot UI surfaces as qualified unless a separate runtime qualification run records them.

Authorization scenarios A–H are loaded from the package-canonical file:

```text
tests/invocation-authorization-scenarios.json
```

Do not duplicate A–H expected semantics into another authority JSON.

Decision ownership scenarios DO-001〜DO-003 are loaded from the separate package-canonical file:

```text
tests/decision-ownership-scenarios.json
```

これらは`implementation-contract-kernel`に対し、SliceLocalContractのdesign-owned itemをscope内に維持し、credential mechanismとManualOnly secret provisioningを分離し、真正なcommit-identity policy escalationを隔離するよう要求します。Full qualification evidenceでは3 scenarioすべてのPASSを要求します。DOだけのtargeted runは`PENDING` evidenceのままsupport-assessment deltaとして利用でき、full evidenceへ再ラベルしません。

`DO-001` is the full-coverage regression path: the harness creates its Slice Living Record and canonical ledger, invokes the kernel with `artifact_mode: slice-living-record` and `output_contract: section-delta`, then requires the emitted `Implementation Contract Decisions`, `Decision Ownership Gate`, `Coverage Ledger Delta`, and terminal verdict.

## Fixtures

- `copilot-cli/standard-slice/` — STD-001 bounded standard-slice E2E seed + external oracle
- `copilot-cli/full-coverage/` — FULL-001 producer/consumer full-coverage E2E seed + external oracles
- `result.schema.json` / `result-template.json` — machine-readable evidence contract
- `results/` — committed qualification evidence (metadata only; raw transcripts stay temporary)

## Commands

```powershell
# Manual GitHub Copilot CLI qualification (calls external model)
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1 `
  -ConfirmExternalModelPayload `
  -Model <available-copilot-model>

# Targeted Issue #117 behavior smoke (calls external model; ManualOnly)
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1 `
  -ConfirmExternalModelPayload `
  -ScenarioIds DO-001,DO-002,DO-003 `
  -KeepWorktree `
  -Model <available-copilot-model>

# Optional remote package source
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1 `
  -ConfirmExternalModelPayload `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <full-sha> `
  -Model <available-copilot-model>

# Static evidence validator (no external model)
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-runtime-qualification.ps1

# Explicit promotion/current-snapshot full qualification gate (no external model)
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-runtime-qualification.ps1 -RequireQualified
```

Isolation: each suite uses a temporary `COPILOT_HOME` with a qualification-only hook observer. Personal `~/.copilot` customizations are not loaded into the qualification context. Use `-KeepWorktree` to retain temporary directories for debugging.

## Status vocabulary

`PASS` / `FAIL` / `NOT_RUN` / `UNOBSERVABLE`

`UNOBSERVABLE` is never an overall PASS substitute. Skill load may be `UNOBSERVABLE` when Copilot CLI does not emit skill-selection events; scenario PASS may still be justified from hooks, artifact deltas, verifiers, and final response when the observable contract is met.

`overall_status`は`source_run`に記録したsource snapshotについてのevidence verdictであり、current support assessmentではありません。通常validationは全committed resultを検査し、snapshot relationを表示しますが、current fingerprintまたはpackage versionとの差異だけでは失敗しません。Targeted scopeが全PASSなら`PENDING` evidenceを出力してcommandは成功し、scenario failureがあれば`FAIL`として失敗します。`-RequireQualified`は分離されたstrict gateであり、current fingerprint、package version、`apm.yml` hash、Plan Coverage・Adaptive・profile finalizerのruntime-relevant qualification input fingerprintへ正確に一致するfull `QUALIFIED` evidenceを要求します。
