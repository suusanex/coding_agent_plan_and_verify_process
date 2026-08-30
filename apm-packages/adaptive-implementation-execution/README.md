# Adaptive Implementation Execution

通常のPlan Mode output、短い実装計画、または明示選択されたDesign Pair handoffから、現在残っているdecision surfaceに応じてimplementation ownershipを切り替える、Codex / GitHub Copilot Chat in VS Code対応のAPM packageです。

## 解決する問題

実装前のPlanが十分に見えても、production code、tests、wiring、build / test結果を確認して初めて分かる責務配置、contract、sequence、state、error、test seam等があります。

このpackageは、実装作業を「高能力モデルは考える」「標準モデルは実装する」と固定分業しません。分割軸は一つです。

> 現在残っている実装作業に、Decision-Surface Implementation Ownerが所有すべきdecision surfaceが残っているか。

## Semantic roles

| Role | Ownership |
| --- | --- |
| Decision-Surface Implementation Owner | unresolved decision surfaceが残る間、code inspection、production code、tests、wiring、focused verification、影響再確認を含むimplementation feedback loopを所有する |
| Bounded-Residual Implementation Owner | decision surface解消後、locked contract / semanticsの適用だけで完了できるbounded residual workを所有する |

agent名はそれぞれ`decision-surface-implementation-owner`、`bounded-residual-implementation-owner`です。

semantic roleはmodel tierやruntime topologyから独立しています。Codex profileやCopilot frontmatterは前者へTerra、後者へLunaを割り当てますが、これはadapter設定でありsemantic ownershipの定義ではありません。parent / subagent、別process、VS Code handoff button等も実行手段にすぎません。

## Flow

```text
ordinary Plan
  -> decision-surface-implementation-owner
       -> CONTINUE_DECISION_SURFACE_IMPLEMENTATION
       -> IMPLEMENTATION_COMPLETED
       -> READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION
            -> bounded-residual-implementation-owner
                 -> IMPLEMENTATION_COMPLETED
                 -> NEEDS_DECISION_SURFACE_REENTRY
                      -> decision-surface-implementation-owner
       -> REPLAN_REQUIRED / HUMAN_DECISION_REQUIRED / BLOCKED
```

Decision-Surface Implementation Ownerは、decision surfaceを解消するために合理的に必要なproduction/test implementationとverificationを行います。code editなしで残作業がboundedと証明できる場合は早期transferできますが、zero-code transferはdefaultでも成功指標でもありません。

自然なtransfer pointがなければ最初のownerが全実装を完了して構いません。transferのためだけにscaffold、TODO、不自然な途中状態を作りません。

## Plan Coverageとの違い

このpackageはimplementation-only flowです。

- 通常Plan、手書きPlan、Issue内の実装計画だけで開始できる
- Plan Coverage artifactsを必須にしない
- change-risk-triage、runtime contract、test design、coverage ledger、residual decisionを再実装しない
- final code reviewや総合architecture reviewを置き換えない

## Design Pair input

利用者が`design-pair-implementation-execution`を明示選択した場合、tracked Design Pair handoffを追加inputとして受け取ります。validな`READY_FOR_ADAPTIVE_IMPLEMENTATION`、complete interaction、Target Map / selection / post-map evidence、集合整合、Locked Decision confirmationを編集前に検証します。

Design Pairが今回新たに作るbinding decisionはvalidなLocked Decisionsだけです。Target Map、Affected files / symbols、Discussed-Unlocked、Adaptive-Owned等はDecision-Surface Implementation Ownerの通常authorityまたはAllowed edit surfaceを拘束しません。

## Package contents

| Content | Path |
| --- | --- |
| Orchestration skill | `.apm/skills/adaptive-implementation-execution/SKILL.md` |
| Implementation Intent reference | skillの`refs/intent.md` |
| Bounded Residual Handoff reference | skillの`refs/handoff.md` |
| Decision-surface owner | `.apm/agents/decision-surface-implementation-owner.agent.md` |
| Bounded-residual owner | `.apm/agents/bounded-residual-implementation-owner.agent.md` |
| Codex profile metadata | `codex-profile-overlays.json` |
| Shared profile finalizer | `../codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs` |
| Static validator | `scripts/validate-adaptive-implementation-execution.ps1` |
| Remote install smoke | `scripts/validate-adaptive-implementation-apm-smoke.ps1` |
| Executable routing scenarios | `tests/routing-scenarios.json` + `tests/validate-routing-scenarios.ps1` |

`.apm/**`がprocess semanticsのcanonical sourceです。CopilotとCodexの生成物、Agent Plugin artifactはこのsourceから導出します。

## Quick start

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

Copilotでは`decision-surface-implementation-owner`から開始します。`bounded-residual-implementation-owner`をfresh intakeとして選びません。agent/model遷移ではtracked handoff pathを渡し、会話履歴だけをdurable stateにしません。

skillは`/adaptive-implementation-execution`で明示起動した場合だけ使用します。通常の「実装して」や自然文での名前言及だけでは自動選択しません。

## Breaking change in 0.6.0

0.6.0はownership contractのbreaking redesignです。

- 旧`high-implementation-starter` / `standard-implementation-completer`は削除
- 旧0.5 handoff schemaとLegacy Adaptive handoff normalizationは非対応
- 旧`READY_FOR_STANDARD_COMPLETION`、`CONTINUE_HIGH_IMPLEMENTATION`、`COMPLETED_BY_HIGH_MODEL`、`NEEDS_HIGH_MODEL_REENTRY`は非対応
- 旧artifactは新schemaへ推測変換せず、invalid completion handoffとしてfail closed

## Documentation

- [Install guide](docs/install-guide.md)
- [Usage guide](docs/usage-guide.md)
- [Validation scenarios](docs/examples/adaptive-routing-validation.md)
- [Manual Copilot smoke](docs/examples/copilot-manual-smoke.md)

0.4.0 / 0.5.0のdated real-model evidenceはhistorical recordとして保持します。0.6.0のqualificationには再利用しません。

## Agent Plugin artifact

Agent Plugin artifactはpackage rootへchecked-inせず、repository共通builderでtemporary stageへ生成します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package adaptive-implementation-execution
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package adaptive-implementation-execution
```

APMがsupported distributionです。未観測の0.6.0 runtime behaviorをPASSへ昇格させません。
