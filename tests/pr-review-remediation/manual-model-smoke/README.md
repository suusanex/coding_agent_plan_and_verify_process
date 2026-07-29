# Goal Context real-model Codex App smoke

## Purpose

PR Review RemediationのGoal Context対応版を、Codex App、本物のmodel、実際のReady PRで確認する対話型manual smokeです。人がPowerShellの作業値を転記する代わりに、Codexが環境確認、fixture作成、package導入、artifact検証を担当します。人は外部状態の変更、modelへの送信、通知runtimeの変更、次の親タスクへの移行を明示的に承認します。

process側のPR自身をreview対象にしません。秘密情報やproduction dataを含まない専用のdisposable target repositoryを一つ選び、そこへsynthetic fixtureを作ります。

このmanual smokeは、次の決定論的証拠を置き換えません。

- `run-pr-review-remediation-agent-smoke.ps1`によるbaseline direct-profile実行
- PRR-002によるsingle-round artifact replay
- PRR-003によるmulti-round state contract replay

決定論的fixtureはCI向けの再現可能なcontract証拠です。この手順は、Codex App上のSkill routing、実model、承認境界、PRごとに固定したReview／Implementationの二つの親タスク、GitHub上のReady PR、通知direct linkを実運用に近い経路で確認します。

## Pass criteria

- process PRの40桁full head SHAからpackageと依存関係を導入している。
- Codexが専用private repositoryをdisposable targetとして一つ提案し、人が利用を承認している。
- 固定Implementation Thread自身が、既知のcode-quality gapとpurpose-only gapを持つsynthetic fixtureを実装し、commit、push、Ready PR作成まで行っている。
- model送信前に対象repository、PR、base/head OID、tracked files、diff、Goal Context、送信境界を提示し、人が承認している。
- round 1で`local-reviewer`と`purpose-reviewer`が独立して実行され、`review-planner`がremote sourceを含むplanへ統合している。
- round 1は`READY_FOR_ADAPTIVE_IMPLEMENTATION`で停止し、Review Thread内で実装を開始していない。
- Adaptive Implementationは人が承認した後、固定された別のImplementation Threadを再開し、同じplanを使って実行される。
- round 2はround 1と同じReview Threadを再開してpurpose-only reviewを行い、過去headのsourceを監査証跡として保持したまま`REVIEW_COMPLETE`へ到達する。
- Review Thread IDとImplementation Thread IDは異なり、同じroleの各工程では同じIDを維持する。
- 各roundとAdaptive完了時のcompletion notificationがtarget PRまたは結果と、現在のrole taskの両方を開ける。
- 各工程のtask ID、OID、hash、verdict、artifact path、承認が結果記録に残る。

本物のmodel出力は非決定的です。既知findingが得られない、予期しないactionable findingが残る、または必要なproviderを利用できない場合は、観測結果を`FAIL`または`BLOCKED`として記録します。期待結果へ合うようartifactを手で書き換えません。

## Safety and authority boundaries

| Action | Codex | Human |
| --- | --- | --- |
| process PR、CI、公開repository metadataのread-only確認 | 実行する | 入力を提示する |
| target repositoryの選定 | 専用名の一候補だけをread-only確認する | 使用対象を決定する |
| repository、branch、commit、Ready PRの作成 | 承認後だけ実行する | 対象と変更範囲を承認する |
| synthetic defectの作成 | 承認されたdisposable repositoryだけで実行する | 提示されたdiffを確認する |
| reviewer modelへのpayload送信 | 承認後だけ実行する | repository、PR、diff、Goal Contextを承認する |
| user-level notification runtimeの変更 | dry-runを先に提示し、承認後だけ実行する | 変更または見送りを決定する |
| Adaptive Implementation | 固定Implementation Thread用の入力を提示する | 同じImplementation Threadを明示的に再開する |
| 次review round | 自動起動しない | 同じReview Threadを明示的に再開する |
| PR close、branch削除、repository archive/delete | 対象を再提示し、承認後だけ実行する | cleanup方法を決定する |

Codex Appの準備タスク自体もmodelを使用します。既存repositoryを再利用する場合は、Codexで開く前に人が秘密情報、個人情報、production dataを含まないことを確認します。第一候補は、このsmoke専用に作成した空のprivate repositoryです。

synthetic defectは次の境界を守ります。

- disposable target repository以外へ追加しない。
- credential、実データ、production resourceを使用しない。
- destructive command、攻撃code、公開serviceへ露出する脆弱性を含めない。
- 小さなtest fixtureとして再現でき、Adaptiveで除去できる。
- process repositoryや既存product codeへ「試しに」混入させない。

## Inputs supplied by the operator

開始時に人が指定する値は次の二つだけです。target repositoryをすでに決めている場合は三つ目も指定できます。

- process repository: 例`suusanex/coding_agent_plan_and_verify_process`
- process PR number: 検証対象packageを含むReady PR番号
- optional target repository: 既存の専用test repository。未指定ならCodexが`<owner>/pr-review-remediation-model-smoke`を第一候補として提案する

PowerShell変数、head SHA、branch名、ローカルpathは人が転記しません。Codexがlive stateから取得し、各gateで提示します。

## Task A: prepare the disposable fixture

### A-1. Start the preparation task

Codex Appでprocess repositoryをworkspaceとして開き、新しいタスクを作成します。次のpromptで`<process-repository>`と`<process-pr-number>`を置き換えます。targetを未指定にする場合はそのまま残します。

```text
tests/pr-review-remediation/manual-model-smoke/README.md のTask Aを実行してください。

process repository: <process-repository>
process PR: <process-pr-number>
target repository: 未指定。認証中のownerに対する<owner>/pr-review-remediation-model-smokeを第一候補にしてください。そのrepository名が利用中なら、その1件のmetadataだけを確認し、smoke専用として再利用できなければ日付suffix付きの新しいprivate repository名を一つ提案してください。既存private repositoryを列挙しないでください。

最初はread-only preflightだけを行い、次を報告して停止してください。
- process PRのReady状態、CI、head branch、40桁full head SHA
- gh、codex、apm、dotnetの利用可否とversion
- target候補を一つに絞った理由、visibility、default branch、同名repositoryがある場合の既存用途
- 作成予定のrepository、branch、commit、Ready PR
- synthetic fixtureのファイル構成と既知gap
- reviewer modelへ送信され得る情報
- notification runtimeの現在状態と、変更する場合のdry-run方針
- cleanup候補

この段階ではrepository作成、clone、file変更、install、commit、push、PR作成、外部reviewer model起動、notification設定変更を行わないでください。
```

Codexは`gh auth status`、tool version、process PR metadata/checksを確認し、`<owner>/pr-review-remediation-model-smoke`を第一候補として一つだけ推奨します。候補名の利用可否を調べるために、そのrepositoryを完全名で確認することはできますが、認証中accountのprivate repository一覧は取得しません。候補がすでに存在する場合は、専用test用途である根拠と既存automationを示します。production、共有開発、deploy連携、秘密情報の可能性があるrepositoryは再利用しません。

### A-2. Approve the target and workspace preparation

報告を確認し、対象が安全な場合だけ同じタスクへ次の形で返信します。

```text
人手での作業が必要な承認結果:
- target repository: <owner/name>
- repositoryの利用または新規作成: 承認
- fixture branch、commit、push、Ready PR作成: 承認
- synthetic fixtureの提示内容: 承認
- external reviewer model payload: まだ承認しない
- notification runtime変更: dry-runのみ承認
- cleanup方針: <keep / close PR and delete branch / archive repository / delete repository>

承認範囲だけを実行してください。このPreparation Taskではtarget workspaceとpackageだけを準備し、fixture、branch、commit、push、PRは作成しないでください。準備後、Implementation Thread用promptとtarget workspaceの絶対pathを返して停止してください。
```

承認後、Codexは次を実行します。

1. target repositoryをcloneまたは新規作成し、ローカル絶対pathを確定する。
2. process PRのfull head SHAから`pr-review-remediation`と`completion-notification-decorator`を導入し、local profileを同期する。
3. package `--check`を実行する。
4. notification installerは`--dry-run`だけを実行する。
5. `result-template.md`をtargetの`.review/manual-model-smoke-result.md`へcopyし、取得したpreflight結果を記録する。`.review/`はtarget cloneの`.git/info/exclude`へ追加し、PR diffへ含めない。
6. target workspaceの絶対pathと、次項のImplementation Thread用promptを提示して停止する。

Preparation Taskは`main` baseline、fixture branch、fixture file、commit、push、Ready PRを作成しません。それらは初回実装の探索・設計コンテキストを保持するImplementation Thread自身が行います。

fixtureには、少なくとも次の安全な既知gapを含めます。Codexは同じ観測可能な結果になる、より小さな実装を選んでも構いません。

- code-quality gap: `int.Parse`相当の処理が不正なPR番号を未処理の例外にする。
- purpose-only gap: 完了messageにtarget PRのdirect URLと、固定Implementation Threadを明示的に再開する案内がない。

不正入力の期待動作はGoal Contextまたはacceptance evidenceへ記載しますが、意図したfindingを直接答えるreview artifactは事前作成しません。

### A-3. Create the Implementation Thread and initial PR

package導入後にtarget workspaceを開き、Implementation Threadとなる新しいtaskを一度だけ作成します。Skillはtask開始時に検出されるため、package導入前から開いていたtaskは再利用しません。このtaskを後のTask Cでも再開するため、終了またはarchiveしません。

人手での作業が必要: Preparation Taskが返した絶対pathをCodex Appでworkspaceとして開き、次のpromptを新しいtaskへ送ります。

```text
このtaskを<owner/repository>の固定Implementation Threadとして使用します。初回実装からレビュー後の修正まで同じtaskを再開するため、終了またはarchiveしないでください。

tests/pr-review-remediation/manual-model-smoke/README.md のTask A-3を実行してください。
Preparation Taskで人が承認したtarget repository、main baseline、fixture branch、commit、push、Ready PR作成、synthetic fixtureの範囲だけを実行してください。

1. repository identityとcleanな開始状態を確認してください。
2. 必要ならmainへ最小baselineを作成してpushし、smoke/goal-context-review-<date>形式の専用branchを作成してください。
3. 安全な小規模.NET fixtureとhuman-reviewed Goal Contextを実装してください。
4. code-quality gapとして不正なPR番号が未処理例外になる処理、purpose-only gapとして完了messageにtarget PRのdirect URLとこのImplementation Threadを明示的に再開する案内がない状態を含めてください。
5. build、baseline validation、canonical Goal Context validation、git diff --checkを実行してください。
6. commit、pushし、DraftではないReady PRを作成してください。
7. 現在のCodex task IDとcodex://threads/<task-id>を取得し、このPRのImplementation Threadとしてresultへ記録してください。取得できない場合は推測せず、人手でUIからcopyする必要があると報告してください。
8. reviewer modelへ送信する前のno-send inspectionを提示して停止してください。review、Adaptive、次roundは開始しないでください。

Preparation Taskの外部reviewer model payload承認はまだありません。reviewer modelへ送信しないでください。
```

このImplementation Threadがfixtureの設計、実装、検証、commit、push、Ready PR作成を担当したことをresultへ記録します。別taskが事前作成したfixtureを単に引き継いだ場合は不合格です。

### A-4. Review the no-send inspection

Codexの報告には最低限、次を含めます。

- process repository、PR、head ref、full head SHA、CI結果
- target repository、Ready PR URL、base/head branchとOID
- targetのtracked files一覧
- `origin/main...HEAD`のdiffとstat
- uncommitted filesと、package導入物がPR diffへ混入していないこと
- Goal Contextのpath、canonical validation結果、正規化SHA-256
- installされたpackageとdependencyのref
- reviewerへ渡すreview context、remote patch、Goal Context、repository rulesのpath
- credential、token、個人情報、production dataが検出されなかったこと
- notification installer dry-runの対象、既存`notify` chain、backup／復旧方法
- round 1で作成予定のcycle pathとartifact directory
- `.review/manual-model-smoke-result.md`の絶対pathと、PR diffから除外されていること

内容が説明できない、target PR以外の作業が混ざる、秘密情報の疑いがある、またはprocess headがremoteと一致しない場合は続行しません。

### A-5. Approve external model payload and notification runtime

no-send inspectionを確認後、同じImplementation Threadへ承認結果を返信します。

```text
人手での作業が必要な承認結果:
- external reviewer model payload: 承認
- approved target repository / PR: <owner/name>#<number>
- approved base / head OID: <base-oid> / <head-oid>
- approved Goal Context path / SHA-256: <path> / <sha256>
- notification runtime install: <承認 / 見送り>
- approved by: <identity>
- approved at: <ISO-8601 with timezone>

承認記録をresultへ保存してください。reviewやAdaptiveはこのタスクで開始せず、現在のImplementation Thread ID／URI、target repositoryの絶対path、Task B用promptを返してください。
```

notification runtime installを承認した場合だけ、Codexはinstallerの`install`と`--check`を実行します。見送った場合、OS notificationの実配信は未検証として記録し、最終結果を完全な`PASS`にしません。

## Task B: run multi-round review round 1

人手での作業が必要: target workspaceでReview Threadとなる新しいtaskを一度だけ作成します。A-5で確定したImplementation Thread ID／URIとTask B自身のReview Thread ID／URIを使って次を送信します。二つのIDが同一なら開始しません。Codex Appが現在task IDを取得できない場合はUIから実値をcopyし、推測値を使いません。

```text
$completion-notification-decorator
$goal-context-pr-review

<owner/repository>#<pr-number>を、<goal-context-path>を使うexplicit multi-round modeのround 1として目的達成レビューしてください。
cycleは.review/pr-<pr-number>/review-cycle.json、artifactはround-001へ保存してください。
Review Thread IDは<review-thread-id>、初回fixture実装から継続するImplementation Thread IDは<implementation-thread-id>です。URIはmanagerがIDから導出し、cycleへ固定してください。両IDが異なることを検証してください。
local-reviewerとpurpose-reviewerを独立に実行し、remote review、inline comment、PR comment、checkをreview-plannerで統合してください。
review planとround artifactを検証し、completion notificationを出したところで停止してください。
同じ親タスクではAdaptive Implementationやproduction code変更を開始しないでください。
結果を.review/manual-model-smoke-result.mdのTask Bへ追記してください。

外部model payloadは、Task Aのresultに記録されたrepository、PR、base/head OID、Goal Context path/hashの範囲で人が承認済みです。identityが一致しない場合は送信せず停止してください。
```

Codexに次を検証・報告させます。

- selection artifactがstrict validationのpathとcontent hashを保持する。
- local findingsに既知の不正入力処理に関する`LR-*`がある。
- purpose findingsにdirect URLまたは固定Implementation Threadへのhandoff欠落に関する`PUR-*`がある。
- reviewer outputsとTask Bがproduction codeを変更していない。
- review planが取得済みremote sourceを網羅する。
- すべての`Apply` findingが実在するscope IDとacceptance IDへ対応する。
- `implementation_intent`とordered remediationのSI/AC集合が完全一致する。
- cycleとreview planが固定Review／Implementation Thread ID、導出URI、plan path/hashを一致させる。
- verdictが`READY_FOR_ADAPTIVE_IMPLEMENTATION`である。
- notificationのdirect linkがtarget PRを開く。
- cycle、round-001、review planのvalidationが成功する。

条件を満たさない場合はTask Cへ進まず、結果を`FAIL`または`BLOCKED`として記録します。

## Task C: resume the Implementation Thread for Adaptive

人手での作業が必要: Task Bのplan、finding、scope、acceptance、Non-goalsを確認します。実装を承認する場合だけ、A-3で初回fixtureを実装した**同じImplementation Thread**を再開して新しい明示ターンを開始します。新しいtaskは作りません。承認者、承認時刻、plan path、正規化SHA-256をpromptへ含めます。

```text
$completion-notification-decorator
$adaptive-implementation-execution

<round-001-review-plan-absolute-or-repository-relative-path>をsource of truthとして実装してください。
このtaskはcycleへ固定されたImplementation Thread <implementation-thread-id>です。review-planの対象Implementation Thread ID／URIと一致し、return先がReview Thread <review-thread-id>／codex://threads/<review-thread-id>であることを確認してください。
review-plan.mdのimplementation_intent、Goal Context Boundary、Non-goalsを保持し、plan外の変更を追加しないでください。
このImplementation Threadに残る探索・設計コンテキストは利用できますが、実装scopeとacceptanceのsource of truthはreview-plan artifactです。
人がAdaptive実行を承認したplanの正規化SHA-256は<plan-sha256>、承認者は<identity>、承認時刻は<ISO-8601 with timezone>です。pathまたはhashが一致しない場合は実装せず停止してください。
記載されたvalidationを実行し、commitとpushが必要な場合は対象branchを再確認してから行ってください。
完了後、変更後head OID、validation結果、Adaptive result reference、target PRへのdirect link、同じReview Threadを再開するURIを報告してください。
結果を.review/manual-model-smoke-result.mdのTask Cへ追記してください。
次のreview roundは開始しないでください。
```

Task C完了時に次を確認します。

- Task IDがA-3でfixture実装、commit、push、Ready PR作成を行ったImplementation Thread IDと一致し、Task BのReview Thread IDとは異なる。
- Adaptive inputのplan path/hashがround 1で承認されたplanと一致する。
- 既知のcode-quality gapとpurpose-only gapがplanどおり修正される。
- acceptanceに記載されたvalidationが成功する。
- unrelated changeがない。
- changeがtarget PRのhead branchへ反映され、head OIDが変わる。
- Adaptive result referenceとcompletion notificationのdirect linkが記録される。
- Task Cがround 2を自動起動していない。

## Task D: resume the Review Thread for the changed head

人手での作業が必要: Task Cの変更とvalidationを確認し、再reviewを承認する場合だけ、**Task Bと同じReview Thread**を再開して新しい明示ターンを開始します。新しいtaskは作りません。承認者と承認時刻をpromptへ含めます。

```text
$completion-notification-decorator
$goal-context-pr-review

<owner/repository>#<pr-number>のGoal Context multi-round review round 2を開始してください。
cycleは.review/pr-<pr-number>/review-cycle.jsonです。
前roundのAdaptive result referenceは<adaptive-result-reference>です。
現在のReview Thread IDは<review-thread-id>、Adaptiveを実行したImplementation Thread IDは<implementation-thread-id>です。cycleの固定bindingと一致しない場合は開始せず停止してください。
round 2開始の承認者は<identity>、承認時刻は<ISO-8601 with timezone>です。
最新のbase/head identityとreview contextを収集し、旧headのreviewとinline commentをhistorical sourceとして保持したままround-002へ保存してください。
round 2はpurpose-onlyです。collectorは--no-wait-for-copilotで実行し、GitHub Copilotレビューを開始・待機しないでください。local-reviewerも実行せず、local-review-findings.mdを作成しないでください。
purpose-reviewerは前roundまでの全active tracking IDをPrior Finding Assessmentでpersistentまたはresolvedへ分類し、新規・reopened・persistentのactionable findingは現在roundのPUR-*だけにしてください。
取得済みまたは新規のCopilot、connector、人間review/comment/checkはremediationへ取り込まず、理由付きnoActionの監査証跡としてsource coverageへ残してください。
purpose-reviewerとreview-plannerを実行し、artifactとcycleを検証してください。
completion notificationを出したところで停止し、Adaptiveや次roundは開始しないでください。
結果を.review/manual-model-smoke-result.mdのTask DとFinal verdictへ追記してください。
```

期待結果は`REVIEW_COMPLETE`です。次を確認します。

- Task IDがTask BのReview Thread IDと一致し、Task CのImplementation Thread IDとは異なる。
- round 1とround 2が別directoryへ保存され、過去artifactが上書きされていない。
- round 2のhead OIDがTask Cの変更後headと一致する。
- round 1のreview sourceとround 2で取得した外部sourceが、理由付き`noAction`の監査証跡としてcoverageへ残る。
- round 2の`reviewMode`が`purpose-only`、Copilot waitが`disabled`であり、`local-findings` artifactが存在しない。
- finding ledgerが`new | persistent | resolved | reopened`を正しく追跡する。
- actionable findingがなく、verdictが`REVIEW_COMPLETE`である。
- 空のreview planやAdaptive handoffが生成されていない。
- notificationの「結果を開く」がtarget PRを開き、「このタスクを開く」が同じReview Threadを開く。

round 2でactionableな`PUR-*` findingが残った場合、結果を改変して`REVIEW_COMPLETE`にしません。verdictが`READY_FOR_ADAPTIVE_IMPLEMENTATION`なら、必要な修正を人が承認し、Task Cと同じImplementation Threadを再開してAdaptiveを実行します。その後、Task Bと同じReview Threadを再開してround 3をpurpose-onlyで開始します。round 3でもCopilotレビューの開始・待機とlocal-reviewer実行は行いません。

round 3でもactionable findingが残り`HUMAN_DECISION_REQUIRED`になった場合は、実行可能planとAdaptive handoffが存在しないことを確認します。第4round以降はこの基本smokeの範囲外です。続行する場合だけ、人がdecision、approver、時刻、理由、新上限、承認plan候補を明示し、`manage-review-cycle.cs resolve`が`APPROVED_FOR_ADAPTIVE_IMPLEMENTATION`を返した後に同じImplementation ThreadでAdaptiveを開始します。

## Record the result

Task Aでtargetの`.review/manual-model-smoke-result.md`へ作成したcopyへ、各タスク終了時にCodexが追記します。raw rollout、credential、個人情報はcommitしません。必要な証拠は次に限定します。

- 人の承認内容と時刻
- Codex task ID
- role task ID／導出URIと、Initial Implementation／remediation／review roundでの継続証拠
- repository、PR、branch、OID、URL
- Goal Contextとartifactのpath/hash
- finding ID、verdict、validation結果
- notification direct link
- cleanup結果

人がchatで行った承認は、Codexが要約してresultへ記録し、人が次gateで内容を確認します。失敗した場合も失敗stage、観測結果、artifact path、再現手順を残し、`PASS`へ書き換えません。

Codex Appのtask IDやtask URLをagentが取得できない場合、人がUIから識別子をcopyしてresultへ記録します。識別子を推測して記入しません。

完全な`PASS`には、Task AからDまでの成功、外部model payload承認、初回fixture実装と各remediationを同じImplementation Threadが担当したこと、Review／Implementationの二つのtask IDが異なること、同一roleでIDが継続すること、purpose-only再reviewでの`REVIEW_COMPLETE`、direct-link notification実配信が必要です。各Taskでは開始直後や内部model完了時に`codex-turn / TURN_ENDED`が表示されず、terminal envelope後に対象processの通知が1件だけ届き、「結果を開く」と「このタスクを開く」がそれぞれ正しいPRと現在taskへ遷移することも確認します。notification runtimeを見送った場合やproviderを利用できない場合は、review cycleが成功してもnotificationを`未検証`とし、全体を`BLOCKED`または限定的な結果として記録します。

## Role task unavailable

固定Review ThreadまたはImplementation Threadを再開できない場合、このsmoke内で新しいtaskへ置き換えません。結果を`BLOCKED`として、再開不能なtask ID／URI、最後に完了したround、artifact pathを記録して停止します。続行方法はcycle外で人が決定し、新しいcycleまたは別の手動工程として扱います。

schema version 1で実行済みのcycleは過去証跡として保持しますが、新しいpurpose-only契約の合格証拠には使用しません。更新packageとnotification runtimeを導入後、別cycle rootまたは新しいdisposable PRでTask Aから再実行します。

## Cleanup

人手での作業が必要: 最終証拠を確認し、Task Aで選択したcleanup方針を確定します。Codexへ対象repository、PR、branchと実行予定操作を再提示させ、承認後だけcleanupを実行します。

推奨する順序は次のとおりです。

1. resultと必要なartifact hashを保存する。
2. disposable PRをcloseする。
3. feature branchを削除する。
4. 専用repositoryをarchive、delete、または次回smoke用に保持する。
5. user-level notification runtimeを変更した場合は、保持またはbackupから復旧するかを決める。

repositoryやbranchのdeleteは復元が難しい操作です。名前、owner、PR URLを人が再確認するまでCodexへ実行させません。

## Diagnostic fallback

Codexの自動preflightが失敗した場合だけ、Codex Appのterminalで個別に次を確認します。これらを人が作業値として転記することは主手順に含めません。

```powershell
gh auth status
codex --version
apm --version
dotnet --version
gh pr view <process-pr-number> --repo <process-repository> --json url,isDraft,headRefName,headRefOid,statusCheckRollup
gh pr view <target-pr-number> --repo <target-repository> --json url,isDraft,baseRefName,baseRefOid,headRefName,headRefOid
```

notification installerの診断では、Codexに実際の`ModuleRoot`を解決させてから次の順で実行します。

```powershell
dotnet run --file <notification-installer> -- --dry-run
dotnet run --file <notification-installer> -- install
dotnet run --file <notification-installer> -- --check
```

`install`はuser-level Codex設定を変更するため、人の承認がない状態では実行しません。
