# GitHub Copilot Chat in VS Code Manual Smoke

このrunbookは、static fixtureでは検証できない実model / VS Code UI handoffを確認するためのものです。未実行の行を`PASS`にせず、実際に観測した値だけを記録します。

## Automation equivalence

実model、選択agent、Skill実行、tracked artifact、変更境界、validation、terminal verdictの確認にはGitHub Copilot CLIを使用できます。Adaptive 0.5.0のCLI実行証拠は[`copilot-cli-real-model-e2e-2026-08-09.md`](copilot-cli-real-model-e2e-2026-08-09.md)へ記録します。2026-07-31のrecordは0.4.0のhistorical evidenceであり、0.5.0の代替にはしません。VS Codeのagent picker、`target` filter、handoff button自体をacceptance対象にする場合だけ、このtemplateをVS Codeで別途実行します。

## Safety and setup

1. disposable repositoryまたは捨てられるworktreeを用意し、開始commit SHAを固定する。
2. APM 0.26.0でAdaptive packageの検証対象commit SHAを固定して導入する。
3. repositoryに、code inspectionだけで非局所decisionを閉じられるimplementation、STANDARDが作成するclass/interface/wiring/tests、許可されたlocal choice、locked non-local decisionを無効化するevidenceを用意する。
4. secret、課金操作、production変更、organization policy変更をfixtureへ含めない。
5. HIGHとSTANDARDを同時に開かず、各agentのterminal verdict後だけ次のagentを選ぶ。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution#<full-commit-sha> --target copilot,agent-skills --https
```

## Environment record

| Field | Observed value |
| --- | --- |
| Date / operator | NOT RUN |
| Repository / start commit | NOT RUN |
| Adaptive package commit | NOT RUN |
| APM version | NOT RUN |
| VS Code version | NOT RUN |
| GitHub Copilot / Copilot Chat extension version | NOT RUN |
| Copilot plan / organization policy relevant to models | NOT RUN |

## Scenario 0: Plain implementation request does not auto-select Adaptive skill

1. agent pickerでAdaptive専用agentを選ばず、通常のCopilot Chat / default agentのまま開始する。
2. Adaptive skill slash commandを使わず、単に「このPlanを実装して」または「実装して」と依頼する。
3. `adaptive-implementation-execution` skill が暗黙選択・自動ロードされないことを確認する。
4. 続けて自然文で「Adaptive Implementationを使ってこのPlanを実装して」と依頼し、これも model 判断による自動ロードにならないことを確認する。
5. 最後に `/adaptive-implementation-execution この Plan を実装してください` と slash 明示起動し、skill を利用者起動できることを確認する。

この項目はUI依存のため自動テスト不能です。観測結果だけを記録し、未実行なら `NOT RUN` のままにします。

## Scenario 1: HIGH closes decisions without code edits

1. agent pickerで`high-implementation-starter`を選ぶ。
2. requested modelが`GPT-5.6 Terra (copilot)`であることを確認する。
3. fresh route identityを`adaptive / default / N/A`として渡す。
4. HIGHがcode、wiring、signatures、call sites、testsを調査し、`HIGH_MODEL code changes: No`、`Delegation basis: non-local-decisions-closed`、全行`Locked / N/A`のDecision closure、Work Packagesを持つtracked handoffを作成することを確認する。
5. HIGHのproduction/test LOCが0でも`READY_FOR_STANDARD_COMPLETION`が受理されることを記録する。

## Scenario 2: STANDARD owns production implementation

1. `high-implementation-starter` / Terraから別fixtureを開始する。
2. HIGHがresponsibility、class/interface signature、DI strategy/location/lifetime、state/error/cancellation/retry semantics、test seam strategyをlockしたtracked `READY_FOR_STANDARD_COMPLETION`を作るまで待つ。HIGH自身によるproduction/test editは要求しない。
3. tracked pathをhandoff promptへ含め、`standard-implementation-completer`へ移る。
4. requested / observed modelが`GPT-5.6 Luna (copilot)`であることを記録する。
5. STANDARDがAllowed edit surface envelope内でclass/interface、method body、DI registration、testsを作成し、private helper、branch構造、test data builderを自律判断して`COMPLETED`を返すことを確認する。

## Scenario 3: Locked non-local decision re-entry

1. STANDARDが、locked signatureではexisting callerを成立させられない、DI lifetimeを変更する必要がある、またはlocked state/error/cancellation/retry/test architectureを変更する必要があるfixtureを実行する。
2. 新規file、locked class/interface、決定済みwiringの実装だけではre-entryせず、locked non-local decisionの変更が必要な場合だけtracked `NEEDS_HIGH_MODEL_REENTRY`を返すことを確認する。
3. re-entry artifactにoriginal Implementation Intent、両route field、Design Pair handoff pathまたは`N/A`、Locked Decisions、invalidating evidence、completed work、files changed、validation、new decision、current worktree state、reentry count、triggerがあることを確認する。
4. completion / re-entryの両artifact pathを渡して`high-implementation-starter`へ戻る。
5. requested / observed modelが再び`GPT-5.6 Terra (copilot)`であり、original intentとLocked Decisionsが保持されることを確認する。

## Scenario 4: Negative routing

- incomplete `READY_FOR_STANDARD_COMPLETION`ではSTANDARDを起動せず、HIGHへartifact修正または実装継続を求める。
- initial HIGHが`Direct completion reason`なしで`COMPLETED_BY_HIGH_MODEL`を返した場合は拒否し、valid exception evidenceまたはSTANDARD delegationを求める。
- `post-reentry-high-ownership`は実際のSTANDARD re-entry前には受理しない。
- route identityが欠落または矛盾するresumeは`BLOCKED / BlockedByInvalidCompletionHandoff`になり、Adaptive defaultを補完しない。
- 同じre-entry triggerが再発し、Remaining workとAllowed edit surfaceの厳密な縮小を証明できない場合はHIGHが完了まで担当し、Lunaへ再委譲しない。
- `REPLAN_REQUIRED`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`では想定外のhandoffがないことを確認する。

## Evidence record

| Phase | Selected agent | Requested model | Observed model | Input artifact(s) | Files changed | Validation commands / results | Terminal verdict | Unexpected automatic handoff |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HIGH start | NOT RUN | Terra | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| STANDARD completion | NOT RUN | Luna | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| HIGH re-entry | NOT RUN | Terra | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

## Work distribution metrics

| Metric | Observed value |
| --- | --- |
| eligible_for_standard_delegation | NOT RUN |
| standard_started | NOT RUN |
| HIGH direct completion reason | NOT RUN |
| HIGH changed LOC / test LOC | NOT RUN |
| STANDARD changed LOC / test LOC | NOT RUN |
| handoff size / token estimate | NOT RUN |
| model input / output token | NOT RUN / `Unavailable` if the client does not expose it |
| re-entry count / trigger category | NOT RUN |
| acceptance miss | NOT RUN |
| review findings | NOT RUN |

STANDARD start rate、STANDARD changed LOC share、re-entry rate、qualityは観測指標でありmerge gateではありません。clientが公開しないtoken値を推測してはいけません。

## Completion decision

- plain implementation request did not auto-select Adaptive skill: NOT RUN
- natural-language "Adaptive Implementationを使って" did not auto-select Adaptive skill: NOT RUN
- explicit `/adaptive-implementation-execution` slash invocation still works: NOT RUN
- HIGH-first observed: NOT RUN
- valid handoff only before Luna: NOT RUN
- locked non-local decision change returned to Terra: NOT RUN
- original intent / route identity / Locked Decisions retained: NOT RUN
- no unexpected automatic handoff: NOT RUN
- terminal verdict: NOT RUN

実行環境が必要: VS Code固有UIまで検証する場合は、利用可能なGitHub Copilot Chat in VS Code環境で上記を実行し、このtemplateを実測値で複製してevidenceを保存します。Terra / Lunaの利用可否はCopilot planとorganization policyに依存します。指定modelを選べない、またはobserved modelが異なる場合はその差異を記録し、要求どおりのmodel smokeを`PASS`にしません。
