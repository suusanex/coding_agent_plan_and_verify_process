# PR Review Remediation

`$pr-review-remediation`は、Goal Contextを使わないbaseline PR review workflowです。Ready PRに紐付くremote review evidenceを集約し、別turnで修正するためのreview planを作成して停止します。repository外のlocal agent reviewerは起動しません。

目的達成review、元のimplementation parentによる修正、同じreviewer sessionでの再reviewが必要な場合は、別packageの[$persistent-purpose-review](../persistent-purpose-review/README.md)を使います。

## Install

対象repository rootで導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target copilot,codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

APMは`pr-review-remediation` Skillと`review-planner`を導入します。finalizerはCodex用planner profileのmodel、reasoning、read-only sandboxを補完します。

## Phase 1

1. repository、current branch、Ready PR、base/head OIDを確定する。
2. `gh pr edit <number> --add-reviewer @copilot`等でGitHub上のreviewを要求する。失敗時はpolling前に停止する。
3. `collect-pr-review-context.cs`でremote PR identity、review/comment/check、patchを取得する。
4. `review-planner`がremote sourceを`Apply | Hold | Reject`へ整理し、implementation intentとvalidationを含むreview planを作成する。
5. `READY_FOR_ADAPTIVE_IMPLEMENTATION | REVIEW_COMPLETE | HUMAN_DECISION_REQUIRED | BLOCKED`を返して停止する。Phase 1ではproduction、commit、pushを変更しない。`REVIEW_COMPLETE`では修正計画やAdaptive開始promptを生成しない。

```powershell
dotnet run --file .agents/skills/pr-review-remediation/scripts/collect-pr-review-context.cs -- --repo owner/name --pr 123 --out .review/pr-123
```

timeout、Draft、identity drift、review要求・GitHub CLI・permission failure、未取得reviewを「指摘なし」と読み替えません。

## Phase 2

利用者が別turnでreview planの実装を明示した場合だけ、別途導入した`$adaptive-implementation-execution`へplanを渡します。このpackageはimplementation agent、purpose review、reviewer session stateを所有しません。

## Package contents

| Content | Path |
| --- | --- |
| Baseline Skill | `.apm/skills/pr-review-remediation/SKILL.md` |
| PR context collector | Skillの`scripts/collect-pr-review-context.cs` |
| Review planner | `.apm/agents/review-planner.agent.md` |
| Codex profile overlay | `codex-profile-overlays.json` |
| Deterministic scenarios | `tests/fixtures/remote-review-scenarios.json` |

## Validation

```powershell
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
```

remote APM install smokeはGitHub Actionsでpackage commitを指定して実行します。real GitHub review、external model payload、Phase 2実装はdeterministic validatorの証明範囲外です。

## Update and remove

```powershell
apm update
apm uninstall pr-review-remediation
```

0.7.0ではlocal-reviewer経路とGoal Context/multi-round planner契約を削除しました。purpose reviewを利用するrepositoryには`persistent-purpose-review` packageとuser-level Runnerを別途導入します。

## Agent Plugin artifact

process semanticsの正本はこのpackageの`.apm/**`です。Agent Plugin artifactはpackage rootへchecked-inせず、repository共通builderでtemporary stageへ生成します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package pr-review-remediation
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package pr-review-remediation
```

APMがsupported distributionです。direct deploymentのstatusとevidenceは`tests/agent-plugin/qualification.json`に記録し、未観測のbehaviorをPASSへ昇格させません。
