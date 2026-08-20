# PR Review Remediation

`$pr-review-remediation`は、Goal Contextを使わないbaseline PR review workflowです。Ready PRのGitHub Copilot reviewとread-only local reviewを集約し、別turnで修正するためのreview planを作成して停止します。

目的達成review、元のimplementation parentによる修正、同じreviewer sessionでの再reviewが必要な場合は、別packageの[$persistent-purpose-review](../persistent-purpose-review/README.md)を使います。baseline packageはGoal Context欠落時の暗黙fallbackではありません。

## Install

対象repository rootで導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

APMは`pr-review-remediation` Skill、`local-reviewer`、`review-planner`を導入します。finalizerはCodex用profileのmodel、reasoning、read-only sandboxを補完します。

## Phase 1

```text
$pr-review-remediation

このReady PRをreviewし、修正planを作成してください。productionは変更せず、plan作成後に停止してください。
```

1. repository、current branch、Ready PR、base/head OIDを確定する。
2. 必要な権限がある場合だけ`gh pr edit <number> --add-reviewer @copilot`でCopilot reviewを要求する。失敗時はpolling前に停止する。
3. `collect-pr-review-context.cs`でremote PR identity、review/comment/check、patchを取得する。
4. `local-reviewer`がread-onlyでcode/test/operation findingsを作成する。
5. `review-planner`が全sourceを`Apply | Hold | Reject`へ整理し、implementation intentとvalidationを含むreview planを作成する。
6. `READY_FOR_ADAPTIVE_IMPLEMENTATION | HUMAN_DECISION_REQUIRED | BLOCKED`を返して停止する。Phase 1ではproduction、commit、pushを変更しない。

collector例:

```powershell
dotnet run --file .agents/skills/pr-review-remediation/scripts/collect-pr-review-context.cs -- --repo owner/name --pr 123 --out .review/pr-123
```

timeout、Draft、identity drift、GitHub CLI失敗、不正JSON、未取得reviewを「指摘なし」と読み替えません。

## Phase 2

利用者が別turnでreview planの実装を明示した場合だけ、別途導入した`$adaptive-implementation-execution`へplanを渡します。このpackageはimplementation agent、purpose review、reviewer session stateを所有しません。

## Package contents

| Content | Path |
| --- | --- |
| Baseline Skill | `.apm/skills/pr-review-remediation/SKILL.md` |
| PR context collector | Skillの`scripts/collect-pr-review-context.cs` |
| Local reviewer | `.apm/agents/local-reviewer.agent.md` |
| Review planner | `.apm/agents/review-planner.agent.md` |
| Codex profile overlays | `codex-profile-overlays.json` |
| Deterministic evidence | `tests/pr-review-remediation/PRR-001/` |

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

0.6.0では旧purpose review契約を削除しました。旧state schemaや実行部品とのmigration、aliasは提供しません。purpose reviewを利用するrepositoryには`persistent-purpose-review` packageとuser-level Runnerを別途導入します。
