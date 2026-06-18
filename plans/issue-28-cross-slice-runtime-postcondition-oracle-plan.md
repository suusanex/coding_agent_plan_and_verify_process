# Issue #28 cross-slice runtime postcondition oracle plan

## Source of truth

- GitHub issue: `https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/28`
- Issue title: `cross-slice verification が runtime postcondition 未確認でも PASS できる問題`
- Issue comments: none at planning time
- Scope: Plan網羅チェック・残件判定フロー / `cross-slice-verification-kernel` / `residual-decision-gate` の verification oracle と evidence classification 強化

## Goal

`cross-slice-verification-kernel` が、production interface / implementation / wiring、source-structure test、CI green だけを根拠に `CROSS_SLICE_VERIFIED` または final PASS 相当へ進めないようにする。

stateful な cross-slice contract では、producer から production wiring を通った後に consumer 側の runtime gate / durable state / async worker / recovery semantics が parent acceptance condition の runtime postcondition を満たすことを必須証跡にする。

## Non-goals

- 特定プロダクトや外部リポジトリの実装修正
- 実 runtime 環境、manual operation、secret、外部サービスを使った検証
- Plan網羅チェック・残件判定フローを full autonomous verification flow に置き換えること
- full-coverage 3層運用を beginner / standard route に昇格すること

## Current gaps

| Gap | Current risk | Required correction |
| --- | --- | --- |
| `Bound` definition | production interface / implementation / wiring の三点確認だけで `Bound` にできる | post-wiring behavior と parent AC runtime postcondition の確認を必須にする |
| Source-structure evidence | 呼び出し順序、DI、method existence を runtime behavior proof と誤認できる | source-structure test は wiring evidence であり、runtime state / async / durable / recovery proof ではないと明記する |
| CI green evidence | test が required postcondition を assertion していなくても close evidence に見える | test body または test-design mapping が required postcondition を assertion している場合だけ close evidence にする |
| Previous gap closure | rerun で前回と同等または弱い evidence により gap close できる | previous gap closure delta と evidence strength comparison を必須化する |
| Forbidden state transfer | parent AC の否定条件が cross-slice verification に転記されない | parent AC から Forbidden state oracle を作り、否定 evidence がない限り PASS 不可にする |
| Version / vocabulary drift | agent prompt や verdict vocabulary の drift を artifact で検出しづらい | agent / skill file path、SHA、allowed verdict vocabulary、actual verdict、vocabulary validation を必須化する |
| Residual skip | previous `RES-*` や `NeedsHumanDecision` が rerun で弱い evidence により消える | residual skip / closure table と explicit decision requirement を必須化する |

## Target files

| File | Planned change |
| --- | --- |
| `.github/agents/cross-slice-verification-kernel.agent.md` | runtime postcondition oracle、evidence strength ladder、forbidden-state oracle、previous gap closure delta、agent version table、stronger `Bound` definition、CI/source-structure evidence rulesを追加する |
| `.github/agents/residual-decision-gate.agent.md` | cross-slice rerun / previous residual inputs、`NeedsHumanDecision` closure rules、residual skip tableを追加する |
| `README.md` | Plan網羅チェック・残件判定フローとcross-slice説明を、runtime postcondition / residual skip / evidence strengthの新ルールへ同期する |
| `docs/token-aware-guardrail-kernel-process-and-agents.md` | agent本文と同じ運用ルール、status vocabulary、artifact structureを著者向けdocsへ反映する |
| `docs/token-aware-full-coverage-decomposition-flow.md` | full-coverage decomposition後のcross-slice close条件を、runtime postcondition oracle前提へ更新する |
| `apm-packages/token-aware-guardrail-kernel-flow/apm.yml` | package pathの追加が不要であることを確認する。agent名変更がない限り変更しない |

## Implementation plan

1. `cross-slice-verification-kernel.agent.md` の冒頭ルールを強化する。
   - `CROSS_SLICE_VERIFIED` は runtime postcondition oracle が全件 `Done` で、Forbidden state が否定され、Residual Decision Gate へ渡す item がない場合だけ許可する。
   - `CROSS_SLICE_VERIFIED_WITH_RESIDUAL_DECISION_REQUIRED` は close-ready ではないことを再明示する。

2. `Agent version` セクションを required output に追加する。
   - 必須列: `Agent file path`, `Agent file SHA`, `Skill file path`, `Skill file SHA`, `Allowed verdict vocabulary`, `Actual verdict`, `Vocabulary valid?`
   - `Actual verdict` が allowed vocabulary に含まれない場合は PASS 不可にする。
   - skill を使わない場合は `N/A` とし、`N/A` の理由を evidence として残す。

3. Cross-slice postcondition oracle を `Step 3` と output structure に追加する。
   - 必須表:

```md
| ID | Producer action chain | Production wiring path | Consumer observable | Required runtime postcondition | Forbidden state | Evidence type | Evidence strength | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
```

   - stateful contract では producer state と consumer gate の両方を確認しない限り `Done` / `Bound` にしない。

4. `Bound` の定義を更新する。
   - production interface / production implementation / production wiring に加えて、post-wiring behavior が parent AC の runtime postcondition を満たす証跡を必須にする。
   - source-structure test は wiring evidence としてのみ扱う。

5. Evidence strength ladder を追加する。
   - `ArtifactStatementOnly`
   - `SourceTextOrSourceStructureTest`
   - `ExactSourceProofOfProducerAndConsumerStateTransition`
   - `UnitBehaviorTestInvokingProducerAndConsumerTogether`
   - `ProductionStartupEquivalentBehaviorTest`
   - `RealRuntimeOrManualOperationEvidence`

6. Rerun gap closure delta を必須化する。
   - 必須表:

```md
| Previous ID | Previous failure mode | Required closure evidence | New evidence delta | Evidence strength vs previous | Closure decision |
| --- | --- | --- | --- | --- | --- |
```

   - previous failure が source-level evidence不足なら、source-structure test + CI green だけでは `Closed` にできない。

7. Forbidden-state oracle を追加する。
   - parent AC の否定条件を `Forbidden state` に転記する。
   - 例: producer active / consumer rejects、request accepted but not durably accepted、startup recovery publishes active before dependent component ready。
   - Forbidden state を否定する behavior evidence または exact source proof がない場合は `BLOCKED_BY_PARENT_ACCEPTANCE_GAP` または `BLOCKED_BY_CROSS_SLICE_CONTRACT_MISMATCH` にする。

8. Source-structure test と CI green の扱いを明文化する。
   - source-structure test は呼び出し順序、DI registration、method call existence の evidence に限定する。
   - CI green は実行された test の成功証跡であり、test body / test-design mapping が required postcondition を assertion している場合だけ close evidence にする。

9. `residual-decision-gate.agent.md` を強化する。
   - optional inputs に `cross-slice-verification-kernel` output と previous residual artifactを追加する。
   - previous `RES-*` がある場合、rerunで skip するには次の表を必須にする。

```md
| RES ID | Previous required decision | Closure type | New evidence | Why human decision no longer needed |
| --- | --- | --- | --- | --- |
```

   - `NeedsHumanDecision` を含む item は、explicit human decision、parent Plan の既決基準に合う code/test修正、または previous RES の前提誤りの新証跡がない限り closeしない。

10. README と docs を同期する。
    - README の Plan網羅チェック・残件判定フロー説明、agent一覧、artifact一覧に、runtime postcondition oracle と residual skip gate を追加する。
    - `docs/token-aware-guardrail-kernel-process-and-agents.md` に同等の著者向け詳細を追加する。
    - `docs/token-aware-full-coverage-decomposition-flow.md` で cross-slice verification は structural wiring確認だけではなく post-wiring runtime postcondition確認であると明記する。

11. Synthetic fixture 方針を検討する。
    - このリポジトリに実行可能テスト基盤がない場合は、まず docs内の synthetic example と expected verdict table に留める。
    - 既存の validation artifact形式に合わせられる場合は、`plans/`または docs exampleとして、consumer gateが閉じたままの例と期待 verdictを追加する。

## Acceptance mapping

| Issue acceptance condition | Planned evidence |
| --- | --- |
| `cross-slice-verification-kernel.agent.md` に runtime postcondition oracle が追加されている | agent required outputに postcondition oracle tableを追加 |
| `Bound` が post-wiring behavior を要求する | status vocabularyとStub-to-Production Binding stepを更新 |
| source-structure test と behavior proof の違いが明文化されている | agent / README / docsにevidence type ruleを追加 |
| CI green はpostcondition assertionがある場合だけclose evidence | agent / docsにCI evidence ruleを追加 |
| rerun artifactでprevious gap / residual closure deltaとevidence strengthを必須化 | cross-slice previous gap tableとresidual skip tableを追加 |
| forbidden-state oracleをparent ACから引き継ぐ | forbidden-state oracle stepとoutput tableを追加 |
| agent / skill version、allowed verdict vocabulary、actual verdict整合確認がartifactに入る | Agent version sectionを追加 |
| `NeedsHumanDecision` / residual candidateをrerunでskipする条件が明文化 | residual-decision-gateにskip条件を追加 |
| stateful cross-slice contractではproducer / consumer両方のstate gate確認が必要 | postcondition oracleとBound定義へ明記 |
| source-structure testだけではstartup / recovery / async worker / durable state / state-machine consistencyを`Done` / `Bound`にできない | evidence strength ladderとMust not doを更新 |

## Validation plan

1. Markdown consistency checks

```powershell
git diff --check
rg -n "runtime postcondition|Forbidden state|Evidence strength|source-structure|CI green|Agent version|Allowed verdict vocabulary|Previous ID|RES ID|Bound" .github\agents README.md docs
```

2. Agent vocabulary checks

```powershell
rg -n "CROSS_SLICE_VERIFIED|BLOCKED_BY_PARENT_ACCEPTANCE_GAP|BLOCKED_BY_CROSS_SLICE_CONTRACT_MISMATCH|READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS|NEEDS_HUMAN_RESIDUAL_DECISION" .github\agents README.md docs
```

3. Package path check

```powershell
rg -n "cross-slice-verification-kernel|residual-decision-gate" apm-packages README.md .github\agents docs
```

4. C# build is not required unless `scripts/*.cs` changes.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Agent output structure becomes too heavy | Keep new tables required only for cross-slice / rerun / residual contexts, not for ordinary single-slice verification |
| `Bound` becomes impossible for all docs-only cases | Allow exact source proof for producer and consumer state transition, but require it to trace required postcondition directly |
| README duplicates too much agent text | README should describe operator-facing rules; detailed table schemas remain in agent and docs |
| Existing package references drift | Do not rename agent files; keep `apm.yml` paths stable |

## Done definition for implementation PR

- Issue #28 acceptance mapping is covered by changed docs / agent prompts.
- `git diff --check` passes.
- grep validation shows the new vocabulary in `.github/agents`, README, and authoring docs.
- No unrelated generated files or package ownership changes are introduced.
- Remaining manual or unverified items are separated in the final report.
