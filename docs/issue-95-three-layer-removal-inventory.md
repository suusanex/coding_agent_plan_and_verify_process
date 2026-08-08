# Issue #95 3-layer removal and rollback inventory

この記録は、Issue #93のrecovery branchにおける第1工程として、Issue #95で削除した`token-aware-full-coverage-3layer`のcurrent surfaceと、Issue #94へ渡すPlan Coverage側のrollback対象を区別する。

Issue #95単独の状態はmainへmergeしない。同じ`issue-93` branchでIssue #94、#96、#97、#98を順に実装し、最終整合後にmergeする。

## 削除したcurrent capability

- `apm-packages/token-aware-full-coverage-3layer/`配下のmanifest、Skill、instructions、agents、references、README
- 3-layer専用workflow、validator、`tests/full-coverage-slice-flow/` fixture suite
- root README、Installation and Maintenance、Plan Coverage README / Skillから3-layer packageを直接選択・導入するnavigation
- Adaptive、Design Pair、Architecture Slice Readiness validatorsとAdaptive / Design Pair workflowsにあった削除package専用assertion / path filter
- `scripts/provision-work-repo-agents.cs`の3-layer package導入、`slice-prep.toml` / `slice-impl.toml`補正、Parent State / Slice Record / Final Record template配布

provisionerのCLI optionsと、Plan Coverage package導入、`high-implementation-starter.toml` / `standard-implementation-completer.toml`補正は維持した。3-layer replacementや互換orchestratorは追加していない。

## Issue #94 rollback inventory

次のcurrent sourceには、PR #80で導入された`compact-slice-record-v2`、Parent Orchestration State、Parent Authorization、Slice Record / Final Record ownership等のsemanticsが残っている。Issue #95では修復、rename、template移植、互換layer追加を行わない。Issue #94でPR #80直前`1932e5a9f66c308130a33b4e3f20ec2eb09ee769`とPR #80 commit`20e46ad838f4628f88decc0ccf9b0f668eae23e8`を比較してsemantic rollbackする。

### Plan Coverage core

- `apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md`
- `apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md`
- `apm-packages/plan-coverage-residual-flow/apm.yml`とpackage validators
- `apm-packages/plan-coverage-residual-flow/README.md`

### Shared decomposition and agents

- `.github/instructions/plan-coverage-shared.instructions.md`
- `.github/agents/plan-slice-decomposition.agent.md`
- `.github/agents/change-risk-triage.agent.md`
- `.github/agents/implementation-contract-kernel.agent.md`
- `.github/agents/implementation-contract-review-kernel.agent.md`
- `.github/agents/runtime-contract-kernel.agent.md`
- `.github/agents/test-design-kernel.agent.md`
- `.github/agents/implementation-handoff-review.agent.md`
- `.github/agents/high-implementation-starter.agent.md`
- `.github/agents/standard-implementation-completer.agent.md`
- `.github/agents/implementation-execution.agent.md`
- `.github/agents/verification-kernel.agent.md`
- `.github/agents/coverage-gap-triage.agent.md`
- `.github/agents/coverage-gap-resolution-slice.agent.md`
- `.github/agents/cross-slice-verification-kernel.agent.md`
- `.github/agents/residual-decision-gate.agent.md`

### Active Plan Coverage documentation

- `docs/plan-coverage-process-and-agents.md`
- `docs/plan-coverage-purpose.md`
- `docs/token-aware-full-coverage-decomposition-flow.md`

### Search matches requiring baseline comparison

`.codex/agents/implementation-execution.toml`、`apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md`、`scripts/validate-architecture-slice-readiness.ps1`にも`Parent Authorization`等の検索語がある。これらは検索語だけでは3-layer由来と断定せず、Issue #94でPR #80 patchとの一致を確認してrollback要否を決める。

## Retained historical records

次は過去の要求、設計、実行、validation evidenceを記録するhistorical surfaceであり、current installation / routing guidanceとして扱わない。内容は一括削除・置換しない。

- `docs/codex-delegation-mustification-goals.md`
- `docs/codex-first-cost-aware-process-goals.md`
- `docs/codex-first-routing-branching.md`
- `docs/codex-full-coverage-3layer-fixes.md`
- `docs/github-copilot-fallback-process-goals.md`
- `docs/architecture-slice-readiness-validation-result.md`
- `plans/**`

`docs/codex-full-coverage-3layer-fixes.md`には、削除済みpackageをcurrent routeとして参照しないためのhistorical-only status noteだけを追加した。

## Search terms

Issue #94では少なくとも次を再検索する。

```text
token-aware-full-coverage-3layer
full-coverage-3layer
slice-prep.agent.md
full-coverage-parent-orchestration-state
full-coverage-slice-record
compact-slice-record-v2
Parent Authorization
```

## Validation result

Issue #95実装後のlocal validation:

| Check | Result | Notes |
| --- | --- | --- |
| Package / dedicated surface deletion | PASS | package directory、dedicated workflow / validator、fixture directoryはいずれも不存在 |
| Current route search | PASS | active README、package、workflow、scriptに3-layer package / routeの参照なし |
| Rollback residual search | PASS | current matchesを本inventoryのIssue #94対象またはbaseline比較対象へ分類 |
| README navigation | PASS | 削除済みpackageへのcurrent linkなし |
| Plan Coverage Residual Flow | PASS | semantic rollbackは未実施 |
| Adaptive Implementation | PASS | 3-layer専用integration assertionsを除去 |
| Design Pair Implementation | PASS | 3-layer専用state / Skill assertionsを除去 |
| Architecture Slice Readiness | EXPECTED FAIL | Plan Coverage Skillから削除済みpackageへのactive routeを機械的に除去したため、historical validation resultに記録されたSkill hashと不一致。Issue #94でsemantic rollback後に再検証する |
| File-based app publish | PASS | `scripts/provision-work-repo-agents.cs`を単一`.cs`のままpublish |
| Provisioner dry-run | PASS | HIGH / STANDARD profilesだけを報告し、3-layer package、slice profiles、templatesを報告しない |
| `git diff --check` | PASS | tracked diffのwhitespace errorなし |

この結果はrecovery完了を意味しない。Architecture validatorの中間失敗や残存semanticsを解消するために、削除済み3-layer implementationを復元・複製・移植してはならない。
