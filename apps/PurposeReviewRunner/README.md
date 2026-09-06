# Purpose Review Runner

`purpose-review-runner`は、同じpurpose reviewer sessionを最大3roundまで維持する.NET 10 CLIです。reviewerの目的判断と、provider CLIのsession lifecycleを分離します。

## Install / Update

通常利用者の配布経路は GitHub Release とする。現在の version に対応する Release の asset を取得し、archive の内容を PATH 上の user-owned directory へ展開する。

- Windows: `purpose-review-runner-win-x64.zip`
- Linux: `purpose-review-runner-linux-x64.tar.gz`

展開したディレクトリを PATH に追加し、実行ファイルを `purpose-review-runner` として呼び出せる状態にする。install path は既存の PATH 上の user-owned directory 方針に従い、環境固有の canonical path は定めない。

初回だけ、Release に同梱される `config.example.json` を参照して user-level config を作成する。設定ファイルは Runner binary の配置先とは別に管理する。`Environment.SpecialFolder.ApplicationData` 配下の `purpose-review-runner/config.json` を使用し、Windows では通常 `%APPDATA%\purpose-review-runner\config.json` となる。state も binary の配置先とは別の user-level location（`Environment.SpecialFolder.LocalApplicationData` 配下）に保存される。

更新時は、同じ install directory に新しい version の Release archive を展開して、既存の Runner files を置き換える。通常の binary update では既存の config/state を作り直したり移行したりしない。更新後は次で version と protocol を確認する。

```powershell
purpose-review-runner version
```

## Release / Maintainer

Runner version の正本は `apps/PurposeReviewRunner/Contracts.cs` の `Protocol.RunnerVersion` と `apps/PurposeReviewRunner/PurposeReviewRunner.csproj` の `<Version>` である。両者を確認し、既存の tag contract に従って `purpose-review-runner-v<runner-version>` tag を作成して push する。例えば version が `0.3.0` なら次の tag となる。

```powershell
git tag purpose-review-runner-v0.3.0
git push origin purpose-review-runner-v0.3.0
```

`purpose-review-runner-v*` tag push で `.github/workflows/release-purpose-review-runner.yml` が起動する。workflow は test、Windows `win-x64` / Linux `linux-x64` の self-contained publish、tag と Runner version の整合確認、sample config の同梱、archive、checksum、GitHub Release 作成まで担当する。tag と Runner version が一致しない場合は検証で失敗し、Release は作成されない。

Release には次の asset が生成される。

- `purpose-review-runner-win-x64.zip`
- `purpose-review-runner-linux-x64.tar.gz`
- `config.example.json`
- `SHA256SUMS`

同じ version の tag または Release が既に存在する場合は、重複発行せず既存の状態を調査する。

## Configuration

`Environment.SpecialFolder.ApplicationData`配下の`purpose-review-runner/config.json`を作成します。Windowsでは通常`%APPDATA%\purpose-review-runner\config.json`です。例は`config.example.json`を参照してください。

設定可能なのは`provider`、`executable`、`model`、`reasoningEffort`、optional `profile`だけです。`provider`は`codex`、`grok`、`copilot`を選べます。same-session、non-modifying reviewer、最大3round、異常時停止は変更できません。filesystem sandboxによるread-only強制は要件ではありません。reviewerはshellで`git diff`、`git log`、`git show`などの調査を行えます。source、tests、docs、Git状態、設定、外部サービスを変更しない役割契約はshell経由にも適用されます。shellからの変更を技術的に防止する保証ではありません。

Grokは`--tools read,view,grep,shell`と`--permission-mode bypassPermissions`で調査用shellを利用できるようにし、write/edit系toolと委任は引き続き制限します。Copilotは`bash`・`powershell`とそのsession操作toolを公開し、`--allow-tool=shell`で実行を許可します。tool公開と実行許可は別の設定です。Codexは従来どおり`--dangerously-bypass-approvals-and-sandbox`とpromptの変更禁止契約を使います。独自の差分収集器やshell command判定器は追加せず、既存のprovider CLIとGitを利用します。設定の根拠は[Grokのpermission仕様](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/22-permissions-and-safety.md)と[Copilotのtool仕様](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#tool-availability-values)です。

`requiredOutcome`による成果中心のfindingはRunner 0.3.0 / protocol v3で導入しました。shell調査と目的逸脱レビューは0.2.3、async jobは0.2.0、Windowsのrestrictive Job Objectからの独立起動は0.2.1、CopilotへのBOMなしUTF-8標準入力prompt転送は0.2.2で導入しました。reviewerへ送る自然言語instructionは日本語、BEGIN_PURPOSE_REVIEWなどのmachine-readable contractは英語です。

## Usage

```powershell
purpose-review-runner version
purpose-review-runner start --repository C:\path\to\repo --context docs\goal-context.md --context C:\path\to\accepted-decisions.md
purpose-review-runner status --run <run-id>
purpose-review-runner continue --run <run-id>
```

`start`と`continue`はprovider完了をforegroundで待ちません。durable jobを登録して独立したworker processを起動し、`jobStatus`が`RUNNING`のJSONを返します。結果は同じ`run-id`で`status`を短時間pollingして取得します。`status`はreviewを再実行しません。workerは起動時に親のstdin/stdout/stderrを継承しません。この分離はimplementation parentやproviderの種類に依存しません。Windowsでは現在プロセスがJob Object内かどうかを見て起動経路を選びます。Jobに入っていなければdetached `CreateProcess`です。Job内ならimmediate Jobのbreakaway可否に関わらず、呼び出し元Job chainを継承しない`Win32_Process.Create`に`CREATE_BREAKAWAY_FROM_JOB`を付けて起動します。nested JobのancestorやWMI provider host側Jobへ残す経路は使いません。独立起動できなければ同じJobへ残さず`WORKER_START_FAILED`で停止します。

stdoutはprotocol v3の単一JSONです。`FINDINGS`の場合だけ元のimplementation parentが修正・検証し、同じ`run-id`を`continue`します。`COMPLETE`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`では停止します。`RUNNING`なら`status`を繰り返します。1回のCLI呼び出しが失敗しても、新しいrunを作らず同じ`status`を問い合わせ直します。

`start`は1件以上のcontextを要求します。相対pathはrepository root基準で解決し、absolute pathも受理します。context本文をproviderへ渡すのはRound 1だけです。`continue`は保存済みsessionをresumeし、contextや前回outputを再送しません。

## Review criteria and evidence

contextは元の問題・期待成果、承認されたscope・採用判断、実装方針として区別します。ユーザーが明示したsourceや目的変更を優先し、計画の新しさだけで当初目的を上書きしません。毎round、利用経路での成果、表面的な充足、優先順位、non-goals、MVP境界、棄却案、周辺機構への偏りを評価します。変更量や設計の好みだけをfindingにせず、目的に必要な補助機構や承認済み手動工程を誤って問題にしません。

reviewerはcontextで明示されたbaseを優先し、なければtaskとGit履歴から比較基準を特定します。確認したbaseのcommit ID、HEAD、未コミット変更の有無を同じsessionで保持し、初回baseからの累積差分と前回round後の変更を調査します。staged、unstaged、関連するuntracked fileも含み、workspaceの評価とPRへ含まれる変更の評価を区別します。前回の未コミット状態が残っていない場合、HEAD間のdiffを完全なround差分とみなしません。Gitや比較基準がない場合も調査可能な現在の実装を評価し、比較限界を報告します。review専用commit、stash、独自snapshotは作りません。

前回指摘も再評価し、誤り・過剰要求を訂正または撤回します。`requiredOutcome`は成立すべき状態・振る舞い・制約を示す必須項目です。具体的な修正方式はparentが設計し、追加・削除・縮小・既存経路への統合などから選びます。複数componentにまたがる責務やauthorityの逆転もfindingであり、関数単位の修正指示に落とす必要はありません。actionableとは、目的との不一致と必要成果が根拠付きで特定され、parentが修正方針を判断できることです。`message`には比較基準、目的判断の根拠、未検証事項と、解消・訂正・撤回したfinding IDと理由を記載します。parentの疑義が既存の作業記録にある場合も独立に調査します。過去出力の再送は不要です。

`COMPLETE`はfindingがなく、今回のscopeの主要成果と否定条件を判断する十分な証拠がある場合に限ります。必要な証拠を取得できなければ`BLOCKED`、目的やscopeの選択が必要なら`HUMAN_DECISION_REQUIRED`です。承認済みの対象外事項や、判定を左右しない未検証事項を新しいblockerにはしません。

output schema v3は`protocolVersion`、`runnerVersion`、`runId`、`round`、`jobStatus`、`status`、`terminal`、`findings`と、必要時の`message`または`error`で構成します。findingは`id`、`severity`、`title`、`summary`、`evidence`、`requiredOutcome`を要求します。`requiredOutcome`の欠落・null・空白、旧`requiredChange`や両項目の混在は不正結果です。成果の具体的な内容はreviewerが判断し、parserは修正手順や関数名を要求しません。`jobStatus`は`RUNNING`、`SUCCEEDED`、`FAILED`です。実行中の`status`は`RUNNING`です。診断はstderrへ出し、stdoutへ別形式のtextを混在させません。exit codeは0がjob受付または有効なreview結果、1がprovider/process実行失敗、2が引数・config・state・protocol違反です。非0でもstdoutはstatus `ERROR`のschema v3です。

v3はv2と非互換です。既存のv2 runは開始時のRunnerで完了させ、RunnerとSkillの更新後の新しい作業からv3を利用します。v2 stateの`continue`やv2保存結果の`status`は`STATE_INCOMPATIBLE`で停止します。旧結果の自動変換、stateの移行、sessionの再構築は行いません。configとjob lifecycleのschemaは変更しません。

stateは`Environment.SpecialFolder.LocalApplicationData`配下の`purpose-review-runner/runs/<run-id>/`へ保存します。`state.json`はreview制御（session、provider snapshot、round、review status）、`job.json`はjob lifecycle、`result.json`は公開結果です。session handleは公開outputへ出しません。config変更は既存runへ反映されません。worker起動処理の診断は同じrun directoryの`launcher.log`へ出します。`worker.log`は`work` processが起動してからの診断です。内部コマンド`work`はSkillから使いません。`PURPOSE_REVIEW_RUNNER_CONFIG_PATH`と`PURPOSE_REVIEW_RUNNER_STATE_ROOT`を両方指定すると、通常の`%APPDATA%` / `%LOCALAPPDATA%`の代わりにそのconfigとstateをworkerも参照します。launcher.logにはJob flags、Job limit query の失敗、選択した起動経路、native / WMI error、worker PIDを残します。provider prompt、response、token、credential、environment全件は記録しません。

各runのtranscriptは同じ`LocalApplicationData`のrun directory配下にある`transcript/round-01-prompt.md`、`round-01-response.md`のようなround別ファイルへ保存します。promptとreviewer responseは全文をローカル保存するため、purpose contextやrepository由来の情報を含み得ます。実装対象repositoryには生成されず、`LocalApplicationData`のrun directory内だけに保存されます。これはRunnerが生成してprovider adapterへ渡したreview payloadと、reviewer response本文の監査用であり、provider内部のsystem promptやnetwork payloadを記録するものではありません。

## Build locally

以下は開発・検証用、または Release 前のローカル build／unreleased build の手動検証用である。通常利用者が `dotnet publish` の成果物を手動配布する用途ではなく、通常利用には上記の GitHub Release archive を使用する。

```powershell
dotnet test tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj
dotnet publish apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r win-x64 --self-contained true
dotnet publish apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r linux-x64 --self-contained true
```

通常の unit / CI test は Job Object と WMI をスタブします。Linux CI は detached worker の process-level 寿命確認を維持します。Windows の実 Job Object / 実 WMI 経路は opt-in qualification です。

```powershell
$env:PURPOSE_REVIEW_RUNNER_WINDOWS_JOB_QUALIFICATION = '1'
dotnet test tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj --filter "FullyQualifiedName~RestrictiveJobObjectDoesNotKillDurableWorker|FullyQualifiedName~DetachedStartReturnsBeforeProviderAndStatusReadsDurableResult"
```

GitHub ReleaseのarchiveをPATH上のuser-owned directoryへ展開し、configをOS userごとに一度作成します。APM SkillはRunner binaryを内包または自動導入しません。

Codex CLIとGrok Build CLIはsemantic persistenceをfresh control付きで確認済みです。GitHub Copilot CLIはsession/resumeの成立を確認済みですが、fresh controlが正解を推測したため同じ強さのsemantic qualificationは与えていません。

上記は過去のsession継続実験の証拠です。現在のshell許可と`requiredOutcome`を含むレビュー依頼文による逸脱検出力を実測したことは意味しません。実モデルでの追加評価は[評価シナリオ](../../tests/PurposeReviewRunner.Tests/purpose-review-scenarios.md)を使い、結果をdeterministic testとは分けて記録します。
