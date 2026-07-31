# GitHub Copilot Chat in VS Code Manual Smoke

このrunbookは、static fixtureでは検証できない実model / VS Code UI handoffを確認するためのものです。未実行の行を`PASS`にせず、実際に観測した値だけを記録します。

## Automation equivalence

実model、選択agent、Skill実行、tracked artifact、変更境界、validation、terminal verdictの確認にはGitHub Copilot CLIを使用できます。CLIによる実行証拠は[`copilot-cli-real-model-e2e-2026-07-31.md`](copilot-cli-real-model-e2e-2026-07-31.md)に記録します。VS Codeのagent picker、`target` filter、handoff button自体をacceptance対象にする場合だけ、このtemplateをVS Codeで別途実行します。

## Safety and setup

1. disposable repositoryまたは捨てられるworktreeを用意し、開始commit SHAを固定する。
2. APM 0.26.0でAdaptive packageの検証対象commit SHAを固定して導入する。
3. repositoryに小さなproduction path、focused tests、Lunaへ渡せるbounded remainder、STANDARD中に発見できるstructural triggerを用意する。
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

## Scenario 1: HIGH starts and completes directly

1. agent pickerで`high-implementation-starter`を選ぶ。
2. requested modelが`GPT-5.6 Terra (copilot)`であることを確認する。
3. fresh route identityを`adaptive / default / N/A`として渡す。
4. HIGHだけで完了できるfixtureを実行する。
5. `COMPLETED_BY_HIGH_MODEL`後にSTANDARDへ自動handoffされず、handoff buttonも押していないことを記録する。

## Scenario 2: Valid bounded completion

1. `high-implementation-starter` / Terraから別fixtureを開始する。
2. HIGHがproduction path / wiring、test seam、focused verification、全acceptance mappingを記録したtracked `READY_FOR_STANDARD_COMPLETION`を作るまで待つ。
3. tracked pathをhandoff promptへ含め、`standard-implementation-completer`へ移る。
4. requested / observed modelが`GPT-5.6 Luna (copilot)`であることを記録する。
5. STANDARDがAllowed edit surface内だけを変更し、`COMPLETED`を返すことを確認する。

## Scenario 3: Structural re-entry

1. STANDARDが新しいproduction class / interface / dependency、API / schema / config、DI / factory / entrypoint、state ownership、error / cancellation / retry、test seam、またはAllowed edit surface外の変更を必要とするfixtureを実行する。
2. STANDARDが独断で構造変更せず、tracked `NEEDS_HIGH_MODEL_REENTRY`を返すことを確認する。
3. re-entry artifactにoriginal Implementation Intent、両route field、Design Pair handoff pathまたは`N/A`、Locked Decisions、invalidating evidence、completed work、files changed、validation、new decision、current worktree state、reentry count、triggerがあることを確認する。
4. completion / re-entryの両artifact pathを渡して`high-implementation-starter`へ戻る。
5. requested / observed modelが再び`GPT-5.6 Terra (copilot)`であり、original intentとLocked Decisionsが保持されることを確認する。

## Scenario 4: Negative routing

- incomplete `READY_FOR_STANDARD_COMPLETION`ではSTANDARDを起動せず、HIGHへartifact修正または実装継続を求める。
- route identityが欠落または矛盾するresumeは`BLOCKED / BlockedByInvalidCompletionHandoff`になり、Adaptive defaultを補完しない。
- 同じre-entry triggerが再発し、Remaining workとAllowed edit surfaceの厳密な縮小を証明できない場合はHIGHが完了まで担当し、Lunaへ再委譲しない。
- `REPLAN_REQUIRED`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`では想定外のhandoffがないことを確認する。

## Evidence record

| Phase | Selected agent | Requested model | Observed model | Input artifact(s) | Files changed | Validation commands / results | Terminal verdict | Unexpected automatic handoff |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HIGH start | NOT RUN | Terra | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| STANDARD completion | NOT RUN | Luna | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| HIGH re-entry | NOT RUN | Terra | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

## Completion decision

- HIGH-first observed: NOT RUN
- valid handoff only before Luna: NOT RUN
- structural trigger returned to Terra: NOT RUN
- original intent / route identity / Locked Decisions retained: NOT RUN
- no unexpected automatic handoff: NOT RUN
- terminal verdict: NOT RUN

実行環境が必要: VS Code固有UIまで検証する場合は、利用可能なGitHub Copilot Chat in VS Code環境で上記を実行し、このtemplateを実測値で複製してevidenceを保存します。Terra / Lunaの利用可否はCopilot planとorganization policyに依存します。指定modelを選べない、またはobserved modelが異なる場合はその差異を記録し、要求どおりのmodel smokeを`PASS`にしません。
