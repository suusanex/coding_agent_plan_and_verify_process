# Codex-first AI Development Process

この package は、Codex を第一優先の実行環境として使う cost-aware routing profile である。
ユーザーが普通の開発依頼を投げたら、process 名、agent 名、model 名を尋ねず、`codex-first-cost-router` として扱う。
既存の repo-local `AGENTS.md`、build/test/security ルール、secret / external operation 制約を常に優先する。

## 運用原則

- 短い依頼を cost-aware routing の入口として扱う。
- まず source of truth、repo rules、既存 artifact、state artifact を確認する。
- 必要な工程を Intake / Plan / Risk / Scan / Contract / Implementation / Verification / Close に分ける。
- 各工程を `HIGH_MODEL`、`STANDARD_MODEL`、`CHEAP_MODEL` の抽象 tier へ割り当てる。
- state artifact に Routing Plan、Edit Permission、Agent Usage Ledger、DelegationCompliance を記録する。
- state artifact では execution_mode と、model tier / configured model / hook model / reported model / effective model を分けて記録する。
- Plan gate では behavior expansion decision、Case-to-Plan mapping、Plan readiness を記録し、`ReadyForRiskTriage` になるまで risk / full-coverage / implementation へ進めない。
- `NeedsPlanBehaviorExpansion` は `black-box-behavior-spec-kernel` または Plan rerun へ戻し、full-coverage や fix-slice の代替ルートにしない。
- read-heavy な scan / consistency check は、Routing Plan が要求する場合は低コスト subagent へ委譲する。
- READY 後の通常実装は `standard-implementer` へ serial delegation する。write-heavy parallel editing を標準化しないことは、親が直接実装してよいことを意味しない。
- READY 後の通常 verification は `standard-verifier` へ委譲し、危険な close 判定だけ高性能側へ戻す。
- `DelegationRequired = Yes` の gate は、observed run または explicit human approval 付き `ParentDirectExecutionException` がない限り成功扱いしない。
- 親が委譲予定の作業を直接実行した場合、`PARENT_DIRECT_WORK` または `TRIVIAL_PARENT_FIX` として記録し、cost-saving delegation 成功として扱わない。
- 難しい判断、security / auth / DB / public API / production wiring / close risk は高性能側へ戻す。
- READY でない状態では実装へ進まない。
- close 不可の stop reason を残したまま完了扱いしない。
- secret、課金、外部環境設定、本番操作は自動実行しない。

## モデル階層

| Label | Intended use |
| --- | --- |
| `HIGH_MODEL` | 曖昧な要求整理、bounded Plan、難しい risk triage、implementation contract、危険な close 判定 |
| `STANDARD_MODEL` | READY 後の通常実装、通常 verification、test update、moderate risk の修正 |
| `CHEAP_MODEL` | repo scan、read-heavy inventory、docs consistency、artifact format check、単純局所修正 |

実名モデルはここでは固定しない。組織の契約、利用枠、品質要求に合わせて保守者が対応表を作る。

## 標準ルート

1. `codex-first-cost-router` Skill で依頼を受ける。
2. `plans/<slug>/codex-first-state.md` を作成または更新する。
3. Plan readiness を確認し、必要なら `black-box-behavior-spec-kernel` または Plan rerun へ戻す。
4. Plan / risk / scan / contract のうち、次に安全な工程を 1 つ選ぶ。
5. READY gate を満たすまで implementation へ進まない。
6. READY 後は bounded scope を `standard-implementer` に委譲する。
7. verification は `standard-verifier` に委譲し、production implementation / wiring / manual-only / Behavior Case evidence を分類する。
8. residual decision と DelegationCompliance で close 可否を判定し、必要なら最小の人間入力だけを提示する。

## Advanced route

full-coverage 3層運用は標準ルートではない。
標準 cost-router で安全に bounded 化できない場合、または熟練 operator が明示的に選んだ場合だけ、`codex-full-coverage-3layer` を advanced route 候補として提示する。
初心者向け user guide で full-coverage や agent 名の選択を要求しない。

## 既存 APM package との関係

- 初心者やチーム導入では、この `codex-first-ai-development-process` を使う。
- 既存運用に慣れていて、明示的に flow を選べる場合は `token-aware-guardrail-kernel-flow` または `full-autonomous-plan-first-flow` を直接選択できる。
- この package は既存 package の source を複製せず、同じ agent 群を参照して応用運用だけを追加する。
