# coding_agent_plan_and_verify_process

GitHub Copilot で Plan-first 開発をするための agent（`.github/agents/`）です。

単純な Plan モードでは不十分と感じた点を、自分の用途向けに改善したものです。

この repository には、大きく分けて 2 系統のプロセスがあります。

1. Full autonomous Plan-first flow  
   runtime evidence・integration test の設計・検証・ギャップ解消を広く使い、ゴールまで自走しやすい従来型のフロー。

2. Token-aware guardrail kernel flow  
   GitHub Copilot のトークン消費を意識し、Plan-first の効果を保ったまま、対象 slice を絞って bounded に進めるフロー。Plan 作成は省略せず、guardrail も削らず、対象範囲を絞ることを重視します。

---

## 基本的な考え方

このプロセスが防ぎたい主な失敗は 2 つです。

1. sequence contract の不一致  
   プロセス間・コンポーネント間の処理で、各コンポーネント内では unit test が通るが、実際につなげると runtime contract・メッセージ・状態遷移・wiring が対応しておらず動かない。

2. stub は完成しているが production 実装が存在しない  
   stub / fake / mock / in-memory 実装を使った自動テストは通るが、対応する production 実装または production wiring が存在しない。

Token-aware guardrail kernel flow では、この失敗を防ぐための guardrail チェーンを維持したまま、対象の runtime slice を絞ります。

```text
Plan requirement / acceptance condition
  -> runtime contract
  -> テストポイント
  -> stub/fake の使用
  -> production 実装
  -> production wiring / entrypoint
  -> 明示的な未解決状態
```

軽量化する場合も、削る対象は プロセスの深さ ではなく プロセスの広さ です。  
つまり「全体を浅く見る」のではなく、「Plan は作る」「選択した危険な contract を十分に深く見る」ことを優先します。

---

## Full autonomous Plan-first flow

従来の、広く自走させる用途向けのフローです。

### 想定用途

次のような場合に使います。

- 機能全体のスコープがまだ広い、または曖昧
- 複数の runtime sequence が絡む
- recovery・retry・rollback・データ整合性が重要
- full runtime evidence や integration test の設計を人間がレビューしたい
- トークンコストより網羅性を優先する
- 一度 agent に大きく自走させ、残ったギャップを後続で処理したい

### 典型的な手順

1. `plan-generation.agent.md`
    1. この中で `integration-test-design.agent.md` と `runtime-evidence.agent.md` を呼び出す
2. `plan-review.agent.md`
3. 通常エージェントで実装
4. `integration-test-verification-implementation.agent.md`
5. `coverage-gap-resolution.agent.md`

### オプション: implementation contract フェーズ

通常はそのまま実装に入ればよいですが、新しい実現方式の採用や、標準 API・既存 OSS・既存コードの比較検討が重要なケースでは、実装前に次のオプションフェーズを追加できます。

1. `implementation-contract-generation.agent.md`
2. `implementation-contract-review.agent.md`

これは、実装の中でも特に採用する API・ライブラリ・既存実装・設計パターンなどを検討するフェーズです。独自実装よりも適切な既存実装やベストプラクティスの採用を明示的に検討することで、AI による不要な車輪の再発明を避けることを狙います。

### プロンプト例

```text
この issue について、Full autonomous Plan-first flow で進めてください。
まず plan-generation.agent.md を使って Plan を作成し、runtime evidence と integration test の設計も含めてください。
その後、plan-review.agent.md で Plan をレビューしてください。
```

---

## Token-aware guardrail kernel flow

トークン消費を意識し、bounded Plan を作成したうえで、選択した runtime contract・テストポイント・ギャップだけを bounded に扱うフローです。

このフローは risk triage から始めません。  
まず `plan-kernel.agent.md` で実装の source of truth になる bounded Plan を作成し、その Plan の中から高リスクな runtime slice を選びます。

### 想定用途

次のような場合に向いています。

- full flow は重すぎるが、Plan-first の効果は保ちたい
- runtime contract の guardrail は外したくない
- 複数のプロセス・サービス・コンポーネントが絡むが、危険な slice は限定できる
- stub / fake を使ったテストがあり、production 実装 / wiring の欠落を防ぎたい
- 検証で見つかったギャップを、選択した ID だけ bounded に修正したい
- トークンコストを抑えるため、1 回の実行で全部を解決しようとしない運用にしたい

### 典型的な手順

1. `plan-kernel.agent.md`
2. `change-risk-triage.agent.md`
3. `implementation-contract-kernel.agent.md`（implementation-realization risk がある場合）
4. `implementation-contract-review-kernel.agent.md` または bounded `implementation-contract-review.agent.md`（contract が non-trivial の場合）
5. `runtime-contract-kernel.agent.md`
6. `test-design-kernel.agent.md`
7. 必要に応じて `implementation-handoff-review.agent.md`
8. `implementation-execution.agent.md` または人間主導で実装
9. 必要に応じて `code-review-focus-kernel.agent.md`
10. `code-review-focus-kernel` を実行した場合は、その出力を使って human code review
11. `verification-kernel.agent.md`
12. 未解決がある場合は `coverage-gap-triage.agent.md`
13. 選択した gap は `coverage-gap-resolution-slice.agent.md`
14. 必要に応じて `verification-kernel.agent.md` を再実行

このフローでは、各 agent が 1 回の bounded な実行を行い、未解決項目は成果物に残して停止します。  
「直るまで修正し続ける」ことは目的ではありません。

`implementation-handoff-review.agent.md` は任意の軽量 gate です。  
常に必須ではありませんが、実装前に Plan → selected runtime contract → test point → production binding requirement の接続を一度だけ確認したい場合に使います。

`code-review-focus-kernel.agent.md` も任意の軽量 gate です。  
常に必須ではありませんが、人手レビューを入れる場合に、実装差分と guardrail artifacts を突き合わせて「どこから読むべきか」を先に整理したいときに使います。

### `implementation-execution.agent.md` に渡すもの

Token-aware flow で `implementation-execution.agent.md` を使って実装に入るときは、`runtime-contract-kernel` だけを渡してはいけません。  
`runtime-contract-kernel` は高リスク境界の guardrail であり、要求全体の仕様ではありません。

`implementation-execution.agent.md` には、少なくとも次を渡してください。

- `plan-kernel.agent.md` が作成した bounded Plan
- `change-risk-triage.agent.md` の出力
- `implementation-contract-kernel.agent.md` の出力（implementation-realization risk が Present / Unclear の場合）
- `implementation-contract-review-kernel.agent.md` の出力（存在する場合）
- `runtime-contract-kernel.agent.md` の出力
- `test-design-kernel.agent.md` の出力
- `implementation-handoff-review.agent.md` の出力（実行した場合）
- selected implementation scope と non-goals

補足:

- runtime-contract artifact は implementation-contract artifact の代替ではありません
- Plan conformance を確認しても、unknown な implementation path の調査は不要になりません
- implementation-realization の unresolved items は guessed address に変換せず、明示的に保持します
- broad なケースでは full-flow `implementation-contract-generation.agent.md` / `implementation-contract-review.agent.md` を継続利用します

`implementation-execution.agent.md` は Plan を source of truth として扱います。kernel artifacts は high-risk slice に対する guardrail であり、Plan の代替ではありません。

人間主導で実装する場合も、上記と同じ artifacts を実装者に渡してください。

human code review に渡すときは、上記に加えて実装差分、changed files 一覧、`plans/<ticket-or-slug>-implementation-execution.md`、必要に応じて `code-review-focus-kernel.agent.md` の出力を渡してください。

---

## Token-aware フローの agent 群

### `plan-kernel.agent.md`

要求された変更に対して、bounded な実装 Plan を作成します。

主な役割:

- token-aware flow の先頭で、実装の source of truth になる Plan を作る
- Goal / Non-goals / Functional requirements / Acceptance conditions を明確にする
- 影響を受ける component / module と expected implementation scope を整理する
- high-risk boundary candidates を軽く拾い、`change-risk-triage` へ渡す
- full runtime evidence や full integration test design には踏み込まない

この agent は実装もテスト作成も行いません。final runtime contracts の選択も行いません。

使う場面:

- Token-aware guardrail kernel flow を開始するとき
- full `plan-generation.agent.md` は重すぎるが、Plan-first は維持したいとき
- 実装に入る前に、scope / non-goals / acceptance conditions を固定したいとき

プロンプト例:

```text
この issue について、Token-aware guardrail kernel flow で進めます。
まず plan-kernel.agent.md を使って bounded Plan を作成してください。
実装・テスト作成・full runtime evidence・full integration test design は行わず、Goal、Non-goals、Functional requirements、Acceptance conditions、Affected components、Known high-risk boundaries、Handoff to change-risk-triage を出してください。
```

---

### `change-risk-triage.agent.md`

bounded Plan を読み、リスクプロファイルを分類し、最小限かつ十分なプロセスプロファイルを推奨します。

主な役割:

- Plan の中から高リスクな runtime 境界を特定する
- implementation-realization risk（dependency / API surface / substitution risk）を分類する
- 対象の runtime contract を 1〜3 件程度に絞る
- `implementation-contract-kernel` / full `implementation-contract-generation` / `contract-kernel` / `standard-slice` / `full-coverage` / `fix-slice` を推奨する
- 後続 agent に渡す引き渡し情報を作る

この agent は Plan 作成・実装・テスト設計を行いません。

使う場面:

- `plan-kernel.agent.md` が bounded Plan を作成した後
- full flow に入る前に、軽量化できるか確認したいとき
- プロセス間・queue・webhook・外部 API・DI・production wiring などのリスクがありそうなとき
- Plan-named dependency/API/provider path の実在確認が未完了なとき

プロンプト例:

```text
plan-kernel.agent.md が作成した bounded Plan を入力として、change-risk-triage.agent.md を実行してください。
Plan の中から高リスクな runtime boundary と implementation-realization risk を分類し、実装やテスト設計は行わず、リスクトリガーのスキャン結果・対象 runtime contract・Implementation realization risk・推奨プロセスプロファイル・次に使う agent を出してください。
```

---

### `implementation-contract-kernel.agent.md`

bounded Plan を concrete な implementation decision に変換し、dependency / API surface / provider path の確認結果を記録します。

主な役割:

- Plan-named implementation requirement を明示する
- dependency / API / symbol の evidence を確認する
- prohibited substitutions と allowed reuse を分離する
- required code changes と verification hooks を定義する
- unresolved implementation-realization items を可視化する

この agent は実装もテスト作成も行いません。

使う場面:

- `change-risk-triage` が implementation-realization risk を `Present` / `Unclear` と判定した後
- runtime-contract-kernel へ進む前に implementation path を固定したいとき

プロンプト例:

```text
bounded Plan と change-risk-triage の出力を入力として、implementation-contract-kernel.agent.md を実行してください。
plans/<ticket-or-slug>-implementation-contract-kernel.md を作成し、Plan-named dependency/API/provider path の確認結果、prohibited substitutions、required code changes、unresolved implementation-realization items を記録してください。
```

---

### `implementation-contract-review-kernel.agent.md`

implementation-contract-kernel の内容を軽量レビューし、runtime-contract または実装へ進めるかを verdict で判定します。

主な役割:

- dependency / API evidence 不足の検出
- unjustified substitution の検出
- Plan と implementation contract の source-of-truth drift の検出
- `READY_FOR_RUNTIME_CONTRACT` / `READY_FOR_IMPLEMENTATION` / `BLOCKED_*` / `NEEDS_HUMAN_DECISION` の判定

この agent は docs-only review gate であり、実装・テスト作成は行いません。

使う場面:

- implementation-contract-kernel が non-trivial な判断を含むとき
- runtime-contract へ進む前に drift を抑止したいとき

プロンプト例:

```text
plans/<ticket-or-slug>.md、plans/<ticket-or-slug>-change-risk-triage.md、plans/<ticket-or-slug>-implementation-contract-kernel.md を入力として、implementation-contract-review-kernel.agent.md を実行してください。
source-of-truth drift、dependency/API evidence 不足、unjustified substitution を確認し、single verdict を出してください。
```

---

### `runtime-contract-kernel.agent.md`

選択された高リスクな runtime contract について、最小限の runtime contract 成果物を作成します。

主な役割:

- `RC-xxx` を安定した runtime contract として固定する
- Producer / Consumer / メッセージ / API / イベントを明確にする
- 必須フィールド・エラー / タイムアウト時の動作・production 実装の所在を記録する
- 後続の `test-design-kernel` や `verification-kernel` が再探索せずに使える引き渡し情報を作る

この agent は実装もテスト作成も行いません。Plan の代替になる仕様書も作りません。

使う場面:

- `change-risk-triage` が `contract-kernel` を推奨した後
- 対象 runtime contract の境界を明確にしたいとき
- full runtime evidence までは不要だが、producer / consumer / contract は固定したいとき

プロンプト例:

```text
change-risk-triage の出力と bounded Plan を入力として、runtime-contract-kernel.agent.md を実行してください。
対象の runtime contract に含まれる RC だけを対象にし、plans/<ticket-or-slug>-runtime-contract-kernel.md を作成してください。
Plan を source of truth として扱い、対象外の contract を追加しないでください。
```

---

### `test-design-kernel.agent.md`

Runtime Contract Kernel の `RC-xxx` を、観測可能な `TP-xxx` テストポイントに落とし込みます。

主な役割:

- 対象の runtime contract ごとにテストポイントを定義する
- 「何を検証するか」と「期待される観測結果」を記録する
- stub / fake / mock / in-memory を使う可能性を明示する
- stub / fake を使う場合、production binding の検証を必須にする
- `verification-kernel` に渡す「必須 production binding チェック」を作る

この agent はテストを実装しません。

使う場面:

- Runtime Contract Kernel が作成された後
- 対象 contract に対する最小限のテスト設計を作りたいとき
- stub / fake は許容するが、実際の実装・本番 wiring の確認を省きたくないとき

プロンプト例:

```text
bounded Plan と runtime-contract-kernel の内容を入力として、test-design-kernel.agent.md を実行してください。
各 RC に対して観測可能なテストポイントを作り、stub/fake を使う場合は production binding の確認を必須にしてください。
```

---

### `implementation-handoff-review.agent.md`

実装に入る直前に、kernel artifact chain の接続を軽量にレビューします。

主な役割:

- base 4 成果物（`plans/<ticket-or-slug>.md`、`change-risk-triage`、`runtime-contract-kernel`、`test-design-kernel`）を読む
- implementation-realization risk が `Present` / `Unclear` の場合は `implementation-contract-kernel`（存在すれば review-kernel も）を追加で読む
- Plan → selected runtime contracts → RC → TP → production binding requirement の接続を確認する
- source code を読まず、artifacts を修正せず、実装もしない
- `READY_FOR_IMPLEMENTATION` / `READY_WITH_NOTES` / `BLOCKED` の単一 verdict を出す
- `implementation-execution.agent.md` または人間の実装者に渡すべき Required handoff inputs を整理する

この agent は optional です。過剰な review を避けるため、常に使う必要はありません。

使う場面:

- selected RC が複数ある
- queue / worker / webhook / external API / DI / production wiring が絡む
- stub / fake / mock / in-memory を使う test point がある
- 実装前に、Plan と kernel artifacts の接続漏れだけを一度確認したい
- `test-design-kernel` に `NeedsHumanDecision` や曖昧な mapping が残っている可能性がある

省略してよい場面:

- selected RC が 0〜1 件で、mapping が明確
- stub / fake / mock / in-memory を使わない
- cross-boundary risk が低い
- 実装者が Plan と kernel artifacts の接続を十分に把握している

プロンプト例:

```text
実装に入る前に、implementation-handoff-review.agent.md を使って軽量レビューを行ってください。

次の base 成果物を対象にしてください。

- plans/<ticket-or-slug>.md
- plans/<ticket-or-slug>-change-risk-triage.md
- plans/<ticket-or-slug>-runtime-contract-kernel.md
- plans/<ticket-or-slug>-test-design-kernel.md

change-risk-triage の Implementation realization risk が Present / Unclear の場合は、次も対象にしてください。

- plans/<ticket-or-slug>-implementation-contract-kernel.md
- plans/<ticket-or-slug>-implementation-contract-review-kernel.md（存在する場合）

source code は読まず、artifacts も修正しないでください。
Plan → selected runtime contracts → RC → TP → production binding requirement の接続を確認し、READY_FOR_IMPLEMENTATION / READY_WITH_NOTES / BLOCKED の verdict を出してください。
```

---

### `implementation-execution.agent.md`

Token-aware flow の bounded な実装フェーズを担当します。

主な役割:

- bounded Plan を source of truth として selected implementation scope 全体を実装する
- runtime-contract / test-design / implementation-contract artifacts を selected high-risk slice の guardrail として使う
- production implementation と production wiring / entrypoint を落とさず実装する
- 必要な tests / checks を bounded に実行し、未実行や失敗を明示する
- downstream の `code-review-focus-kernel.agent.md` と `verification-kernel.agent.md` が使う `Implementation Self-Map` を `plans/<ticket-or-slug>-implementation-execution.md` に残す

この agent は optional ではありません。Token-aware flow を agent ベースで通すなら、実装フェーズの標準担当として使います。人間主導で実装する場合も、この agent の入力契約と出力契約を満たす形で進めるのが望ましいです。

プロンプト例:

```text
implementation-execution.agent.md を使って、selected scope だけを実装してください。

次の成果物を必ず読んでください。

- plans/<ticket-or-slug>.md もしくは plan-kernel.agent.md が作成した bounded Plan
- plans/<ticket-or-slug>-change-risk-triage.md
- plans/<ticket-or-slug>-implementation-contract-kernel.md（implementation-realization risk が Present / Unclear の場合）
- plans/<ticket-or-slug>-implementation-contract-review-kernel.md（存在する場合）
- plans/<ticket-or-slug>-runtime-contract-kernel.md
- plans/<ticket-or-slug>-test-design-kernel.md
- plans/<ticket-or-slug>-implementation-handoff-review.md（存在する場合）

実装の source of truth は bounded Plan です。
runtime-contract-kernel と test-design-kernel は、selected high-risk slice に対する guardrail として使ってください。
implementation-handoff-review がある場合は、その verdict、blocking issues、recommended implementation prompt additions を確認してください。

次の制約を守ってください。

- Plan の Functional requirements と Acceptance conditions を満たす
- Non-goals と Out of scope for this pass に含まれる作業は行わない
- selected runtime contracts / test points に必要な production implementation と wiring を落とさない
- stub / fake / mock / in-memory test だけで production complete と判断しない
- selected scope 外の redesign や unrelated refactoring は行わない
- `plans/<ticket-or-slug>-implementation-execution.md` に Implementation Self-Map、Test / Check Summary、Remaining Work を残す
- 完了できない項目は Remaining work として報告する

最後に、変更した files、対応した Runtime Contract ID、対応した Test Point ID、実行した tests、未実行 tests、Implementation Self-Map の保存先、Remaining work を報告してください。
```

---

### `code-review-focus-kernel.agent.md`

実装後に、人手レビューで優先して読むべき code surface を整理します。

主な役割:

- implementation diff と changed files を読む
- Plan / triage / implementation-contract / runtime-contract / test-design artifact と差分を突き合わせる
- P0 / P1 の review target、skim でよい file、未確認の不確実性を切り分ける
- human code review の読む順番と注意点を `plans/<ticket-or-slug>-code-review-focus-kernel.md` にまとめる
- code review の承認や修正は行わない

この agent は optional です。実装差分が小さく、人手レビューを重点化する必要が薄い場合は省略できます。

使う場面:

- human code review を入れたい
- queue / retry / state transition / DI / public API / persistence shape など high-risk diff がある
- 実装差分が広く、review で読む順番を先に絞りたい
- AI 実装の前提誤りや test false confidence を人手で重点確認したい

省略してよい場面:

- 変更差分がごく小さく、P0 / P1 の候補がほぼ自明
- human code review 自体を今回行わない
- changed files と selected scope の対応が単純で、review map を別成果物に分けるほどではない

プロンプト例:

```text
実装後、人手でコードレビューしたいので code-review-focus-kernel.agent.md を実行してください。

次を入力として、selected scope に関係する changed files だけを読んでください。

- plans/<ticket-or-slug>.md
- plans/<ticket-or-slug>-change-risk-triage.md
- plans/<ticket-or-slug>-runtime-contract-kernel.md
- plans/<ticket-or-slug>-test-design-kernel.md
- plans/<ticket-or-slug>-implementation-contract-kernel.md（存在する場合）
- plans/<ticket-or-slug>-implementation-contract-review-kernel.md（存在する場合）
- plans/<ticket-or-slug>-implementation-handoff-review.md（存在する場合）
- working tree diff または PR diff

可能であれば、PR number または base/head commit range を diff source として明示してください。
例: base=main, head=<current-branch> または PR #123

production code や test code は修正せず、plans/<ticket-or-slug>-code-review-focus-kernel.md を作成してください。
P0 / P1 の review target、skim でよい file、未確認の不確実性、Suggested human review order をまとめてください。
```

---

### `verification-kernel.agent.md`

実装後に対象の contract / テストポイントを検証し、production binding と wiring の状態を分類します。

主な役割:

- 対象テストポイントのテスト成果物 / 手動のみの理由を確認する
- stub / fake / mock / in-memory の使用有無を確認する
- production interface / 具体的な実装 / wiring / entrypoint を確認する
- runtime contract のフィールドとエラー時の動作が production コードに表現されているか確認する
- `PASS_FOR_SELECTED_SCOPE` / `BLOCKED_BY_*` などの判定結果を出す

この agent はギャップを修正しません。修正が必要な場合は、ギャップを分類して後続 agent へ渡します。

使う場面:

- 対象 slice の実装後
- fake テストが production ready と誤判定されていないか確認したいとき
- `Bound` を正式に判断したいとき
- `coverage-gap-triage` に渡す未解決項目を作りたいとき
- human code review の後で、selected scope の verification を bounded に実行したいとき

プロンプト例:

```text
実装後の状態について、verification-kernel.agent.md を実行してください。
bounded Plan、Runtime Contract Kernel、Test Design Kernel の対象テストポイントだけを確認し、stub/fake の使用有無・production 実装・production wiring/entrypoint を検証してください。
修正は行わず、判定結果と未解決項目を出してください。
```

---

### `coverage-gap-triage.agent.md`

未解決のカバレッジギャップを分類し、次に行う bounded な修正範囲を推奨します。

主な役割:

- `verification-kernel.md` または `implementation-coverage-of-integration-test.md` から未解決項目を抽出する
- ギャップの種別を統制語彙で分類する
- `ImplementationContractMissing` / `DependencyMissing` / `ApiSurfaceUnknown` / `UnjustifiedSubstitution` / `SourceOfTruthDrift` / `ProductionImplementationMissing` / `ProductionWiringMissing` / `ContractMismatch` などを分ける
- 人間の判断が必要なものを分離する
- `coverage-gap-resolution-slice` に渡す後続セレクターを作る

この agent は修正を行いません。

使う場面:

- `verification-kernel` の後
- `integration-test-verification-implementation` の後
- 未解決ギャップが複数あり、どれをどの範囲で修正すべきか整理したいとき

プロンプト例:

```text
verification-kernel の出力を入力として、coverage-gap-triage.agent.md を実行してください。
未解決項目をギャップ種別ごとに分類し、coverage-gap-resolution-slice.agent.md に渡す bounded な修正範囲を提案してください。
```

---

### `coverage-gap-resolution-slice.agent.md`

明示的に選択されたカバレッジギャップだけを、1 回の bounded な実行で修正します。

主な役割:

- 呼び出し元または `coverage-gap-triage` が指定した後続セレクターだけを対象にする
- Plan の要件 / Runtime Contract ID / テストポイント ID に戻して修正する
- implementation-realization gap（`ImplementationContractMissing` / `DependencyMissing` / `ApiSurfaceUnknown` / `UnjustifiedSubstitution` / `SourceOfTruthDrift`）では、repair 前に implementation-contract artifact を consume または create する
- production 実装・production wiring・テストの oracle・ドキュメントの陳腐化など、ギャップ種別に応じた最小限の修正を行う
- カバレッジドキュメントまたはステータス成果物の更新結果を記録する
- 修正できなかった残件を「残作業」に残す

この agent は発見・分類を行いません。後続セレクターが曖昧な場合は修正を開始せず、`coverage-gap-triage` の実行を推奨します。

使う場面:

- `coverage-gap-triage` が推奨修正範囲を出した後
- 修正対象 ID とギャップ種別が明示されているとき
- 全ギャップではなく、選択したギャップだけを bounded に修正したいとき

プロンプト例:

```text
coverage-gap-triage の推奨修正範囲から Slice 1 だけを対象に、coverage-gap-resolution-slice.agent.md を実行してください。
後続セレクターに含まれる ID / ギャップ種別だけを修正し、選択スコープ外へ広げないでください。
修正後、必要であれば verification-kernel.agent.md の再実行を次のステップとして記録してください。
```

---

## フローの選び方

### Full autonomous Plan-first flow を使う場合

- 要求が広い、または曖昧
- 複数のシナリオをまとめて設計したい
- runtime evidence と integration test の設計を詳細に作りたい
- トークンコストより網羅性を優先する
- agent にある程度ゴールまで自走させたい

### Token-aware guardrail kernel flow を使う場合

- Plan-first は維持したいが、full flow は重すぎる
- bounded Plan を作り、その中の高リスク slice だけ深く扱いたい
- 境界をまたぐリスクはあるが、全体の runtime evidence までは不要
- implementation-realization risk がある場合だけ implementation-contract branch を差し込みたい
- stub / fake テストと production 実装 / wiring の対応を確認したい
- ギャップを選択した ID ごとに分割して修正したい
- トークンコストと bounded な進捗を重視する

### `implementation-handoff-review.agent.md` を使う場合

- 実装前に一度だけ横断的な漏れチェックを入れたい
- selected RC が複数あり、Plan → RC → TP の対応が見落とされそう
- stub / fake / mock / in-memory を使う test point がある
- production binding required の指定漏れが特に怖い
- `implementation-execution.agent.md` または人間の実装者に渡す handoff が複数 artifacts に分かれており、接続確認をしておきたい

### `implementation-handoff-review.agent.md` を省略してよい場合

- selected RC が 0〜1 件で単純
- stub / fake / mock / in-memory を使わない
- `test-design-kernel` までの対応関係が明確
- 追加レビューのコストをかけるほどの risk がない

### kernel flow から full flow に切り替えるべき場合

- bounded Plan を安全に作れないほど要求が曖昧
- 対象の contract が 5 件を超えそう
- kernel のテーブルだけでは sequence の因果関係が表現できない
- retry / rollback / replay / recovery の仕様が複雑
- 複数の contract が相互依存しており、1 slice に分けると危険
- 詳細な runtime evidence を人間がレビューする必要がある

---

## よく使うプロンプトパターン

### Token-aware flow を Plan から始める

```text
この変更について、Token-aware guardrail kernel flow で進めます。
まず plan-kernel.agent.md を使って bounded Plan を作成してください。
実装・テスト作成・full runtime evidence・full integration test design は行わず、実装の source of truth になる Plan と、change-risk-triage への handoff を出してください。
```

### Plan をもとにトリアージする

```text
plan-kernel.agent.md が作成した bounded Plan を入力として、change-risk-triage.agent.md を使ってください。
Plan の中から高リスクな runtime boundary を分類し、実装やテスト設計は行わず、リスクトリガーのスキャン結果・対象 runtime contract・推奨プロセスプロファイル・次の agent を出してください。
```

### implementation-realization risk がある場合に implementation-contract-kernel を作る

```text
change-risk-triage の出力で Implementation realization risk が Present / Unclear なので、implementation-contract-kernel.agent.md を実行してください。
plans/<ticket-or-slug>-implementation-contract-kernel.md を作成し、Plan-named dependency/API/provider path の確認結果、prohibited substitutions、required code changes、verification hooks、unresolved items を記録してください。
```

### implementation-contract をレビューしてから runtime-contract へ進む

```text
plans/<ticket-or-slug>.md、plans/<ticket-or-slug>-change-risk-triage.md、plans/<ticket-or-slug>-implementation-contract-kernel.md を入力として、implementation-contract-review-kernel.agent.md を実行してください。
single verdict を出し、READY_FOR_RUNTIME_CONTRACT の場合のみ runtime-contract-kernel へ進めてください。
```

### 選択した contract だけに絞って contract-kernel を実行する

```text
bounded Plan と change-risk-triage の出力にある RC-001 と RC-002 だけを対象に、runtime-contract-kernel.agent.md を実行してください。
対象外の contract を追加せず、不明な項目は推測せず注意事項 / 前提に残してください。
```

### テストを実装せずにテストポイントを設計する

```text
bounded Plan と runtime-contract-kernel の RC-001 と RC-002 を対象に、test-design-kernel.agent.md を実行してください。
テストは実装せず、テストポイント ID・期待される観測結果・stub/fake の使用有無・必須 production binding チェックを作成してください。
```

### 実装前に handoff review を行う

```text
実装に入る前に、implementation-handoff-review.agent.md を使って軽量レビューを行ってください。

次の base 成果物を対象にしてください。

- plans/<ticket-or-slug>.md
- plans/<ticket-or-slug>-change-risk-triage.md
- plans/<ticket-or-slug>-runtime-contract-kernel.md
- plans/<ticket-or-slug>-test-design-kernel.md

change-risk-triage の Implementation realization risk が Present / Unclear の場合は、次も対象にしてください。

- plans/<ticket-or-slug>-implementation-contract-kernel.md
- plans/<ticket-or-slug>-implementation-contract-review-kernel.md（存在する場合）

source code は読まず、artifacts も修正しないでください。
Plan → selected runtime contracts → RC → TP → production binding requirement の接続を確認し、READY_FOR_IMPLEMENTATION / READY_WITH_NOTES / BLOCKED の verdict を出してください。
```

### implementation-execution に実装させる

```text
implementation-execution.agent.md を使って、selected scope だけを実装してください。

次の成果物を必ず読んでください。

- plans/<ticket-or-slug>.md もしくは plan-kernel.agent.md が作成した bounded Plan
- plans/<ticket-or-slug>-change-risk-triage.md
- plans/<ticket-or-slug>-implementation-contract-kernel.md（implementation-realization risk が Present / Unclear の場合）
- plans/<ticket-or-slug>-implementation-contract-review-kernel.md（存在する場合）
- plans/<ticket-or-slug>-runtime-contract-kernel.md
- plans/<ticket-or-slug>-test-design-kernel.md
- plans/<ticket-or-slug>-implementation-handoff-review.md（存在する場合）

実装の source of truth は bounded Plan です。
kernel artifacts は high-risk slice に対する guardrail として使ってください。
implementation-handoff-review がある場合は、その verdict、blocking issues、recommended implementation prompt additions を確認してください。

Plan の Functional requirements と Acceptance conditions を満たし、Non-goals / Out of scope に含まれる作業は行わないでください。
stub / fake / mock / in-memory test だけで production complete と判断せず、production implementation と wiring を落とさないでください。
実装後は plans/<ticket-or-slug>-implementation-execution.md に Implementation Self-Map、Test / Check Summary、Remaining Work を記録してください。
```

### 実装後に review focus を作る

```text
人手レビュー用の読み順を整理したいので、code-review-focus-kernel.agent.md を実行してください。
bounded Plan と kernel artifacts、plans/<ticket-or-slug>-implementation-execution.md、working tree diff を入力にして、selected scope の changed files だけを読み、P0 / P1 review target と Suggested human review order を出してください。
可能であれば、PR number または base/head commit range を diff source として明示してください。例: base=main, head=<current-branch> または PR #123
```

### review focus を使って人手レビューする

```text
plans/<ticket-or-slug>-code-review-focus-kernel.md を見ながら人手レビューを行います。
まず Suggested human review order の順に P0 / P1 を読み、必要なら Files not inspected / uncertainty に書かれた箇所を追加で確認してください。
human code review の指摘で P0 / P1 target、public API、state transition、production wiring、test substitute 周辺に追加変更が入った場合は、verification-kernel の前に code-review-focus-kernel.agent.md を再実行してください。
```

### 実装後に検証する

```text
実装後の状態について、verification-kernel.agent.md を実行してください。
bounded Plan、Test Design Kernel の TP-001 と TP-002 だけを対象にし、production 実装と wiring/entrypoint を確認してください。
ギャップは修正せず、判定結果と未解決項目を出してください。
```

### 未解決ギャップをトリアージする

```text
verification-kernel の未解決項目を対象に、coverage-gap-triage.agent.md を実行してください。
ギャップ種別を分類し、coverage-gap-resolution-slice.agent.md に渡す後続セレクターを作ってください。
```

### 選択したギャップだけを修正する

```text
coverage-gap-triage の Slice 1 だけを対象に、coverage-gap-resolution-slice.agent.md を実行してください。
選択した後続セレクター以外へスコープを広げず、1 回の bounded な実行で修正してください。
完了できない項目は残作業に残してください。
```

---

## 成果物の命名規則

Token-aware guardrail kernel flow では、通常は次の成果物を作成します。

| 成果物 | 目的 |
| --- | --- |
| `plans/<ticket-or-slug>.md` | bounded Plan。実装の source of truth |
| `plans/<ticket-or-slug>-change-risk-triage.md` | リスクプロファイル・対象 contract・推奨プロセスプロファイル |
| `plans/<ticket-or-slug>-implementation-contract-kernel.md` | Plan-named dependency/API/provider path の確認結果、required code changes、prohibited substitutions |
| `plans/<ticket-or-slug>-implementation-contract-review-kernel.md` | implementation-contract の readiness / blocking verdict |
| `plans/<ticket-or-slug>-runtime-contract-kernel.md` | runtime contract・producer / consumer・メッセージ・フィールド・production 実装の所在 |
| `plans/<ticket-or-slug>-test-design-kernel.md` | テストポイントマッピング・stub/fake の使用有無・production binding 確認要件 |
| `plans/<ticket-or-slug>-implementation-handoff-review.md` | 実装直前の lightweight review verdict と required handoff inputs |
| `plans/<ticket-or-slug>-implementation-execution.md` | 実装結果、Implementation Self-Map、Test / Check Summary、Remaining Work |
| `plans/<ticket-or-slug>-code-review-focus-kernel.md` | 人手コードレビュー向けの重点確認箇所・読む順番・不確実性の整理 |
| `plans/<ticket-or-slug>-verification-kernel.md` | production binding / wiring / contract の検証結果 |
| `plans/<ticket-or-slug>-coverage-gap-triage.md` | 未解決ギャップの分類と推奨修正範囲 |
| `plans/<ticket-or-slug>-coverage-gap-resolution-slice.md` | 選択したギャップの修正結果と残作業 |

---

## 運用原則

- Token-aware flow でも Plan 作成を省略しない
- 実装の source of truth は bounded Plan とする
- kernel artifacts は high-risk slice の guardrail として扱い、Plan の代替にしない
- `implementation-handoff-review.agent.md` は必要な場合だけ使う optional gate とする
- `code-review-focus-kernel.agent.md` は human code review を行うときの optional gate とする
- 対象スコープを明示する
- 不明な項目を推測で埋めない
- テストが通ることを production binding の証拠にしない
- fake / stub だけを production の完成と扱わない
- 1 回の bounded な実行で停止し、残件は成果物に残す
- `Bound` の正式判定は `verification-kernel.agent.md` に任せる

