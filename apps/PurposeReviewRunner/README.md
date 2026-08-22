# Purpose Review Runner

`purpose-review-runner`は、同じpurpose reviewer sessionを最大3roundまで維持する.NET 10 CLIです。reviewerの目的判断と、provider CLIのsession lifecycleを分離します。

## Configuration

`Environment.SpecialFolder.ApplicationData`配下の`purpose-review-runner/config.json`を作成します。Windowsでは通常`%APPDATA%\purpose-review-runner\config.json`です。例は`config.example.json`を参照してください。

設定可能なのは`provider`、`executable`、`model`、`reasoningEffort`、optional `profile`だけです。`provider`は`codex`、`grok`、`copilot`を選べます。same-session、non-modifying reviewer、最大3round、異常時停止は変更できません。filesystem sandboxによるread-only強制は要件ではありません。GrokとCopilotは副作用なくwrite/edit系toolを禁止できるため、その制約を使います。Codexには同等の安定したtool restrictionが無いので、promptの`Do not modify files`契約だけでnon-modifying reviewerを成立させます。`--ignore-user-config`下のCodex default sandboxはread-onlyのため、別sandboxへの置換ではなく`--dangerously-bypass-approvals-and-sandbox`でsandbox自体を無効化します。この契約はRunner 0.1.1以上が必要です。長時間reviewをforeground commandの寿命から分離するasync job契約はRunner 0.2.0以上が必要です。

## Usage

```powershell
purpose-review-runner version
purpose-review-runner start --repository C:\path\to\repo --context docs\goal-context.md --context C:\path\to\accepted-decisions.md
purpose-review-runner status --run <run-id>
purpose-review-runner continue --run <run-id>
```

`start`と`continue`はprovider完了をforegroundで待ちません。durable jobを登録して独立したworker processを起動し、`jobStatus`が`RUNNING`のJSONを返します。結果は同じ`run-id`で`status`を短時間pollingして取得します。`status`はreviewを再実行しません。

stdoutはprotocol v2の単一JSONです。`FINDINGS`の場合だけ元のimplementation parentが修正・検証し、同じ`run-id`を`continue`します。`COMPLETE`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`では停止します。`RUNNING`なら`status`を繰り返します。1回のCLI呼び出しが失敗しても、新しいrunを作らず同じ`status`を問い合わせ直します。

`start`は1件以上のcontextを要求します。相対pathはrepository root基準で解決し、absolute pathも受理します。context本文をproviderへ渡すのはRound 1だけです。`continue`は保存済みsessionをresumeし、contextや前回outputを再送しません。

output schema v2は`protocolVersion`、`runnerVersion`、`runId`、`round`、`jobStatus`、`status`、`terminal`、`findings`と、必要時の`message`または`error`で構成します。`jobStatus`は`RUNNING`、`SUCCEEDED`、`FAILED`です。実行中の`status`は`RUNNING`です。診断はstderrへ出し、stdoutへ別形式のtextを混在させません。exit codeは0がjob受付または有効なreview結果、1がprovider/process実行失敗、2が引数・config・state・protocol違反です。非0でもstdoutはstatus `ERROR`のschema v2です。

stateは`Environment.SpecialFolder.LocalApplicationData`配下の`purpose-review-runner/runs/<run-id>/`へ保存します。`state.json`はreview制御（session、provider snapshot、round、review status）、`job.json`はjob lifecycle、`result.json`は公開結果です。session handleは公開outputへ出しません。config変更は既存runへ反映されません。workerの診断は同じrun directoryの`worker.log`へ出します。内部コマンド`work`はSkillから使いません。

各runのtranscriptは同じ`LocalApplicationData`のrun directory配下にある`transcript/round-01-prompt.md`、`round-01-response.md`のようなround別ファイルへ保存します。promptとreviewer responseは全文をローカル保存するため、purpose contextやrepository由来の情報を含み得ます。実装対象repositoryには生成されず、`LocalApplicationData`のrun directory内だけに保存されます。これはRunnerが生成してprovider adapterへ渡したreview payloadと、reviewer response本文の監査用であり、provider内部のsystem promptやnetwork payloadを記録するものではありません。

## Build and publish

```powershell
dotnet test tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj
dotnet publish apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r win-x64 --self-contained true
dotnet publish apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r linux-x64 --self-contained true
```

GitHub ReleaseのarchiveをPATH上のuser-owned directoryへ展開し、configをOS userごとに一度作成します。APM SkillはRunner binaryを内包または自動導入しません。

Codex CLIとGrok Build CLIはsemantic persistenceをfresh control付きで確認済みです。GitHub Copilot CLIはsession/resumeの成立を確認済みですが、fresh controlが正解を推測したため同じ強さのsemantic qualificationは与えていません。
