# Codex delegation must化 修正ゴール

作成日: 2026-06-07  
対象 repository: `suusanex/coding_agent_plan_and_verify_process`  
対象プロセス:

1. `token-aware-full-coverage-3layer` / Plan網羅チェック full-coverage 3層運用
2. `codex-first-ai-development-process` / Codex-first cost-aware routing

## 0. この文書の位置づけ

この文書は、後続の Plan / 実装のための **ゴール定義** です。  
実装手順そのものではなく、現状の問題点、修正すべき不変条件、完了条件をまとめます。

今回の修正の中心は、次の1点です。

> **「delegate してもよい」ではなく、「この工程は delegate しなければならない」と明示する。**

3層運用では、`slice-prep` は動いたが `slice-impl` が使われず、親エージェントが実装・テスト・検証まで直接進めた実例が確認された。  
Codex-first AI Development Process でも、同じ弱さがある場合、利用者が気づかないまま高価な親モデルが実装・検証まで抱え込み、cost-aware routing の目的を壊す可能性がある。

この文書は、その問題を両プロセス共通で修正するための要求を定義します。

---

## 1. 前提と外部制約

### 1.1 Codex subagent は自動で必ず起動するものではない

Codex は subagent workflow を持つが、subagent は明示的に要求されたときに起動される前提で扱う必要がある。  
そのため、プロセス文書側で「使ってよい」「必要に応じて使う」と書くだけでは、親エージェントが自分で続行する余地が残る。

### 1.2 Skills はワークフロー定義に向くが、実行の強制境界ではない

Codex Skills は再利用可能な workflow を定義するのに適している。  
ただし、skill は「読むべき手順」を与えるものであり、delegate しなかったことを自動で失敗にする仕組みではない。  
したがって、skill 内に delegation gate / audit / ledger / stop reason を明示し、さらに AGENTS / instructions / custom agent 側にも同じ不変条件を置く必要がある。

### 1.3 実績確認は自己申告だけでは弱い

Codex CLI では `/status` で token usage などを確認できるが、agent別・工程別の実行量や wall-clock duration を後から標準UIだけで安定集計できるとは限らない。  
Codex hooks には `SubagentStart` / `SubagentStop` があり、`agent_id` / `agent_type` / `model` / `turn_id` などを記録できるため、後続で実績ログを取りたい場合は hooks と repository-tracked ledger を併用する。

---

## 2. 現状調査: full-coverage 3層運用

### 2.1 現状の良い点

`token-aware-full-coverage-3layer` skill は、3層構造自体を明確に定義している。

- 親エージェントが `slice 実行表`、依存関係、parallel可否、parent review gate を管理する。
- `slice-prep` が per-slice risk / contract / test design artifact を下書きする。
- `slice-impl` が親承認済み slice を実装し、slice-local verification-kernel まで進める。
- 最後に親が cross-slice-verification-kernel と residual-decision-gate を行う。

`slice-prep` agent は `gpt-5.6-terra` / medium / read-only で、production code / tests を編集せず、per-slice artifact を準備する。
`slice-impl` agent は `gpt-5.6-luna` / high / workspace-write で、親が READY と承認した slice だけを実装する。

### 2.2 現状の問題点

#### P3L-001: `slice-prep` / `slice-impl` 利用が must ではなく optional に見える

現状の skill には、次のような弱い表現がある。

- 「親エージェントは、準備可能な slice ごとに `slice-prep` custom agent を使ってよい」
- 「親レビューで READY になった slice だけ、`slice-impl` custom agent に渡してよい」

これは「use may」になっており、「use must」ではない。  
実例として、`slice-prep` だけが3回動き、実装・テスト・検証は親エージェントが直接行った。  
この挙動は、skill の意図には反するが、文言上は完全には封じられていない。

#### P3L-002: 親エージェントの直接編集禁止が明確でない

現状の 3層運用では、親の責務は orchestration / review / final verification である。  
しかし、親エージェントに対して次の不変条件が十分に強く書かれていない。

> 親エージェントは production code / tests を直接編集してはならない。  
> 直接編集できるのは orchestration artifact / review artifact / usage ledger / final summary に限る。

この禁止が弱いと、親が「READYになったので自分で実装する」と判断してしまう。

#### P3L-003: 実装委譲の成否を判定する audit が足りない

現状の最終監査には、次のような確認がある。

- `plan-slice-decomposition` から直接実装していない
- `slice-prep` と parent review gate を通している
- READYでないsliceを実装していない
- cross-slice verification を実行している

しかし、今回検出した問題を捕まえる次の項目がない。

- READY slice がすべて `slice-impl` に渡されたか
- `slice-impl` run が存在しない slice を親が直接実装していないか
- 親が production code / tests を直接編集していないか
- 実装委譲できなかった場合に `PARENT_DIRECT_IMPLEMENTATION_EXCEPTION` として記録したか

#### P3L-004: 3層運用のモードが未定義

現在は「準備だけで止める」「実装まで進める」の例はあるが、実行モードが machine-readable に定義されていない。  
そのため、後から実績を見ても、その実行が「委譲成功」「意図的な親直接実装」「逸脱」なのか分類しにくい。

---

## 3. 現状調査: Codex-first AI Development Process

### 3.1 現状の良い点

Codex-first AI Development Process は、初心者が自然文で依頼するだけで、Codex側が工程分解し、難易度・リスク・必要判断に応じてモデル階層へ自動配分することを最上位ゴールとしている。

現在の設計には、次の良い点がある。

- 利用者に process名 / agent名 / model tier / full-coverage 判断を要求しない。
- `codex-first-cost-router` が intake、state、model tier assignment、agent / subagent delegation choice、READY / close permission を所有する。
- `HIGH_MODEL` / `STANDARD_MODEL` / `CHEAP_MODEL` の抽象 tier を使い、実名モデル対応は組織側に委ねる。
- `plans/<slug>/codex-first-state.md` を state artifact として使う設計がある。
- `standard-implementer`、`standard-verifier`、`cheap-repo-scanner` などの custom agent file がある。

### 3.2 現状の問題点

#### PCF-001: cost-aware routing が「選択」までで止まり、委譲強制になっていない

`codex-first-cost-router` は、工程ごとの tier と agent / subagent delegation choice を持つ。  
しかし、現状の文言は主に「delegate when useful」「subagentを使ってよい」「route normal READY implementation to standard agents」という形であり、親エージェントが直接実装することを明示的に禁止していない。

Codex-first の主目的は、高価な親モデルがすべて抱え込むのを防ぎ、標準実装や軽量調査を低コスト側へ寄せることにある。  
したがって、`recommended model tier = STANDARD_MODEL` または `CHEAP_MODEL` の工程について、親が `HIGH_MODEL` のまま直接実行することを許すと、プロセスの価値が大きく落ちる。

#### PCF-002: 「write-heavy parallel editing は標準化しない」と「write-heavy delegated serial editing」を区別できていない

Codex-first の設計では、write-heavy な並列編集を標準にしない方針は正しい。  
しかし、これが「実装を subagent に渡さず、親が直接やってよい」と解釈される余地がある。

必要な区別は次の通り。

- **禁止または慎重:** write-heavy な *parallel* editing
- **推奨または必須:** READY済み scope の *serial delegated* implementation

つまり、標準実装は `standard-implementer` に1本ずつ委譲し、必要なら直列化すればよい。  
並列化しないことと、委譲しないことは別問題である。

#### PCF-003: `standard-implementer` / `standard-verifier` の model と effort を明示する

現在の profile では、`standard-implementer` は `gpt-5.6-luna` / high、`standard-verifier` は `gpt-5.6-terra` / medium に設定する。
この差は tier label の単純な一律 mapping ではなく、実装と検証の責務に応じた意図的な agent-specific mapping である。

この package は抽象 tier を使う方針なので、実名モデル固定そのものは非ゴールだが、少なくとも default profile では次を明確にすべきである。

- `STANDARD_MODEL` は agent ごとの model / effort を mapping 文書で明示すること
- `CHEAP_MODEL` は read-heavy / simple local work 用であること
- `standard-implementer` は Luna / high、`standard-verifier` は Terra / medium として扱うこと
- 組織導入時に model-tier mapping を必ず確認すること

#### PCF-004: state artifact に「期待された委譲」と「実際の委譲」の記録欄がない

現在の state artifact の最低限フィールドには、`recommended model tier`、`allowed to edit`、`artifacts created / consumed` などがある。  
しかし、効果測定とデバッグに必要な次の情報がない。

- expected agent / subagent
- actual agent / subagent
- delegation required?
- delegation observed?
- parent direct execution occurred?
- parent direct execution exception reason
- model / reasoning effort
- phase owner
- edit owner
- run count
- artifact evidence

これがないと、「結果は出たが、cost-aware routing として成功したのか」を後から判定できない。

#### PCF-005: close / done 判定に delegation compliance が含まれていない

Codex-first は READY / close permission を重要視している。  
しかし、cost-aware process としては「成果物ができた」だけでなく、「適切な tier / agent へ委譲された」ことも成功条件に含めるべきである。

特に初心者向けプロセスでは、利用者が「高価な親モデルが全部やってしまった」ことに気づかない。  
そのため、少なくとも state / final summary / close gate で delegation compliance を記録する必要がある。

---

## 4. 共通修正方針

### 4.1 用語を追加する

両プロセスで共通して次の用語を導入する。

| 用語 | 意味 |
| --- | --- |
| `ExecutionMode` | 今回の実行モード。例: `PREP_ONLY`, `DELEGATED_IMPLEMENTATION`, `PARENT_DIRECT_EXCEPTION` |
| `PhaseOwner` | その工程の判断責任者。例: parent, high-planner, cost-router |
| `EditOwner` | 実際に production code / tests を編集してよい agent |
| `DelegationRequired` | この工程は subagent/custom agent へ委譲必須か |
| `DelegationObserved` | 実際に委譲された証拠があるか |
| `ParentDirectExecutionException` | 親が直接実装した例外。明示承認または不可避理由が必要 |
| `DelegationCompliance` | 期待された委譲と実績が一致しているかの判定 |
| `Agent Usage Ledger` | agent / subagent の期待・実績・成果物を記録する ledger |

### 4.2 MUST / SHOULD / MAY の基準を明確にする

今後の文書では、委譲に関して次を使い分ける。

- `MUST delegate`  
  その工程を親が直接実行してはいけない。委譲できない場合は停止または例外記録が必要。
- `SHOULD delegate`  
  原則委譲するが、極小作業や環境制約では親が行ってよい。ただし ledger に理由を記録する。
- `MAY delegate`  
  効果があれば委譲してよい。cost-aware 成功条件には含めない。

今回の修正対象は、特に `MAY` と書かれているべきでない箇所を `MUST` または `SHOULD` に変えること。

---

## 5. full-coverage 3層運用の修正ゴール

### 5.1 ExecutionMode を必須化する

3層運用 skill は、開始時に次のいずれかの mode を決めて記録する。

| Mode | 意味 | production code / tests 編集 |
| --- | --- | --- |
| `PREP_ONLY` | slice-prep と parent review gate まで | 禁止 |
| `DELEGATED_IMPLEMENTATION` | READY slice を `slice-impl` へ委譲して実装 | 親は禁止、`slice-impl` のみ可 |
| `PARENT_DIRECT_IMPLEMENTATION_EXCEPTION` | 例外的に親が直接実装 | 明示理由とユーザー承認が必要。3層委譲成功とは扱わない |

### 5.2 親エージェントの編集範囲を制限する

3層運用で親エージェントが直接編集してよいのは、原則として次に限定する。

- `plans/*-slice-execution-table.md`
- `plans/*-parent-review-gate.md`
- `plans/*-cross-slice-verification-kernel.md`
- `plans/*-residual-decision-gate.md`
- `plans/*-agent-usage-ledger.md`
- final summary / handoff artifact

親エージェントは、`DELEGATED_IMPLEMENTATION` mode では production code / tests を編集してはならない。

### 5.3 `slice-prep` / `slice-impl` の must条件

#### slice-prep

executable slice について、次のいずれかでなければならない。

- `slice-prep` run が存在する
- parent review gate が、その slice を `BLOCKED` / `NEEDS_HUMAN_DECISION` / `TRIAGE_ONLY` として実装対象外にした
- 明示的な `PARENT_PREP_EXCEPTION` がある

#### slice-impl

`Can implement now? = Yes` かつ `DELEGATED_IMPLEMENTATION` mode の slice について、次の条件を必須にする。

- `slice-impl` run が存在する
- `slice-impl` output が `Slice Implementation Result: SL-xxx` を持つ
- `Agent type: slice-impl` / `Model` / `Reasoning effort` / `Parent authorization artifact` が記録されている
- `Changed files` / `Checks run` / `Verification verdict` が記録されている

これを満たさない場合、親は `BLOCKED_BY_MISSING_SLICE_IMPL_DELEGATION` として停止する。

### 5.4 3層運用の Agent Usage Ledger

3層運用では、次の ledger を必須成果物にする。

```md
# Agent Usage Ledger

## Execution mode

- Mode: PREP_ONLY / DELEGATED_IMPLEMENTATION / PARENT_DIRECT_IMPLEMENTATION_EXCEPTION
- Parent model:
- Parent direct code edit allowed: Yes / No
- Reason if exception:

## Expected delegation

| Phase | Slice | Delegation required | Expected agent type | Expected tier/model | Edit owner | Parallel group |
| --- | --- | --- | --- | --- | --- | --- |

## Observed agent runs

| Run ID | Phase | Slice | Agent name | Agent type | Model | Reasoning effort | Edit allowed | Artifact | Outcome |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Delegation compliance

| Rule | Status | Evidence |
| --- | --- | --- |
| All executable slices passed slice-prep or were blocked | PASS / FAIL | |
| All READY slices were implemented by slice-impl | PASS / FAIL | |
| Parent did not edit production code/tests | PASS / FAIL | |
| Cross-slice verification was run by parent | PASS / FAIL | |
```

### 5.5 Final audit に追加する項目

3層運用 skill の最終監査に次を追加する。

- ExecutionMode が記録されている
- `DELEGATED_IMPLEMENTATION` の場合、親が production code / tests を直接編集していない
- `Can implement now? = Yes` の slice はすべて `slice-impl` に渡されている
- `slice-impl` run が存在しない READY slice は `BLOCKED_BY_MISSING_SLICE_IMPL_DELEGATION`
- `Agent Usage Ledger` が作成・更新されている
- `PARENT_DIRECT_IMPLEMENTATION_EXCEPTION` は明示理由とユーザー承認がある場合だけ許可される
- `PARENT_DIRECT_IMPLEMENTATION_EXCEPTION` は3層委譲成功としてカウントしない

---

## 6. Codex-first AI Development Process の修正ゴール

### 6.1 cost-router が Routing Plan を必ず出す

`codex-first-cost-router` は、実行前に次の routing plan を state artifact に書く。

```md
## Routing Plan

| Gate | Recommended tier | Delegation required | Expected agent type | Edit owner | Parent may execute directly? | Stop if unavailable |
| --- | --- | --- | --- | --- | --- | --- |
```

最低限、次を満たす。

- `CHEAP_MODEL` の read-heavy / docs / artifact format check は原則 delegate。
- `STANDARD_MODEL` の READY implementation / verification は、親が `HIGH_MODEL` 相当で動いている場合は delegate。
- `HIGH_MODEL` の plan / risk / implementation contract / closure risk は親または high agent が担当してよい。
- 親が直接実行してよい gate と、直接実行してはいけない gate を明示する。

### 6.2 `allowed_to_edit` を `EditOwner` として強化する

現在の state artifact の `allowed to edit` を、次のように拡張する。

```md
## Edit Permission

- allowed_to_edit: Yes / No
- edit_owner: parent / standard-implementer / cheap-fixer / human / none
- parent_direct_edit_allowed: Yes / No
- allowed_paths:
- forbidden_paths:
- required_authorization_artifact:
```

READY implementation では、原則として `edit_owner = standard-implementer` にする。  
親が直接編集する場合は `parent_direct_edit_allowed = Yes` とし、理由と承認を記録する。

### 6.3 `standard-implementer` と `standard-verifier` を実際に使わせる

Codex-first の標準実装工程は次を満たすべき。

- Implementation gate が READY になったら、親は `standard-implementer` へ委譲する。
- Verification gate では、親は `standard-verifier` へ委譲する。ただし close が危険な場合は `high-closure-reviewer` へ戻す。
- 親は implementation / verification を直接抱え込まない。
- 委譲できない場合は `DelegationUnavailable` / `NeedsHigherModelReview` / `ParentDirectExecutionException` のいずれかで止める。

### 6.4 `write-heavy parallel editing` と `delegated implementation` を分離する

Codex-first の文書では、次の方針を明記する。

```text
write-heavy parallel editing を標準にしない。
しかし、READY scope の implementation は standard-implementer へ serial delegation する。
並列にしないことは、親が直接実装してよいことを意味しない。
```

### 6.5 model tier mapping の検証を追加する

profile の default mapping は、導入時に次を満たす必要がある。

- `HIGH_MODEL` は高判断・計画・危険判定用。
- `STANDARD_MODEL` は通常実装・検証用で、`HIGH_MODEL` より低コストまたは低effortである。
- `CHEAP_MODEL` は read-heavy / format / docs / simple local fix 用。
- `STANDARD_MODEL` と `HIGH_MODEL` が同じ実名モデルを使う場合、reasoning effort差で cost-aware routing として許容するのか、明示する。
- default profile の agent-specific model / effort と、configured / recommended / observed / reported / effective の各値を混同しないこと。

### 6.6 Codex-first State に Agent Usage Ledger を統合する

`plans/<slug>/codex-first-state.md` に、次を追加する。

```md
## Agent Usage Ledger

### Expected delegation

| Gate | Delegation required | Expected agent | Expected tier | Edit owner | Reason |
| --- | --- | --- | --- | --- | --- |

### Observed runs

| Run ID | Gate | Agent name | Agent type | Model | Reasoning effort | Edited? | Artifact | Outcome |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Delegation compliance

| Check | Status | Evidence |
| --- | --- | --- |
| CHEAP work delegated when required | PASS / FAIL / N/A | |
| STANDARD implementation delegated | PASS / FAIL / N/A | |
| STANDARD verification delegated | PASS / FAIL / N/A | |
| Parent direct execution exception documented | PASS / FAIL / N/A | |
```

### 6.7 close gate に delegation compliance を含める

Codex-first の close gate は、成果物・テスト・residual だけでなく、次も確認する。

- cost-aware routing が期待どおり実行されたか
- 親が直接実装した場合、その理由と承認があるか
- `DelegationRequired = Yes` の gate が未委譲のまま成功扱いされていないか
- 実装成果があるが `standard-implementer` run がない場合、`ReadyToClose` にしない

close可能な状態は、次のいずれかに限る。

- `DelegationCompliance = PASS`
- `DelegationCompliance = EXCEPTION_ACCEPTED` かつ explicit human decision がある

---

## 7. 共通の新しい stop reason / verdict 語彙

両プロセスで次の語彙を追加する。

| Status | 意味 |
| --- | --- |
| `DelegationRequired` | 次工程は委譲必須で、親は直接実行できない |
| `DelegationUnavailable` | 必要な custom agent / subagent が利用できない |
| `DelegationEvidenceMissing` | 委譲されたはずだが run / artifact 証拠がない |
| `ParentDirectExecutionException` | 例外的に親が直接実行した |
| `ParentDirectExecutionNotAllowed` | 親が直接実行してはいけない工程である |
| `RoutingPolicyViolation` | routing plan と実績が一致しない |
| `BlockedByMissingDelegationLedger` | usage ledger がなく評価不能 |
| `BlockedByMissingSliceImplDelegation` | READY slice に slice-impl 実績がない |
| `ReadyForDelegatedImplementation` | 実装準備はできたが、実装 owner は delegated agent |
| `ReadyForDelegatedVerification` | 検証準備はできたが、検証 owner は delegated agent |

---

## 8. 修正対象ファイル候補

### 8.1 full-coverage 3層運用

- `apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md`
  - `slice-prep` / `slice-impl` の利用を `MUST` 化
  - ExecutionMode 追加
  - Parent direct edit prohibition 追加
  - Agent Usage Ledger 追加
  - final audit 強化

- `apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md`
  - 条件付きで弱く読める表現ではなく、`DELEGATED_IMPLEMENTATION` mode では必ず `slice-impl` と明記
  - 親の production code / tests 直接編集禁止を追加

- `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md`
  - output に `Agent type` / `Model` / `Reasoning effort` / `Parent authorization artifact` を追加
  - `Delegation evidence` section を追加

- `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-prep.agent.md`
  - output に `Agent type` / `Model` / `Reasoning effort` を追加
  - parent review へ渡す delegation evidence を追加

### 8.2 Codex-first AI Development Process

- `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md`
  - Routing Plan 必須化
  - `DelegationRequired` と `EditOwner` を導入
  - READY implementation / verification の delegated owner を明記
  - `write-heavy parallel editing` と `serial delegated implementation` の区別を追加

- `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md`
  - `Use subagents as a routing mechanism` を `MUST delegate when gate owner differs from parent tier` に強化
  - main thread の責務を final permission / close decision / state update に限定
  - state artifact の usage ledger 追加

- `apm-packages/codex-first-ai-development-process/profiles/codex-first/AGENTS.md`
  - 普通の依頼時に `codex-first-cost-router` を使うだけでなく、routing plan の delegated gate は必ず custom agent に渡すことを明記

- `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/standard-implementer.toml`
  - cost-aware default として本当に低コスト側にするか、same-model-lower-effort を文書化
  - output に Agent Usage Ledger 用 metadata を追加

- `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/standard-verifier.toml`
  - output に delegation evidence と close blocker を追加

- `apm-packages/codex-first-ai-development-process/docs/codex-first-ai-development-process.md`
  - 標準ルートの implementation / verification が delegated serial work であることを明記
  - 直接親実行は exception として扱う

- `apm-packages/codex-first-ai-development-process/docs/user-guide.md`
  - ユーザーが agent を選ばなくてよい説明は維持
  - ただし内部的に低コストagentへ委譲されること、結果には usage summary が出ることを説明

- `apm-packages/codex-first-ai-development-process/docs/maintainer-guide.md`
  - model tier mapping の検証方法
  - hooks / ledger を使った実績確認方法
  - standard profile の mapping が高価モデルに偏った場合の危険を説明

- `apm-packages/codex-first-ai-development-process/templates/model-tier-mapping.example.md`
  - `HIGH_MODEL` / `STANDARD_MODEL` / `CHEAP_MODEL` の差分が実際に存在することを確認する欄を追加

---

## 9. 実績ログ / デバッグループのゴール

### 9.1 repository-tracked ledger を必須にする

実績ログは、Codexの自己申告だけに頼らず、成果物として残す。  
最低限、次を各 run で記録する。

- session id（分かる場合）
- task slug
- gate
- expected tier
- expected agent
- actual agent
- model
- reasoning effort
- edit owner
- changed files
- checks run
- outcome
- parent direct execution の有無
- exception reason

### 9.2 hooks は推奨ローカル設定として提供する

Codex hooks で `SubagentStart` / `SubagentStop` を JSONL に出す sample を提供する。  
ただし、hooks は環境依存なので、プロセスの唯一の成功条件にはしない。  
repository-tracked ledger を主、hooks を補助証跡にする。

### 9.3 効果測定指標

両プロセスで、最低限次の指標を見られるようにする。

| Metric | 意味 |
| --- | --- |
| `expected_delegated_runs` | routing / parent review が要求した委譲回数 |
| `observed_delegated_runs` | 実際に確認できた委譲回数 |
| `parent_direct_code_edit_count` | 親が直接 code / tests を編集した回数 |
| `delegation_compliance_rate` | 委譲要求に対する実績率 |
| `high_model_implementation_count` | 高価モデルが実装を抱えた回数 |
| `standard_implementation_count` | 標準agentが実装した回数 |
| `cheap_scan_count` | cheap agent が read-heavy scan を担当した回数 |
| `delegation_exception_count` | 例外として親直接実装した回数 |
| `blocked_by_delegation_count` | 委譲不可で止めた回数 |

---

## 10. 完了条件

この修正が完了したと判断できる条件は次の通り。

### 10.1 文書上の完了条件

- full-coverage 3層運用で、READY slice の実装は `slice-impl` に `MUST delegate` と書かれている。
- full-coverage 3層運用で、親エージェントの production code / tests 直接編集が明示禁止されている。
- Codex-first で、READY implementation は `standard-implementer` に `MUST delegate` または `SHOULD delegate with recorded exception` として定義されている。
- Codex-first で、READY verification は `standard-verifier` に `MUST delegate` または `SHOULD delegate with recorded exception` として定義されている。
- `write-heavy parallel editing` と `serial delegated implementation` が明確に区別されている。
- state artifact / Agent Usage Ledger に expected vs observed delegation が記録される。
- close / final audit に `DelegationCompliance` が含まれる。

### 10.2 実行上の完了条件

#### 3層運用のテストケース

入力:

```text
$token-aware-full-coverage-3layer を使って進めてください。
parent review gate で READY になった slice だけ実装してください。
```

期待:

- `slice-prep` が executable slice ごとに動く、または blocked reason が記録される。
- parent review gate が `Can implement now?` を出す。
- `DELEGATED_IMPLEMENTATION` mode では、READY slice ごとに `slice-impl` run が存在する。
- 親が production code / tests を直接編集しない。
- `Agent Usage Ledger` に expected / observed runs が残る。
- `slice-impl` run が欠けた場合は `BlockedByMissingSliceImplDelegation` で止まる。

#### Codex-first のテストケース

入力:

```text
この issue を進めてください。
```

期待:

- 利用者に process / agent / model を選ばせない。
- `codex-first-state.md` が作成または更新される。
- Routing Plan が作成される。
- READY implementation の EditOwner が `standard-implementer` になる。
- 親が直接実装する場合は `ParentDirectExecutionException` と理由が記録される。
- 実装後、`standard-verifier` または `high-closure-reviewer` による verification / closure review が行われる。
- close gate が DelegationCompliance を見る。

### 10.3 回帰判定

次の実績が出たら、修正は不十分と判定する。

- `slice-prep` は動くが `slice-impl` が0件のまま親が実装する。
- `recommended_model_tier = STANDARD_MODEL` の implementation を親の `HIGH_MODEL` が直接実行する。
- `cheap-repo-scanner` 相当の read-heavy scan を親が大量に抱える。
- final summary に agent usage / delegation compliance がない。
- state artifact に expected delegation はあるが observed run がないのに成功扱いされる。
- parent direct implementation が例外記録なしに行われる。

---

## 11. 非ゴール

今回の修正でやらないこと。

- Codex の標準UIだけで正確な agent別 token usage を保証すること。
- write-heavy な並列編集を標準化すること。
- すべての実名モデルをこの repository で固定すること。
- full-coverage 3層運用を Codex-first の標準ルートにすること。
- hooks なしで wall-clock duration を正確に取れると主張すること。
- 親エージェントを一切使わない構成にすること。親は orchestration / permission / close decision に必要。

---

## 12. 実装時の優先順位

### Priority 0: 逸脱防止

1. 3層運用 skill に ExecutionMode と parent direct edit prohibition を入れる。
2. READY slice は `slice-impl` に `MUST delegate` と明記する。
3. Codex-first cost-router に Routing Plan / EditOwner / DelegationRequired を追加する。
4. Agent Usage Ledger を state / 3層運用に追加する。

### Priority 1: 効果測定

1. expected vs observed delegation を成果物へ残す。
2. final audit / close gate に DelegationCompliance を追加する。
3. `standard-implementer` / `standard-verifier` の output に model / reasoning / artifact evidence を追加する。
4. hooks sample を maintainer guide に追加する。

### Priority 2: model tier mapping の整備

1. default profile の `STANDARD_MODEL` が本当に lower-cost か確認する。
2. `same-model-lower-effort` を許容するなら、その意図と限界を明記する。
3. 導入組織が mapping を差し替える場所を明確にする。

---

## 13. 調査メモ: 主な参照箇所

### Repository 内

- `README.md`
  - Plan網羅チェック・残件判定フローの典型手順、full-coverage handling、3層運用の位置づけ。
- `apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md`
  - 3層運用 skill。現状は `slice-prep` / `slice-impl` について `使ってよい` 系の optional 表現が残る。
- `apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md`
  - full-coverage 3層運用の project guidance。
- `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-prep.agent.md`
  - read-only の slice preparation agent。
- `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md`
  - workspace-write の slice implementation agent。
- `docs/codex-first-cost-aware-process-goals.md`
  - Codex-first の最上位ゴール。初心者に agent / model / process 選択を要求しないこと、cost-aware routing が目的であることを定義。
- `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md`
  - Codex-first の routing skill。model tier assignment と delegation choice を持つが、must delegation が弱い。
- `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md`
  - Codex-first の entry behavior / required gates / cost-aware routing。
- `apm-packages/codex-first-ai-development-process/profiles/codex-first/AGENTS.md`
  - profile entry rule。
- `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/*.toml`
  - `high-planner`、`high-risk-triage`、`standard-implementer`、`standard-verifier`、`cheap-repo-scanner` などの実体。

### Codex 仕様側

- subagent は明示的に要求された場合に起動される前提。
- custom agents は `.codex/agents/` または user-level agents で定義できる。
- Skills は reusable workflow として使えるが、skill instructions が実行強制そのものになるわけではない。
- Hooks には `SubagentStart` / `SubagentStop` があり、agent別実績ログの補助に使える。
- `/status` と `/statusline` は現在セッションや token counters の確認に使えるが、repository-tracked な効果測定には ledger が必要。
