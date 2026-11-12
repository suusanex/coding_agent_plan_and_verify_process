# Install Guide

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
```

APMがSkillとportable agentsを導入します。現行APMがCodex agentのconcrete profileを生成しない場合だけ、共通finalizerを実行します。

```powershell
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target --check
```

finalizerは`.codex/agents/*.toml`の`model`、`model_reasoning_effort`、`sandbox_mode`だけを補完します。`AGENTS.md`、Skill、Copilot agentを変更しません。

## 親と子の設定

親decision-surface-implementation-ownerはmodel指定なし。現在の親sessionで契約を読み、選択済みmodelを使います。子bounded-residual-implementation-ownerだけGPT-6 Luna (copilot) / gpt-6-lunaを設定します。finalizerは子だけを補完し、親projectionのmodel / reasoning / sandbox pinはエラーにします。

Codex / Copilot CLI / VS Codeで現在の親へSkillを明示起動します。別上位processや上位model切替は不要です。人への構造提示で停止し、実承認とreadinessが揃ってから子を直列起動します。手動のagent pickerやhandoff buttonは承認validatorを代替しません。子からは元親へ返します。

## 0.7への更新

旧親projectionのmodel pinや旧agent本文を確認し、package管理下の旧projectionを削除してAPMから再導入します。独自変更は自動削除・上書きしません。finalizer --forceでも親pinを黙って上書きしません。

0.6以前のhandoffは自動移行せず、旧版で完了するか元intentから新規の構造レビューを開始します。旧0.5 high-implementation-starter / standard-implementation-completerも再利用しません。

## Verify source repository

```powershell
pwsh -NoProfile -File .\apm-packages\adaptive-implementation-execution\tests\validate-routing-scenarios.ps1
pwsh -NoProfile -File .\apm-packages\adaptive-implementation-execution\scripts\validate-adaptive-implementation-execution.ps1
pwsh -NoProfile -File .\apm-packages\codex-profile-finalizer\tests\validate-finalizer.ps1
```

remote install smokeはcandidate commitをremote refとして参照できる状態で実行します。
