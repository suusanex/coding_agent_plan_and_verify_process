# PR Review Remediation

`$pr-review-remediation`は、Goal Contextを使わないbaseline PR review / remediation workflowです。Ready PRに紐付くremote review evidenceを集約し、現在の親エージェントが各findingを評価して、必要な修正、validation、commit、pushまでを同じ作業内で完了します。repository外のlocal agent reviewerは起動しません。

目的達成review、元のimplementation parentによる修正、同じreviewer sessionでの再reviewが必要な場合は、別packageの[$persistent-purpose-review](../persistent-purpose-review/README.md)を使います。

## Install

対象repository rootで導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target copilot,codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

APMは`pr-review-remediation` Skillと読み取り専用の`review-planner`を導入します。finalizerはCodex用planner profileのmodel、reasoning、read-only sandboxを補完します。

## Workflow

1. repository、current branch、Ready PR、base/head OIDを確定する。
2. `gh pr edit <number> --add-reviewer @copilot`等でGitHub上のreviewを要求する。失敗時はpolling前に停止する。
3. `collect-pr-review-context.cs`でremote PR identity、review/comment/check、patchを取得する。
4. `review-planner`が全sourceを`Apply | Hold | Reject`のrecommendationへ整理し、source coverageとimplementation intentを作る。
5. 現在の親が各recommendationを検討してfinal decisionを確定する。`Hold`やproduct / scope判断を未解決のまま通常完了へ進めない。
6. `Apply`は同じ親がproduction / tests / docsへ反映してvalidationする。`Reject`は反映しない理由を保持する。
7. remediation差分がありvalidationが成功した場合、利用者から否定指示がなければcommitしてPR branchへpushする。差分がなければempty commitを作らない。
8. 全findingのdecision / evidence、validation、Git結果を`REVIEW_COMPLETE | HUMAN_DECISION_REQUIRED | BLOCKED`で報告する。

```powershell
dotnet run --file .agents/skills/pr-review-remediation/scripts/collect-pr-review-context.cs -- --repo owner/name --pr 123 --out .review/pr-123
```

timeout、Draft、identity drift、review要求・GitHub CLI・permission failure、未取得reviewを「指摘なし」と読み替えません。remediation後のremote head drift、validation failure、push failureも正常完了にしません。

## Adaptive Implementation

Adaptive Implementationは標準の必須経路ではありません。利用者が明示的に`$adaptive-implementation-execution`を指定した場合だけremediation実装に利用できます。指定がなければ現在の親が実装し、Adaptiveの導入、起動、別turnを要求しません。明示利用した場合も、この親がreview coverage、validation、commit / push、最終報告まで継続します。

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

remote APM install smokeはGitHub Actionsでpackage commitを指定して実行します。real GitHub review、external model payload、実repositoryへのremediationとGit操作はdeterministic validatorの証明範囲外です。

## Update and remove

```powershell
apm update
apm uninstall pr-review-remediation
```

0.8.0ではremediationを同一parent完結型へ変更し、Adaptive Implementationを利用者が明示指定した場合だけ使う任意経路にしました。0.7.0で導入したremote-only review evidence、fail-closedな取得、読み取り専用plannerの境界は維持します。purpose reviewを利用するrepositoryには`persistent-purpose-review` packageとuser-level Runnerを別途導入します。

## Agent Plugin artifact

process semanticsの正本はこのpackageの`.apm/**`です。Agent Plugin artifactはpackage rootへchecked-inせず、repository共通builderでtemporary stageへ生成します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package pr-review-remediation
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package pr-review-remediation
```

APMがsupported distributionです。direct deploymentのstatusとevidenceは`tests/agent-plugin/qualification.json`に記録し、未観測のbehaviorをPASSへ昇格させません。
