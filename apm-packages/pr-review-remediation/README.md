# PR Review Remediation

Ready PRの成立、local Codex review、GitHub Copilot review収集、統合remediation plan、別親ターンのAdaptive Implementationによる修正実装・検証を一つの運用として提供するAPM packageです。基礎版`$pr-review-remediation`と、独立した目的達成reviewを追加する`$goal-context-pr-review`を明示的に分けます。

```text
Phase 1 baseline: PR preparation -> review collection -> local-reviewer -> review-planner -> review-plan.md -> stop
Phase 1 Goal Context: shared preparation/collection -> local-reviewer + purpose-reviewer -> shared review-planner -> review-plan.md -> stop
Phase 2: explicit new parent turn -> adaptive-implementation-execution -> implementation and validation
Optional multi-round: explicit review turn -> explicit Adaptive turn -> explicit next review turn
Human escalation: HUMAN_DECISION_REQUIRED (no handoff) -> explicit human choice -> resolve and bind approved plan -> explicit Adaptive turn
```

Phase 1の停止はレビュー反映全体の完了ではありません。実装責務は削除せず、既存Adaptive Implementationへ一本化します。

Goal Context対応版は同じpackage内の別Skillです。collector、`local-reviewer`、`review-planner`、review plan、Adaptive dependencyを基礎版と共有し、`purpose-reviewer`とGoal Context selectionだけを追加します。Goal Context文書契約は依存するGoal Context Authoring Skillのcanonical validatorを再利用し、selectorへ複製しません。

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
| Baseline review Skill | `.apm/skills/pr-review-remediation/SKILL.md` |
| Goal Context review Skill | `.apm/skills/goal-context-pr-review/SKILL.md` |
| Goal Context selector | Goal Context Skillの`scripts/select-goal-context.cs` |
| Multi-round cycle manager | Goal Context Skillの`scripts/manage-review-cycle.cs` |
| Multi-round planner result schema example | Goal Context Skillの`templates/review-result.example.json` |
| Multi-round round-result schema example | Goal Context Skillの`templates/review-round-result.example.json` |
| PRR-002 deterministic replay validator | `scripts/validate-prr-002-contract.cs` |
| Collector | Skillの`scripts/collect-pr-review-context.cs` |
| Review templates | Skillの`templates/` |
| Usage/migration/troubleshooting | Skillの`references/` |
| Review profiles | `codex-agents/*.toml` (`local-reviewer` / `purpose-reviewer` / `review-planner`) |
| Profile sync helper | `scripts/sync-pr-review-remediation-local.cs` |
| Validator | `scripts/validate-pr-review-remediation.ps1` |
| Actual agent smoke runner | `scripts/run-pr-review-remediation-agent-smoke.ps1` |
| Remote APM smoke | `scripts/validate-pr-review-remediation-apm-smoke.ps1` |

## Validation

静的contract、collector fixture、profile helper、固定された実agent証跡、PRR-002のidentity・hash・source coverage・decision mapping・handoff、およびPRR-003のmulti-round state遷移とnegative mutationを検証します。PRR-003の正本3round scenarioはchecked-in collector snapshotを使い、旧head sourceの累積、remote patch binding、Adaptive intentのSI/AC完全一致、収束までを再現します。非収束scenarioでは`HUMAN_DECISION_REQUIRED`に実行可能planがないこと、人間承認とplan hashを`resolve`がAdaptive前に記録することも検証します。PRR-002とPRR-003は記録済み入力の決定論的replayであり、外部model実行を宣言しません。

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
dotnet run --file apm-packages/pr-review-remediation/scripts/validate-prr-002-contract.cs -- --fixture-root tests/pr-review-remediation/PRR-002 --format json
dotnet run --file apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-review-cycle.cs -- validate --cycle <review-cycle.json> --format json
```

実agent chainを再実行して`tests/pr-review-remediation/PRR-001/`を更新する場合:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -DescribePayload

pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -ConfirmExternalModelPayload
```

最初のコマンドは送信対象を表示するだけでmodelを起動しません。内容を確認し、外部model serviceへの送信を明示承認した場合だけ2番目のコマンドを実行します。

APM 0.26.0によるremote package導入、transitive dependency、relative asset、5 profile、sentinel不変を検証する場合:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1 `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <git-ref>
```

実agent smokeは認証とmodel利用権限を必要とするためCIで毎回再実行せず、固定証跡をvalidatorで検査します。remote APM smokeはpull requestのfull head SHA、pushの`github.sha`を使い、検証対象packageを一意に固定します。

Goal Context対応版のmerge前manual smokeは、検証対象のprocess PR自身ではなくdisposable target repositoryで実施します。Codex Appが安全なtarget候補の提示、synthetic fixture作成、full head SHA固定の導入、artifact検証を担当し、人がGitHub変更、model送信、通知runtime、別親タスクの開始を承認します。round 1 review、別親タスクのAdaptive、round 2の`REVIEW_COMPLETE`までの手順と記録様式は`tests/pr-review-remediation/manual-model-smoke/README.md`を参照してください。

詳細はSkillの`references/usage.md`を参照してください。

Goal Context対応の通知付き二ターン例、軽量開発、Plan Coverage、Design Pairから共通review cycleへ入る例は`goal-context-pr-review/references/usage.md`を参照してください。
