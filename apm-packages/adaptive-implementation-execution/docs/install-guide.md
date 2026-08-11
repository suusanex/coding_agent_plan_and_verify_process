# Install Guide

## Prerequisites

- APM CLI
- Codex custom agents を使用できる環境
- GitHub Copilot Chat custom agentsを使用できるVS Code環境（Copilot経路を使う場合）
- .NET 10 SDK 以降（現行 APM の不足設定を補完する互換スクリプトを使う場合）
- 対象 repository の `.codex/agents` / `.github/agents` を確認できる権限

正式サポート target は `copilot`、`codex`、`agent-skills` です。repositoryで固定しているAPM CLIは0.26.0です。APMの`vscode`入力は`copilot`へ正規化され、`github-copilot`は有効なAPM targetではありません。

## Install with APM

対象 repository の root で実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
```

APM install が skill と portable custom agents を導入する本体です。導入後、少なくとも次を確認します。

- `.agents/skills/adaptive-implementation-execution/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/refs/intent.md`
- `.agents/skills/adaptive-implementation-execution/refs/handoff.md`
- `.github/agents/high-implementation-starter.agent.md`
- `.github/agents/standard-implementation-completer.agent.md`
- Codex が生成した `high-implementation-starter` と `standard-implementation-completer` の custom agent entry

現行 APM が生成した Codex TOML に concrete model、reasoning、sandbox 設定がない場合だけ、導入済みmoduleの共通 finalizerで package-owned overlay を補完します。

### Local package validation on APM 0.26.0

この package の manifest は repository root のportable agentを`git: parent`で参照します。APM 0.26.0でもpackage全体をlocal filesystem pathから導入すると、parent repositoryを継承できず`git: parent cannot inherit from a local path dependency`で停止します。

これは repository URL から導入する通常経路とは別の local development 制約です。未公開の変更を local 検証する場合は、skill directory を直接導入し、互換スクリプトと static validator を組み合わせます。

```powershell
apm install C:\path\to\adaptive-implementation-execution\.apm\skills\adaptive-implementation-execution --target agent-skills
dotnet run --file C:\path\to\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs -- . --dry-run
```

portable agent の `git: parent` dependency は static validator で path existence を確認します。repository URL と branch ref を使った remote install / rollback の実証結果は [Adaptive Routing Validation](examples/adaptive-routing-validation.md) に記録しています。

Windows remote installはGit cacheの深いcheckout pathからpackageをコピーするため、このpackageはskill内templateを短い`refs/intent.md`と`refs/handoff.md`に配置し、legacy path-length boundaryを超えないようstatic validatorでpath budgetを検証します。

## GitHub Copilot Chat in VS Code

APM install後、VS Codeでrepositoryを開き、Copilot Chatのagent pickerから`high-implementation-starter`を選択します。fresh intakeで`standard-implementation-completer`を選ばないでください。

| Role | Agent | Requested model |
| --- | --- | --- |
| HIGH non-local decision closure | `high-implementation-starter` | `GPT-5.6 Terra (copilot)` |
| Decision-closed STANDARD implementation | `standard-implementation-completer` | `GPT-5.6 Luna (copilot)` |
| Structural re-entry | `high-implementation-starter` | `GPT-5.6 Terra (copilot)` |

HIGHからSTANDARDへのhandoff buttonはvalidな`READY_FOR_STANDARD_COMPLETION`とtracked artifactがある場合だけ使います。`COMPLETED_BY_HIGH_MODEL`、`REPLAN_REQUIRED`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`では次agentへ進みません。STANDARDからHIGHへのbuttonは`NEEDS_HIGH_MODEL_REENTRY`とtracked re-entry artifactがある場合だけ使います。

modelがpickerにない、organization policyで禁止される、またはobserved modelがrequested modelと異なる場合は実行済みとして扱いません。HIGHをLunaで黙って代替せず、管理者への確認または明示的なadapter mapping変更を行い、requested / observed modelをmanual smoke evidenceへ記録します。

Design Pair Implementation HandoffはAdaptiveへのvalid inputとして保持されます。`design-pair-implementation-execution` packageも`copilot` targetを宣言し、GitHub Copilot CLI上の明示選択・post-map対話・durable handoff・READY後のAdaptive開始はDesign Pair packageのformal supportです。導入時はAdaptiveとDesign Pairを`--target copilot,agent-skills`でco-installします。

## Complete missing Codex custom agent settings

package の `codex-profile-overlays.json` には concrete model mapping の初期値があります。共通 finalizerは、現行 APM が model 未設定の custom agent TOML を生成する制約を補う互換処理です。APM が必要な設定を直接生成できる環境では no-op になります。

- `high-implementation-starter`: HIGH_MODEL mapping、high reasoning、workspace-write
- `standard-implementation-completer`: STANDARD_MODEL mapping、high reasoning、workspace-write

実モデル名は skill の意味ではありません。組織の契約、利用枠、品質要求に合わせて owning package の `codex-profile-overlays.json` を変更し、top-level `model` と `model_reasoning_effort` を変更できます。ただし HIGH_MODEL と STANDARD_MODEL には異なる model mapping が必要です。

finalizerはoverlayに対応するTOMLの `model`、`model_reasoning_effort`、`sandbox_mode` だけを補完します。導入先の `AGENTS.md` を読み書きせず、skillの使用や自動選択を設定しません。

```powershell
dotnet run --file C:\path\to\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs -- C:\path\to\target --dry-run
dotnet run --file C:\path\to\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs -- C:\path\to\target
dotnet run --file C:\path\to\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs -- C:\path\to\target --check
```

APM が生成した model 未設定の同名 TOML は、top-level `name` が package-owned agent と一致する場合、初回導入の中間状態として `--force` なしで補完します。明示済み profile field が推奨値と異なる場合は既定で停止し、`--force` のときだけ更新します。

衝突内容を確認し、package-owned file と判断できる場合だけ `--force` を指定します。利用者が変更した可能性のあるTOMLを無条件に上書きしません。

`--check` は次を検証します。

- 2つのcustom agent TOMLが存在する
- 両 TOML に non-empty `model` と `model_reasoning_effort` がある
- 両 TOML の `sandbox_mode` が `workspace-write` である
- HIGH_MODEL と STANDARD_MODEL が異なる agent 名と異なる model mapping を使用する

skill と bundled refs、portable agent dependency は package static validator が検証します。

## Collision and merge policy

- `.codex/agents/*.toml`: 3つの profile field が同一なら変更しない
- APM-generated model-less stub: top-level `name` と package-owned agent の一致を確認して自動補完する
- 明示済み profile field が異なる同名 TOML: 既定では停止し、`--force` の明示がある場合だけ対象fieldを更新する
- skill: APM の ownership に従う。finalizerは skill を読み書きしない
- `.github/agents/*.agent.md`: 初回APM install時に異なる未管理同名fileがある場合は`--force`なしで保持される。内容を確認せず`--force`を使わない
- `AGENTS.md`: finalizerは存在確認を含めてアクセスしない

## Verify

package source repository では次を実行します。

```powershell
./scripts/validate-adaptive-implementation-execution.ps1
./scripts/validate-adaptive-implementation-apm-smoke.ps1 -Repository suusanex/coding_agent_plan_and_verify_process -Ref <full-commit-sha>
dotnet publish ./../codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs
git diff --check
```

導入先では次を実行します。

```powershell
dotnet run --file C:\path\to\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs -- C:\path\to\target --check
```

## Update

```powershell
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --dry-run
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --yes
```

update 後、APM が concrete model 設定を生成しない場合は overlay の差分を確認し、共通 finalizerを `--dry-run`、必要に応じた `--force`、`--check` の順で再実行します。

## Remove or rollback

最初に APM の direct package を削除します。

```powershell
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --dry-run
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution
```

次に、finalizerが補完したTOMLを確認して削除します。明示変更されたprofile fieldは、内容を確認してから人手で扱います。

```powershell
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --dry-run
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution
```

最後にorphanとなったportable agent packagesをdry-runで確認してpruneします。

```powershell
apm prune --dry-run
apm prune
```

## Migration from the former managed section

旧versionのinstallerがroot `AGENTS.md`へ追加したmanaged sectionは、finalizerでは削除しません。通常のinstall、update、check、removeが `AGENTS.md` へアクセスしないことを優先し、専用cleanup機能も追加していません。

旧sectionが残っている場合は、`<!-- adaptive-implementation-execution:start -->` から対応するend markerまでのpackage-owned sectionだけを人手で削除してください。marker外のrepository固有ルールは保持します。

人手での作業が必要: 従来のmanaged-section導入経路を利用したrepositoryでは、上記markerの有無を確認し、存在する場合だけmanaged sectionを削除します。

## Skill selection

finalizerの実行はskillの使用を強制しません。skillは利用者が `/adaptive-implementation-execution` で slash 起動した場合だけ選択され、通常の「実装して」「このPlanを実装して」、および「Adaptive Implementationを使って」などの自然文での名前言及だけでは選択されません。frontmatter の `disable-model-invocation: true` により model 判断での暗黙起動を禁止し、`user-invocable: true` により利用者の slash 明示起動は維持します。選択後の実行順序、HIGH_MODELとSTANDARD_MODELの役割、handoff、re-entry、verification boundaryは `SKILL.md` がsource of truthです。
