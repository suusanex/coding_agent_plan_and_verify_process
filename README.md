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
3. `runtime-contract-kernel.agent.md`
4. `test-design-kernel.agent.md`
5. 通常エージェントまたは人間主導で実装
6. `verification-kernel.agent.md`
7. `coverage-gap-triage.agent.md`
8. `coverage-gap-resolution-slice.agent.md`
9. 必要に応じて `verification-kernel.agent.md` を再実行

このフローでは、各 agent が 1 回の bounded な実行を行い、未解決項目は成果物に残して停止します。  
「直るまで修正し続ける」ことは目的ではありません。

### 実装に渡すもの

Token-aware flow で実装に入るときは、`runtime-contract-kernel` だけを渡してはいけません。  
`runtime-contract-kernel` は高リスク境界の guardrail であり、要求全体の仕様ではありません。

実装 agent には、少なくとも次を渡してください。

- `plan-kernel.agent.md` が作成した bounded Plan
- `change-risk-triage.agent.md` の出力
- `runtime-contract-kernel.agent.md` の出力
- `test-design-kernel.agent.md` の出力
- selected implementation scope と non-goals

実装 agent は Plan を source of truth として扱います。kernel artifacts は high-risk slice に対する guardrail であり、Plan の代替ではありません。

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
- 対象の runtime contract を 1〜3 件程度に絞る
- `contract-kernel` / `standard-slice` / `full-coverage` / `fix-slice` を推奨する
- 後続 agent に渡す引き渡し情報を作る

この agent は Plan 作成・実装・テスト設計を行いません。

使う場面:

- `plan-kernel.agent.md` が bounded Plan を作成した後
- full flow に入る前に、軽量化できるか確認したいとき
- プロセス間・queue・webhook・外部 API・DI・production wiring などのリスクがありそうなとき

プロンプト例:

```text
plan-kernel.agent.md が作成した bounded Plan を入力として、change-risk-triage.agent.md を実行してください。
Plan の中から高リスクな runtime boundary を分類し、実装やテスト設計は行わず、リスクトリガーのスキャン結果・対象 runtime contract・推奨プロセスプロファイル・次に使う agent を出してください。
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
対象の runtime contract に含まれる RC だけを対象にし、plans/<slug>-runtime-contract-kernel.md を作成してください。
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

### 実装フェーズ

Token-aware flow では、実装専用 agent が別途あるわけではありません。通常の GitHub Copilot agent、通常の coding agent、または人間主導の実装で進めます。

ただし、実装に渡す入力は明確にしてください。

プロンプト例:

```text
次の成果物を必ず読んで、selected scope だけを実装してください。

- plans/<slug>.md もしくは plan-kernel.agent.md が作成した bounded Plan
- plans/<slug>-change-risk-triage.md
- plans/<slug>-runtime-contract-kernel.md
- plans/<slug>-test-design-kernel.md

実装の source of truth は bounded Plan です。
runtime-contract-kernel と test-design-kernel は、selected high-risk slice に対する guardrail として使ってください。

次の制約を守ってください。

- Plan の Functional requirements と Acceptance conditions を満たす
- Non-goals と Out of scope for this pass に含まれる作業は行わない
- selected runtime contracts / test points に必要な production implementation と wiring を落とさない
- stub / fake / mock / in-memory test だけで production complete と判断しない
- selected scope 外の redesign や unrelated refactoring は行わない
- 完了できない項目は Remaining work として報告する

最後に、変更した files、対応した Runtime Contract ID、対応した Test Point ID、実行した tests、未実行 tests、Remaining work を報告してください。
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
- `ProductionImplementationMissing` / `ProductionWiringMissing` / `ContractMismatch` などを分ける
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
- stub / fake テストと production 実装 / wiring の対応を確認したい
- ギャップを選択した ID ごとに分割して修正したい
- トークンコストと bounded な進捗を重視する

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

### Plan と kernel artifacts を渡して実装する

```text
次の成果物を必ず読んで、selected scope だけを実装してください。

- plans/<slug>.md もしくは plan-kernel.agent.md が作成した bounded Plan
- plans/<slug>-change-risk-triage.md
- plans/<slug>-runtime-contract-kernel.md
- plans/<slug>-test-design-kernel.md

実装の source of truth は bounded Plan です。
kernel artifacts は high-risk slice に対する guardrail として使ってください。

Plan の Functional requirements と Acceptance conditions を満たし、Non-goals / Out of scope に含まれる作業は行わないでください。
stub / fake / mock / in-memory test だけで production complete と判断せず、production implementation と wiring を落とさないでください。
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
| `plans/<ticket-or-slug>-runtime-contract-kernel.md` | runtime contract・producer / consumer・メッセージ・フィールド・production 実装の所在 |
| `plans/<ticket-or-slug>-test-design-kernel.md` | テストポイントマッピング・stub/fake の使用有無・production binding 確認要件 |
| `plans/<ticket-or-slug>-verification-kernel.md` | production binding / wiring / contract の検証結果 |
| `plans/<ticket-or-slug>-coverage-gap-triage.md` | 未解決ギャップの分類と推奨修正範囲 |
| `plans/<ticket-or-slug>-coverage-gap-resolution-slice.md` | 選択したギャップの修正結果と残作業 |

---

## 運用原則

- Token-aware flow でも Plan 作成を省略しない
- 実装の source of truth は bounded Plan とする
- kernel artifacts は high-risk slice の guardrail として扱い、Plan の代替にしない
- 対象スコープを明示する
- 不明な項目を推測で埋めない
- テストが通ることを production binding の証拠にしない
- fake / stub だけを production の完成と扱わない
- 1 回の bounded な実行で停止し、残件は成果物に残す
- `Bound` の正式判定は `verification-kernel.agent.md` に任せる

