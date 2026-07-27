# Goal Context real-model manual smoke

## Purpose

PR Review RemediationのGoal Context対応版を、本物のmodelと実際のReady PRでmerge前に1回確認する手順です。PR #60自身を対象にせず、秘密情報やproduction dataを含まないdisposable target repositoryを使用します。

このmanual smokeは、既存の`run-pr-review-remediation-agent-smoke.ps1`が検証するbaseline direct-profile実行の代替ではありません。ここではAPMでPR #60のfull head SHAを導入し、interactiveな二つの親ターンを通してGoal Context固有の運用境界を確認します。

## Pass criteria

- PR #60のfull head SHAからpackageと依存関係を導入している。
- target PRに、既知のcode-quality findingとpurpose-only findingが一つ以上ある。
- `local-reviewer`と`purpose-reviewer`が独立して実行される。
- `review-planner`が両findingとremote review sourceを一つのplanへ統合する。
- Phase 1は`review-plan.md`を生成して停止し、同じ親ターンで実装を始めない。
- completion notificationのdirect linkがtarget PRを開く。
- 利用者が別親ターンを開始し、同じplanを既存Adaptive Implementationへ渡す。
- Phase 2の変更がplanのscopeとacceptanceへ対応し、target repositoryのvalidationが成功する。

## 1. Prerequisites

- PR #60のCIが成功している。
- `gh auth status`、`codex --version`、`apm --version`、`dotnet --version`が成功する。
- APMはCIと同じ0.26.0を使用する。
- disposable target repositoryを作成・push・削除またはarchiveできる。
- Codexのmodel利用権限と、completion notification providerが利用できる。

作業値を設定します。

```powershell
$ProcessRepository = 'suusanex/coding_agent_plan_and_verify_process'
$ProcessPullRequest = 60
$ProcessRoot = '<absolute-path-to-this-process-repository>'
$ProcessPr = gh pr view $ProcessPullRequest --repo $ProcessRepository --json headRefName,headRefOid | ConvertFrom-Json
$ProcessHeadRef = $ProcessPr.headRefName
$ProcessHeadSha = $ProcessPr.headRefOid
$TargetRepository = '<owner>/<disposable-repository>'
$TargetRoot = '<absolute-path-to-disposable-repository>'
```

短縮SHAやbranch名ではなく40桁のfull head SHAであることを確認します。

```powershell
if ($ProcessHeadSha -notmatch '^[0-9a-f]{40}$') { throw 'PR head SHA is not a full SHA.' }
$RemoteHeadSha = ((git ls-remote "https://github.com/$ProcessRepository.git" "refs/heads/$ProcessHeadRef") -split "`t")[0]
if ($RemoteHeadSha -ne $ProcessHeadSha) { throw 'PR head SHA does not match the remote branch.' }
```

remote branchが存在しない、またはSHAが一致しない場合は続行しません。

## 2. Create the disposable target PR

target repositoryの`main`へ最小のbaselineをcommitします。その後、feature branchで次のような意図的に不完全な変更を作成します。

```csharp
public static class ReviewCompletion
{
    public static string BuildMessage(string repository, string pullRequest)
    {
        var number = int.Parse(pullRequest);
        return $"Review completed for {repository} #{number}.";
    }
}
```

この変更には、少なくとも次の二つの既知リスクがあります。

- code-quality: `int.Parse`が不正入力を未処理のまま例外にする。
- purpose-only: messageにtarget PRのdirect URLと、Phase 1停止後に別親ターンでAdaptiveを開始する案内がない。

Goal Contextには、repositoryに含まれるhuman-reviewed fixtureを使用できます。

```powershell
New-Item -ItemType Directory -Path (Join-Path $TargetRoot 'docs') -Force | Out-Null
Copy-Item `
  (Join-Path $ProcessRoot 'tests/pr-review-remediation/PRR-002/fixture/docs/goal-context-direct-review-notification.md') `
  (Join-Path $TargetRoot 'docs/goal-context-direct-review-notification.md')
```

`Copy-Item`のsourceはこのprocess repositoryのcheckoutです。target repositoryでcommitする前に、内容がsynthetic testだけを指し、秘密情報や個人情報を含まないことを確認します。

feature branchをpushし、Ready PRを作成します。base/head OIDとURLを記録します。

```powershell
gh pr create --repo $TargetRepository --base main --head '<feature-branch>' --title 'Manual smoke fixture' --body 'Synthetic PR Review Remediation smoke.'
gh pr view --repo $TargetRepository --json number,url,isDraft,baseRefName,baseRefOid,headRefName,headRefOid
```

Draft PRでは続行しません。Copilot reviewを利用する場合は、この時点でreviewを要求し、terminal reviewとinline commentが揃うまで待ちます。Copilotが利用できない場合は、その状態を「未取得」として記録し、成功扱いに置き換えません。

## 3. Install the exact PR package into the target

target repository rootで実行します。

```powershell
Set-Location $TargetRoot
apm install "$ProcessRepository/apm-packages/pr-review-remediation#$ProcessHeadSha" --target codex,agent-skills --https
apm install "$ProcessRepository/apm-packages/completion-notification-decorator#$ProcessHeadSha" --target codex,agent-skills --https

$ModuleRoot = Join-Path $TargetRoot 'apm_modules/suusanex/coding_agent_plan_and_verify_process'
dotnet run --file (Join-Path $ModuleRoot 'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs') -- $TargetRoot
dotnet run --file (Join-Path $ModuleRoot 'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs') -- $TargetRoot
dotnet run --file (Join-Path $ModuleRoot 'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs') -- $TargetRoot --check
dotnet run --file (Join-Path $ModuleRoot 'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs') -- $TargetRoot --check
```

direct-link notificationを実際に確認する場合はuser-level Codex notification runtimeも必要です。既存設定への変更内容をdry-runで確認してから導入します。

```powershell
$NotificationInstaller = Join-Path $ModuleRoot 'scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs'
dotnet run --file $NotificationInstaller -- --dry-run
dotnet run --file $NotificationInstaller -- install
dotnet run --file $NotificationInstaller -- --check
```

このinstallerはuser-level Codex設定を変更します。dry-runの対象、既存`notify` chain、backup／復旧方法を確認できない場合は停止します。

次を確認します。

- `.agents/skills/pr-review-remediation`と`.agents/skills/goal-context-pr-review`が存在する。
- `.agents/skills/goal-context-authoring`と`.agents/skills/adaptive-implementation-execution`が存在する。
- `.agents/skills/completion-notification-decorator`が存在する。
- `.codex/agents/`にlocal、purpose、planner、HIGH、STANDARD profileが存在する。
- `apm.lock.yaml`が`$ProcessHeadSha`と必要なtransitive dependenciesを記録する。
- targetの`AGENTS.md`と既存`.codex/config.toml`が意図せず変更されていない。

Goal Contextをinstalled canonical validatorで検証します。

```powershell
dotnet run --file '.agents/skills/goal-context-authoring/scripts/validate-goal-context.cs' -- `
  --goal-context 'docs/goal-context-direct-review-notification.md' `
  --mode strict `
  --format json
```

`status: PASS`、`lifecycleStatus: human-reviewed`、`sensitiveReview: passed`を要求します。

## 4. No-send inspection and explicit authorization

model起動前に、target repositoryから外部modelへ提示され得る内容を確認します。

```powershell
git -C $TargetRoot status --short
git -C $TargetRoot ls-files
git -C $TargetRoot diff origin/main...HEAD --stat
git -C $TargetRoot diff origin/main...HEAD
Get-Content -Raw (Join-Path $TargetRoot 'docs/goal-context-direct-review-notification.md')
```

次のいずれかに該当する場合は停止します。

- credential、token、個人情報、production dataが含まれる。
- target PR以外のuncommitted fileがある。
- 選択したGoal Contextまたは送信対象を説明できない。

確認後、外部modelへの送信を承認する場合だけ、`result-template.md`の`External model payload approved`へ`Yes`、承認者、日時、repository、PR、base/head OID、Goal Context hashを記録します。`Yes`がない状態でmodelを起動しません。

## 5. Run Phase 1 in one parent task

target repositoryをworkspaceとして新しいCodex taskを開始し、次を送信します。

```text
$completion-notification-decorator
$goal-context-pr-review

このbranchのReady PRを docs/goal-context-direct-review-notification.md で目的達成レビューしてください。
local-reviewerとpurpose-reviewerを独立に実行し、remote review/comment/checkをreview-plannerで統合してください。
review-plan.mdを作成したところで停止し、同じ親ターンではAdaptive Implementationを開始しないでください。
```

Phase 1完了時に確認します。

- selection artifactがstrict validationのpathとcontent hashを保持する。
- local findingsに`int.Parse`の不正入力処理に関する`LR-*`がある。
- purpose findingsにdirect URLまたは別親ターンhandoff欠落に関する`PUR-*`がある。
- reviewer outputsはいずれもproduction codeを変更していない。
- review planのdecision ledgerがlocal、purpose、取得済みremote sourceを網羅する。
- すべての`Apply` findingが実在するscope IDとacceptance IDへ対応する。
- verdictが`READY_FOR_ADAPTIVE_IMPLEMENTATION`である。
- Phase 1 task内にAdaptive executionやproduction code変更がない。
- completion notificationのdirect linkを開くとtarget PRへ移動する。

条件を満たさない場合はPhase 2へ進みません。

## 6. Run Phase 2 in a separate parent task

Phase 1とは別の新しいCodex taskをtarget repositoryで開始し、生成されたplan pathを明示します。

```text
$completion-notification-decorator
$adaptive-implementation-execution

<review-plan-path> をsource of truthとして実装し、記載されたvalidationを実行してください。
Goal Context BoundaryとNon-goalsを保持し、plan外の変更を追加しないでください。
```

Phase 2完了時に確認します。

- task/thread IDがPhase 1と異なる。
- Adaptive inputのplan pathがPhase 1で生成されたpathと一致する。
- `int.Parse`の不正入力処理とpurpose-only gapがplanどおり修正される。
- acceptanceに記載されたvalidationが成功する。
- unrelated changeがない。
- completion notificationがtarget PRまたはPhase 2結果へのdirect linkを持つ。

## 7. Record and clean up

`result-template.md`をcopyして結果を記録します。raw rollout、credential、個人情報はcommitしません。必要な証拠はID、hash、verdict、artifact path、validation結果に限定します。

失敗した場合も、失敗stage、観測結果、artifact path、再現手順を記録します。失敗を`PASS`へ書き換えません。

人手での作業が必要: 証拠を確認した後、disposable PRをcloseし、repositoryをarchiveまたは削除します。対象を再確認してからGitHub上のcleanupを実行してください。
