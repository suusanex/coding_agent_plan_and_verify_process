# Codex-first routing branching

Codex-first cost-aware routing は、「軽い作業はシンプルに処理し、重い作業は Plan網羅チェック・残件判定フローへ送る」という二択ではありません。

実際の router は、次の 3 軸を組み合わせて分岐を決めます。

```text
1. task_weight      : 作業の重さ・不確実性・影響範囲の分類
2. selected_process : どのプロセス経路に乗せるか
3. execution_mode   : 親が判断だけするか、委譲して作業するか、止めるか
```

このため、`high-risk-bounded` と判断された作業でも、常に `advanced-full-coverage` に進むわけではありません。仕様が明確で、1 つの bounded implementation pass に収まる場合は、`selected_process: normal` のまま、Plan / risk / implementation contract / implementation handoff review / close gate だけを厚くして進めます。

## task_weight

| task_weight | 典型的な意味 | 通常の扱い |
| --- | --- | --- |
| `trivial-local` | typo、formatting-only、挙動変更なし | `normal` の trivial route または `lower-cost-delegated-scan` |
| `small-bounded` | 1 component、受け入れ条件が明確、local check がある | `normal` |
| `medium-bounded` | 複数 file / tests、source of truth が明確、production risk は管理可能 | `normal` with bounded Plan / risk check / handoff review |
| `high-risk-bounded` | auth / security / DB / public API / production wiring / external SDK / async boundary などがあるが、作業範囲は bounded | `normal` または `higher-model-review`。full coverage とは限らない |
| `needs-plan-behavior-expansion` | source requirements に未展開の behavior cases、negative expectations、recovery / rollback / retry / replay / cleanup、state transitions、または unmapped Case IDs がある | Plan gate へ戻し、`black-box-behavior-spec-kernel` または Plan rerun。full-coverage へ送らない |
| `broad-full-coverage-candidate` | `ReadyForRiskTriage` の Plan が広い、強く相互接続している、複数 runtime sequence、cross-slice contract、または過去の sequence / production-binding gap がある | `advanced-full-coverage` candidate。要求展開不足や期待動作未決には使わない |
| `blocked-human-required` | secret、credential、本番操作、課金、GitHub 設定変更、手動検証 owner など人間判断が必要 | `human-decision-wait` |

`risk` という語は曖昧になりやすいため、運用上は少なくとも次の観点に分けて読むと判断しやすくなります。

```text
scope_breadth              : 作業範囲の広さ
ambiguity                  : 要求や source of truth の曖昧さ
behavior_expansion         : source-to-case expansion と Case-to-Plan mapping の完了度
implementation_complexity  : 実装難度
production_binding_risk    : production 実装 / wiring との接続リスク
external_side_effect_risk  : 外部 API / tenant / billing / destructive operation の副作用リスク
verification_cost          : 完了確認に必要な検証コスト
delegation_suitability     : cheap / standard / high agent へ分けやすいか
```

## selected_process

| selected_process | 役割 | 例 |
| --- | --- | --- |
| `normal` | 標準ルート。軽量な Plan / risk / contract / implementation handoff review を state artifact に残し、handoff authorization 後は実装・検証を serial delegation する | `small-bounded`、`medium-bounded`、bounded な `high-risk-bounded` |
| `lower-cost-delegated-scan` | cheap agent による read-heavy scan、docs consistency、format check を中心にした低コスト経路 | typo 確認、対象 file の探索、docs 整合確認 |
| `higher-model-review` | 実装前に HIGH_MODEL で判断・契約整理を強める経路 | SDK/API が不明、security/auth 境界、public API 変更 |
| `advanced-full-coverage` | Plan網羅チェック・残件判定フロー、または full-coverage 3層運用へ進める高度経路 | 複数 component / runtime sequence / compensation / retry / cross-slice contract |
| `human-decision-wait` | 人間判断が揃うまで実装しない停止経路 | 本番 credential、tenant mutation、plugin trust boundary、billing / GitHub settings |

重要なのは、`selected_process` は「軽量処理か、Plan網羅チェック・残件判定フローか」の二択ではないことです。`normal` の中にも bounded Plan / risk / implementation contract / implementation handoff review / READY / verification / close の gate があり、必要な情報は `plans/<slug>/codex-first-state.md` に残します。

## execution_mode

| execution_mode | 意味 |
| --- | --- |
| `ROUTE_ONLY` | intake / plan / risk / contract / close judgment のみ。production code / tests は編集しない |
| `DELEGATED_WORK` | selected agent / subagent が bounded work を所有し、親は state 更新・ledger・close 判断を担当する |
| `PARENT_DIRECT_WORK` | 親が直接作業する例外経路。理由記録が必要で、cost-saving delegation には数えない |
| `TRIVIAL_PARENT_FIX` | 明示的な低リスク局所修正だけ親が直接行う。これも cost-saving delegation には数えない |

通常の READY implementation は `standard-implementer`、通常 verification は `standard-verifier` へ serial delegation します。write-heavy parallel editing を標準化しないことは、親が直接実装してよいことを意味しません。

通常の READY implementation の前には、`implementation-handoff-review` または明示的に同等の pre-implementation gate が parent authorization artifact を作成します。`Expansion required: Yes` の場合は、`behavior_case_coverage_ledger_status = Complete` になるまで `standard-implementer` へ渡してはいけません。

## 典型的な分岐例

```text
trivial-local
  -> selected_process: lower-cost-delegated-scan または normal trivial route
  -> execution_mode: ROUTE_ONLY then TRIVIAL_PARENT_FIX or cheap delegated check

small-bounded / medium-bounded
  -> selected_process: normal
  -> implementation handoff review: parent authorization artifact を作成
  -> execution_mode: ROUTE_ONLY then DELEGATED_WORK
  -> implementation: standard-implementer
  -> verification: standard-verifier

needs-plan-behavior-expansion
  -> selected_process: normal または human-decision-wait
  -> execution_mode: ROUTE_ONLY
  -> next gate: black-box-behavior-spec-kernel または plan-kernel rerun
  -> risk / full-coverage / implementation へ進めない

high-risk-bounded だが scope は明確
  -> selected_process: normal または higher-model-review
  -> HIGH_MODEL で plan / risk / implementation contract / close を厚くする
  -> implementation handoff review: Parent Plan Coverage Ledger と必要な Behavior Case Coverage Ledger を作成
  -> 実装・検証は standard agent へ委譲
  -> external / production / destructive operation は accepted residual または human-decision-wait に分離

broad-full-coverage-candidate
  -> selected_process: advanced-full-coverage
  -> 前提: Plan readiness = ReadyForRiskTriage
  -> Plan網羅チェック・残件判定フローまたは full-coverage 3層運用へ進める
  -> slice decomposition / Guardrail Focus / residual decision を使う

blocked-human-required
  -> selected_process: human-decision-wait
  -> 必要な人間判断、credential、owner、manual verification method が揃うまで実装しない
```

## 今回のような `high-risk-bounded + normal` の読み方

例として、Microsoft Graph、ユーザー無効化、グループ削除、承認 JSON、destructive option が絡むツールは、外部副作用や tenant impact の観点では高リスクです。

一方で、仕様書が明確で、実装対象が 1 つの .NET utility に閉じており、通常 verification も local test / dry-run planner までに限定できるなら、作業範囲は bounded です。

その場合は次のような分岐が妥当です。

```text
task_weight: high-risk-bounded
selected_process: normal
execution_mode: DELEGATED_WORK
Plan / risk / implementation contract / close: HIGH_MODEL
implementation / verification: STANDARD_MODEL delegated agents
implementation handoff review: standard implementation の前に必須
real tenant mutation / credentials / destructive approval: out of scope or human-decision-wait
```

つまり `high-risk-bounded` は「必ず Plan網羅チェック・残件判定フローへ行く」という意味ではありません。「bounded だが安全境界や close 判断を厚くする」という意味で使います。
