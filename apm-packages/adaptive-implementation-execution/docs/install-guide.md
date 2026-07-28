# Install Guide

## Prerequisites

- APM CLI
- Codex custom agents を使用できる環境
- .NET 10 SDK 以降（現行 APM の不足設定を補完する互換スクリプトを使う場合）
- 対象 repository の `.codex/agents` を確認できる権限

正式サポート target は `codex` と `agent-skills` です。Copilot の model tier switching と re-entry routing はこの package では検証済みとして扱いません。

## Install with APM

対象 repository の root で実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
```

APM install が skill と portable custom agents を導入する本体です。導入後、少なくとも次を確認します。

- `.agents/skills/adaptive-implementation-execution/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/agents/openai.yaml`
- `.agents/skills/adaptive-implementation-execution/refs/intent.md`
- `.agents/skills/adaptive-implementation-execution/refs/handoff.md`
- Codex が生成した `high-implementation-starter` と `standard-implementation-completer` の custom agent entry

現行 APM が生成した Codex TOML に concrete model、reasoning、sandbox 設定がない場合だけ、次節の互換スクリプトで package 付属設定を補完します。

`agents/openai.yaml` は skill とともに展開される Codex 固有 policy で、`allow_implicit_invocation: false` により一般的な実装依頼からの暗黙起動を無効にします。Codex が意図する利用者向けの標準的な明示起動方法は `$adaptive-implementation-execution` ですが、Codex のバージョンによっては explicit-only skill の起動が失敗する既知の問題があります（[openai/codex#23454](https://github.com/openai/codex/issues/23454)）。この場合と上位 workflow からの委譲では、展開済みの `.agents/skills/adaptive-implementation-execution/SKILL.md` を明示的に読み、その内容を実装実行契約として適用します。裸の skill 名による暗黙解決や manifest dependency だけに依存しません。Codex Skill の標準的な起動方法は [公式Skill documentation](https://developers.openai.com/codex/skills) を参照してください。

### Local package validation on APM 0.18.0

この package の manifest は repository root の portable agent を `git: parent` で参照します。APM 0.18.0 は package 全体を local filesystem path から導入すると、parent repository を継承できず `git: parent cannot inherit from a local path dependency` で停止します。

これは repository URL から導入する通常経路とは別の local development 制約です。未公開の変更を local 検証する場合は、skill directory を直接導入し、互換スクリプトと static validator を組み合わせます。

```powershell
apm install C:\path\to\adaptive-implementation-execution\.apm\skills\adaptive-implementation-execution --target agent-skills
dotnet run --file C:\path\to\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- . --dry-run
```

portable agent の `git: parent` dependency は static validator で path existence を確認します。repository URL と branch ref を使った remote install / rollback の実証結果は [Adaptive Routing Validation](examples/adaptive-routing-validation.md) に記録しています。

APM 0.18.0 の Windows remote install は、Git cache の深い checkout path から package をコピーします。この package は skill 内 template を短い `refs/intent.md` と `refs/handoff.md` に配置し、legacy path-length boundary を超えないよう static validator で repository-relative path budget を111文字に制限します。この111文字の境界は、Windows上のAPM 0.18.0 remote smokeで最長の `agents/openai.yaml` が実際に展開されることを根拠とします。将来この上限を広げる場合も、同等のWindows remote installによる実証が必要です。

## Complete missing Codex custom agent settings

package の `codex-agents` には concrete model mapping の初期値があります。補助スクリプトは、現行 APM が model 未設定の custom agent TOML を生成する制約を補う互換処理です。APM が必要な設定を直接生成できる環境では実行不要です。

- `high-implementation-starter`: HIGH_MODEL mapping、high reasoning、workspace-write
- `standard-implementation-completer`: STANDARD_MODEL mapping、high reasoning、workspace-write

実モデル名は skill の意味ではありません。組織の契約、利用枠、品質要求に合わせて package source の TOML を fork し、top-level `model` と `model_reasoning_effort` を変更できます。ただし HIGH_MODEL と STANDARD_MODEL には異なる model mapping が必要です。

補助スクリプトは2つのTOMLだけを `.codex/agents` に同期します。導入先の `AGENTS.md` を読み書きせず、skillの使用や自動選択を設定しません。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --dry-run
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --check
```

APM が生成した model 未設定の同名 TOML は、`name`、`description`、`developer_instructions` だけを持つ既知の APM-generated model-less stub shape と package metadata が一致する場合、初回導入の中間状態として `--force` なしで補完します。model field を持つ、未知の key がある、metadata が異なるなど、APM stub と証明できない同名 TOML は既定で停止します。

衝突内容を確認し、package-owned file と判断できる場合だけ `--force` を指定します。利用者が変更した可能性のあるTOMLを無条件に上書きしません。

`--check` は次を検証します。

- 2つのcustom agent TOMLが存在する
- 両 TOML に non-empty `model` と `model_reasoning_effort` がある
- 両 TOML の `sandbox_mode` が `workspace-write` である
- HIGH_MODEL と STANDARD_MODEL が異なる agent 名と異なる model mapping を使用する

skill と bundled refs、portable agent dependency は package static validator が検証します。

## Collision and merge policy

- `.codex/agents/*.toml`: 内容が同一なら変更しない
- APM-generated model-less stub: 既知の3 key shape、package metadata、agent instruction opening が一致する場合だけ自動補完する
- その他の異なる同名 TOML: 既定では停止し、`--force` の明示がある場合だけ置換する
- skill: APM の ownership に従う。補助スクリプトは skill を読み書きしない
- `AGENTS.md`: 補助スクリプトは存在確認を含めてアクセスしない

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

## Update

```powershell
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --dry-run
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --yes
```

update 後、APM が concrete model 設定を生成しない場合は source TOML の差分を確認し、補助スクリプトを `--dry-run`、必要に応じた `--force`、`--check` の順で再実行します。

## Remove or rollback

最初に APM の direct package を削除します。

```powershell
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --dry-run
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution
```

次に、補助スクリプトが配置したTOMLを確認して削除します。TOMLがpackage sourceと一致しない場合、既定では削除しません。

```powershell
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --remove --dry-run
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --remove
dotnet run --file C:\path\to\package\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --remove --check
```

最後にorphanとなったportable agent packagesをdry-runで確認してpruneします。

```powershell
apm prune --dry-run
apm prune
```

## Migration from the former managed section

旧versionのinstallerがroot `AGENTS.md`へ追加したmanaged sectionは、現在の補助スクリプトでは削除しません。通常のinstall、update、check、removeが `AGENTS.md` へアクセスしないことを優先し、専用cleanup機能も追加していません。

旧sectionが残っている場合は、`<!-- adaptive-implementation-execution:start -->` から対応するend markerまでのpackage-owned sectionだけを人手で削除してください。marker外のrepository固有ルールは保持します。

人手での作業が必要: 旧installerを利用したrepositoryでは、上記markerの有無を確認し、存在する場合だけmanaged sectionを削除します。

## Skill selection

補助スクリプトの実行はskillの使用を強制しません。skillは通常のskill選択規則に従い、利用者が明示指定した場合、またはtaskがこのpackageの直列workflowを明確に必要とする場合に選択されます。選択後の実行順序、HIGH_MODELとSTANDARD_MODELの役割、handoff、re-entry、verification boundaryは `SKILL.md` がsource of truthです。
