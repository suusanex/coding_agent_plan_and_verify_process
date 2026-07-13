# Adaptive Implementation Execution

通常の Plan Mode output または短い実装計画から、非自明な実装を HIGH_MODEL が開始し、残作業から構造上の意思決定がなくなった場合だけ STANDARD_MODEL へ直列委譲する APM package です。

## 解決する問題

外部仕様や課題全体の規模が小さくても、実装開始後には責務配置、signature、dependency、production wiring、error handling、state ownership、test seam などの判断が必要になる場合があります。

この package は、実装前の文書だけで model tier を固定せず、HIGH_MODEL が実コードを編集し、build / focused test の evidence を得た後に残存 decision surface を評価します。

## Plan Coverage Flow との違い

この package は implementation-only flow です。

- 通常 Plan、手書き Plan、Issue 内の実装計画だけで開始できる
- Plan Coverage artifacts を必須にしない
- change-risk-triage、runtime contract、test design、coverage ledger、residual decision を再実装しない
- final code review や総合 architecture review を置き換えない

Plan Coverage Flow が必要な課題は、既存の `plan-coverage-residual-flow` を使用してください。

## Flow

```text
ordinary Plan
  -> high-implementation-starter [HIGH_MODEL]
       -> READY_FOR_STANDARD_COMPLETION
            -> standard-implementation-completer [STANDARD_MODEL]
                 -> COMPLETED
                 -> NEEDS_HIGH_MODEL_REENTRY
                      -> high-implementation-starter [HIGH_MODEL]
       -> COMPLETED_BY_HIGH_MODEL
       -> REPLAN_REQUIRED / HUMAN_DECISION_REQUIRED / BLOCKED
```

HIGH_MODEL と STANDARD_MODEL の write-heavy work は並列化しません。安全な delegation point がない場合、HIGH_MODEL が完了まで実装します。

## Package contents

| Content | Path |
| --- | --- |
| Orchestration skill | `.apm/skills/adaptive-implementation-execution/SKILL.md` |
| Implementation Intent reference | skill の `references/implementation-intent.md` |
| Completion Handoff reference | skill の `references/implementation-completion-handoff.md` |
| Portable HIGH_MODEL agent | repository root `.github/agents/high-implementation-starter.agent.md` |
| Portable STANDARD_MODEL agent | repository root `.github/agents/standard-implementation-completer.agent.md` |
| Codex profile guidance | `profiles/adaptive-implementation/AGENTS.md` |
| Codex model mappings | `profiles/adaptive-implementation/agents/*.toml` |
| Profile installer | `scripts/install-adaptive-implementation-local.cs` |
| Static validator | `scripts/validate-adaptive-implementation-execution.ps1` |

Templates are bundled as skill references instead of standalone manifest file dependencies. This keeps the package compatible with APM 0.18.0, which installs skill directories and their `references/` content but rejects standalone file paths as package dependencies.

## Quick start

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
```

必要に応じて package profile の concrete model mapping を導入先へ同期します。

```powershell
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --dry-run
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --force
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --check
```

installer は File-based app であり、`.csproj` は不要です。`--force` は同名 custom agent との衝突内容を確認した後だけ使用してください。

起動例:

```text
$adaptive-implementation-execution を使って、この Plan を実装してください。
```

## Documentation

- [Install guide](docs/install-guide.md)
- [Usage guide](docs/usage-guide.md)
- [Validation scenarios](docs/examples/adaptive-routing-validation.md)

