# Codex-first Cost-aware Development Process Goal Document

作成日: 2026-06-06  
対象: `suusanex/coding_agent_plan_and_verify_process` の `apm-packages/codex-first-ai-development-process`  
位置づけ: 後続の Plan / 実装が満たすべきゴール定義。詳細な実装手順ではなく、目的・境界・完成条件を漏れなく定義する。

---

## 1. 背景

勤務先では Codex と GitHub Copilot を併用している。費用面では、まず Codex のサブスク枠を優先して使い、Codex の枠が不足した場合や利用者の環境都合がある場合に GitHub Copilot を fallback として使う方針を想定している。

一方で、AI活用に詳しくない利用者は、Planモード、Codex App / CLI、モデル切替、工程分割、subagent、full-coverage 分岐などを意識して使うことが難しい。現状では、VS Code Chat や Codex へ「この issue やって」「この機能を実装して」のように一括依頼し、設計から実装・確認までを1プロンプトで済ませようとしがちである。

熟練者であれば、課題の難所を上位モデルへ、簡単な調査・整合確認・局所実装を下位モデルへ割り当てる手動運用ができる。しかし、この判断を利用者に要求すると、そもそも初心者向けのプロセスパックとして成立しない。

この文書は、`Codex-first AI Development Process` を「3層運用の標準化」ではなく、**Codexで事前定義されたagent / subagent / team profileを使い、難しい工程は上位モデル、軽い工程は下位モデルへ自動的に寄せる cost-aware routing の標準運用**として再定義する。

---

## 2. 最上位ゴール

`codex-first-ai-development-process` は、利用者が通常の開発依頼を自然文で投げるだけで、Codex 側が作業を工程分解し、各工程の難易度・リスク・必要な判断に応じて適切なモデル階層へ自動配分するプロセスパックでなければならない。

利用者は、次のような依頼だけでよい。

```text
この issue を進めて。
このバグを直して。
この機能を実装して。
この PR の残件を片付けて。
続きやって。
```

利用者に、次の判断やプロンプト投入を要求してはならない。

- `Codex-first AI Development Process で進めて` と明示すること
- `full-coverage` かどうかを判断すること
- `3層運用` を使うかどうかを判断すること
- `plan-kernel`、`change-risk-triage`、`implementation-handoff-review` などの agent 名を選ぶこと
- `HIGH_MODEL` / `STANDARD_MODEL` / `CHEAP_MODEL` を選ぶこと
- `subagent` や `parallel agent` を使うタイミングを判断すること
- READY / close / residual の判定を利用者側で行うこと

---

## 3. この文書での重要な設計転換

### 3.1 3層運用は標準ルートにしない

既存の Codex 向け full-coverage 3層運用は、重要な既存資産である。ただし、このプロセスパックの主目的は、3層運用を初心者向け標準ルートに入れることではない。

3層運用は次の位置づけにする。

- 熟練 operator 向けの高度運用
- full-coverage な大規模変更で、コストをかけても並列化・加速したい場合の選択肢
- 複数sliceの親管理、slice-prep、slice-impl、cross-slice verification が必要な場合の advanced route
- 標準 user guide では利用者に判断させない
- 標準 cost-aware routing の内部実装として常用しない

標準ルートでは、3層運用の思想のうち、次だけを借りる。

- 親が判断・方針・状態を握る
- 下位作業者には bounded な作業だけを渡す
- 実装前に READY gate を置く
- 軽い作業や読取中心作業は低コスト側へ寄せる
- 難しい判断は上位モデル側へ寄せる

### 3.2 中核は cost-aware routing

中核成果物は `codex-first-cost-router` である。

`codex-first-cost-router` は、ユーザーの雑な依頼を受け取り、次を行う。

1. 作業の意図を読む
2. 必要な状態・既存artifactを確認する
3. 作業を工程へ分解する
4. 各工程を HIGH / STANDARD / CHEAP のモデル階層へ分類する
5. 必要に応じて事前定義agent / subagentへ委譲する
6. 実装してよい状態でない場合は実装しない
7. 実行結果・残件・次工程を状態artifactへ保存する
8. 利用者には、必要最小限の次アクションだけを提示する

---

## 4. 対象ユーザー

### 4.1 主対象

主対象は、次のような利用者である。

- Codex App / CLI / IDE extension の違いに詳しくない
- Planモードや段階的なAI依頼に慣れていない
- モデル切替をほとんど使っていない
- `AGENTS.md`、subagent、Skills、APM package の意味を知らない
- VS Code Chat や Codex へ1プロンプトで大きな依頼を出しがち
- ただし、AIを使って開発を前進させたい意思はある

この層に対して、プロセス理解を要求するのではなく、**プロセスを入口へ埋め込む**ことを目標とする。

### 4.2 副対象

副対象は、次のような利用者である。

- AI活用に慣れている開発者
- Codex / Copilot の運用コストを管理したい人
- チーム向けに標準プロファイルを整備する人
- `coding_agent_plan_and_verify_process` を保守する人
- full-coverage 3層運用など高度運用を明示的に選べる熟練 operator

副対象向けには maintainer guide / advanced guide で詳細を提供する。ただし、主対象向け user guide に高度判断を露出させない。

---

## 5. Codex仕様に基づく前提

このプロセスは、Codex の次の性質を前提にする。

### 5.1 AGENTS.md の layering

Codex は作業前に `AGENTS.md` 系の指示を読む。グローバルスコープ、プロジェクトルート、現在の作業ディレクトリへ向かう順に instruction chain を構成し、後ろに来るより近い指示が前の指示を上書きしやすい。

したがって、team profile 側の global `AGENTS.md` と、対象リポジトリ側の既存 `AGENTS.md` は、基本的に置き換えではなく layered に読まれる前提で設計する。

ただし、次に注意する。

- 同一階層に `AGENTS.override.md` がある場合、その階層では通常の `AGENTS.md` が無視される
- Codex は combined guidance のサイズ上限に達するとそれ以上追加しない
- そのため、team profile の global `AGENTS.md` は短く保つ
- 詳細は Skills / docs / templates へ逃がす
- 既存リポジトリの instruction が大きい場合は bootstrap / dry-run merge が必要になる可能性がある

### 5.2 subagent は目的ではなく手段

Codex の subagent workflow は、探索・テスト・triage・要約など read-heavy な作業を main thread から分離するのに向く。一方で、write-heavy な並列編集は競合や調整コストが増える。

このプロセスでは、subagent を「3層運用の標準化」ではなく、**モデル階層ごとの役割分担を実現する手段**として扱う。

### 5.3 subagent は明示的に使わせる必要がある

Codex は subagent を完全自動で勝手にspawnするものではなく、subagent / parallel agent work を使うよう明示されたときに使う前提で設計する。

したがって、team profile / launcher / global `AGENTS.md` / cost-router skill のいずれかで、次を明示する必要がある。

- このプロセスでは、必要に応じて事前定義subagentへ委譲してよい
- subagent委譲はモデルtier分担のために使う
- read-heavy 作業や軽量確認は低コストsubagentへ寄せてよい
- 難しい判断は高性能agentへ寄せる
- full-coverage 3層運用は標準ルートではなく advanced route として扱う

### 5.4 モデル名は固定しない

Codex では agent file や prompt で model / reasoning effort を指定できるが、組織の契約・時期・利用枠によって最適な実名モデルは変わる。

このプロセスパックは、実名モデルではなく次の抽象ラベルを使う。

- `HIGH_MODEL`
- `STANDARD_MODEL`
- `CHEAP_MODEL`

実名モデル対応表は、導入組織またはチームの責務として別に持つ。

---

## 6. 期待する利用体験

### 6.1 初回依頼

利用者は、普通に依頼する。

```text
この issue を進めて。
```

Codex は次を自動で行う。

- Codex-first cost-aware process の対象として扱う
- いきなり実装しない
- 既存 `AGENTS.md` / repo rules / build rules を読む
- 必要な既存artifactを探す
- Plan / triage / scan / implementation / verification のどこから始めるべきか判断する
- 必要なら state artifact を作る
- 今回実行する次工程を1つ選ぶ
- その工程に適切な model tier / agent / subagent を割り当てる

### 6.2 継続依頼

利用者は、次のように依頼できる。

```text
続きやって。
```

Codex は次を自動で行う。

- 最新の state artifact を探す
- `current_gate` / `next_gate` / `stop_reason` / `allowed_to_edit` を読む
- 次に実行してよい工程だけを実行する
- state artifact を更新する
- READYでない状態では実装しない
- close不可ならcloseしない

### 6.3 停止時

Codex は、止まる必要があるときだけ止まる。

止まる理由は、次のように明示される。

- `NeedsHumanDecision`
- `ManualVerificationRequired`
- `NeedsHigherModelReview`
- `NeedsSecretInput`
- `NeedsExternalOperation`
- `Blocked`
- `TooCostlyForCurrentPass`
- `ReadyButAwaitingHumanApproval`

利用者には、必要な質問を1つまたはまとまった最小単位で提示する。工程名やagent名を選ばせない。

---

## 7. 標準ルートのゴール

標準ルートは、full-coverage 3層運用ではなく、cost-aware routing とする。

### 7.1 Intake / Request understanding

ゴール:

- ユーザーの雑な依頼を受け取れる
- process名やagent名がなくても開始できる
- issue / PR / branch / file / supplied text などの入力を識別できる
- 不明点があっても、すぐに質問せず、作業仮説と不足情報を分ける
- いきなり実装に進まない

推奨 tier:

- 通常: `STANDARD_MODEL`
- 曖昧・広範囲・高リスク: `HIGH_MODEL`

### 7.2 Plan / Goal framing

ゴール:

- 依頼を bounded な作業単位へ整理する
- Parent Plan または equivalent artifact を作る
- Completion Criteria / Acceptance Criteria / Non-goals を明確にする
- 後続工程で source of truth として読める形にする
- 既存の Plan網羅チェック・残件判定フローと整合する

推奨 tier:

- 原則 `HIGH_MODEL`
- 小さく明確な修正では `STANDARD_MODEL` でもよい

### 7.3 Risk triage

ゴール:

- 実装前にリスクを分類する
- 外部API、SDK、DI、config、public API、DB、auth、非同期処理、production wiring などを検出する
- 難しい判断が必要な場合は上位モデルへ寄せる
- 3層運用へ自動で入るのではなく、標準cost-router内で扱えるかを判断する
- 3層運用が必要なほど大きい場合は advanced route として停止または熟練者判断へ回す

推奨 tier:

- 通常 `STANDARD_MODEL`
- broad / ambiguous / strongly interconnected / security / DB / auth / production wiring では `HIGH_MODEL`

### 7.4 Repository scan / evidence collection

ゴール:

- read-heavy な調査を低コスト化する
- 既存コード、構成、ファイル位置、API surface、テスト位置を確認する
- main thread を汚さない
- raw output ではなく要約を返す
- 実装判断を勝手に行わない

推奨 tier:

- `CHEAP_MODEL`
- API surface が曖昧で実装判断に直結する場合は `STANDARD_MODEL`

### 7.5 Implementation contract / design decision

ゴール:

- 実装方法、採用API、代替可否、禁止する近傍実装流用を決める
- 依存関係やSDK/API surfaceが不明なまま実装しない
- implementation-realization risk がある場合に上位モデルへ寄せる
- 必要な human decision を分離する

推奨 tier:

- 原則 `HIGH_MODEL`
- 小規模でAPI surfaceが明確なら `STANDARD_MODEL`

### 7.6 Implementation

ゴール:

- READYになった範囲だけ実装する
- Parent Plan / contract / handoff を無視しない
- Plan外の大規模リファクタへ広げない
- ビルド失敗やテスト失敗時に無限試行しない
- repo固有の build/test 制約を優先する
- 外部API、本番環境、secret操作を勝手に実行しない

推奨 tier:

- 通常 `STANDARD_MODEL`
- 単純・局所・明確な修正では `CHEAP_MODEL`
- 実装中に設計判断が必要になった場合は停止し、`HIGH_MODEL` 側へ戻す

### 7.7 Test / verification

ゴール:

- 実装結果が Parent Plan / Acceptance Criteria に対応しているか確認する
- fake / mock / stub だけの成功を production 成功扱いしない
- production implementation / production wiring / entrypoint を確認する
- manual-only な確認を明示する
- close判定の材料を作る

推奨 tier:

- 通常 `STANDARD_MODEL`
- 形式的な差分・文書整合は `CHEAP_MODEL`
- close判断が危険な場合は `HIGH_MODEL`

### 7.8 Close / residual decision

ゴール:

- `ManualVerificationRequired`、`NeedsHumanDecision`、`NeedsHigherModelReview` が残る場合はcloseしない
- residual を記録しただけで解決扱いにしない
- explicit human decision が必要なものを明確にする
- `READY_TO_CLOSE` と `READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS` を区別する
- 完了判定は Parent Plan Coverage Ledger / Residual Decision Ledger と整合する

推奨 tier:

- 通常 `STANDARD_MODEL`
- 影響範囲が広い、判断が難しい、残件が多い場合は `HIGH_MODEL`

---

## 8. 必須成果物

### 8.1 Team profile / launcher

ゴール:

- チーム共通の Codex-first profile を提供する
- `CODEX_HOME` などを使い、既存リポジトリへ直接変更しなくても導入できる
- global `AGENTS.md` / config / agents / skills を含む
- 通常の Codex 起動よりも、cost-aware routing が有効になることが明確である

想定名:

```text
codex-first
codex-first-start
```

満たすべきこと:

- 対象リポジトリの既存 `AGENTS.md` と共存する
- repo-specific rules を弱めない
- build/test/security のrepo固有ルールを優先する
- global instruction は短くする
- 詳細は Skills / docs / templates へ逃がす

### 8.2 Global AGENTS.md

ゴール:

- 普通の開発依頼を Codex-first cost-aware routing として扱う
- 利用者に process名・agent名・model名を要求しない
- 必要に応じて subagent delegation を使ってよいことを明示する
- subagent はモデルtier分担の手段であり、3層運用標準化ではないことを明記する
- full-coverage 3層運用は advanced route として分離する
- repo-local `AGENTS.md` の指示を尊重する

### 8.3 Cost Router Skill

ゴール:

- cost-aware routing の中核になる
- 入力を工程へ分解する
- 各工程に model tier を割り当てる
- subagent / agent の利用可否を判断する
- state artifact を作成・更新する
- READYでない実装を防ぐ
- close不可状態をcloseしない
- ユーザーに工程選択を要求しない

必要な出力:

- 現在の工程
- 次の工程
- 推奨model tier
- 実装可否
- stop reason
- human-required事項
- residual事項
- 使った / 使うべき agent or subagent
- 次にユーザーへ求める最小入力

### 8.4 Predefined agents / subagents

ゴール:

事前定義されたagent / subagentによって、モデル階層を分担できること。

最低限の候補:

- `high-planner`
- `high-risk-triage`
- `high-implementation-contract`
- `high-closure-reviewer`
- `standard-implementer`
- `standard-verifier`
- `cheap-repo-scanner`
- `cheap-doc-consistency`
- `cheap-artifact-format-checker`

各agentは次を持つ。

- 役割
- model tier
- reasoning effort
- editing allowed / read-only
- 入力
- 出力
- 禁止事項
- 失敗時の stop reason

実名モデルは固定しない。抽象ラベルで指定し、導入組織が対応表を持つ。

### 8.5 State artifact

ゴール:

- 「続きやって」で再開できる
- ユーザーが工程を覚える必要をなくす
- 現在地・次工程・実装可否・stop reason を明示する
- モデルtier分担の判断を記録する
- 途中中断後も同じ方針で再開できる

想定パス:

```text
plans/<slug>/codex-first-state.md
```

最低限含める情報:

- task slug
- original user intent
- current gate
- next gate
- recommended model tier
- allowed to edit
- current status
- stop reason
- human required items
- artifacts created / consumed
- unresolved residuals
- next action
- operations not allowed in current state
- last updated summary

### 8.6 User Guide

ゴール:

- 短くする
- process名やagent名を利用者に覚えさせない
- full-coverage 3層運用を標準利用者に判断させない
- 利用者が普通に依頼すればよいことを説明する
- 止まったときの見方だけ説明する

User Guide に載せるべき例:

```text
この issue を進めて。
このバグを直して。
この機能を実装して。
続きやって。
```

User Guide から消すべきもの:

- `codex-full-coverage-3layer を使って` のようなプロンプト例
- `token-aware-guardrail-kernel-flow` を直接指定させる説明
- agent名の一覧をユーザーに選ばせる説明
- model tierをユーザーに選ばせる説明

### 8.7 Maintainer Guide

ゴール:

- team profile / launcher の構成を説明する
- global AGENTS と repo AGENTS の layering を説明する
- `AGENTS.override.md` の注意点を説明する
- instruction size limit による欠落リスクを説明する
- repo bootstrap / dry-run merge が必要になる条件を説明する
- モデル実名対応表は組織管理であることを説明する
- full-coverage 3層運用は advanced route であることを説明する

### 8.8 Bootstrap / merge support

ゴール:

team profile だけで足りないリポジトリ向けに、既存リソースへ安全に統合する手段を用意する。

最低限、後続計画に含めるべきこと:

- 既存 `AGENTS.md` / `AGENTS.override.md` / `.codex` / scripts の検出
- instruction size の概算
- 既存ルールとの衝突検出
- dry-run 出力
- 追記案の提示
- ユーザー承認後のみ変更
- repo固有build/test/securityルールを優先することの明記
- 既存リソースを破壊しないこと
- 自動マージできない場合はレポートして停止

---

## 9. モデル階層ゴール

### 9.1 HIGH_MODEL

用途:

- 要件理解が曖昧
- bounded Plan作成
- risk triage が難しい
- implementation contract 判断
- SDK/API/外部仕様の採否
- セキュリティ・認可・DB・migration・public API
- close判定が危険
- residualを受け入れてよいかの判断

ゴール:

- 誤った方向の実装を防ぐ
- 難しい判断だけに使う
- 長時間の実装ループに使わない

### 9.2 STANDARD_MODEL

用途:

- READY後の通常実装
- 通常verification
- test design / test update
- code review focus
- moderate risk な修正
- handoff review

ゴール:

- 実装の主戦力にする
- 判断が重くなったら HIGH_MODEL へ戻す
- 不明なまま突き進まない

### 9.3 CHEAP_MODEL

用途:

- repo scan
- read-heavy exploration
- docs consistency
- artifact formatting
- simple test additions
- simple local fixes
- grep / inventory / summary
- large-file read-only review

ゴール:

- token / credit / time を節約する
- main thread のcontext pollutionを防ぐ
- 判断の最終責任を持たせない
- 書き込みは限定する

---

## 10. Advanced route: full-coverage 3層運用

full-coverage 3層運用は、標準ルートの一部ではない。

次の場合だけ advanced route として扱う。

- 熟練 operator が明示的に選ぶ
- コストをかけても並列化・加速したい
- 変更が大規模で、親・slice-prep・slice-implの分離が必要
- cross-slice contract / field continuity / production wiring が複雑
- 標準cost-routerでは安全に bounded 化できない

標準 user guide では、full-coverage 3層運用のプロンプト例を示さない。  
maintainer / advanced guide には、別章として配置する。

---

## 11. 非目的

このプロセスパックは、次を目的にしない。

- full-coverage 3層運用を初心者向け標準ルートにすること
- 利用者に正しいプロンプト投入を教育すること
- 利用者にagent名やmodel名を覚えさせること
- 実名モデルを固定すること
- すべてを上位モデルで動かすこと
- すべてを下位モデルで安く済ませること
- AIが本番環境・外部API・secret・課金操作を自動実行すること
- 既存リポジトリの `AGENTS.md` や build/test ルールを上書きすること
- GitHub Copilot fallback を最初の主成果物にすること
- 人間判断を完全になくすこと
- 失敗時に無限試行すること

---

## 12. 成功条件

### 12.1 ユーザー体験の成功条件

- 利用者は「この issue を進めて」だけで開始できる
- 利用者は「続きやって」だけで再開できる
- 利用者は process名を知らなくてよい
- 利用者は full-coverage / 3層運用を判断しなくてよい
- 利用者は model tier を選ばなくてよい
- 利用者は agent / subagent を選ばなくてよい
- 止まった場合、必要な人間判断だけが示される

### 12.2 cost-aware routing の成功条件

- 難しい判断が HIGH_MODEL に寄る
- 通常実装が STANDARD_MODEL に寄る
- read-heavy scan / docs consistency / simple format check が CHEAP_MODEL に寄る
- subagent はモデル分担の手段として使われる
- write-heavy な並列編集を標準化しない
- main thread に探索ログや大量出力を溜めすぎない
- 実名モデルを固定しない

### 12.3 safety / quality の成功条件

- READYでない状態で実装しない
- Parent Plan / acceptance criteria を縮小しない
- fake / mock / stub の成功だけで production 完了扱いしない
- ManualVerificationRequired を残して close しない
- NeedsHumanDecision を残して close しない
- NeedsHigherModelReview を残して close しない
- external operation / secret / production access を勝手に実行しない
- repo固有の build/test/security ルールを優先する

### 12.4 rollout の成功条件

- team profile / launcher で既存repoに非破壊導入できる
- global AGENTS と repo AGENTS の layering を前提にできる
- `AGENTS.override.md` や size limit の注意が文書化されている
- 既存repoへ明示統合が必要な場合の bootstrap / dry-run merge 方針がある
- Copilot fallback は後続として分離されている

---

## 13. 受け入れテスト観点

### 13.1 novice request

入力:

```text
この issue を進めて。
```

期待:

- Codex-first cost-aware routing として扱う
- process名を要求しない
- いきなり実装しない
- Plan / triage / scan のどこから始めるか判断する
- 推奨model tierを内部記録する
- state artifact を作る、または更新する

### 13.2 resume request

入力:

```text
続きやって。
```

期待:

- state artifact を読む
- next gate を1つ実行する
- 実装可否を確認する
- state artifact を更新する
- 利用者にagent名を尋ねない

### 13.3 simple local fix

入力:

```text
このtypoを直して。
```

期待:

- CHEAP_MODEL または低コスト相当で処理できる
- 不要なPlan-heavy flowに入らない
- ただし repo rules は読む
- 必要以上に広範囲探索しない

### 13.4 ambiguous high-risk change

入力:

```text
認証まわりの処理を直して。
```

期待:

- HIGH_MODEL 側へ寄る
- いきなり実装しない
- human decision / risk triage / implementation contract が必要か判断する
- security/auth を軽い修正扱いしない

### 13.5 full-coverage advanced boundary

入力:

```text
この大規模変更を並列化して進めたい。
```

期待:

- 標準ルートではなく advanced route 候補として扱う
- full-coverage 3層運用が必要か判断する
- 熟練 operator 向けの確認に回す
- 初心者向け標準user guideには露出しない

### 13.6 existing repo AGENTS

前提:

- 対象repoに既存 `AGENTS.md` がある

期待:

- team profile の global guidance と repo guidance が layered に扱われる
- repo固有の build/test/security ルールが優先される
- 置き換え前提で壊さない

### 13.7 AGENTS.override / size limit

前提:

- 対象repoに `AGENTS.override.md` がある
- または instruction が大きい

期待:

- リスクを検出できる
- bootstrap / dry-run merge の必要性をレポートできる
- 自動破壊しない

---

## 14. ドキュメント構成ゴール

最終的に、少なくとも次の文書が必要である。

```text
apm-packages/codex-first-ai-development-process/
  docs/
    user-guide.md
    maintainer-guide.md
    cost-router-goals.md
    team-profile-launcher.md
    bootstrap-and-merge-policy.md
    advanced-full-coverage-3layer.md
    examples/
      novice-issue-request.md
      resume-from-state.md
      simple-local-fix.md
      ambiguous-high-risk-change.md
      existing-agents-layering.md
```

`user-guide.md` は短く、初心者向け。  
`maintainer-guide.md` は導入・保守者向け。  
`advanced-full-coverage-3layer.md` は熟練者向けで、標準ルートから分離する。

---

## 15. 実装成果物構成ゴール

実装成果物は、少なくとも次を満たす。

```text
apm-packages/codex-first-ai-development-process/
  apm.yml
  AGENTS.md
  .apm/
    skills/
      codex-first-cost-router/
        SKILL.md
  .codex/
    agents/
      high-planner.toml
      high-risk-triage.toml
      high-implementation-contract.toml
      high-closure-reviewer.toml
      standard-implementer.toml
      standard-verifier.toml
      cheap-repo-scanner.toml
      cheap-doc-consistency.toml
      cheap-artifact-format-checker.toml
  templates/
    codex-first-state.md
    stop-report.md
    model-tier-mapping.example.md
```

この構成は目標例であり、後続Planでよりよい配置が示される場合は変更してよい。  
ただし、次のゴールは変えてはならない。

- cost-router が中核である
- model tier 分担が中核である
- full-coverage 3層運用は advanced route である
- user guide は初心者に判断を要求しない
- team profile / launcher を第一級の導入手段として扱う

---

## 16. 完了判定

このゴール文書を満たす実装は、次を満たす必要がある。

- `user-guide.md` から、ユーザーにagent名・skill名・full-coverage分岐を指定させる説明が消えている
- `codex-first-cost-router` のゴール・役割・入出力が定義されている
- model tierごとの責務が明確である
- 事前定義agent / subagent が、モデルtier分担のために設計されている
- team profile / launcher 方式が文書化されている
- global AGENTS と repo AGENTS の layering と注意点が文書化されている
- repo bootstrap / dry-run merge の必要条件が文書化されている
- full-coverage 3層運用が advanced route として分離されている
- novice request / resume request の受け入れ観点がある
- READYでない実装、close不可状態のclose、無限試行、外部副作用が防止されている
- 実名モデルに依存していない
- GitHub Copilot fallback は後続扱いになっている

---

## 17. 後続Planへの期待

後続のPlanでは、この文書を source of truth として、次を決める。

- 既存 `apm-packages/codex-first-ai-development-process` のどのファイルを修正するか
- どの既存agent / skill / packageを再利用するか
- どの新規 skill / agent / template を追加するか
- team profile / launcher をどの形で表現するか
- bootstrap / merge support を今回実装するか、後続WorkItemへ分けるか
- user guide / maintainer guide / advanced guide をどう分離するか
- サンプルと受け入れテストをどこへ置くか

後続の実装では、この文書に書かれたゴールを削って進めてはならない。  
実装上の制約で一部を満たせない場合は、その制約を明示し、代替案または未達項目として残す。

---

## 18. 参考情報

この文書は、Codex の AGENTS.md discovery / layering、subagent workflow、agentごとの model / reasoning effort 設定、read-heavy subagent の適性、write-heavy 並列作業の注意点を前提にしている。これらの具体的な実装可否や構文は、後続Plan作成時に最新のCodex公式ドキュメントで再確認する。
