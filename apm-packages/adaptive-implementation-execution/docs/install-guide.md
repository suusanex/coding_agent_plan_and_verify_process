# Install Guide

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
```

APMがSkillとportable agentsを導入します。Codex targetでは、導入または`apm update`の後に共通finalizerを実行し、導入済みパッケージのcanonical定義へ管理対象agentを同期します。

```powershell
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target --check
```

`apm install --global` または `apm update --global` の後は、project配下ではなくuser-globalの導入結果を同期します。APM homeは環境変数 `APM_HOME`、未設定時は `~/.apm` です。Codex homeは環境変数 `CODEX_HOME`、未設定時は `~/.codex` です。

```powershell
$apmHome = if ($env:APM_HOME) { $env:APM_HOME } else { Join-Path $env:USERPROFILE '.apm' }
$moduleRoot = Join-Path $apmHome 'apm_modules\suusanex\coding_agent_plan_and_verify_process'
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- --global
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- --global --check
```

正本の `apm_modules` または Codex profile overlay が見つからない `--global` は、終了コード 1 で失敗します。成功にはなりません。

finalizerは次の管理対象Codex agentだけを、導入済みパッケージのcanonical `.agent.md` とCodex profile overlayから再生成します。APMが `Kept user-edited file` として旧TOMLを残しても、通常実行で正本へ戻します。この同期に `--force` は不要です。

- `decision-surface-implementation-owner.toml`
- `bounded-residual-implementation-owner.toml`

同名のCodex agent TOMLは更新のたびに上書きされます。独自編集を残したい場合は、このagent名を併用せず、別名で管理するかパッケージをフォークしてください。

他のagent TOML、Codexの一般設定、`AGENTS.md`、Skill、Copilot agentは変更しません。

## 親と子の設定

親 `decision-surface-implementation-owner` は `model`、`model_reasoning_effort`、`sandbox_mode` を持ちません。現在の親sessionの選択済みmodelを継続します。同期時にこれらの固定設定が残っていれば取り除きます。

子 `bounded-residual-implementation-owner` は [codex-profile-overlays.json](../codex-profile-overlays.json) の `model` / `model_reasoning_effort` / `sandbox_mode` を反映します。Copilot側のmodelは `GPT-6 Luna (copilot)`、Codex側のoverlayは `gpt-6-luna` です。両agentの本文はcanonical `.agent.md` と一致させます。

`--check` は古い本文や設定を失敗として検出します。`--dry-run` は変更予定を表示し、ファイルは変えません。一致している状態でもう一度実行してもファイルは変わりません。

Codex / Copilot CLI / VS Codeで現在の親へSkillを明示起動します。別上位processや上位model切替は不要です。人への構造提示で停止し、実承認とreadinessが揃ってから子を直列起動します。手動のagent pickerやhandoff buttonは承認validatorを代替しません。子からは元親へ返します。

## 0.7への更新

0.6以前のhandoffは自動移行せず、旧版で完了するか元intentから新規の構造レビューを開始します。旧0.5 high-implementation-starter / standard-implementation-completerも再利用しません。

管理対象の旧TOML本文や親のmodel pinは、ファイルを削除して再導入する必要はありません。上のfinalizerを通常実行すると、導入済みパッケージの正本へ同期されます。

## Verify source repository

```powershell
pwsh -NoProfile -File .\apm-packages\adaptive-implementation-execution\tests\validate-routing-scenarios.ps1
pwsh -NoProfile -File .\apm-packages\adaptive-implementation-execution\scripts\validate-adaptive-implementation-execution.ps1
pwsh -NoProfile -File .\apm-packages\codex-profile-finalizer\tests\validate-finalizer.ps1
```

remote install smokeはcandidate commitをremote refとして参照できる状態で実行します。
