# Codex Profile Finalizer

APMがCodex projectionへ保持しない concrete model、model_reasoning_effort、sandbox_mode を package-owned overlayから補完する共通互換 utilityです。Adaptive Implementationが管理する既存名のCodex agentについては、canonical `.agent.md` の本文も同じ実行で同期します。portable agent contractやSkill自体は変更しません。

## Usage

対象へ必要な APM packageを導入したあと、導入済みmoduleから一度実行します。

project-local導入:

    $moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
    dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
    dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- . --check

`apm install --global` / `apm update --global` のあと:

    $apmHome = if ($env:APM_HOME) { $env:APM_HOME } else { Join-Path $env:USERPROFILE '.apm' }
    $moduleRoot = Join-Path $apmHome 'apm_modules\suusanex\coding_agent_plan_and_verify_process'
    dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- --global
    dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- --global --check

`--global` は `APM_HOME`（未設定時は `~/.apm`）の `apm_modules` を正本の探索先にし、`CODEX_HOME`（未設定時は `~/.codex`）の `agents` へ管理対象を同期します。`--dry-run` は予定変更を表示します。管理対象以外で、明示済み concrete profile の異値を package推奨値へ更新する場合だけ `--force` を使います。異なる package overlay の競合は `--force` でも停止します。

各 owning package の `codex-profile-overlays.json` は、`schemaVersion`、`package`、`profiles`を持ち、各entryに`agent`、`model`、`model_reasoning_effort`、`sandbox_mode`を直接記述します。portable agent contractはpackage-owned `.apm/agents/*.agent.md`が唯一の正本です。配置済みTOMLは正本にしません。

Adaptiveの管理対象は既存名の `decision-surface-implementation-owner.toml` と `bounded-residual-implementation-owner.toml` だけです。通常実行は、利用者の編集やAPMが `Kept user-edited file` として残した旧本文であっても、canonical本文とoverlayへ戻します。この同期に `--force` は不要です。親は `model`、`model_reasoning_effort`、`sandbox_mode` を持たず、現在のsessionの選択済みmodelを継続します。子だけがoverlayの3項目を持ちます。再実行で差分がなければファイルは変えません。`--check` は古い本文と設定を失敗にします。

同名TOMLの独自編集は維持されません。残したい場合は、そのagent名を併用せず別名で管理するか、パッケージをフォークしてください。他のagent TOML、Codexの一般設定、`AGENTS.md`、Skill、Copilot agentは変更しません。
