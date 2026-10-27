# Purpose Review Runner Technical Reference

この文書は、Purpose Review Runnerのprotocol、state、worker起動、provider adapterをまとめたtechnical referenceです。通常利用の導入・設定・更新は[Purpose Review Runner README](../apps/PurposeReviewRunner/README.md)を正本とします。Skillの工程契約は[`$persistent-purpose-review`](../apm-packages/persistent-purpose-review/README.md)を正本とします。

一般利用では`start` / `status` / `continue`を手で呼ぶ必要はありません。reviewはバックグラウンドworkerで実行されるため、長時間でも親CLIに依存しません。

## Public CLI

```powershell
purpose-review-runner version
purpose-review-runner start --repository C:\path\to\repo --context docs\goal-context.md --context C:\path\to\accepted-decisions.md
purpose-review-runner status --run <run-id>
purpose-review-runner continue --run <run-id>
```

`start`と`continue`はprovider完了をforegroundで待ちません。入力検証を通過したあとdurable jobを登録して独立したworker processを起動し、`jobStatus`が`RUNNING`のJSONを返します。結果は同じ`run-id`で`status`を短時間pollingして取得します。`status`はreviewを再実行しません。durable job / `run-id`が成立したあとにCLI呼び出しの結果だけが不明な場合は、同じ`start` / `continue`を再submitせず、その`run-id`の`status`を問い合わせ直します。`CONTEXT_NOT_FOUND`のようにjob成立前の確定的なpreflight failureは、この再問い合わせの対象ではありません。再開の可否はSkillのretry / recovery契約に従います。

`start`は1件以上のcontextを要求します。相対pathはrepository root基準で解決し、absolute pathも受理します。context本文をReview Leadへ渡すのはRound 1だけです。任意のInvestigatorには開始時に固定したcontextを毎round渡します。`continue`は保存済みsessionをresumeし、contextや前回outputを再送しません。内部コマンド`work`はSkillから使いません。

## Output schema v3

stdoutはprotocol v3の単一JSONです。公開fieldsは`protocolVersion`、`runnerVersion`、`runId`、`round`、`jobStatus`、`status`、`terminal`、`findings`と、必要時の`message`または`error`です。

findingは`id`、`severity`、`title`、`summary`、`evidence`、`requiredOutcome`を要求します。成果の具体的な内容はreviewerが判断し、parserは修正手順や関数名を要求しません。`jobStatus`は`RUNNING`、`SUCCEEDED`、`FAILED`です。実行中の`status`は`RUNNING`です。診断はstderrへ出し、stdoutへ別形式のtextを混在させません。

`FINDINGS`の場合だけ元のimplementation parentが修正・検証し、同じ`run-id`を`continue`します。`COMPLETE`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`では、そのrunを継続せず停止します。terminal `ERROR`のrunも`continue`しません。これは、原因解消後に別のreview runをRound 1から開始する判断とは別です。その区別はSkillが所有します。`RUNNING`なら、成立済みの`run-id`に対する`status`を繰り返します。

`COMPLETE`は実装reviewの完了を表し、申し送り済みの未実施testが成功したことや、実環境検証・リリース条件が完了したことは表しません。エージェントが実行不能・実行不許可、または承認済み後工程のtestだけが残り、対象、理由、主体と時点、環境と手順、期待結果と合否基準、記録先と失敗時の戻し先が揃っていれば、reviewerは未実施だけをblockerにせず、未検証事項と人手作業を`message`に残せます。schemaとstatusはprotocol v3のままです。

## Exit codes

| Exit code | 意味 |
| --- | --- |
| 0 | job受付または有効なreview結果 |
| 1 | provider / process実行失敗 |
| 2 | 引数・config・state・protocol違反 |

非0でもstdoutはstatus `ERROR`のschema v3です。

## State layout

stateは`Environment.SpecialFolder.LocalApplicationData`配下の`purpose-review-runner/runs/<run-id>/`へ保存します。Windowsでは通常`%LOCALAPPDATA%\purpose-review-runner\runs\<run-id>\`、Linuxでは通常`~/.local/share/purpose-review-runner/runs/<run-id>/`です。`XDG_DATA_HOME`が設定されている場合は、その配下を使います。

| File | 役割 |
| --- | --- |
| `state.json` | review制御（session、provider snapshot、round、review status） |
| `job.json` | job lifecycle |
| `result.json` | 公開結果 |
| `launcher.log` | worker起動処理の診断 |
| `worker.log` | `work` processが起動してからの診断 |
| `transcript/round-NN-prompt.md` | そのroundのreview payload |
| `transcript/round-NN-response.md` | そのroundのreviewer response本文 |
| `investigator/transcript/round-NN-prompt.md` / `round-NN-response.md` | 任意のInvestigatorの入力とraw出力。parse失敗時も診断用に保持 |
| `investigator-report-N.json` | 検証・保存に成功したInvestigator report。Leadへのhandoff |

session handleは公開outputへ出しません。config変更は既存runへ反映されません。`start`時のprovider設定をrun stateへsnapshotするため、その後にuser-level configを変更しても既存runへは反映されません。同じ`runId`で`continue`する再reviewは、同じreviewer sessionと同じprovider / model / reasoning effortで継続します。

transcriptのpromptとreviewer responseは全文をローカル保存するため、purpose contextやrepository由来の情報を含み得ます。実装対象repositoryには生成されず、`LocalApplicationData`のrun directory内だけに保存されます。これはRunnerが生成してprovider adapterへ渡したreview payloadと、reviewer response本文の監査用であり、provider内部のsystem promptやnetwork payloadを記録するものではありません。

`PURPOSE_REVIEW_RUNNER_CONFIG_PATH`と`PURPOSE_REVIEW_RUNNER_STATE_ROOT`を両方指定すると、通常のuser-level locationの代わりにそのconfigとstateをworkerも参照します。launcher.logにはJob flags、Job limit queryの失敗、選択した起動経路、native / WMI error、worker PIDを残します。provider prompt、response、token、credential、environment全件は記録しません。

## Worker isolation

workerは起動時に親のstdin/stdout/stderrを継承しません。この分離はimplementation parentやproviderの種類に依存しません。Windowsでは現在プロセスがJob Object内かどうかを見て起動経路を選びます。Jobに入っていなければdetached `CreateProcess`です。Job内ならimmediate Jobのbreakaway可否に関わらず、呼び出し元Job chainを継承しない`Win32_Process.Create`に`CREATE_BREAKAWAY_FROM_JOB`を付けて起動します。nested JobのancestorやWMI provider host側Jobへ残す経路は使いません。独立起動できなければ同じJobへ残さず`WORKER_START_FAILED`で停止します。

## Non-modifying reviewer contract

filesystem sandboxによるread-only強制は要件ではありません。reviewerには変更禁止を指示しますが、OS-levelのread-only isolationではありません。reviewerはshellで`git diff`、`git log`、`git show`などの調査を行えます。source、tests、docs、Git状態、設定、外部サービスを変更しない役割契約はshell経由にも適用されます。shellからの変更を技術的に防止する保証ではありません。変更概要は既存のGitコマンドで収集します。独自の差分解析器やshell command判定器は追加しません。

same-session、non-modifying reviewer、最大3round、異常時停止はconfigで変更できません。

providerごとの調査許可は次のとおりです。

- Grokは`--tools read,view,grep,shell`と`--permission-mode bypassPermissions`で調査用shellを利用できるようにし、write/edit系toolと委任は引き続き制限します。
- Copilotは`bash`・`powershell`とそのsession操作toolを公開し、`--allow-tool=shell`で実行を許可します。tool公開と実行許可は別の設定です。
- Codexは`--dangerously-bypass-approvals-and-sandbox`とpromptの変更禁止契約を使います。Codexのdefault sandboxはReadOnlyですが、`--ignore-user-config`ではproject trustから昇格せず、`-s workspace-write`もWindowsでは実効read-onlyになる報告があるため、別sandboxへ置換せずbypassします。resumeでもbypassを再指定します。

設定の根拠は[Grokのpermission仕様](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/22-permissions-and-safety.md)と[Copilotのtool仕様](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#tool-availability-values)です。

## Role orchestration（0.5.0）

worker内部で変更概要を準備し、任意のfresh Investigatorを呼び出し、最後にpersistent Review Leadを1回呼び出します。外部protocol v3、1 round / 1 job、最大3roundは維持します。config v2の`reviewLead`と`investigator`は独立したprovider snapshotとして保存します。config v1とInvestigator未指定はLead-onlyです。

変更概要はGitのHEAD、worktree status、HEADに対するname-status / statです。これは意味的なreview baseではなく、比較基準はunknownと明示します。purpose context中の明示baseはreviewerが確認します。未コミット差分のないbranchにも既存commitの変更があり得るため、空のdiffをreview不要の判定には使いません。Gitが利用不能ならその限界を示して現在の実装をreviewします。

Investigatorの返却は、行単独の`BEGIN_PURPOSE_INVESTIGATION` / `END_PURPOSE_INVESTIGATION`で囲った厳密なJSONです。CLIが進捗文を開始境界の直前へ改行なしで連結する場合も受理し、開始境界行の次からJSONとして扱います。進捗文はevidenceとして使いません。境界なしのraw JSONも受理しますが、不完全・複数・順序不正の境界は拒否します。JSON文字列内に境界名を引用しただけでは境界と数えません。JSONは`schemaVersion: 1`、`evidence`、`checked_scope`、`unchecked_scope`、`uncertainties`、`candidate_findings`を必須とします。evidenceは一意な`id`、`path`、`description`、正の行位置（`startLine`と任意の`endLine`）または`symbol`を持ちます。candidate findingは`id`、`title`、`summary`、存在するevidenceへの非空の`evidence_ids`を持ちます。確認範囲は空にできず、候補0件でも未確認範囲と不確実事項を明示します。

検証済みreportだけをrun-local handoffとして保存し、Lead promptにはそのpathを渡します。report本文を初期promptへ展開しません。不正出力・provider failureはtraceに残し、Leadへ利用不能を知らせてLead-onlyへ退避します。失敗をclean evidenceへ変換せず、Leadのsessionを作り直しません。各providerのtimeoutはそれぞれ独立しています。

独立観点の形成→report読込→不足観点・重要主張の原典確認→最終判定という順序はpromptの行動契約です。Runnerが機械的に保証するのは構造・参照整合性と呼出順序であり、観点形成の実行時系列やreport内容の真実性ではありません。Leadの計画・思考過程の新規監査artifactは作りません。

## Reviewer evaluation owned by Skill and prompt

レビュー観点、`requiredOutcome`の意味、finding判断は`$persistent-purpose-review` SkillとRunnerが生成するreview promptが所有します。このreferenceはCLIとruntimeの機械的契約だけを扱います。
