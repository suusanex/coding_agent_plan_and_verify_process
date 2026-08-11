# Codex Profile Finalizer

APM 0.26.0 が Codex projection に保持できない concrete model、model_reasoning_effort、sandbox_mode を package-owned overlay metadataから補完する共通互換 utilityです。portable agent contractやSkillは変更しません。

## Usage

対象 repository で必要な APM packageをすべて導入した後、導入済みmoduleから一度実行します。

    $moduleRoot = ".\\apm_modules\\suusanex\\coding_agent_plan_and_verify_process"
    dotnet run --file "$moduleRoot\\apm-packages\\codex-profile-finalizer\\scripts\\finalize-codex-agent-profiles.cs" -- .
    dotnet run --file "$moduleRoot\\apm-packages\\codex-profile-finalizer\\scripts\\finalize-codex-agent-profiles.cs" -- . --check

`--dry-run` は予定変更を表示し、`--force` は明示済み concrete profile の異値を package推奨値へ更新します。異なる package overlay の競合は `--force` でも停止します。

各 owning package の `codex-profile-overlays.json` は、`schemaVersion`、`package`、`profiles`を持ち、各entryに`agent`、`model`、`model_reasoning_effort`、`sandbox_mode`を直接記述します。portable agent contractはpackage-owned `.apm/agents/*.agent.md`が唯一の正本です。APMが将来これらのfieldを正しくprojectionできる場合、finalizerはno-opになります。
