# coding_agent_plan_and_verify_process

GitHub Copilot で Plan-first 開発をするための Agents（`.github/agents/`）です。

単純な Plan mode では不十分と感じた点を、自分の用途向けに改善したものです。

この repository には、大きく分けて 2 系統の process があります。

1. **Full autonomous Plan-first flow**  
   runtime evidence / integration test design / verification / gap resolution を広く使い、ゴールまで自走しやすい従来型の flow。

2. **Token-aware guardrail kernel flow**  
   GitHub Copilot の token consumption を意識し、対象 slice を絞って bounded に進める flow。guardrail は削らず、対象範囲を narrow にすることを重視します。

---

## Core idea

この process が防ぎたい主な失敗は 2 つです。

1. **Sequence contract mismatch**  
   Cross-process / cross-component の処理で、各 component 内では unit test が通るが、実際につなげると runtime contract、message、state transition、wiring が対応しておらず動かない。

2. **Stub-complete but production-missing**  
   stub / fake / mock / in-memory implementation を使った automated test は通るが、対応する production implementation または production wiring が存在しない。

Token-aware guardrail kernel flow では、この失敗を防ぐための guardrail chain を維持したまま、対象 runtime slice を絞ります。

```text
runtime contract
  -> test point
  -> stub/fake usage
  -> production implementation
  -> production wiring / entrypoint
  -> explicit unresolved status
```

軽量化する場合も、削る対象は **process depth** ではなく **process breadth** です。  
つまり「全体を浅く見る」のではなく、「選択した危険な contract を十分に深く見る」ことを優先します。

---

## Full autonomous Plan-first flow

従来の、広く自走させる用途向けの flow です。

### Intended use

次のような場合に使います。

- 機能全体の scope がまだ広い、または曖昧
- 複数の runtime sequence が絡む
- recovery、retry、rollback、data consistency が重要
- full runtime evidence や integration test design を人間が review したい
- token cost よりも網羅性を優先する
- 一度 agent に大きく走らせ、残った gap を後続で処理したい

### Typical order

1. `plan-generation.agent.md`
    1. この中で `integration-test-design.agent.md` と `runtime-evidence.agent.md` を呼び出す
2. `plan-review.agent.md`
3. 通常エージェントで実装
4. `integration-test-verification-implementation.agent.md`
5. `coverage-gap-resolution.agent.md`

### Optional implementation contract phase

通常はそのまま実装に入ればよいですが、新しい実現方式の採用や、標準 API・既存 OSS・既存コードの比較検討が重要なケースでは、実装前に次の optional phase を追加できます。

1. `implementation-contract-generation.agent.md`
2. `implementation-contract-review.agent.md`

これは、具体的な実装の中でも特に採用する API、library、既存実装、設計 pattern などを検討する phase です。独自実装よりも適切な既存実装や best practice の採用を明示的に検討することで、AI による不要な車輪の再発明を避けることを狙います。

### Example prompt

```text
この issue について、Full autonomous Plan-first flow で進めてください。
まず plan-generation.agent.md を使って Plan を作成し、runtime evidence と integration test design も含めてください。
その後、plan-review.agent.md で Plan を review してください。
```

---

## Token-aware guardrail kernel flow

Token consumption を意識し、selected runtime contracts / selected test points / selected gaps だけを bounded に扱う flow です。

### Intended use

次のような場合に向いています。

- full flow は重すぎるが、runtime contract の guardrail は外したくない
- 複数 process / service / component が絡むが、危険な slice は限定できる
- stub / fake を使った test があり、production implementation / wiring の欠落を防ぎたい
- verification で見つかった gap を、選択 ID だけ bounded に直したい
- token cost を抑えるため、1 回の pass で全部を解決しようとしない運用にしたい

### Typical order

1. `change-risk-triage.agent.md`
2. `runtime-contract-kernel.agent.md`
3. `test-design-kernel.agent.md`
4. 通常エージェントまたは人間主導で実装
5. `verification-kernel.agent.md`
6. `coverage-gap-triage.agent.md`
7. `coverage-gap-resolution-slice.agent.md`
8. 必要に応じて `verification-kernel.agent.md` を再実行

この flow では、各 agent が 1 回の bounded pass を行い、未解決事項は artifact に残して停止します。  
「直るまで修正し続ける」ことは目的ではありません。

---

## Token-aware agents

### `change-risk-triage.agent.md`

要求された変更の risk profile を分類し、最小十分な process profile を推奨します。

主な役割:

- high-risk runtime boundary を特定する
- selected runtime contracts を 1〜3 件程度に絞る
- `contract-kernel` / `standard-slice` / `full-coverage` / `fix-slice` を推奨する
- 後続 agent に渡す handoff を作る

この agent は実装も test design も行いません。

使う場面:

- どの flow で進めるべきか迷うとき
- full flow に入る前に、軽量化できるか確認したいとき
- cross-process / queue / webhook / external API / DI / production wiring などの risk がありそうなとき

Example prompt:

```text
この issue について、change-risk-triage.agent.md を使って risk profile を分類してください。
実装は行わず、最小十分な process profile と selected runtime contracts を出してください。
```

---

### `runtime-contract-kernel.agent.md`

選択された high-risk runtime contracts について、最小限の runtime contract artifact を作成します。

主な役割:

- `RC-xxx` を stable な runtime contract として固定する
- Producer / Consumer / Message / API / Event を明確にする
- Required fields、error / timeout behavior、production implementation address を記録する
- 後続の `test-design-kernel` や `verification-kernel` が再探索せず使える handoff を作る

この agent は実装も test 作成も行いません。

使う場面:

- `change-risk-triage` が `contract-kernel` を推奨した後
- selected runtime contracts の境界を明確にしたいとき
- full runtime evidence までは不要だが、producer / consumer / contract は固定したいとき

Example prompt:

```text
change-risk-triage の出力を入力として、runtime-contract-kernel.agent.md を実行してください。
Selected runtime contracts to cover に含まれる RC だけを対象にし、plans/<slug>-runtime-contract-kernel.md を作成してください。
```

---

### `test-design-kernel.agent.md`

Runtime Contract Kernel の `RC-xxx` を、observable な `TP-xxx` test point に落とし込みます。

主な役割:

- selected runtime contract ごとに test point を定義する
- `What to verify` と `Expected observation` を記録する
- stub / fake / mock / in-memory を使う可能性を明示する
- stub / fake を使う場合、production binding verification を必須にする
- `verification-kernel` に渡す `Required production binding checks` を作る

この agent は tests を実装しません。

使う場面:

- Runtime Contract Kernel が作成された後
- selected contracts に対する最小限の test design を作りたいとき
- stub / fake を許すが、本物実装・本番 wiring の確認を抜かしたくないとき

Example prompt:

```text
runtime-contract-kernel の内容を入力として、test-design-kernel.agent.md を実行してください。
各 RC に対して observable な test point を作り、stub/fake を使う場合は production binding required を必ず Yes にしてください。
```

---

### `verification-kernel.agent.md`

実装後に selected contracts / test points を検証し、production binding と wiring の状態を分類します。

主な役割:

- selected test points の test artifact / manual-only reason を確認する
- stub / fake / mock / in-memory の使用有無を確認する
- production interface / concrete implementation / wiring / entrypoint を確認する
- runtime contract fields と error behavior が production code に表現されているか確認する
- `PASS_FOR_SELECTED_SCOPE` / `BLOCKED_BY_*` などの verdict を出す

この agent は gap を修正しません。修正が必要な場合は、gap を分類して後続 agent へ渡します。

使う場面:

- selected slice の実装後
- fake test が production ready と誤判定されていないか確認したいとき
- `Bound` を正式に判断したいとき
- `coverage-gap-triage` に渡す unresolved items を作りたいとき

Example prompt:

```text
実装後の状態について、verification-kernel.agent.md を実行してください。
Test Design Kernel の selected test points を対象に、stub/fake の使用有無、production implementation、production wiring/entrypoint を確認してください。
修正は行わず、verdict と unresolved items を出してください。
```

---

### `coverage-gap-triage.agent.md`

未解決の coverage gap を分類し、次に行う bounded fix slice を推奨します。

主な役割:

- `verification-kernel.md` または `implementation-coverage-of-integration-test.md` から unresolved items を抽出する
- gap type を controlled vocabulary で分類する
- `ProductionImplementationMissing` / `ProductionWiringMissing` / `ContractMismatch` などを分ける
- human decision が必要なものを分離する
- `coverage-gap-resolution-slice` に渡す downstream selectors を作る

この agent は修正を行いません。

使う場面:

- `verification-kernel` の後
- `integration-test-verification-implementation` の後
- 未解決 gap が複数あり、どれをどの slice で直すべきか整理したいとき

Example prompt:

```text
verification-kernel の出力を入力として、coverage-gap-triage.agent.md を実行してください。
Unresolved items を gap type ごとに分類し、coverage-gap-resolution-slice.agent.md に渡す bounded fix slices を提案してください。
```

---

### `coverage-gap-resolution-slice.agent.md`

明示的に選択された coverage gap だけを、1 回の bounded pass で修正します。

主な役割:

- caller または `coverage-gap-triage` が指定した selected gap selectors だけを対象にする
- Plan requirement / Runtime Contract ID / Test Point ID に戻して修正する
- production implementation、production wiring、test oracle、documentation stale など gap type に応じた最小修正を行う
- coverage document または status artifact の更新結果を記録する
- 修正できなかった残件を `Remaining work` に残す

この agent は discovery / triage を行いません。selected selector が曖昧な場合は修正を開始せず、`coverage-gap-triage` の実行を推奨します。

使う場面:

- `coverage-gap-triage` が recommended fix slice を出した後
- 修正対象 ID と gap type が明示されているとき
- 全 gap ではなく、選択された gap だけを bounded に直したいとき

Example prompt:

```text
coverage-gap-triage の Recommended fix slices から Slice 1 だけを対象に、coverage-gap-resolution-slice.agent.md を実行してください。
Downstream selectors に含まれる ID / gap type だけを修正し、選択 scope 外へ広げないでください。
修正後、必要なら verification-kernel.agent.md の再実行を Recommended next step に記録してください。
```

---

## Choosing the right flow

### Use `Full autonomous Plan-first flow` when

- 要求が広い、または曖昧
- 複数 scenario をまとめて設計したい
- runtime evidence と integration test design を詳細に作りたい
- token cost より網羅性を優先する
- agent にある程度ゴールまで自走させたい

### Use `Token-aware guardrail kernel flow` when

- 対象にする runtime slice を絞れる
- cross-boundary risk はあるが、full flow は重すぎる
- stub / fake test と production implementation / wiring の対応を確認したい
- gap を selected IDs ごとに分割して直したい
- token cost と bounded progress を重視する

### Escalate from kernel flow to full flow when

- selected contracts が 5 件を超えそう
- kernel table だけでは sequence の因果関係が表現できない
- retry / rollback / replay / recovery semantics が複雑
- multiple contracts が相互依存しており、1 slice で分けると危険
- human review のために detailed runtime evidence が必要

---

## Common prompt patterns

### Start with triage

```text
この変更について、まず change-risk-triage.agent.md を使ってください。
実装や test design は行わず、risk trigger scan、selected runtime contracts、recommended profile、next agent を出してください。
```

### Run contract-kernel only for selected contracts

```text
change-risk-triage の出力にある RC-001 と RC-002 だけを対象に、runtime-contract-kernel.agent.md を実行してください。
対象外の contract を追加せず、unknown な項目は推測せず Notes / assumptions に残してください。
```

### Design test points without implementing tests

```text
runtime-contract-kernel の RC-001 と RC-002 を対象に、test-design-kernel.agent.md を実行してください。
Tests は実装せず、TP ID、Expected observation、stub/fake usage、Required production binding checks を作成してください。
```

### Verify after implementation

```text
実装後の状態について、verification-kernel.agent.md を実行してください。
Test Design Kernel の TP-001 と TP-002 だけを対象にし、production implementation と wiring/entrypoint を確認してください。
Gap は修正せず、verdict と unresolved items を出してください。
```

### Triage unresolved gaps

```text
verification-kernel の unresolved items を対象に、coverage-gap-triage.agent.md を実行してください。
Gap type を分類し、coverage-gap-resolution-slice.agent.md に渡す Downstream selectors を作ってください。
```

### Fix only selected gaps

```text
coverage-gap-triage の Slice 1 だけを対象に、coverage-gap-resolution-slice.agent.md を実行してください。
Selected gap selectors 以外へ scope を広げず、1 回の bounded pass で修正してください。
Done にできない項目は Remaining work に残してください。
```

---

## Artifact naming convention

Token-aware guardrail kernel flow では、通常は次の artifact を作成します。

| Artifact | Purpose |
| --- | --- |
| `plans/<ticket-or-slug>-change-risk-triage.md` | risk profile、selected contracts、recommended profile |
| `plans/<ticket-or-slug>-runtime-contract-kernel.md` | runtime contract、producer / consumer、message、fields、production address |
| `plans/<ticket-or-slug>-test-design-kernel.md` | test point mapping、stub/fake usage、production binding requirement |
| `plans/<ticket-or-slug>-verification-kernel.md` | production binding / wiring / contract verification result |
| `plans/<ticket-or-slug>-coverage-gap-triage.md` | unresolved gap classification と recommended fix slices |
| `plans/<ticket-or-slug>-coverage-gap-resolution-slice.md` | selected gap repair result と remaining work |

---

## Operating principles

- selected scope を明示する
- unknown を推測で埋めない
- test が通ることを production binding の証拠にしない
- fake / stub だけを production completion と扱わない
- Plan を implementation behavior の source of truth とする
- 1 回の bounded pass で停止し、残件は artifact に残す
- `Bound` の正式判定は `verification-kernel.agent.md` に任せる

