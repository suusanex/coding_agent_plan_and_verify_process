# PR Review Remediation

Ready PRの成立、local Codex review、GitHub Copilot review収集、統合remediation plan、別親ターンのAdaptive Implementationによる修正実装・検証を一つの運用として提供するAPM packageです。

```text
Phase 1: PR preparation -> review collection -> local-reviewer -> review-planner -> review-plan.md -> stop
Phase 2: explicit new parent turn -> adaptive-implementation-execution -> implementation and validation
```

Phase 1の停止はレビュー反映全体の完了ではありません。実装責務は削除せず、既存Adaptive Implementationへ一本化します。

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills
dotnet run --file apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs -- . --dry-run
dotnet run --file apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs -- .
dotnet run --file apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs -- .
dotnet run --file apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs -- . --check
```

APMがSkillとcanonical agentsを導入し、二つのhelperがreview/Adaptiveの具体的Codex profileをそれぞれ同期します。どちらも`AGENTS.md`と`.codex/config.toml`を操作しません。

## Package contents

| Content | Path |
| --- | --- |
| Orchestration Skill | `.apm/skills/pr-review-remediation/SKILL.md` |
| Collector | Skillの`scripts/collect-pr-review-context.cs` |
| Review templates | Skillの`templates/` |
| Usage/migration/troubleshooting | Skillの`references/` |
| Review profiles | `codex-agents/*.toml` |
| Profile sync helper | `scripts/sync-pr-review-remediation-local.cs` |
| Validator | `scripts/validate-pr-review-remediation.ps1` |

詳細はSkillの`references/usage.md`を参照してください。

