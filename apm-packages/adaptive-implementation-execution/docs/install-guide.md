# Global導入と保守

正式な導入scopeはOSユーザー単位の`--global`です。任意のdirectoryから実行し、work repositoryへの追加installは行いません。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --global --target copilot,codex,agent-skills
$apmUserHome = if ($env:OS -eq 'Windows_NT') { $env:USERPROFILE } else { $env:HOME }
$apmHome = Join-Path $apmUserHome '.apm'
$moduleRoot = Join-Path $apmHome 'apm_modules/suusanex/coding_agent_plan_and_verify_process'
$finalizer = Join-Path $moduleRoot 'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs'
dotnet run --file $finalizer -- --global --dry-run
dotnet run --file $finalizer -- --global
dotnet run --file $finalizer -- --global --check
```

APMがSkillとportable agentsを配布し、FinalizerがCodex agentの対象profile fieldだけを補完します。検証対象APM v0.26.0のhomeは`~/.apm`です。Windowsでは`USERPROFILE`、他OSでは`HOME`をユーザーホームとして解決します。Codex homeは`CODEX_HOME`、未設定時は`~/.codex`です。

Finalizerは`name`、`description`、`developer_instructions`をpackage-owned portable contractと照合します。本文の独自編集、同名agentの衝突、不正TOML、欠落は上書きせず失敗します。`--force`でも本文は修復しません。APMが旧ファイルを残した場合はownershipを確認し、独自編集を退避してAPMによる再配布を完了してから再実行してください。

## 親と子の設定

親`decision-surface-implementation-owner`は`model`、`model_reasoning_effort`、`sandbox_mode`を持たず、現在のsessionで選択したmodelを継続します。固定profileが残る場合は検査を失敗させます。子`bounded-residual-implementation-owner`だけに[overlay](../codex-profile-overlays.json)の3fieldを補完します。Copilotの子modelは`GPT-6 Luna (copilot)`、Codexは`gpt-6-luna`です。

`--dry-run`は変更予定だけを表示し、`--check`は不足・不一致を失敗として検出します。明示済みの異なるprofile値を推奨値へ更新するときだけ`--force`を使います。対象外key、comment、本文、他agent、一般設定、`AGENTS.md`は保持します。一致済みの再実行では変更しません。modulesやoverlayの欠落も失敗です。

現在の親へSkillを明示起動します。人への構造提示、実承認後の子への直列委譲、元親へのre-entryは変わりません。

## 更新・削除・旧local配置からの切替

[共通運用手順](../../../docs/installation-and-maintenance.md#global-lifecycle)に従い`apm update --global`後にFinalizerと`--check`を実行します。global uninstallも同手順に従います。local互換経路や自動削除は提供しません。0.6以前のhandoffは自動移行せず、旧版で完了するか元intentから新規の構造レビューを開始します。

## Source検証

```powershell
pwsh -NoProfile -File ./apm-packages/adaptive-implementation-execution/tests/validate-routing-scenarios.ps1
pwsh -NoProfile -File ./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
pwsh -NoProfile -File ./apm-packages/codex-profile-finalizer/tests/validate-finalizer.ps1
```

remote install smokeはcandidate commitをremote refとして参照できる状態で実行します。
