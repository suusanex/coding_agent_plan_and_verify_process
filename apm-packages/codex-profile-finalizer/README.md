# Codex Profile Finalizer

APM global配布後のCodex agentへ、package-owned overlayの`model`、`model_reasoning_effort`、`sandbox_mode`だけを補完するutilityです。agent本文とSkillはAPMが配布します。

## 使用方法

```powershell
$apmUserHome = if ($env:OS -eq 'Windows_NT') { $env:USERPROFILE } else { $env:HOME }
$apmHome = Join-Path $apmUserHome '.apm'
$moduleRoot = Join-Path $apmHome 'apm_modules/suusanex/coding_agent_plan_and_verify_process'
$finalizer = Join-Path $moduleRoot 'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs'
dotnet run --file $finalizer -- --global --dry-run
dotnet run --file $finalizer -- --global
dotnet run --file $finalizer -- --global --check
```

正式なscopeは`--global`だけです。APM module探索先はOSのユーザーホーム配下の`~/.apm/apm_modules`、Codex agent出力先は`CODEX_HOME/agents`（未設定時`~/.codex/agents`）です。modulesやoverlayの欠落は通常実行とdry-runも失敗します。

overlayは`schemaVersion`、`package`、`profiles`を持ち、各entryに`agent`、`model`、`model_reasoning_effort`、`sandbox_mode`を宣言します。manifest ownershipとpackage-owned `.apm/agents/*.agent.md`のportable contractを照合します。配置済みTOMLのname・description・developer_instructionsが一致しない場合、本文は上書きせず失敗します。不正TOML、欠落、異なるownerの同名agent、overlay間の競合も失敗します。

Adaptiveの親`decision-surface-implementation-owner`は3profile fieldsを持たず、選択済みmodelを継承します。子`bounded-residual-implementation-owner`だけにoverlayを補完します。親に固定profileがある場合は自動削除せず検査を失敗させます。

`--dry-run`は予定変更だけを表示し、`--check`は不足・不一致を失敗にします。異なる明示済みprofile値を推奨値へ変更するときだけ`--force`を使います。forceでも本文・ownership不一致やoverlay競合を無視しません。対象外key、comment、本文、他agent、一般設定、`AGENTS.md`は保持します。再実行で一致済みなら変更しません。

APM更新が旧本文を保持した場合は、独自編集を退避しownershipを確認してAPMによる再配布を完了してください。Finalizerは本文を修復しません。更新・削除・旧local配置からの切替は[共通運用手順](../../docs/installation-and-maintenance.md#global-lifecycle)を参照してください。
