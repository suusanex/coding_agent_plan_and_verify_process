# Usage

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\pr-review-remediation\scripts\sync-pr-review-remediation-local.cs -- . --dry-run
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\pr-review-remediation\scripts\sync-pr-review-remediation-local.cs -- .
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- .
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\pr-review-remediation\scripts\sync-pr-review-remediation-local.cs -- . --check
```

最初のhelperはreview agent profileを同期します。Adaptiveのmodel mapping、agent validation、installation policyは既存Adaptive helperをsource of truthとして使います。

## Start Phase 1

```text
$pr-review-remediation を使って、このbranchのPRをレビュー反映プロセスで処理してください。
base/headとPRを成立させ、Codex/Copilot reviewを収集し、review-plan.mdを作成したところで親ターンを停止してください。
```

PRを明示する場合:

```text
$pr-review-remediation を使って owner/name#123 を処理してください。
出力先は .review/pr-123 としてください。
```

## Start Phase 2

Phase 1が`READY_FOR_ADAPTIVE_IMPLEMENTATION`になった後、別の親ターンで開始します。

```text
$adaptive-implementation-execution を使って .review/pr-123/review-plan.md を実装してください。
review-plan.md の implementation_intent を source of truth とし、既存 Adaptive Implementation の router、agents、verdict、handoff、validation contract を変更または複製しないでください。
```

Phase 1の停止は全体完了ではありません。Phase 2の`COMPLETED_BY_HIGH_MODEL`または`COMPLETED`も、既存Adaptive contractどおりfinal code reviewや独立verificationの完了を意味しません。

## Artifacts

| Artifact | Owner | Purpose |
| --- | --- | --- |
| `review-context.json` | collector | machine-readable PR/review/check context |
| `review-context.md` | collector | human-readable context |
| `pr-diff.patch` | collector | confirmed remote base/head patch |
| `local-review-findings.md` | parent from local-reviewer output | local Codex findings |
| `review-plan.md` | parent from review-planner output | Adaptive-ready remediation plan |

