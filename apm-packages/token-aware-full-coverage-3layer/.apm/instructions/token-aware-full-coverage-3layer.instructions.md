---
description: Codex project guidance for Plan網羅チェック・残件判定フロー when full-coverage decomposition requires three-layer slice orchestration.
---

## Codex 向けプロジェクト指示

この repository は、coding agent に Plan-first / verification-first の作業プロセスを渡すための agent / skill / documentation を管理します。

GitHub Copilot 向けの `.github/agents/*.agent.md` が既存の主成果物です。Codex で作業する場合も、既存の Plan網羅チェック・残件判定フロー の用語・責務・artifact chain を source of truth として扱ってください。

## Plan網羅チェック・残件判定フロー の扱い

`change-risk-triage.agent.md` が `ReadyForRiskTriage` の Plan に対して `full-coverage` を診断した場合、Codex は `plan-slice-decomposition.agent.md` の出力から直接実装に入ってはいけません。

`full-coverage` は多数の executable slice が必要という意味ではありません。`plan-slice-decomposition.agent.md` の `Slice granularity review` と `Small slice justification` を読み、cross-slice contract、field continuity、Behavior Case mapping を保持できる少数 slice は正しい decomposition として扱ってください。

`merge-candidate`、`too-small-to-delegate`、`coalesce-with-SL-xxx` と記録された候補は executable slice ではありません。親エージェントはこれらを `slice-prep` に渡さず、統合または除外理由を Agent Usage Ledger / parent review gate に残してください。

Plan readiness が `NeedsPlanBehaviorExpansion` または `NeedsHumanDecision` の場合、この skill は使いません。要求展開不足、Case-to-Plan mapping 不足、期待動作の未決は full-coverage ではなく Plan フェーズへ戻します。

その場合は、原則として `$token-aware-full-coverage-3layer` skill を使ってください。この skill 名は互換用の legacy invocation です。本文では Plan網羅チェック・残件判定フローとして扱います。

この skill は、次の3層で進めます。

1. 親エージェントによる orchestration と parent review gate
2. slice-prep subagent による slice 単位の kernel artifact 下書き
3. slice-impl subagent による親承認済み slice-local bounded parent Plan pass の実装と verification-kernel
4. 親エージェントによる cross-slice-verification-kernel と residual-decision-gate

開始時に `ExecutionMode` を `PREP_ONLY` / `DELEGATED_IMPLEMENTATION` / `PARENT_DIRECT_IMPLEMENTATION` のいずれかとして `plans/*-agent-usage-ledger.md` に記録してください。

同時に、親エージェントは `plans/<ticket-or-slug>-parent-orchestration-state.md` を作成または更新してください。これは会話履歴を共有しない後続の親エージェントが最初に読む single resume entrypoint です。標準 template は `apm-packages/token-aware-full-coverage-3layer/.apm/templates/full-coverage-parent-orchestration-state.md` にあります。`setup-work-repo-agents.cs` を使う consuming repo では `plans/_templates/full-coverage-parent-orchestration-state.md` にも配置されます。template file が見つからない場合でも、Resume header、Artifact index、Slice queue、Cross-slice blockers、Pending parent decisions、Parent decisions made、Recent checkpoint delta、Emergency checkpoint を持つ state artifact を作成してください。

Parent Orchestration State には、Current phase、Last completed checkpoint、Next required action、Stop reason、Resume safety、Artifact index、Slice queue、Cross-slice blockers、Pending parent decisions、Parent decisions made、Recent checkpoint delta、Emergency checkpoint を compact に記録します。parent Plan、slice artifact、subagent output、verification result の本文を貼らず、path / status / next action / blocking reason を中心にしてください。source excerpt は原則禁止し、必要な場合だけ短い pointer に抑えます。file が大きくなりすぎた場合は、完了済み slice 行を短い summary に圧縮し、詳細は元の slice artifact に残してください。

Parent Orchestration State は次の major checkpoint と delegation boundary で更新してください。

- full-coverage 3層運用の開始時
- ExecutionMode 決定時
- slice-prep batch の開始前と結果統合後
- parent review gate 後
- slice-impl batch の開始前と結果統合後
- cross-slice verification の前後
- residual decision gate 後
- planned handoff / tool switch / model switch の前
- token limit や tool failure が近い場合の `Emergency checkpoint`

every turn、minor reasoning step、表記揺れだけの修正、source artifact / subagent output の全文転記では更新しないでください。token limit が近い場合は完全更新ではなく `Emergency checkpoint` の最小更新だけでよいです。

ユーザーが「実施」「進める」「このプロセスで実装する」と依頼し、かつ「実装はまだ行わない」「準備まで」「レビューまでで停止」と明示していない場合、既定の `ExecutionMode` は `DELEGATED_IMPLEMENTATION` です。`PREP_ONLY` は明示的な準備・レビュー停止指示がある場合だけ選んでください。

`DELEGATED_IMPLEMENTATION` mode では、親エージェントは production code / tests を直接編集してはいけません。親が編集できるのは orchestration artifact、parent review gate、Agent Usage Ledger、cross-slice verification、residual decision、final summary / handoff artifact に限定します。

Parent review gate は人間レビュー待ちではありません。親エージェントが実装可否を判定する gate です。`DELEGATED_IMPLEMENTATION` mode では、`Can implement now? = Yes` の slice が1つでも存在する場合、親は parent review gate で成功終了してはいけません。`Human decision required` / `NEEDS_HUMAN_DECISION` の slice は停止対象として記録しつつ、実装可能な READY slice は必ず `slice-impl` に委譲してください。

停止できるのは、すべての slice が `Can implement now? = No` / `BLOCKED` / `NEEDS_HUMAN_DECISION` / `TRIAGE_ONLY` のいずれかであり、委譲可能な READY slice が存在しない場合、または custom agent / subagent 起動が利用できず `BlockedByMissingSliceImplDelegation` として記録した場合に限ります。

再開時は、prior conversation context に依存してはいけません。まず現在の ticket / slug / branch / work item / PR と一致する `plans/<ticket-or-slug>-parent-orchestration-state.md` を選びます。複数の `plans/*-parent-orchestration-state.md` が見つかる場合は、各 file の `Resume header` だけを読み、`Work item / ticket`、`Repo / branch`、明示された slug が現在の作業と一致するものを1つに絞ってください。一意に絞れない場合、または候補が現在の branch / work item と矛盾する場合は fail closed し、ユーザーに対象 state を確認してください。別 ticket の state を推測で読んではいけません。

対象 state を選んだ後、`Resume header` の `Current phase`、`Next required action`、`Resume safety` を確認してください。次に `Artifact index` に載っている source artifact だけを優先して読みます。`Artifact index` の `contradicted` は現在 branch、work item、slice queue、またはより新しい listed artifact と矛盾している状態です。`Slice queue` で完了済み slice を確認し、不用意に再実行してはいけません。`Parent decisions made`、`Cross-slice blockers`、`Pending parent decisions` を確認し、既決の authorization / blocking decision を見落としたり、親判断が必要な gate を飛ばしたりしないでください。最後に `Agent Usage Ledger` と照合し、delegation evidence missing を成功扱いしないでください。再開前に `Recent checkpoint delta` を更新します。

`Agent Usage Ledger` は expected / observed delegation、model metadata、edit owner、changed files、checks run、delegation compliance の記録です。`Parent Orchestration State` は現在地、次 action、artifact index、slice queue、blocking decision の記録です。両者を重複させず、必要な場合は path で相互参照してください。

## 重要な禁止事項

- `plan-slice-decomposition` の slice artifact を「実装準備完了」とみなしてはいけません。
- `Parent Orchestration State` に full transcript、source artifact 本文、subagent output 全文、長い reasoning trace を貼ってはいけません。
- Plan readiness が `ReadyForRiskTriage` ではない work を full-coverage decomposition に進めてはいけません。
- `Slice granularity review` で統合対象になった候補を executable slice として扱ってはいけません。
- `Small slice justification` の `Why not merged` が説明されていない小さい slice を `slice-prep` に渡してはいけません。
- per-slice `change-risk-triage`、必要な `implementation-contract-kernel`、`runtime-contract-kernel`、`test-design-kernel` を飛ばしてはいけません。
- executable slice は `slice-prep` に MUST delegate してください。blocked / human decision / triage only の場合は理由を Agent Usage Ledger に記録してください。
- `DELEGATED_IMPLEMENTATION` で READY になった slice は `slice-impl` に MUST delegate してください。`slice-impl` run の証跡がない READY slice は `BlockedByMissingSliceImplDelegation` として停止してください。
- 親直接実装は `PARENT_DIRECT_IMPLEMENTATION`、明示理由、explicit human approval がある場合だけ許可します。これは3層委譲成功として扱いません。
- cross-slice contract (`XC-xxx`) を単一 slice 内で完了扱いにしてはいけません。
- source evidence のない field / state / identifier を fallback、空文字、推測、本文からの生成値で埋めて `Done` にしてはいけません。
- `verification-kernel` や `cross-slice-verification-kernel` で見つけた gap を、その場で scope 拡大して修正してはいけません。必要なら `coverage-gap-triage` に渡してください。

## Codex での典型的な起動例

```text
$token-aware-full-coverage-3layer を使って進めてください。
ExecutionMode は DELEGATED_IMPLEMENTATION とします。

parent review gate で READY になった slice は、そこで停止せず必ず slice-impl に渡してください。
各 slice の verification-kernel 後に cross-slice-verification-kernel と residual-decision-gate まで実行してください。

人間判断が必要な slice だけ NEEDS_HUMAN_DECISION として止め、実装可能な slice は進めてください。
```

準備・レビューまでで止める場合は、依頼文で `ExecutionMode = PREP_ONLY` と明示し、実装はまだ行わないことを指定してください。
