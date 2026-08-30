# Install Guide

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
```

APMがSkillとportable agentsを導入します。現行APMがCodex agentのconcrete profileを生成しない場合だけ、共通finalizerを実行します。

```powershell
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target --check
```

finalizerは`.codex/agents/*.toml`の`model`、`model_reasoning_effort`、`sandbox_mode`だけを補完します。`AGENTS.md`、Skill、Copilot agentを変更しません。

## Installed semantic owners

| Semantic role | Agent | Default requested model |
| --- | --- | --- |
| Decision-Surface Implementation Owner | `decision-surface-implementation-owner` | `GPT-5.6 Terra (copilot)` / `gpt-5.6-terra` |
| Bounded-Residual Implementation Owner | `bounded-residual-implementation-owner` | `GPT-5.6 Luna (copilot)` / `gpt-5.6-luna` |

model mappingはruntime adapter設定であり、semantic role定義ではありません。組織policy等でmappingを変更する場合も、2 roleを異なるmodel mappingへ割り当て、変更を明示的に記録します。黙って同一tierへfallbackしません。

## GitHub Copilot Chat in VS Code

1. `decision-surface-implementation-owner`をagent pickerから選ぶ。
2. validな`READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION`とtracked handoffがある場合だけ`bounded-residual-implementation-owner`へ移る。
3. validな`NEEDS_DECISION_SURFACE_REENTRY`とtracked re-entry handoffがある場合だけ前者へ戻る。

handoff buttonは遷移候補でありauthorization validatorではありません。stop verdictや`IMPLEMENTATION_COMPLETED`では次agentへ進みません。

## Breaking upgrade from 0.5

0.6.0では旧agent TOML / Copilot agentと旧handoffを削除してから再installします。

- `high-implementation-starter`
- `standard-implementation-completer`
- 0.5 `Implementation Completion Handoff`
- `Legacy Adaptive handoff normalization`

旧artifactを新schemaへ自動変換しません。進行中の旧runは旧versionで完了するか、新しいOriginal Implementation Intentから0.6.0を開始します。

## Verify source repository

```powershell
pwsh -NoProfile -File .\apm-packages\adaptive-implementation-execution\tests\validate-routing-scenarios.ps1
pwsh -NoProfile -File .\apm-packages\adaptive-implementation-execution\scripts\validate-adaptive-implementation-execution.ps1
pwsh -NoProfile -File .\apm-packages\codex-profile-finalizer\tests\validate-finalizer.ps1
```

remote install smokeはcandidate commitをremote refとして参照できる状態で実行します。
