# Usage

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target copilot,codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- . --check
```

## Start Phase 1

```text
$pr-review-remediation を使って、このbranchのReady PRにGitHub上のreviewを要求し、remote review evidenceだけからreview-plan.mdを作成したところで停止してください。
```

PRを明示する場合:

```text
$pr-review-remediation を使って owner/name#123 を処理してください。出力先は .review/pr-123 としてください。
```

## Start Phase 2

Phase 1が`READY_FOR_ADAPTIVE_IMPLEMENTATION`になり、利用者が別turnで実装を明示した場合だけAdaptiveを導入して開始します。`REVIEW_COMPLETE`は修正不要の終端であり、Adaptiveを導入または開始しません。

```text
$adaptive-implementation-execution を使って .review/pr-123/review-plan.md を実装してください。
review-plan.md の implementation_intent を source of truth としてください。
```

## Artifacts

| Artifact | Owner | Purpose |
| --- | --- | --- |
| `review-context.json` | collector | machine-readable remote PR/review/check context |
| `review-context.md` | collector | human-readable remote context |
| `pr-diff.patch` | collector | confirmed remote base/head patch |
| `review-plan.md` | parent from review-planner output | Adaptive-ready remediation plan |

`$persistent-purpose-review`は別run、別stateを所有し、このartifact集合へ目的review結果を混在させません。

## Validation

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
```

外部modelを通常CIから呼びません。runtime qualificationでは送信対象をrepo-owned fixtureまたは明示されたReady PRに限定し、取得できないreviewをPASSへ昇格させません。
