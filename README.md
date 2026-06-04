# coding_agent_plan_and_verify_process

GitHub Copilot / Codex で Plan-first 開発をするための agent（`.github/agents/`）と運用ドキュメントを管理する repository です。

この repository には、大きく分けて 2 系統のプロセスがあります。

1. Full autonomous Plan-first flow
   runtime evidence・integration test の設計・検証・ギャップ解消を広く使い、ゴールまで自走しやすい従来型のフロー。

2. Plan網羅チェック・残件判定フロー
   English helper name: Plan Coverage Check and Residual Decision Flow

   bounded Plan を source of truth として維持しながら、通常可能な実装・検証は parent Plan に沿って進めるフロー。深い runtime / production-binding 確認は Guardrail Focus に絞れるが、それは implementation scope ではありません。高コスト、manual-only、blocked、ambiguous、human decision が必要な項目は residual candidate として記録し、Residual Decision Gate で明示判断します。

Migration note: 旧称 `Token-aware guardrail kernel flow` は、この新フローへ移行済みの legacy name です。通常の prompt では新名称を使ってください。

---

## 基本的な考え方

このプロセスが防ぎたい主な失敗は 3 つです。

1. sequence contract の不一致
   プロセス間・コンポーネント間の処理で、各コンポーネント内では unit test が通るが、実際につなげると runtime contract・メッセージ・状態遷移・wiring が対応していない。

2. stub は完成しているが production 実装が存在しない
   stub / fake / mock / in-memory 実装を使った自動テストは通るが、対応する production 実装または production wiring が存在しない。

3. parent Plan の縮小を完了と誤認する
   深く確認した Guardrail Focus だけを見て、parent Plan の FR / AC 全体が完了したように扱ってしまう。

Plan網羅チェック・残件判定フローでは、次の guardrail chain を維持します。

```text
Plan requirement / acceptance condition
  -> Guardrail Focus runtime contract
  -> Guardrail Focus test point
  -> stub/fake の使用
  -> production 実装
  -> production wiring / entrypoint
  -> Parent Plan Coverage Ledger
  -> Residual Decision Ledger
```

軽量化する場合も、削る対象は parent Plan の責務ではありません。Guardrail Focus は deep-check subset であり、implementation scope ではありません。

---

## Full autonomous Plan-first flow

従来の、広く自走させる用途向けのフローです。

### 想定用途

- 機能全体のスコープがまだ広い、または曖昧
- 複数の runtime sequence が絡む
- recovery・retry・rollback・データ整合性が重要
- full runtime evidence や integration test の設計を人間がレビューしたい
- トークンコストより網羅性を優先する
- 一度 agent に大きく自走させ、残ったギャップを後続で処理したい

### 典型的な手順

1. `plan-generation.agent.md`
2. `plan-review.agent.md`
3. 通常エージェントで実装
4. `integration-test-verification-implementation.agent.md`
5. `coverage-gap-resolution.agent.md`

### オプション: implementation contract フェーズ

新しい実現方式の採用や、標準 API・既存 OSS・既存コードの比較検討が重要なケースでは、実装前に次のオプションフェーズを追加できます。

1. `implementation-contract-generation.agent.md`
2. `implementation-contract-review.agent.md`

---

## Plan網羅チェック・残件判定フロー

bounded Plan を作成し、その parent Plan を実装・検証の source of truth として維持します。

### 想定用途

- full flow は重すぎるが、Plan-first の効果は保ちたい
- runtime contract の guardrail は外したくない
- 複数のプロセス・サービス・コンポーネントが絡むが、深く確認すべき runtime / production-binding surface は限定できる
- stub / fake を使ったテストがあり、production 実装 / wiring の欠落を防ぎたい
- 1 回の bounded pass で全項目を無理に終わらせず、残件を明示判断したい

### 不変条件

- parent Plan は `plan-kernel.agent.md` が作成した bounded Plan であり、実装・検証の source of truth です。
- `change-risk-triage`、`runtime-contract-kernel`、`test-design-kernel`、`implementation-handoff-review` は parent Plan を縮小しません。
- Guardrail Focus は deep runtime / production-binding verification の重点対象です。implementation scope ではありません。
- Guardrail Focus 外の parent Plan item も Parent Plan Coverage Ledger で必ず分類します。
- residual は記録しただけでは accepted ではありません。`ManualVerificationRequired` は close 不可の candidate status です。explicit human decision により owner / method / required evidence が明示された場合だけ、`AcceptedResidual`、`ManualVerificationDelegated`、`DeferredWithOwner`、`AbortedWithReason` などの close 可能な decision status にできます。
- final done は Parent Plan Coverage Ledger と Residual Decision Ledger で判定します。

### 典型的な手順

1. `plan-kernel.agent.md`
2. `change-risk-triage.agent.md`
3. `implementation-contract-kernel.agent.md`（implementation-realization risk がある場合）
4. `implementation-contract-review-kernel.agent.md`（contract が non-trivial の場合）
5. `runtime-contract-kernel.agent.md`
6. `test-design-kernel.agent.md`
7. `implementation-handoff-review.agent.md`
8. `implementation-execution.agent.md` または人間主導で bounded parent Plan pass を実行
9. 必要に応じて `code-review-focus-kernel.agent.md`
10. human code review
11. `verification-kernel.agent.md`
12. 未解決がある場合は `coverage-gap-triage.agent.md`
13. `residual-decision-gate.agent.md`
14. FixNow items がある場合だけ `coverage-gap-resolution-slice.agent.md`
15. 必要に応じて `verification-kernel.agent.md` と `residual-decision-gate.agent.md` を再実行

各 agent は 1 回の bounded な実行を行い、未解決項目は成果物に残して停止します。「直るまで修正し続ける」ことは目的ではありません。

### full-coverage handling

`change-risk-triage.agent.md` が `full-coverage` と診断した場合でも、parent Plan coverage は縮小しません。`full-coverage` は「bounded pass / decomposition / re-plan / human decision のいずれかが必要」という診断です。

```text
full-coverage
  -> plan-slice-decomposition.agent.md
  -> per-slice bounded parent Plan pass
  -> cross-slice-verification-kernel.agent.md
  -> residual-decision-gate.agent.md
```

slice decomposition は scope shrink ではありません。各 slice は parent Plan item mapping を持ち、最後に cross-slice verification と residual decision を通します。

### `implementation-execution.agent.md` に渡すもの

`implementation-execution.agent.md` は parent Plan に対する 1 bounded implementation pass を行います。`runtime-contract-kernel` だけを渡してはいけません。

少なくとも次を渡してください。

- `plans/<ticket-or-slug>.md`
- `plans/<ticket-or-slug>-change-risk-triage.md`
- `plans/<ticket-or-slug>-implementation-contract-kernel.md`（implementation-realization risk が Present / Unclear の場合）
- `plans/<ticket-or-slug>-implementation-contract-review-kernel.md`（存在する場合）
- `plans/<ticket-or-slug>-runtime-contract-kernel.md`
- `plans/<ticket-or-slug>-test-design-kernel.md`
- `plans/<ticket-or-slug>-implementation-handoff-review.md`
- `plans/<ticket-or-slug>-slice-decomposition.md`（full-coverage decomposition 由来の slice を扱う場合）
- parent Plan の Non-goals / constraints / residual policy

実装者は通常可能な FR / AC を parent Plan に沿って進め、詰まった項目は `Blocked`、`NeedsHumanDecision`、`ManualVerificationRequired`、`TooCostlyForBoundedPass`、`ImplementationEvidenceMissing` などで記録します。

---

## Agent 群

### `plan-kernel.agent.md`

bounded Plan を作成し、Goal / Non-goals / Functional requirements / Acceptance conditions / Affected components / Residual policy / Guardrail Focus candidates を記録します。final runtime contracts は選びません。

### `change-risk-triage.agent.md`

parent Plan 全体の risk inventory を作り、implementation-realization risk、Guardrail Focus recommendation、Residual risk candidates、Recommended process path を出します。実装 scope は縮小しません。

### `plan-slice-decomposition.agent.md`

full-coverage 診断時に、parent Plan coverage を維持したまま bounded execution slice に分解します。各 slice は parent Plan item mapping と cross-slice verification requirements を持ちます。

### `implementation-contract-kernel.agent.md`

dependency / API / provider / substitution risk を確認し、unresolved implementation-realization items を guessed address に変換せず residual candidate として保持します。

### `implementation-contract-review-kernel.agent.md`

source-of-truth drift、evidence 不足、unjustified substitution を review し、unresolved item を accepted residual と扱わず次工程へ渡します。

### `runtime-contract-kernel.agent.md`

Guardrail Focus runtime contract だけを深く固定します。focus 外の parent Plan item を out-of-scope 扱いにせず、Parent Plan Coverage Ledger へ残す前提で downstream に渡します。

### `test-design-kernel.agent.md`

Guardrail Focus RC を Guardrail Focus TP に落とし、stub / fake / mock / in-memory を使う場合は production binding check を必須にします。focus 外 parent Plan item の verification responsibility は消えません。

### `implementation-handoff-review.agent.md`

実装前 gate です。Plan → Guardrail Focus RC → TP → production binding requirement の接続と Parent Plan Coverage Ledger を確認し、`READY_FOR_BOUNDED_PARENT_PLAN_PASS` 系または `BLOCKED_*` verdict を出します。

### `implementation-execution.agent.md`

parent Plan に対する 1 bounded implementation pass を行い、Implementation Self-Map と item ごとの status を記録します。通常可能な FR / AC は実装し、残るものは residual candidate として明示します。

### `code-review-focus-kernel.agent.md`

human review 用の重点 surface を整理します。parent Plan item に影響する changed files と Guardrail Focus surface を分けて出します。

### `verification-kernel.agent.md`

Parent Plan Coverage Ledger を更新し、Guardrail Focus RC/TP については production binding / wiring / contract representation を深く確認します。final verdict は parent Plan verdict です。

### `coverage-gap-triage.agent.md`

Parent Plan Coverage Ledger から unresolved items を抽出し、FixNow items、manual decision candidates、Residual decision candidates を分けます。defer / abort / manual delegation を承認しません。

### `residual-decision-gate.agent.md`

coverage-gap-triage または verification-kernel 後の docs-only gate です。explicit human decision がある項目だけ accepted residual として扱い、Residual Decision Ledger と final next-step verdict を出します。

### `coverage-gap-resolution-slice.agent.md`

post-verification repair subflow です。coverage-gap-triage または residual-decision-gate が出した explicit FixNow selector だけを修正し、修正後は verification-kernel と residual-decision-gate に戻します。

### `cross-slice-verification-kernel.agent.md`

slice ごとの pass を parent Plan completion と扱わず、parent acceptance conditions、cross-slice contracts、residual decisions を統合して residual-decision-gate へ渡します。

---

## Verdict 語彙

### implementation-handoff-review

- `READY_FOR_BOUNDED_PARENT_PLAN_PASS`
- `READY_FOR_BOUNDED_PARENT_PLAN_PASS_WITH_DECLARED_RESIDUAL_RISKS`
- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
- `BLOCKED_BY_ARTIFACT_MISMATCH`
- `BLOCKED_BY_HUMAN_DECISION`
- `BLOCKED`

### verification-kernel

- `PARENT_PLAN_VERIFIED`
- `PARENT_PLAN_VERIFIED_WITH_ACCEPTED_RESIDUALS`
- `PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES`
- `PARENT_PLAN_NEEDS_RESIDUAL_DECISION`
- `BLOCKED_BY_PRODUCTION_BINDING_GAP`
- `BLOCKED_BY_CONTRACT_MISMATCH`
- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
- `BLOCKED_BY_HUMAN_DECISION`

### residual-decision-gate

- `READY_TO_CLOSE_WITH_NO_RESIDUALS`
- `READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS`
- `READY_FOR_NEXT_BOUNDED_FIX_PASS`
- `READY_FOR_MANUAL_VERIFICATION_HANDOFF`
- `NEEDS_HUMAN_RESIDUAL_DECISION`
- `REPLAN_REQUIRED`
- `ABORT_RECOMMENDED`

`READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS` は、input artifact、issue comment、PR comment、user prompt などに explicit human decision がある場合だけ出せます。`ManualVerificationRequired` のままでは close 不可で、owner / method / required evidence が明示された `ManualVerificationDelegated` に変換されている必要があります。

---

## フローの選び方

### Full autonomous Plan-first flow を使う場合

- 要求が広い、または曖昧
- 複数のシナリオをまとめて設計したい
- runtime evidence と integration test の設計を詳細に作りたい
- トークンコストより網羅性を優先する
- agent にある程度ゴールまで自走させたい

### Plan網羅チェック・残件判定フローを使う場合

- Plan-first は維持したいが、full flow は重すぎる
- bounded parent Plan pass で進めたい
- Guardrail Focus を深く確認しつつ parent Plan coverage を落としたくない
- implementation-realization risk がある場合だけ implementation-contract branch を差し込みたい
- residual を explicit decision なしに accepted 扱いしたくない
- トークンコストと bounded な進捗を重視する

---

## よく使うプロンプトパターン

### Plan から始める

```text
この変更について、Plan網羅チェック・残件判定フローで進めます。
まず plan-kernel.agent.md を使って bounded Plan を作成してください。
実装・テスト作成・full runtime evidence・full integration test design は行わず、Goal、Non-goals、Functional requirements、Acceptance conditions、Affected components、Residual policy、Guardrail Focus candidates、change-risk-triage への handoff を出してください。
```

### Plan をもとにトリアージする

```text
plans/<ticket-or-slug>.md を入力として、change-risk-triage.agent.md を実行してください。
parent Plan 全体の risk inventory、Guardrail Focus recommendation、Residual risk candidates、Implementation-realization risk、Recommended process path を出してください。実装 scope は縮小しないでください。
```

### 実装前に handoff review を行う

```text
実装に入る前に、implementation-handoff-review.agent.md を必須 gate として使ってください。
source code は読まず、artifacts も修正しないでください。
Parent Plan Coverage Ledger を作成し、Plan → Guardrail Focus RC → TP → production binding requirement の接続を確認してください。
Guardrail Focus ready と Parent Plan coverage ledger complete を分け、READY_FOR_BOUNDED_PARENT_PLAN_PASS 系または BLOCKED_* verdict を出してください。
```

### implementation-execution に実装させる

```text
implementation-execution.agent.md を使って、parent Plan に対する 1 bounded implementation pass を行ってください。

次の成果物を必ず読んでください。

- plans/<ticket-or-slug>.md
- plans/<ticket-or-slug>-change-risk-triage.md
- plans/<ticket-or-slug>-implementation-contract-kernel.md（implementation-realization risk が Present / Unclear の場合）
- plans/<ticket-or-slug>-implementation-contract-review-kernel.md（存在する場合）
- plans/<ticket-or-slug>-runtime-contract-kernel.md
- plans/<ticket-or-slug>-test-design-kernel.md
- plans/<ticket-or-slug>-implementation-handoff-review.md

実装の source of truth は bounded Plan です。Guardrail Focus artifacts は deep-check guardrail として使い、implementation scope として扱わないでください。
通常可能な Functional requirements と Acceptance conditions を満たし、Non-goals / constraints / parent Plan 外の作業は行わないでください。
完了できない項目は NeedsHumanDecision / ManualVerificationRequired / TooCostlyForBoundedPass / ImplementationEvidenceMissing などで Implementation Self-Map と Remaining Work に記録してください。
```

### 実装後に review focus を作る

```text
人手レビュー用の読み順を整理したいので、code-review-focus-kernel.agent.md を実行してください。
bounded Plan、kernel artifacts、plans/<ticket-or-slug>-implementation-execution.md、working tree diff または PR diff を入力にしてください。
parent Plan item に影響する changed files と Guardrail Focus surface を分け、P0 / P1 / P2 review target と Suggested human review order を出してください。
```

### 実装後に検証する

```text
実装後の状態について、verification-kernel.agent.md を実行してください。
Parent Plan Coverage Ledger を更新し、Guardrail Focus RC/TP は production implementation、wiring/entrypoint、contract representation を深く確認してください。
focus 外の parent Plan item も implemented / verified / ManualVerificationRequired / ResidualDecisionCandidate / unmapped のいずれかに分類してください。
修正は行わず、parent Plan verdict と未解決項目を出してください。
```

### residual decision を行う

```text
verification-kernel と coverage-gap-triage の出力を入力として、residual-decision-gate.agent.md を実行してください。
Residual Decision Ledger を作成し、`ManualVerificationRequired` は close 不可の candidate action、`ManualVerificationDelegated` は owner / method / required evidence が明示された explicit decision 後の decision status として扱ってください。
explicit human decision がある項目だけ AcceptedResidual / ManualVerificationDelegated / DeferredWithOwner / AbortedWithReason として扱ってください。
human decision がない residual は NEEDS_HUMAN_RESIDUAL_DECISION として停止してください。
```

### 選択した FixNow だけを修正する

```text
coverage-gap-triage または residual-decision-gate の FixNow selector だけを対象に、coverage-gap-resolution-slice.agent.md を実行してください。
FixNow selector 外へ広げず、parent Plan との整合を崩さないでください。
修正後、verification-kernel.agent.md と residual-decision-gate.agent.md の再実行を次のステップとして記録してください。
```

---

## 成果物の命名規則

Plan網羅チェック・残件判定フローでは、通常は次の成果物を作成します。

| 成果物 | 目的 |
| --- | --- |
| `plans/<ticket-or-slug>.md` | bounded Plan。実装の source of truth |
| `plans/<ticket-or-slug>-change-risk-triage.md` | risk inventory、Guardrail Focus recommendation、Residual risk candidates |
| `plans/<ticket-or-slug>-implementation-contract-kernel.md` | dependency/API/provider path の確認結果、required code changes、prohibited substitutions |
| `plans/<ticket-or-slug>-implementation-contract-review-kernel.md` | implementation-contract の readiness / blocking verdict |
| `plans/<ticket-or-slug>-runtime-contract-kernel.md` | Guardrail Focus runtime contract・producer / consumer・メッセージ・フィールド・production 実装の所在 |
| `plans/<ticket-or-slug>-test-design-kernel.md` | Guardrail Focus TP・stub/fake の使用有無・production binding 確認要件 |
| `plans/<ticket-or-slug>-implementation-handoff-review.md` | 実装直前の lightweight review verdict と Parent Plan Coverage Ledger |
| `plans/<ticket-or-slug>-implementation-execution.md` | 実装結果、Implementation Self-Map、Test / Check Summary、Remaining Work |
| `plans/<ticket-or-slug>-code-review-focus-kernel.md` | 人手コードレビュー向けの重点確認箇所・読む順番・不確実性の整理 |
| `plans/<ticket-or-slug>-verification-kernel.md` | Parent Plan Coverage Ledger 更新、production binding / wiring / contract の検証結果 |
| `plans/<ticket-or-slug>-coverage-gap-triage.md` | 未解決ギャップの分類、FixNow items、Residual decision candidates |
| `plans/<ticket-or-slug>-residual-decision-gate.md` | Residual Decision Ledger と next-step verdict |
| `plans/<ticket-or-slug>-coverage-gap-resolution-slice.md` | FixNow selector の修正結果と残作業 |

---

## 運用原則

- Plan網羅チェック・残件判定フローでも Plan 作成を省略しない
- 実装の source of truth は bounded Plan とする
- Guardrail Focus は implementation scope ではない
- kernel artifacts は deep-check guardrail として扱い、Plan の代替にしない
- parent Plan を agent が勝手に縮小しない
- Parent Plan Coverage Ledger を実装前と検証後に維持する
- Residual Decision Ledger なしに residual を accepted 扱いしない
- `AcceptedResidual` は explicit human decision がある場合だけ使う
- `ManualVerificationRequired` は「確認済み」ではなく、decision gate へ渡す close 不可の candidate status として扱う
- `ManualVerificationDelegated` は owner / method / required evidence が明示された explicit human decision 後の close 可能な decision status として扱う
- 不明な項目を推測で埋めない
- テストが通ることを production binding の証拠にしない
- fake / stub だけを production の完成と扱わない
- 1 回の bounded な実行で停止し、残件は成果物に残す
- final done は parent Plan coverage と residual decision の両方で判定する
