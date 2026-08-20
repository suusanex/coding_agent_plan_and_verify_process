# Purpose Review Runner

`purpose-review-runner`は、同じpurpose reviewer sessionを最大3roundまで維持する.NET 10 CLIです。reviewerの目的判断と、provider CLIのsession lifecycleを分離します。

## Configuration

`Environment.SpecialFolder.ApplicationData`配下の`purpose-review-runner/config.json`を作成します。Windowsでは通常`%APPDATA%\purpose-review-runner\config.json`です。例は`config.example.json`を参照してください。

設定可能なのは`provider`、`executable`、`model`、`reasoningEffort`、optional `profile`だけです。`provider`は`codex`、`grok`、`copilot`を選べます。same-session、read-only、最大3round、異常時停止は変更できません。

## Usage

```powershell
purpose-review-runner version
purpose-review-runner start --repository C:\path\to\repo --context docs\goal-context.md --context C:\path\to\accepted-decisions.md
purpose-review-runner continue --run <run-id>
```

stdoutはprotocol v1の単一JSONです。`FINDINGS`の場合だけ元のimplementation parentが修正・検証し、同じ`run-id`を`continue`します。`COMPLETE`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`では停止します。

`start`は1件以上のcontextを要求します。相対pathはrepository root基準で解決し、absolute pathも受理します。context本文をproviderへ渡すのはRound 1だけです。`continue`は保存済みsessionをresumeし、contextや前回outputを再送しません。

output schema v1は`protocolVersion`、`runnerVersion`、`runId`、`round`、`status`、`terminal`、`findings`と、必要時の`message`または`error`で構成します。診断はstderrへ出し、stdoutへ別形式のtextを混在させません。exit codeは0が有効なreview結果、1がprovider/process実行失敗、2が引数・config・state・protocol違反です。非0でもstdoutはstatus `ERROR`のschema v1です。

stateは`Environment.SpecialFolder.LocalApplicationData`配下の`purpose-review-runner/runs/<run-id>/state.json`へ保存します。session handleは公開outputへ出しません。config変更は既存runへ反映されません。

## Build and publish

```powershell
dotnet test tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj
dotnet publish apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r win-x64 --self-contained true
dotnet publish apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r linux-x64 --self-contained true
```

GitHub ReleaseのarchiveをPATH上のuser-owned directoryへ展開し、configをOS userごとに一度作成します。APM SkillはRunner binaryを内包または自動導入しません。

Codex CLIとGrok Build CLIはsemantic persistenceをfresh control付きで確認済みです。GitHub Copilot CLIはsession/resumeの成立を確認済みですが、fresh controlが正解を推測したため同じ強さのsemantic qualificationは与えていません。
