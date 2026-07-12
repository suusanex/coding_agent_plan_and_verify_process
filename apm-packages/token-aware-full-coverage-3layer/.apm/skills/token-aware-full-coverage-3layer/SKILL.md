---
name: token-aware-full-coverage-3layer
description: Plan網羅チェック・残件判定フローで full-coverage 診断後、Architecture Slice Readiness Gateを通過したdecompositionをCodexの親エージェント・slice-prep・slice-implの3層運用で安全に進めるためのskill。
---

# Plan網羅チェック full-coverage 3層運用 Skill

<!--
Copyright (c) 2026 suusanex (GitHub UserName)
SPDX-License-Identifier: CC-BY-4.0
License: https://creativecommons.org/licenses/by/4.0/
Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
-->

## 目的

この skill は、Plan網羅チェック・残件判定フローで `ReadyForRiskTriage` の Plan に対して `change-risk-triage.agent.md` が `full-coverage` を診断し、Architecture Slice Readiness Gateが`ReadyForSliceDecomposition`または`ArchitectureNotRequired`を返した後に使います。

`token-aware-full-coverage-3layer` という skill 名と `$token-aware-full-coverage-3layer` の起動例は互換用の legacy invocation です。新しい作業では本文の概念を Plan網羅チェック・残件判定フロー、Guardrail Focus、Residual Decision Gate として扱ってください。

目的は、広い parent Plan を bounded な slice 実行に戻しつつ、slice 間の runtime contract、field continuity、production wiring、parent acceptance condition を失わないことです。

この skill は「全部をサブエージェントに丸投げする」ためのものではありません。親エージェントが設計整合を握り、サブエージェントには bounded な準備・実装・検証だけを任せます。

この package は Plan網羅チェック・残件判定フローの kernel agents を前提にします。APM manifest では `token-aware-guardrail-kernel-flow` と同じ shared instruction / kernel agent paths を dependency として含めます。手動で一部だけコピーする場合も、`plan-kernel`、`black-box-behavior-spec-kernel`、`change-risk-triage`、`implementation-contract-kernel`、`implementation-handoff-review`、`verification-kernel`、`cross-slice-verification-kernel`、`residual-decision-gate` などの Plan Coverage kernel agents を同時に利用可能にしてください。

## 発動条件

次のいずれかに当てはまる場合に使ってください。

- `change-risk-triage.agent.md` が `full-coverage` を推奨した
- `plan-slice-decomposition.agent.md` の出力を Codex で実行したい
- full-coverage decomposition 由来の slice を、並列化しつつ安全に進めたい
- cross-slice contract (`XC-xxx`) を含む Plan網羅チェック・残件判定フローを進めたい

次の場合は使いません。

- 1つの bounded Plan を通常の Plan網羅チェック・残件判定フローで進めれば足りる
- `fix-slice` だけの小さな既知 gap 修正である
- Full autonomous Plan-first flow を明示的に選んでいる
- Plan readiness が `NeedsPlanBehaviorExpansion` または `NeedsHumanDecision` であり、behavior spec / Case-to-Plan mapping / product semantics が未解決である
- 人間が各 artifact を手作業で作成し、Codex には単発実装だけを依頼する

## 必須入力

親エージェントは、少なくとも次を source artifact として読む必要があります。

- parent bounded Plan
- Black-box Behavior Spec artifact（Behavior spec artifact required: Yes の場合）
- parent Plan の inline behavior sketch または Black-box behavior coverage / Case-to-Plan mapping
- parent `change-risk-triage.agent.md` の出力
- `plans/<ticket-or-slug>-architecture-slice-readiness.md`
- verdictが`ReadyForSliceDecomposition`の場合は`plans/<ticket-or-slug>-slice-architecture.md`
- verdictが`ArchitectureNotRequired`の場合はreadiness artifact内のLightweight architecture baseline。readiness artifact自身をbaseline authorityとする
- `plans/<ticket-or-slug>-slice-decomposition.md`
- 各 executable slice artifact: `plans/<ticket-or-slug>-slice-SL-xxx.md`
- 既存の関連 docs / architecture docs / domain docs（必要な範囲のみ）

repository 全体を無差別に読んではいけません。必要な artifact と関係ファイルに限定してください。

## 3層運用の全体像

```text
Layer 1: 親エージェント
  parent Plan / triage / slice decomposition を読み、
  slice 実行表・依存関係・parallel 可否・parent review gate を管理する。

Layer 2: slice-prep subagent
  slice artifact を bounded Plan として扱い、
  per-slice risk / contract / test design artifact を下書きする。
  ここでは実装しない。

Layer 3: slice-impl subagent
  親が READY と判定した slice だけを実装し、
  slice-local verification-kernel まで進めて停止する。

Final gate: 親エージェント
  全 slice の verification 結果を集約し、
  cross-slice-verification-kernel と residual-decision-gate を実行する。
```

## ExecutionMode と delegation invariant

親エージェントは開始時に `plans/<ticket-or-slug>-agent-usage-ledger.md` を作成または更新し、次のいずれかの `ExecutionMode` を必ず記録してください。

### Default ExecutionMode

ユーザーが「実施」「進める」「このプロセスで実装する」「複数 slice を進める」と依頼し、かつ「実装はまだ行わない」「準備まで」「レビューまでで停止」と明示していない場合、`ExecutionMode` は `DELEGATED_IMPLEMENTATION` とします。

`PREP_ONLY` は、ユーザーが明示的に準備・レビューまでで停止すると指定した場合だけ選んでください。未指定時に安全側として `PREP_ONLY` へ倒してはいけません。

| ExecutionMode | 意味 | production code / tests 編集 |
| --- | --- | --- |
| `PREP_ONLY` | slice-prep と parent review gate までで停止する | 禁止 |
| `DELEGATED_IMPLEMENTATION` | READY slice を `slice-impl` に委譲して実装する | 親は禁止、`slice-impl` のみ可 |
| `PARENT_DIRECT_IMPLEMENTATION` | 例外的に親が直接実装する | 明示理由とユーザー承認が必要。3層委譲成功とは扱わない |

`DELEGATED_IMPLEMENTATION` では、親エージェントは production code / tests を直接編集してはいけません。親が直接編集してよいのは、原則として orchestration / review / usage ledger / final summary / handoff artifact だけです。

親が直接編集できる artifact の例:

- `plans/*-slice-execution-table.md`
- `plans/*-parent-orchestration-state.md`
- `plans/*-parent-review-gate.md`
- `plans/*-cross-slice-verification-kernel.md`
- `plans/*-residual-decision-gate.md`
- `plans/*-agent-usage-ledger.md`
- final summary / handoff artifact

委譲が必要な工程で custom agent / subagent を起動できない場合、親はその工程を自分で続行せず、`DelegationUnavailable` または `BlockedByMissingSliceImplDelegation` として停止してください。親直接実装は `PARENT_DIRECT_IMPLEMENTATION` と explicit human approval がある場合だけ許可されます。

`DELEGATED_IMPLEMENTATION` mode の成功完了には、すべての executable slice が `slice-prep` を通過している、または `BLOCKED` / `NEEDS_HUMAN_DECISION` / `TRIAGE_ONLY` として記録されていることが必要です。さらに、parent review gate、すべての READY slice の `slice-impl` 委譲、各 slice の `Slice Implementation Result`、slice-local verification-kernel、親による cross-slice-verification-kernel、residual-decision-gate まで完了していなければ、成功完了として報告してはいけません。

## Parent Orchestration State

親エージェントは `plans/<ticket-or-slug>-parent-orchestration-state.md` を作成または更新し、後続の親エージェントが会話履歴なしで再開できる single resume entrypoint として扱ってください。標準 template は `apm-packages/token-aware-full-coverage-3layer/.apm/templates/full-coverage-parent-orchestration-state.md` です。`provision-work-repo-agents.cs` を使う consuming repo では `plans/_templates/full-coverage-parent-orchestration-state.md` にも配置されます。template file が見つからない場合でも、この section に列挙された required sections で state artifact を作成してください。

この artifact は会話ログの再現ではなく、再開に必要な索引と差分だけを持ちます。parent Plan、slice artifact、triage、contract、verification result の本文をコピーしてはいけません。subagent output の全文、長い reasoning trace、append-only の長大な履歴ログも標準 artifact には入れません。source excerpt は原則禁止し、必要な場合だけ短い pointer に抑えてください。原則として path / status / next action / blocking reason を中心にしてください。file が大きくなりすぎた場合は、完了済み slice 行を短い summary に圧縮し、詳細は元の slice artifact に残します。

Parent Orchestration State は次を記録します。

- 現在の phase / gate
- 最後に完了した checkpoint
- 次に実行すべき action
- 最新 source artifact の path と status
- slice ごとの pending-prep / prep-ready / blocked / ready-for-impl / impl-running / impl-done / verification-done / stale
- cross-slice contract / field continuity / production wiring / Behavior Case の未検証項目
- 親が下した判断、その evidence、保留中の判断
- stop reason と resume safety

Parent Orchestration State の required sections は次です。

- `Resume header`
- `Artifact index`
- `Slice queue`
- `Cross-slice blockers`
- `Pending parent decisions`
- `Parent decisions made`
- `Recent checkpoint delta`
- `Emergency checkpoint`

MUST update:

- full-coverage 3層運用の開始時
- ExecutionMode 決定時
- slice-prep の batch を開始する前
- slice-prep の batch 結果を親が統合した後
- parent review gate を出した後
- slice-impl の batch を開始する前
- slice-impl の batch 結果を親が統合した後
- cross-slice verification の前後
- residual decision gate の後
- planned handoff / tool switch / model switch の前
- token limit や tool failure が近い場合の emergency checkpoint

SHOULD NOT update:

- every turn / every minor reasoning step
- source artifact や subagent output の全文転記
- 表記揺れだけの修正
- 完了済み情報の長い再要約

token limit や tool failure が近い場合は、完全更新ではなく `Emergency checkpoint` の最小更新を許可します。`Emergency checkpoint` には minimal next action、avoid repeating、must read before continuing、known blocker だけを残してください。

後続の親エージェントは、再開時に次の順で確認してください。

1. 現在の ticket / slug / branch / work item / PR と一致する `plans/<ticket-or-slug>-parent-orchestration-state.md` を選ぶ。
2. 複数の `plans/*-parent-orchestration-state.md` が見つかる場合は、各 file の `Resume header` だけを読み、`Work item / ticket`、`Repo / branch`、明示された slug が現在の作業と一致するものを1つに絞る。
3. 一意に絞れない場合、または候補が現在の branch / work item と矛盾する場合は fail closed し、ユーザーに対象 state を確認する。別 ticket の state を推測で読んではいけません。
4. 選んだ state の `Resume header` の `Current phase`、`Next required action`、`Resume safety` を確認する。
5. `Artifact index` に載っている source artifact だけを読む。missing / stale / contradicted の場合だけ追加調査する。`contradicted` は現在 branch、work item、slice queue、またはより新しい listed artifact と矛盾している状態です。
6. `Slice queue` を見て、完了済み slice を不用意に再実行しない。
7. `Parent decisions made`、`Cross-slice blockers`、`Pending parent decisions` を確認し、既決の authorization / blocking decision を見落としたり、親判断が必要な gate を飛ばしたりしない。
8. `Agent Usage Ledger` と照合し、delegation evidence missing を成功扱いしない。
9. 作業を再開する前に、state artifact の `Recent checkpoint delta` を更新する。

When switching parent tools or sessions, do not rely on prior conversation context. The next parent agent must select the matching `plans/<ticket-or-slug>-parent-orchestration-state.md`, treat that selected state as the resume entrypoint, then verify Agent Usage Ledger and listed artifacts before continuing.

## Layer 1: 親エージェント orchestration

親エージェントは最初に、`plan-slice-decomposition` の出力を実装指示ではなく「slice 実行候補」として扱ってください。

readiness verdictが`NeedsArchitectureElaboration`または`NeedsHumanDecision`、blocking architecture residualが残る、tracked source / watch path freshness checkが失敗する、required baseline authorityがmissing / stale / contradictedのいずれかなら、このskillを開始せずArchitecture Slice Readiness Gateへ戻してください。HEAD一致もpath一致も単独のfreshness条件にしてはいけません。

親エージェントは次を行います。

1. parent Plan の goal / non-goals / functional requirements / acceptance conditions を確認する。
2. parent triage の high-risk boundaries / parent-level runtime contract candidates / implementation-realization risk summaryを確認する。
3. Architecture Slice Readiness verdictと、存在する場合はslice architecture baselineを確認する。
   - `ReadyForSliceDecomposition`: currentなslice architecture artifactがbaseline authority。
   - `ArchitectureNotRequired`: currentなreadiness artifactのLightweight architecture baselineがbaseline authority。
4. slice decomposition artifactから、各sliceのscope / non-goals / dependencies / related XC IDs / architecture traceability / recommended profileを抽出する。
5. `Slice granularity review` と `Small slice justification` を抽出する。
6. `Cross-slice Contracts` と `Cross-slice field continuity` を抽出する。
7. parent-level contract mappingとBehavior Case mappingが消えていないか確認する。
8. candidate disposition対象をexecutable sliceから除外する。
9. slice実行表を作り、architecture ownershipとshared resourceを考慮して並列可否を決める。

### Slice 実行表の形式

親エージェントは、最初に次の表を作成してください。

```md
| Slice ID | Goal | Recommended profile | Blocking dependency | Shared ownership risk | Related XC IDs | Delegation required | Prep agent | Implementation allowed now? | Edit owner | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
```

`Implementation allowed now?` は初期状態では原則 `No` です。`plan-slice-decomposition` の出力だけで `Yes` にしてはいけません。

## Layer 2: slice preparation

親エージェントは、executable な slice ごとに `slice-prep` custom agent へ MUST delegate してください。

`merge-candidate`、`too-small-to-delegate`、`coalesce-with-SL-xxx` と記録された候補は executable slice ではありません。これらは slice 実行表に理由を残してよいですが、`slice-prep` へ委譲してはいけません。

executable slice は、次のいずれかを満たす必要があります。

- `slice-prep` run が存在する。
- parent review gate が `BLOCKED` / `NEEDS_HUMAN_DECISION` / `TRIAGE_ONLY` として実装対象外にした。
- `PARENT_PREP_EXCEPTION` が agent usage ledger に明示されている。

`slice-prep` に渡す入力は、少なくとも次です。

- parent Plan
- Black-box Behavior Spec artifact（Behavior spec artifact required: Yes の場合）
- Expansion required: Yes でも inline behavior sketch sufficient の場合は、parent Plan / slice artifact 内の Inline behavior sketch と Case mapping
- parent triage output
- Architecture Slice Readiness artifact
- `ReadyForSliceDecomposition`の場合はslice architecture artifactとassigned sliceに関係するarchitecture excerpt
- `ArchitectureNotRequired`の場合はreadiness artifact内のLightweight architecture baseline
- parent slice decomposition artifact
- assigned slice artifact
- assigned slice の Black-box behavior coverage / Case-to-Slice mapping
- assigned slice に関係する cross-slice contract excerpt
- assigned slice に関係する field continuity items
- この pass での bounded parent Plan pass / Guardrail Focus coverage / non-goals / stop condition

`slice-prep` は次を行います。

1. assigned slice artifact を bounded Plan として扱う。
2. assigned slice の Case-to-Slice mapping を確認し、Case IDs が slice-local / cross-slice verification / explicit disposition のどこへ行くかを記録する。
3. per-slice `change-risk-triage` を実行する。
4. implementation-realization risk が `Present` または `Unclear` の場合、per-slice `implementation-contract-kernel` を下書きする。
5. implementation-contract-kernel の `Self-check / Readiness verdict` を記録する。`implementation-contract-review-kernel` は、self-check verdict に対する独立 review が明示的に必要な場合だけ explicit review-only fallback として扱い、通常の non-trivial 判断だけを理由に作成しない。
6. selected slice-local RC IDs について `runtime-contract-kernel` を下書きする。
7. `test-design-kernel` を下書きし、selected slice に関係する Behavior Case IDs を test / manual / cross-slice route へ接続する。
8. 実装は行わない。
9. cross-slice contract を slice 内で完了扱いにしない。
10. Behavior Case ID を slice 内で消したり、unmapped のまま READY にしない。
11. 最後に `READY_FOR_PARENT_REVIEW`、`BLOCKED`、`NEEDS_HUMAN_DECISION` のいずれかを返す。

### slice-prep の出力形式

`slice-prep` は、親エージェントに次の形式で返してください。

```md
# Slice Preparation Result: SL-xxx

## Verdict

- Status: READY_FOR_PARENT_REVIEW / BLOCKED / NEEDS_HUMAN_DECISION
- Reason:

## Agent metadata

- Agent type: slice-prep
- Configured model:
- Configured reasoning effort:
- Hook model:
- Effective model: unknown unless independently verified
- Parent authorization artifact:
- Delegation evidence:

## Generated / drafted artifacts

- Per-slice change-risk-triage:
- Implementation-contract-kernel:
- Implementation-contract-review-kernel:
- Runtime-contract-kernel:
- Test-design-kernel:

## Bounded parent Plan pass / Guardrail Focus

## Behavior Case mapping

| Case ID | Parent FR / AC | Slice FR / AC | Route | Status | Notes |
| --- | --- | --- | --- | --- | --- |

## Non-goals

## RC / TP / XC ledger

| ID | Kind | Owned / Consumed / Deferred | Notes |
| --- | --- | --- | --- |

## Production binding requirements

## Cross-slice risks to parent-review

## Unresolved items

## Stop condition
```

## Parent review gate

親エージェントは、すべての slice-prep 出力を実装前にレビューします。

Parent review gate は人間レビュー待ちではありません。親エージェントが source artifact と slice-prep 出力をもとに、機械的に実装可否を判定する gate です。

親レビューでは次を確認してください。

- parent Plan の FR / AC が slice 群で保持されているか
- slice ごとの per-slice triage が parent triage と矛盾していないか
- implementation-realization risk が `Present` / `Unclear` なのに implementation-contract branch が省略されていないか
- runtime-contract-kernel と test-design-kernel が Plan の代替として扱われていないか
- `XC-xxx` の producer / consumer / required fields / mechanism が一致しているか
- field continuity の source artifact / producer output / consumer requirement が traceable か
- Behavior Case IDs が slice / cross-slice verification / explicit disposition のどこへ行ったか traceable か
- `Slice granularity review` が存在し、小さすぎる slice が統合済みまたは明示的に正当化されているか
- 小さい slice の `Small slice justification` に `Why not merged` があり、独立 verification / rollback / owner-profile / blocker / producer-consumer 境界のいずれかが成立しているか
- `merge-candidate`、`too-small-to-delegate`、`coalesce-with-SL-xxx` が実装 authorization に混入していないか
- shared DTO / DB schema / DI / config / public API / migration / durable state の ownership が重複していないか
- parallel implementation してよい slice と、直列化すべき slice が分かれているか
- source evidence のない fabricated value が `Done` 扱いされていないか
- production binding requirement が test-only stub / fake で代替されていないか
- state owner、source precedence、identity、temporal sequence、retry / release、capacity、schema、production wiringがselected baseline authorityからdriftしていないか
- slice-prepがshared semanticsの変更を提案していないか。提案している場合は`Can implement now? = No`としてArchitecture Slice Readiness Gateへ戻す
- tracked sourceのrevision/content hashが一致し、`source_repository_commit...current HEAD`のdiffがwatch pathへ影響しないか。artifact追加だけのHEAD変更はself-invalidationさせない

親レビューの出力は次の形式にしてください。

```md
# Parent Review Gate

## Verdict per slice

| Slice ID | Verdict | Can implement now? | Parallel group | Blocking reason |
| --- | --- | --- | --- | --- |

## Cross-slice contract review

| XC ID | Producer | Consumer | Status | Notes |
| --- | --- | --- | --- | --- |

## Field continuity review

| Field / state / identifier | Required by | Source / producer | Consumer | Status | Notes |
| --- | --- | --- | --- | --- | --- |

## Architecture drift review

| Slice ID | Readiness verdict | Baseline authority | Baseline identity | Observed semantics | Match / Drift / Unclear | Required action |
| --- | --- | --- | --- | --- | --- | --- |

`ArchitectureNotRequired`でもdrift reviewを省略しません。readiness artifactのLightweight architecture baselineに対し、新しいshared semanticsが導入されていなければ`Match`、導入されていれば`Drift`、証明不足またはbaseline freshness不明なら`Unclear`です。slice-impl authorizationはcurrent baselineに対する`Match`だけを許可します。

## Implementation authorization

- Authorized slices:
- Serialized slices:
- Blocked slices:
- Human decision required:

## Parent instructions for slice-impl
```

`Can implement now?` が `No` の slice を `slice-impl` に渡してはいけません。

`DELEGATED_IMPLEMENTATION` mode では、`Can implement now? = Yes` の slice が1つでも存在する場合、親エージェントは parent review gate で成功終了してはいけません。`Human decision required` / `NEEDS_HUMAN_DECISION` の slice は停止対象として記録しつつ、実装可能な READY slice は必ず `slice-impl` custom agent へ委譲してください。

停止できるのは、すべての slice が `Can implement now? = No` / `BLOCKED` / `NEEDS_HUMAN_DECISION` / `TRIAGE_ONLY` のいずれかであり、委譲可能な READY slice が存在しない場合、または custom agent / subagent 起動が利用できず `BlockedByMissingSliceImplDelegation` として記録した場合に限ります。

## Layer 3: implementation and verification

`DELEGATED_IMPLEMENTATION` mode では、親レビューで `Can implement now? = Yes` になった slice は必ず `slice-impl` custom agent に渡してください。親は READY slice を自分で実装してはいけません。

READY slice は、次の証跡を満たす必要があります。

- `slice-impl` run が存在する。
- `slice-impl` output が `Slice Implementation Result: SL-xxx` を持つ。
- `Agent type: slice-impl` / `Configured model` / `Configured reasoning effort` / `Hook model` / `Effective model` / `Parent authorization artifact` が記録されている。
- `Changed files` / `Checks run` / `Verification verdict` が記録されている。

これを満たさない場合、親は `BlockedByMissingSliceImplDelegation` として停止し、成功扱いしてはいけません。

`slice-impl` に渡す入力は、少なくとも次です。

- parent Plan
- Black-box Behavior Spec artifact（Behavior spec artifact required: Yes の場合）
- Expansion required: Yes でも inline behavior sketch sufficient の場合は、parent Plan / slice artifact 内の Inline behavior sketch と Case-to-Slice mapping
- parent triage output
- Architecture Slice Readiness artifact
- `ReadyForSliceDecomposition`の場合はslice architecture artifact
- `ArchitectureNotRequired`の場合はreadiness artifact内のLightweight architecture baseline
- parent slice decomposition artifact
- assigned slice artifact
- assigned slice の Black-box behavior coverage / Case-to-Slice mapping
- per-slice change-risk-triage
- per-slice implementation-contract-kernel（必要な場合）
- per-slice implementation-contract-review-kernel（explicit review-only fallback が存在する場合）
- per-slice runtime-contract-kernel
- per-slice test-design-kernel
- implementation-handoff-review または Inline Ready Gate equivalent の Behavior Case Coverage Ledger / Case mapping（Behavior spec artifact required: Yes の場合、または inline sketch の Case IDs を実装条件として扱う場合）
- parent review gate の implementation authorization
- bounded parent Plan pass / Guardrail Focus coverage / non-goals / stop condition

`slice-impl` は次を行います。

1. `implementation-handoff-review` を実行する。
2. READY でない場合は実装せず停止する。
3. `Behavior spec artifact required: Yes` の場合は Black-box Behavior Spec、Case-to-Slice mapping、Behavior Case Coverage Ledger が complete であることを確認する。`Expansion required: Yes` でも inline behavior sketch sufficient の場合は、parent Plan / slice artifact 内の Inline behavior sketch、Case-to-Slice mapping、Inline Ready Gate equivalent の coverage disposition を確認する。必要な behavior evidence が欠落・不完全・`UnmappedBlocking`・実装前 `NeedsHumanDecision` を含む場合は実装せず停止する。
4. 親が承認した assigned slice-local bounded parent Plan pass を実装する。Guardrail Focus artifacts は deep-check guardrail として扱い、implementation scope として扱わない。Behavior Case IDs と negative expectations は実装条件として扱う。
5. 無関係な refactoring や redesign を行わない。
6. required checks を実行する。実行できない check は理由を明記する。
7. slice-local `verification-kernel` を実行し、Behavior Case Evidence Ledger が current Case IDs を扱っているか確認する。
8. slice-local verification-kernel の verdict（例: `PARENT_PLAN_VERIFIED`、`PARENT_PLAN_NEEDS_RESIDUAL_DECISION`、`PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES`、`BLOCKED_*`）と Remaining Work / residual candidates を出力して停止する。

`slice-impl` は次を行ってはいけません。

- parent review gate が承認した bounded parent Plan pass を広げる
- cross-slice-verification-kernel を実行する
- `XC-xxx` を単独で完了扱いにする
- Behavior Case ID、negative expectation、Case-to-Slice mapping を読まずに実装する
- gap を見つけた場で coverage-gap-resolution へ進む
- さらに subagent を起動する

### slice-impl の出力形式

```md
# Slice Implementation Result: SL-xxx

## Verdict

- Status: PARENT_PLAN_VERIFIED / PARENT_PLAN_NEEDS_RESIDUAL_DECISION / PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES / BLOCKED_*
- Reason:

## Agent metadata

- Agent type: slice-impl
- Configured model:
- Configured reasoning effort:
- Hook model:
- Effective model: unknown unless independently verified
- Parent authorization artifact:
- Delegation evidence:

## Changed files

## Covered IDs

| ID | Kind | Status | Notes |
| --- | --- | --- | --- |

## Behavior Case Coverage

| Case ID | Expected behavior / negative expectation | Implemented by | Verification route | Status | Notes |
| --- | --- | --- | --- | --- | --- |

## Checks run

## Checks not run

## Production binding evidence

## Remaining Work

## Handoff to parent
```

## Agent Usage Ledger

親エージェントは `plans/<ticket-or-slug>-agent-usage-ledger.md` を必須成果物として作成・更新してください。

`Agent Usage Ledger` と `Parent Orchestration State` は責務を分けます。`Agent Usage Ledger` は expected / observed delegation、model metadata、edit owner、changed files、checks run、delegation compliance を記録します。`Parent Orchestration State` は親 orchestration の現在地、次 action、artifact index、slice queue、blocking decision を記録します。両者の内容を重複させず、必要な場合は path で相互参照してください。

```md
# Agent Usage Ledger

## Execution mode

- Mode: PREP_ONLY / DELEGATED_IMPLEMENTATION / PARENT_DIRECT_IMPLEMENTATION
- Parent configured model:
- Parent direct code edit allowed: Yes / No
- Reason if exception:
- Explicit human approval if exception:

## Expected delegation

| Phase | Slice | Delegation required | Expected agent type | Configured model | Edit owner | Parallel group |
| --- | --- | --- | --- | --- | --- | --- |

## Observed agent runs

| Run ID | Agent type | Slice | Configured model | Hook model | Effective model | ExecutionMode | DelegationRequired | EditOwner | DelegationViolation | Phase | Outcome | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Delegation compliance

| Rule | Status | Evidence |
| --- | --- | --- |
| All executable slices passed slice-prep or were blocked | PASS / FAIL | |
| All READY slices were implemented by slice-impl | PASS / FAIL | |
| Parent did not edit production code/tests | PASS / FAIL | |
| Cross-slice verification was run by parent | PASS / FAIL | |
```

## Final gate: cross-slice-verification-kernel and residual-decision-gate

すべての実装対象 slice の verification-kernel 結果が出そろった後、親エージェントは `cross-slice-verification-kernel.agent.md` を実行し、その後に unresolved items を `residual-decision-gate.agent.md` へ渡します。

確認対象は次です。

- parent Plan
- parent triage output
- Architecture Slice Readiness artifact
- slice architecture artifact（`ArchitectureNotRequired`以外）
- slice decomposition artifact
- 各 slice artifact
- 各 slice-prep artifact
- 各 slice-impl result
- 各 verification-kernel result
- Black-box Behavior Spec artifact と Behavior Case mapping（Behavior spec artifact required: Yes の場合）、または Inline behavior sketch と Case mapping（inline behavior sketch sufficient の場合）

cross-slice verification では次を確認してください。

- parent acceptance conditions が slice 分割後も満たされているか
- `XC-xxx` の producer / consumer / mechanism / required fields / state / identifiers が一致しているか
- field continuity が upstream source から downstream consumer まで traceable か
- production wiring / entrypoint / DI / config / migration / persistence が slice 間でつながっているか
- stub-only success や production binding gap が残っていないか
- Remaining Work が parent PASS を妨げるものかどうか分類されているか
- Behavior Case IDs と negative expectations が slice-local verification または cross-slice verification evidence へ接続されているか
- implementation後のshared semanticsがapproved slice architectureと一致し、driftが新しいexpected behaviorとしてfixture化されていないか

cross-slice verification では、見つけた gap をその場で修正しません。必要なら `coverage-gap-triage.agent.md` に渡すための handoff を作成し、residual candidate は `residual-decision-gate.agent.md` で explicit human decision の有無を判定して停止します。

## 並列化ルール

並列化してよいのは、次を満たす場合だけです。

- parent review gate が `Can implement now? = Yes` と判定している
- shared ownership risk が低い
- 同じ production wiring / public API / schema / migration / durable state を編集しない
- producer slice の output が consumer slice の実装前提になっていない
- `XC-xxx` に unresolved field / state / identifier が残っていない
- relevant Behavior Case ID が unmapped のまま残っていない
- 失敗時に単独で rollback / discard できる

次の場合は直列化してください。

- 同じ files / modules / schema / public API を触る
- producer / consumer の片方だけを実装すると false PASS になり得る
- `NeedsHumanDecision` / `Deferred` が downstream behavior に影響する
- implementation-realization risk の解消結果で downstream design が変わる
- migration / state transition / retry / recovery semantics が絡む

## Codex への短い指示例

標準の委譲実装として進める場合:

```text
$token-aware-full-coverage-3layer を使って進めてください。
ExecutionMode は DELEGATED_IMPLEMENTATION とします。

parent review gate で READY になった slice は、そこで停止せず必ず slice-impl に渡してください。
各 slice の verification-kernel 後に cross-slice-verification-kernel と residual-decision-gate まで実行してください。

人間判断が必要な slice だけ NEEDS_HUMAN_DECISION として止め、実装可能な slice は進めてください。
```

準備までで止める場合:

```text
$token-aware-full-coverage-3layer を使って、この full-coverage decomposition を Plan網羅チェック・残件判定フローとして進めてください。
ExecutionMode は PREP_ONLY とします。
slice-prep で各 slice の準備 artifact を作り、parent review gate までで停止してください。
実装はまだ行わないでください。
```

## 最終監査

親エージェントは完了前に次を確認してください。

- ExecutionMode が `Agent Usage Ledger` に記録されている
- `Parent Orchestration State` が作成・更新され、Current phase / Next required action / Resume safety / Slice queue が再開可能な状態になっている
- `DELEGATED_IMPLEMENTATION` の場合、親が production code / tests を直接編集していない
- `plan-slice-decomposition` から直接実装していない
- Architecture Slice Readiness Gateを通過し、required architecture artifactがcurrentである
- slice-prepまたはslice-implのarchitecture driftをparent reviewで見逃していない
- slice-prep と parent review gate を通している
- READY でない slice を実装していない
- `Can implement now? = Yes` の slice はすべて `slice-impl` に渡されている
- `slice-impl` run が存在しない READY slice は `BlockedByMissingSliceImplDelegation` として停止している
- `Agent Usage Ledger` が作成・更新され、`DelegationCompliance` が PASS / FAIL / EXCEPTION_ACCEPTED で判定されている
- `PARENT_DIRECT_IMPLEMENTATION` は明示理由とユーザー承認がある場合だけ使われ、3層委譲成功としてカウントされていない
- cross-slice contract を slice 内で完了扱いにしていない
- Behavior Case ID を slice 内で消したり、unmapped のまま READY / PASS にしていない
- verification-kernel で gap 修正に進んでいない
- cross-slice-verification-kernel と residual-decision-gate を最後に実行している、または未実行理由を明示している
