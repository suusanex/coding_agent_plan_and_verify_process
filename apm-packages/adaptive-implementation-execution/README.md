# Adaptive Implementation Execution

通常の Plan Mode output、短い実装計画、または明示選択された Design Pair handoff から、非自明な実装を HIGH_MODEL が開始し、残作業から構造上の意思決定がなくなった場合だけ STANDARD_MODEL へ直列委譲する APM package です。

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

## Design Pair input

`design-pair-implementation-execution` を利用者が明示選択した場合、この package は tracked Design Pair handoff を追加 input として受け取ります。binding なのは handoff の `Locked Decisions` に Decision ID と explicit human confirmation がある entry だけです。

Target Map、Discussed-Unlocked、Adaptive-Owned、Known Evidence、file / symbol references は HIGH_MODEL の通常 authority または allowed edit surface を拘束しません。Locked Decision conflict は黙って変更せず、Decision ID と actual-code evidence を伴う stop verdict で返します。Design Pair 未使用時の通常 Adaptive route は変わりません。

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
| Implementation Intent reference | skill の `refs/intent.md` |
| Completion Handoff reference | skill の `refs/handoff.md` |
| Portable HIGH_MODEL agent | repository root `.github/agents/high-implementation-starter.agent.md` |
| Portable STANDARD_MODEL agent | repository root `.github/agents/standard-implementation-completer.agent.md` |
| Codex agent configuration sources | `codex-agents/*.toml` |
| Compatibility installer | `scripts/install-adaptive-implementation-local.cs` |
| Static validator | `scripts/validate-adaptive-implementation-execution.ps1` |

Templates are bundled inside the skill instead of being standalone manifest file dependencies. Their short `refs/` paths keep APM 0.18.0 remote installs below the legacy Windows path-length boundary while preserving separate template files.

## Quick start

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
```

APM install が skill と portable custom agents を導入する本体です。現行 APM が `.codex/agents/*.toml` に concrete model 設定を生成しない場合だけ、互換処理として package 付属の設定を同期し、検証します。

```powershell
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --dry-run
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --check
```

installer は File-based app であり、`.csproj` は不要です。APM が生成した model 未設定の同名 custom agent は、既知の APM stub shape と package metadata が一致する場合だけ `--force` なしで補完します。それ以外の異なる同名 TOML は衝突として停止するため、内容を確認して package-owned file と判断できる場合だけ `--force` を指定します。

補助スクリプトがアクセスする導入先ファイルは2つの `.codex/agents/*.toml` だけです。`AGENTS.md` を作成・変更・削除せず、実行しても skill の使用や自動選択を意味しません。`--check` は model / reasoning / workspace-write 設定、role ごとの agent 名、HIGH_MODEL と STANDARD_MODEL の異なる model mapping を検証します。APM が必要な設定を直接生成できるようになれば、この互換処理は不要になる可能性があります。

skill の選択条件と、選択後の実行順序、handoff、re-entry、verification boundary の source of truth は `.apm/skills/adaptive-implementation-execution/SKILL.md` です。この package は repository 内のすべての Plan や実装作業へ skill を強制しません。

起動例:

```text
$adaptive-implementation-execution を使って、この Plan を実装してください。
```

## Documentation

- [Install guide](docs/install-guide.md)
- [Usage guide](docs/usage-guide.md)
- [Validation scenarios](docs/examples/adaptive-routing-validation.md)
