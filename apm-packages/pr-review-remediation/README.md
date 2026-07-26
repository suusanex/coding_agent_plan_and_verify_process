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
| Actual agent smoke runner | `scripts/run-pr-review-remediation-agent-smoke.ps1` |
| Remote APM smoke | `scripts/validate-pr-review-remediation-apm-smoke.ps1` |

## Validation

静的contract、collector fixture、profile helper、固定された実agent証跡を検証します。

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
```

実agent chainを再実行して`tests/pr-review-remediation/PRR-001/`を更新する場合:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -DescribePayload

pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -ConfirmExternalModelPayload
```

最初のコマンドは送信対象を表示するだけでmodelを起動しません。内容を確認し、外部model serviceへの送信を明示承認した場合だけ2番目のコマンドを実行します。

APM 0.26.0によるremote package導入、transitive dependency、relative asset、4 profile、sentinel不変を検証する場合:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1 `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <git-ref>
```

実agent smokeは認証とmodel利用権限を必要とするためCIで毎回再実行せず、固定証跡をvalidatorで検査します。remote APM smokeはbase repositoryのevent refを使うCI merge gateです。pull requestでは`refs/pull/<number>/merge`を指定するため、checkoutされたmerge snapshotとremote packageの内容が一致します。

詳細はSkillの`references/usage.md`を参照してください。
