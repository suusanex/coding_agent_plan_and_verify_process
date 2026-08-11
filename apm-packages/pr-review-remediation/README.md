# PR Review Remediation

Ready PRのreview/remediationを提供するAPM packageです。入口は二つです。

- `$pr-review-remediation`: Goal Contextを使わない基礎版。review planを作成し、separate Adaptive turnの前で停止します。
- `$goal-context-pr-review`: Goal Contextを必須にし、初回実装を担当した同じ親task内で独立review、親修正、purpose-only再reviewを最大3roundまで進めるcanonical flowです。

Goal Context normal pathは次のとおりです。

```text
original implementation parent
  -> auto-resolve current repository / current-branch-or-unique Ready PR / free-form Goal Context
  -> round 1: request GitHub Copilot review, then collect Copilot + read-only local-reviewer + read-only purpose-reviewer
  -> parent-only remediation and validation
  -> round 2/3: new read-only purpose-reviewer only
  -> Complete | HumanDecisionRequired | Blocked
```

別top-level Review / Implementation task、thread ID、PR番号、artifact path、hash、JSON、result referenceの転記をnormal pathへ要求しません。reviewerはread-onlyで、production source、tests、docsを変更できるのは元の親agentだけです。

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

Copilot-only導入ではCodex profileが不要なため、finalizerの実行も不要です。APMはreview Skillsとcanonical reviewer agentsを導入し、共通 finalizerは`codex-profile-overlays.json`に定義された3つのCodex concrete profileだけを補完します。`review-planner`は基礎版とhistorical compatibility用です。Goal Context canonical same-parent pathのround decision/write ownershipは元の親agentが持ちます。finalizerは`AGENTS.md`と`.codex/config.toml`を操作しません。

基礎版`$pr-review-remediation`のreview planを別turnのAdaptive Phase 2で実装する場合だけ、optional add-onを別途導入します。canonical same-parent flowには不要です。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

## Usage

初回実装とReady PR作成を担当した親taskで次を実行します。

```text
$goal-context-pr-review

この実装のReady PRをGoal Contextに照らしてreviewし、必要な修正と再reviewを同じtask内で完了してください。
```

Goal Contextは自然言語のfree-form textです。作成元、filename、frontmatter、見出し、lifecycle、approval recordを要求しません。exact Goal Context pathが必要な場合だけ同じpromptへ添えます。PRはcurrent branchのReady PRを優先し、fallbackが曖昧な場合だけ短い番号またはURLを確認します。内部run stateは`.review/pr-N/same-thread/<run-id>/`へ自動作成され、利用者は管理しません。

Round 1の`start`は`gh pr edit <number> --add-reviewer @copilot`でreviewを要求してからcollectorを起動します。要求権限またはCopilot code review利用条件を満たさない場合は、polling前に具体的な失敗を返して`Blocked`になります。collectorがcurrent-head terminal reviewをcompleteと判定した場合は、inline commentが0件の`reviewOnly`と、1件以上の`reviewAndInline`をどちらも受理します。Copilot sourceと二つのread-only reviewer raw outputsはmandatoryです。local/purpose reviewerは`execute-reviewer.cs`がtyped `--execution-app`（`codex-exec` / `copilot-cli`）と`--model`で決定的に起動・待機・raw保存します。親LLMはassessmentとremediationだけを担い、任意commandの手作業起動は不要です。parentはactionable findingを修正・検証し、current remote headを更新します。Round 2/3はcollectorをCopilot waitなしでrefreshし、同じexecutorで新しいpurpose reviewerだけを実行します。active findingがround 3に残る場合やproduct判断が必要な場合は`HumanDecisionRequired`、安全な入力・source・head更新が成立しない場合は`Blocked`です。automatic round 4はありません。

Terminal projectionはschema/process/status/safe title/current concrete PR URIだけを含み、thread/turn IDを含みません。terminal時に親agentは`completion-notification.txt`を最終assistant message末尾へverbatimで追加し、callback runtimeへPR linkを渡します。real Windows actionはmanual verificationです。

## Package contents

| Content | Path |
| --- | --- |
| Baseline review Skill | `.apm/skills/pr-review-remediation/SKILL.md` |
| Goal Context same-parent Skill | `.apm/skills/goal-context-pr-review/SKILL.md` |
| Canonical same-parent state manager | Goal Context Skillの`scripts/manage-same-parent-review.cs` |
| Deterministic reviewer executor | Goal Context Skillの`scripts/execute-reviewer.cs` |
| Goal Context selector | Goal Context Skillの`scripts/select-goal-context.cs` |
| Historical fixed two-task validator | Goal Context Skillの`scripts/manage-review-cycle.cs` |
| Assessment example | Goal Context Skillの`templates/round-assessment.example.json` |
| Collector | Baseline Skillの`scripts/collect-pr-review-context.cs` |
| Codex profile metadata | `codex-profile-overlays.json` |
| Shared profile finalizer | `../codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs` |
| Package validator | `scripts/validate-pr-review-remediation.ps1` |
| Same-parent deterministic validator | `scripts/validate-same-parent-review.ps1` |
| Reviewer executor deterministic validator | `scripts/validate-execute-reviewer.ps1` |
| Remote APM smoke | `scripts/validate-pr-review-remediation-apm-smoke.ps1` |

## Validation

外部modelへ送信するpayloadを伴うagent smokeは、先に送信対象だけを表示します。内容を確認し、送信を明示承認した場合だけ実行します。

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -DescribePayload

pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -ConfirmExternalModelPayload
```

`-DescribePayload`は外部modelを呼びません。通常の文書変更やstatic contract変更では、`-ConfirmExternalModelPayload`を自動実行しません。

```powershell
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/validate-same-parent-review.ps1
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/validate-execute-reviewer.ps1
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
dotnet publish apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -o <temporary-output>
dotnet publish apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/execute-reviewer.cs -o <temporary-output>
```

Same-parent validatorはauto intake、Draft/0/複数Ready PR、Goal Context欠落、round 1 source coverage、read-only output、parent remediation後のnew-head gate、purpose-only round 2/3、finding transition、round cap、terminal projectionをfake GitHub fixtureで検証します。Executor validatorはtyped config、adapter argv、timeout/empty/non-zero、atomic raw publishをfake Codex/Copilot CLIで検証します。fake passだけでreal model independence、real GitHub write、real parent-owned remediation、real Windows/Codex callback/buttonをclose-readyと判定しません。

Remote APM導入を検証する場合:

```powershell
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1 `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <git-ref>
```

## Historical compatibility

`manage-review-cycle.cs`とPRR-003は、既存fixed Review Thread / Implementation Thread evidenceのhistorical validationとして保持します。新しいGoal Context normal usage、canonical Skill、manual smokeの開始契約として扱いません。

詳細はGoal Context Skillの`references/usage.md`、`references/design.md`、`references/troubleshooting.md`を参照してください。
