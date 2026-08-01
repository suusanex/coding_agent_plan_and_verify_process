---
name: goal-context-pr-review
description: Use from the original implementation parent task to run Goal Context-aware independent PR review, parent-owned remediation, and bounded purpose-only re-review without separate top-level review or implementation tasks.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Goal Context PR Review

初回実装を担当した元の親task内で、Ready PRの独立review、親による修正、purpose-only再reviewを最大3roundまで実行するcanonical flowです。利用者の通常操作は、このSkillを同じ親taskで一度開始することだけです。

```text
$goal-context-pr-review

この実装のReady PRをGoal Contextに照らしてreviewし、必要な修正と再reviewを同じtask内で完了してください。
```

別top-level Review / Implementation task、thread ID、artifact path、hash、JSON、result referenceの転記をnormal pathへ要求しません。Goal Contextのexact pathや、曖昧時のPR番号/URLを利用者が短く指定することはできますが、pathやhashの管理を要求しません。Goal Contextは自然言語のfree-form textであり、作成元、filename、frontmatter、見出し、lifecycle、approval recordを要求しません。

## Ownership and non-goals

- production source、tests、docsの唯一のwrite ownerは、このSkillを開始した元の親agentです。
- `local-reviewer`と`purpose-reviewer`は毎回新しいread-only subagentとして実行し、raw outputだけを返します。
- reviewerはcommit、push、PR更新、review artifact編集を行いません。
- same-parent managerが行うGitHub mutationは、round 1開始時のGitHub Copilot review要求だけです。
- round 1だけがGitHub Copilot sources + local reviewer + purpose reviewerです。
- round 2/3は新しいpurpose reviewerだけです。Copilot待機とlocal reviewerを再実行しません。
- 自動round 4、Adaptive executorへの置換、複数top-level task間の復旧、Goal Contextの多段承認、Plugin移行は行いません。
- Issue本文はGoal Contextの代替になりません。

## Start: auto-resolve and bind current inputs

親agentは現在のrepository rootから次の一操作を実行します。`--goal-context`はexact pathが会話で選択済みの場合だけ追加します。GitHub CLI認証には対象PRへreviewerを要求できる権限が必要です。

```powershell
dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- start --repository-root . --format json
```

このcommandは次をfail closedで行います。

1. current GitHub repositoryを解決する。
2. current branchのReady PRを優先し、存在しない場合だけrepository全体のunique Ready PRへfallbackする。曖昧な場合は`--pr <number-or-url>`を短く確認する。
3. exact指定または`goal-context-*.md`のunique discoveryでGoal Contextを選び、readable non-empty free-form textであることだけを確認する。exact指定ではfilenameや拡張子を制限しない。
4. `gh pr edit <number> --add-reviewer @copilot`でGitHub Copilot reviewを明示要求する。
5. collectorでcurrent base/head、remote patch、GitHub Copilot terminal reviewとinline sourcesを取得する。collectorがcompleteと判定した場合は、inline commentなしの`reviewOnly`と、inline commentありの`reviewAndInline`をどちらも受理する。
6. `.review/pr-N/same-thread/<run-id>/round-001/`と`run-state.json` / `run-summary.md`を自動生成する。

Ready PRが0件、current branchにも一意fallbackにも決められない、Draftを明示指定した、Goal Contextが欠落/曖昧/読取不能、Copilot review要求が権限・policy・利用条件によって失敗した、collector timeout、head driftの場合は、reviewerやremediationへ進まず、具体的なblockerを一つ返して`Blocked`で停止します。PRだけが曖昧な場合は`--pr`へ短い番号またはURLを受け取って再実行します。利用者へ内部stateの作成や修復を求めません。

## Round 1: independent mandatory sources

親agentは生成済み`round-001/review-context.json`、`pr-diff.patch`、Goal Context selection、対象repository規約を直接読み、次の二つを独立したread-only subagentとして起動します。

- `local-reviewer`: code/test/operation findingsを`LR-*`で返す。
- `purpose-reviewer`: Goal Context outcome findingsを`PUR-*`で返す。

返却内容を改変せず、それぞれ次へ保存します。

- `round-001/local-reviewer.raw.md`
- `round-001/purpose-reviewer.raw.md`

collectorのGitHub Copilot sourcesが三つ目のmandatory sourceです。親agentの自己review、片方のreviewer、空artifactで代替しません。raw evidenceは常に`run-summary.md`より上位です。

親agentはraw evidenceをstable `TRK-*`へprojectionし、同じroundの`round-assessment.json`へ保存して次を実行します。shapeは`templates/round-assessment.example.json`を使います。

```powershell
dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- assess --run <auto-created-run-root> --round 1 --assessment <auto-created-run-root>/round-001/round-assessment.json --format json
```

`assess`はmandatory source、reviewed head、`Production code changed: No`、finding IDを検証し、`Complete | Remediating | HumanDecisionRequired | Blocked`へ遷移します。

## Parent-owned remediation

`Remediating`の場合、元の親agentだけがactive findingを修正します。

1. Goal Context boundaryと対象`TRK-*`を保持してproduction/tests/docsを編集する。
2. repository規約に従って関連build/test/lint/formatを実行する。
3. current PR headへcommit/pushする権限がある場合だけ更新する。権限がない、validation不能、または安全に更新できない場合は`block --reason`で停止する。
4. current remote headを推測せず、次のcommandでcollector authorityからrefreshする。

```powershell
dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- next-round --run <auto-created-run-root> --format json
```

同じhead、Draft、head drift、collector failureは`Blocked`です。new current headを確認できた場合だけ`round-002/`または`round-003/`を作ります。

## Rounds 2 and 3: purpose-only

`next-round`はcollectorを`--no-wait-for-copilot`で実行し、current identity/patchを監査証跡として保持します。親agentは`local-reviewer`を起動せず、新しいread-only `purpose-reviewer`だけを起動します。

purpose reviewerへ次を渡します。

- current roundのcollector-declared identityとremote patch
- selected Goal Contextとselection artifact
- `run-state.json`のactive `TRK-*`
- 直前roundのraw purpose evidenceとexplicit prior assessment
- 親が実施した変更とvalidationの事実

raw outputを`round-NNN/purpose-reviewer.raw.md`へ保存します。全active `TRK-*`に対し、current `PUR-*` evidenceで`persistent | resolved`を明示します。新規/reopened findingもcurrent `PUR-*`だけを根拠にします。remote review/comment/checkはaudit-onlyであり、新しいactionable findingに変換しません。

purpose-only `round-assessment.json`のmandatory sourceは`purpose-reviewer`だけです。`assess`はlocal artifact、Copilot mandatory source、prior assessment欠落、non-`PUR-*` actionable evidenceを拒否します。

## Terminal decision and notification projection

- mandatory sourcesが揃いactive findingがない: `Complete`
- product/policy/risk acceptance判断が必要: `HumanDecisionRequired`
- round 3でactive findingが残る: `HumanDecisionRequired`
- identity/evidence/reviewer/validation/pushが安全に成立しない: `Blocked`

terminal時はrun rootへ`terminal-projection.json`と`completion-notification.txt`を自動生成します。projectionに含めるfieldは`schema_version`、`primary_process`、`observed_status`、safe `title`、current concrete HTTPS PR `result_uri`だけです。`thread-id` / `turn-id`を生成・推測・受領しません。callback identityはnotification runtimeのauthorityです。

親agentはterminal responseを返す直前に`completion-notification.txt`をraw textとして読み、そこにあるfenced blockを最終assistant messageの末尾へ一字一句変更せず一度だけ追加します。blockの後へ本文を追加しません。notification runtimeはcallbackの`last-assistant-message`だけを読むため、このappendがcurrent task linkとPR linkを同じ通知へ渡すproducer/consumer境界です。

```powershell
dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- validate --run <auto-created-run-root> --format json
```

## Manual-only evidence

deterministic fixtureはsame-parent state contractとreviewer role/count ledgerを検証しますが、次を完了証拠にしません。

- real model reviewer independence
- real parent-owned remediation
- real GitHub Copilot review request / current remote PR head update
- real Windows/Codex callback count、notification target、button operation

real same-parent smokeではreviewer roles/countを`run-summary.md`から記録し、private callback identityやunsupported hierarchy filterを作りません。

## Historical compatibility

`scripts/manage-review-cycle.cs`は、過去の固定Review Thread / Implementation Thread evidenceを検証するhistorical compatibility utilityとして保持します。canonical same-parent flowの開始、state authority、normal usageとして再ラベルしません。新規normal runで利用者へrole task IDやmanual Adaptive handoffを要求しません。

## Assets

- `scripts/manage-same-parent-review.cs`: canonical same-parent orchestration/state address
- `scripts/select-goal-context.cs`: canonical Goal Context selection integration
- `scripts/manage-review-cycle.cs`: historical fixed two-task compatibility only
- `templates/purpose-review-findings.md`
- `templates/round-assessment.example.json`
- `references/design.md`
- `references/usage.md`
- `references/troubleshooting.md`
- shared collector: `../pr-review-remediation/scripts/collect-pr-review-context.cs`
