# Install Guide

## Prerequisites

- APM CLI
- Codex custom agents を使用できる環境
- profile installer を使う場合は .NET 10 SDK 以降
- 対象 repository の既存 `AGENTS.md` と `.codex/agents` を確認できる権限

正式サポート target は `codex` と `agent-skills` です。Copilot の model tier switching と re-entry routing はこの package では検証済みとして扱いません。

## Install with APM

対象 repository の root で実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
```

導入後、少なくとも次を確認します。

- `.agents/skills/adaptive-implementation-execution/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/references/implementation-intent.md`
- `.agents/skills/adaptive-implementation-execution/references/implementation-completion-handoff.md`
- Codex が生成した `high-implementation-starter` と `standard-implementation-completer` の custom agent entry

APM が agent definition を Codex TOML に変換した場合、model、reasoning effort、sandbox の top-level fields が local policy と一致するか確認してください。

### Local package validation on APM 0.18.0

この package の manifest は repository root の portable agent を `git: parent` で参照します。APM 0.18.0 は package 全体を local filesystem path から導入すると、parent repository を継承できず `git: parent cannot inherit from a local path dependency` で停止します。

これは repository URL から導入する通常経路とは別の local development 制約です。未公開の変更を local 検証する場合は、skill directory を直接導入し、profile installer と static validator を組み合わせます。

```powershell
apm install C:\path\to\adaptive-implementation-execution\.apm\skills\adaptive-implementation-execution --target agent-skills
dotnet run --file C:\path\to\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- . --dry-run
```

portable agent の `git: parent` dependency は static validator で path existence を確認し、repository URL から取得可能になった後に remote install validation を行います。

## Apply the Codex profile mapping

package の `profiles/adaptive-implementation` には concrete model mapping の初期値があります。

- `high-implementation-starter`: HIGH_MODEL mapping、high reasoning、workspace-write
- `standard-implementation-completer`: STANDARD_MODEL mapping、high reasoning、workspace-write

実モデル名は package の意味ではありません。組織の契約、利用枠、品質要求に合わせて TOML の top-level `model` と `model_reasoning_effort` を変更できます。

profile installer は、既存 `AGENTS.md` を置き換えず managed section を追加し、2つの TOML を `.codex/agents` に同期します。

最初に dry-run を実行します。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --dry-run
```

同名 TOML が存在し内容が異なる場合、installer は既定で停止します。package-owned agent と確認できた場合だけ `--force` を指定します。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --force
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --check
```

## Collision and merge policy

- root `AGENTS.md`: managed markers 外の既存内容を保持する
- `.codex/agents/*.toml`: 内容が同一なら変更しない
- 同名 TOML が異なる: 既定では停止し、`--force` の明示がある場合だけ置換する
- skill: APM の ownership に従う。profile installer は skill を上書きしない
- repository-specific coding / security / validation rules: root `AGENTS.md` の既存ルールを優先する

model mapping を変更する場合、package source の profile TOML を直接組織向けに fork するか、導入後の TOML を local ownership として管理してください。後者は update 時の collision 対象になります。

## Verify

package source repository では次を実行します。

```powershell
./scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./scripts/install-adaptive-implementation-local.cs
git diff --check
```

導入先では次を実行します。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --check
```

Codex で skill と両 custom agents が選択可能であることを確認し、[validation scenarios](examples/adaptive-routing-validation.md) の VAL-001〜VAL-008 を参照します。

## Update

最初に update plan を確認します。

```powershell
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --dry-run
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --yes
```

update 後に profile source の差分を確認し、必要なら installer を `--dry-run`、`--force`、`--check` の順で実行します。

## Remove or rollback

profile installer が追加した managed section と TOML を先に確認します。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --remove --dry-run
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --remove
```

TOML が導入後に変更されている場合、installer は既定で削除しません。不要と確認できた場合だけ `--force` を使用します。

その後、APM package を削除します。

```powershell
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --dry-run
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution
```

rollback 後は `AGENTS.md`、`.codex/agents`、`.agents/skills` に意図しない残存や削除がないことを確認してください。
