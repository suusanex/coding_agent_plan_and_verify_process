# Install Guide

## Prerequisites

- APM CLI
- Codex custom agents を使用できる環境
- .NET 10 SDK 以降（必須の profile installer 用）
- 対象 repository の既存 `AGENTS.md` と `.codex/agents` を確認できる権限

正式サポート target は `codex` と `agent-skills` です。Copilot の model tier switching と re-entry routing はこの package では検証済みとして扱いません。

## Install with APM

対象 repository の root で実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
```

APM install だけでは concrete model tier、reasoning、sandbox の profile contract は完了しません。次節の profile installer 適用と `--check` 成功までを通常の必須導入手順とします。

導入後、少なくとも次を確認します。

- `.agents/skills/adaptive-implementation-execution/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/refs/intent.md`
- `.agents/skills/adaptive-implementation-execution/refs/handoff.md`
- Codex が生成した `high-implementation-starter` と `standard-implementation-completer` の custom agent entry

APM が生成した Codex TOML は、次節で package profile の検証済み mapping に同期します。

### Local package validation on APM 0.18.0

この package の manifest は repository root の portable agent を `git: parent` で参照します。APM 0.18.0 は package 全体を local filesystem path から導入すると、parent repository を継承できず `git: parent cannot inherit from a local path dependency` で停止します。

これは repository URL から導入する通常経路とは別の local development 制約です。未公開の変更を local 検証する場合は、skill directory を直接導入し、profile installer と static validator を組み合わせます。

```powershell
apm install C:\path\to\adaptive-implementation-execution\.apm\skills\adaptive-implementation-execution --target agent-skills
dotnet run --file C:\path\to\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- . --dry-run
```

portable agent の `git: parent` dependency は static validator で path existence を確認します。repository URL と branch ref を使った remote install / rollback の実証結果は [Adaptive Routing Validation](examples/adaptive-routing-validation.md) に記録しています。

APM 0.18.0 の Windows remote install は、Git cache の深い checkout path から package をコピーします。この package は skill 内 template を短い `refs/intent.md` と `refs/handoff.md` に配置し、legacy path-length boundary を超えないよう static validator で path budget を検証します。

## Apply the required Codex profile mapping

package の `profiles/ai` には concrete model mapping の初期値があります。この短い source path は Windows の APM cache 展開で path-length boundary を避けるためのもので、導入先の custom agent 名は変わりません。この installer の適用は任意の override ではなく、profile activation の通常の必須手順です。

- `high-implementation-starter`: HIGH_MODEL mapping、high reasoning、workspace-write
- `standard-implementation-completer`: STANDARD_MODEL mapping、high reasoning、workspace-write

実モデル名は package の意味ではありません。組織の契約、利用枠、品質要求に合わせて package source の TOML を fork し、top-level `model` と `model_reasoning_effort` を変更できます。ただし HIGH_MODEL と STANDARD_MODEL には異なる model mapping が必要です。

profile installer は、既存 `AGENTS.md` を置き換えず managed section を追加し、2つの TOML を `.codex/agents` に同期します。

最初に dry-run を実行します。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --dry-run
```

APM が生成した同名 TOML を含め、同名 TOML が存在し内容が異なる場合、installer は既定で停止します。衝突内容を確認し、package profile を適用する場合だけ `--force` を指定します。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --force
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --check
```

`--check` は次をすべて検証します。

- APM-installed skill と bundled refs が存在する
- `high-implementation-starter` と `standard-implementation-completer` の custom agent TOML が存在する
- 両 TOML に non-empty `model` と `model_reasoning_effort` がある
- 両 TOML の `sandbox_mode` が `workspace-write` である
- HIGH_MODEL と STANDARD_MODEL が異なる agent 名と異なる model mapping を使用する

`--check` が失敗した状態では profile を起動しません。

## Collision and merge policy

- root `AGENTS.md`: managed markers 外の既存内容を保持する
- `.codex/agents/*.toml`: 内容が同一なら変更しない
- 同名 TOML が異なる: 既定では停止し、`--force` の明示がある場合だけ置換する
- skill: APM の ownership に従う。profile installer は skill を上書きしない
- repository-specific coding / security / validation rules: root `AGENTS.md` の既存ルールを優先する

model mapping を変更する場合、package source の profile TOML を組織向けに fork して installer を実行してください。導入後の TOML を直接変更した場合は update と `--check` の collision 対象になります。

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

update 後に profile source の差分を確認し、installer を `--dry-run`、必要に応じた `--force`、`--check` の順で必ず再実行します。

## Remove or rollback

最初に APM の direct package を削除します。この時点では APM 0.18.0 が transitive portable agent packages を orphan として残すため、後続の profile removal と `apm prune` まで実行します。

```powershell
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --dry-run
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution
```

次に、profile installer が追加した managed section と TOML を確認して削除します。installer は APM package の外にある source checkout から実行してください。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --remove --dry-run
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --remove
```

TOML が導入後に変更されている場合、installer は既定で削除しません。不要と確認できた場合だけ `--force` を使用します。削除後は `--remove --check` を実行します。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --remove --check
```

最後に orphan となった portable agent packages を dry-run で確認し、prune します。

```powershell
apm prune --dry-run
apm prune
```

dry-run にこの package の2つの portable agents 以外が表示された場合は、他 package の ownership を確認するまで `apm prune` を実行しないでください。

rollback 後は `AGENTS.md`、`.codex/agents`、`.agents/skills` に意図しない残存や削除がないことを確認してください。
