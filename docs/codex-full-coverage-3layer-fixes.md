# Codex 3層運用 agent 定義 修正ゴール

> Status update (2026-07-14): この文書は `slice-impl` を標準 owner としていた時点の調査・修正履歴です。Issue #44 以降、`slice-impl` は legacy compatibility entry であり、非自明な READY slice は `high-implementation-starter` から開始し、valid handoff 後だけ `standard-implementation-completer` を使います。現行 route は `token-aware-full-coverage-3layer` package の skill / instructions を参照してください。

## 目的

`suusanex/coding_agent_plan_and_verify_process` に追加済みの Codex 向け 3層運用ファイル群について、実験リポジトリ `suusanex/temp_codex_log_test` で判明した問題を反映し、本番運用で誤解なく使える状態に整える。

主な目的は次の4つ。

1. `slice-prep` / `slice-impl` の model / reasoning / sandbox 設定を、Codex が実際に解釈する top-level field として明示する。現行のこのリポジトリでは frontmatter で保持している。
2. `developer_instructions` 内の説明文・出力テンプレートが、実行設定と矛盾しないようにする。
3. 3層運用の実績ログ・Agent Usage Ledger で、`hook_model` / `configured_model` / `reported_model` / `effective_model` を混同しないようにする。
4. 歴史記録（model-routing-history allowlist）である `gpt-5.4 -> gpt-5.5` migration notice と CLI/App 差分など、未解決事項を本番修正とは分離して扱えるようにする。

## 背景

実験リポジトリでの調査により、当初の「subagent が gpt-5.4 ではなく gpt-5.5 で動いているように見える」問題（model-routing-history allowlist）は、主に custom agent 定義の書き方に起因する可能性が高いと判明した。

重要な切り分け結果:

- `slice-prep` / `slice-impl` の original definition では、`model` / `model_reasoning_effort` が Codex に解釈される top-level field として存在せず、`developer_instructions` 内の説明文にしか書かれていなかった。
- 実験で top-level field を追加したところ、Desktop/App 経路では Hook log の `model` が configured child model を反映した。
- したがって、少なくとも Desktop/App 経路では「Hook の `model` が常に親modelを返している」という説明は主因ではない。
- 歴史記録（model-routing-history allowlist）として、`gpt-5.4 -> gpt-5.5` の migration notice が user-level config に存在したが、`model = "gpt-5.4"` を明示した child agent が migration されるかは未確認。
- CLI 経路では自然言語委譲時に `agent_type = default` となり、App/Desktop の `slice-prep` / `slice-impl` 呼び出しと apples-to-apples な比較になっていない。

## 参照した事実

### Codex custom agent 仕様

Codex custom agent file では、`name` / `description` / `developer_instructions` が基本要素であり、`model`、`model_reasoning_effort`、`sandbox_mode` などは top-level field として指定する。

`developer_instructions` 内に「推奨実行境界: model: ...」と書いても、それは自然言語指示であり、実行設定としては扱われない。

### Codex Hook 仕様

Hook payload の `model` はログ上の observed value として扱う。ただし、課金・実行実体として完全に検証されたものとは限らないため、レポート上は `hook_model` と呼ぶ。

### 実験結果

Desktop/App 経路では、top-level `model` を追加した custom agent の Hook log が configured model を反映した。

ただし、歴史記録（model-routing-history allowlist）である `gpt-5.4` migration notice の影響と CLI 経路の agent type 指定は未解決。

## 対象リポジトリ

`suusanex/coding_agent_plan_and_verify_process`

## 主要対象ファイル

現行 repository の source of truth:

```text
apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-prep.agent.md
apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md
apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md
apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md
.codex/config.toml
```

以前の `.codex/agents/*` や `.agents/skills/token-aware-full-coverage-3layer/SKILL.md` はこの repository では source of truth ではなく、現在は `apm-packages/token-aware-full-coverage-3layer/.apm/` 配下を正として扱う。

必要なら、次のような修正ゴール文書を追加してもよい。

```text
docs/codex-full-coverage-3layer-fixes.md
```

## 修正項目

## 1. custom agent 定義に実行設定を top-level field として明示する

### 問題

`model` / `model_reasoning_effort` / `sandbox_mode` を `developer_instructions` 内の説明文だけに書くと、Codex の実行設定としては効かない。

### 対応

現行 repository では `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-prep.agent.md` と `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md` の frontmatter に、必ず top-level field として次を明示する。

### `slice-prep.toml`

```toml
name = "slice-prep"
description = "..."

model = "gpt-5.6-terra"
model_reasoning_effort = "medium"
sandbox_mode = "read-only"

developer_instructions = """
...
"""
```

### `slice-impl.toml`

```toml
name = "slice-impl"
description = "..."

model = "gpt-5.6-luna"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"

developer_instructions = """
...
"""
```

### 注意

歴史記録（model-routing-history allowlist）として、`gpt-5.4` が user-level migration により `gpt-5.5` に移行される可能性は未解決だった。現在の本番設定は GPT-5.6 系へ更新し、この migration 実験は別タスクとして扱う。

- 旧設定の `model = "gpt-5.4"` を維持する選択肢
- 旧設定の `model = "gpt-5.4-mini"` など migration 影響がないモデルで運用する選択肢
- `STANDARD_MODEL` のような抽象名を文書上で使い、実ファイルでは現在使える実名モデルを明示する

ただし、TOML上では Codex が解釈できる実名モデルを置くこと。

## 2. developer_instructions 内の「推奨実行境界」を削除または非設定扱いにする

### 問題

`developer_instructions` 内に次のような記述があると、読む側が実設定と誤認する。

```text
推奨実行境界:
- model / reasoning / sandbox は、この custom agent file の top-level field を参照する。
- `slice-prep` は gpt-5.6-terra / medium / read-only。
- `slice-impl` は gpt-5.6-luna / high / workspace-write。
```

### 対応

このブロックは削除するか、次のように明確化する。

```text
実行設定は、この custom agent file の top-level field で定義されます。現行 repository では frontmatter がそれに当たります。
この developer_instructions 内の説明文を、実行設定として扱ってはいけません。
```

ただし、原則として model / reasoning / sandbox の値は top-level field だけに置き、developer_instructions では値を重複させない。

## 3. 出力テンプレートの Model 表記を修正する

### 問題

agent 出力テンプレートに固定の `Model` 値を書くと、top-level field や Hook log と不整合になりやすい。

### 対応

`slice-prep` / `slice-impl` の出力形式に `Agent metadata` を追加し、次のように意味を分ける。

```markdown
## Agent metadata

- Agent type: slice-prep
- Configured model: <top-level TOML model>
- Configured reasoning effort: <top-level TOML model_reasoning_effort>
- Hook model: <available from Hook log, otherwise unknown>
- Effective model: unknown unless independently verified
- Parent authorization artifact:
- Delegation evidence:
```

`Configured model` は custom agent file に書いた値。  
`Hook model` は Hook payload に記録された値。  
`Effective model` は課金・実行実体として確認できた場合だけ埋める。通常は `unknown` でよい。

## 4. Agent Usage Ledger 用語を統一する

### 問題

`model` という1語だけで、設定値・Hook観測値・agent自己申告・実効モデルを表すと混乱する。

### 対応

3層運用 Skill と agent output template で、次の用語を統一する。

```text
configured_model:
  custom agent TOML top-level の model

configured_reasoning_effort:
  custom agent TOML top-level の model_reasoning_effort

hook_model:
  Hook payload の model

reported_model:
  agent が最終出力で自己申告した model

effective_model:
  実際に課金・実行されたmodelとして別経路で確認できた場合のみ
  未確認なら unknown
```

Agent Usage Ledger には、最低限次の列を追加する。

```markdown
| Run ID | Agent type | Slice | Configured model | Hook model | Effective model | Phase | Outcome | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
```

## 5. 3層運用 Skill に implementation delegation の強制を追加する

### 問題

親エージェントが `slice-prep` までは使っても、READY 後の実装・テスト・検証を親が直接進めてしまう可能性がある。

### 対応

`apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md` に、次の実行モードを追加する。

```text
ExecutionMode:
- PREP_ONLY
- DELEGATED_IMPLEMENTATION
- PARENT_DIRECT_IMPLEMENTATION
```

ユーザーが「実施」「進める」「このプロセスで実装する」と依頼し、かつ「実装はまだ行わない」「準備まで」「レビューまでで停止」と明示していない場合、既定の ExecutionMode は `DELEGATED_IMPLEMENTATION` とする。`PREP_ONLY` は明示的な準備・レビュー停止指示がある場合だけ選ぶ。

### `PREP_ONLY`

- `slice-prep` と parent review gate まで進める
- production code / tests は編集しない

### `DELEGATED_IMPLEMENTATION`

- READY slice の実装は必ず `slice-impl` custom agent に渡す
- 親エージェントは production code / tests を直接編集しない
- 親エージェントは parent review、結果集約、cross-slice verification を担当する
- parent review gate は人間レビュー待ちではなく、親エージェントによる実装可否判定 gate とする
- 成功完了には、READY slice の `slice-impl` 委譲、slice-local verification、cross-slice verification、residual-decision-gate までの証跡を必要とする

### `PARENT_DIRECT_IMPLEMENTATION`

- ユーザーが明示的に許可した場合のみ
- このモードは「3層運用の実装委譲評価対象外」として Agent Usage Ledger に記録する

### Skill へ追加する禁止事項

```text
DELEGATED_IMPLEMENTATION の場合、親エージェントは production code / tests を直接編集してはいけません。
READY slice は `slice-impl` custom agent に委譲してください。
親が直接編集した場合、Agent Usage Ledger に delegation violation として記録してください。
```

## 6. `slice-impl` の入力条件を強化する

### 問題

`slice-impl` が親承認済みでない slice を実装してしまうと、3層運用の境界が崩れる。

### 対応

`slice-impl.toml` に次を明記する。

```text
実装開始条件:
- parent review gate が存在する
- assigned slice が READY と判定されている
- Agent Usage Ledger または parent authorization artifact に
  ExecutionMode = DELEGATED_IMPLEMENTATION
  DelegationRequired = Yes
  EditOwner = slice-impl
  が記録されている
```

READY 条件が満たされない場合は、実装せず `BLOCKED_MISSING_PARENT_AUTHORIZATION` で停止する。

## 7. `slice-prep` / `slice-impl` から実験用 sentinel を除去する

### 問題

実験リポジトリでは、`SENTINEL_AGENT`、`EXPECTED_CONFIGURED_MODEL`、`AGENT_FILE_MARKER` などの diagnostics marker が本番agentに一時的に入っていた。

### 対応

本番リポジトリへは sentinel marker を反映しない。

削除対象:

```text
SENTINEL_AGENT=...
EXPECTED_CONFIGURED_MODEL=...
EXPECTED_REASONING_EFFORT=...
AGENT_FILE_MARKER=...
Diagnostics marker (...)
```

ただし、diagnostics用の marker agent を別ファイルとして残す場合は、`diagnostics/` 配下など本番agentとは別の場所に置く。

## 8. logger / diagnostics への反映事項を文書化する

### 問題

実験では logger 側にも次のズレが確認された。

- runtime log は `agent-usage-YYYY-MM-DD.jsonl` に出ている
- logger source の既定値は `agent-usage.jsonl` のまま
- `agent_transcript_path` と `last_assistant_message` は key存在しか保存していない
- marker検証に transcript scraping へ依存しやすい

### 対応

本番agent定義リポジトリ側では、少なくとも次を文書化する。

```text
- Hook log の `model` は `hook_model` と呼ぶ
- Hook log のファイル名は dated log を推奨する
- logger は agent_transcript_path を保存することを推奨する
- logger は last_assistant_message_preview を短く保存できるようにする
- transcript全文保存には依存しない
```

`coding_agent_plan_and_verify_process` 自体に logger 実装を持たない場合でも、`AGENTS.md` または Skill に「Agent Usage Ledgerでの用語」と「推奨logger項目」を書く。

## 9. 未解決事項を本番修正とは分けて扱う

### 未解決1（model-routing-history allowlist）: `notice.model_migrations` の影響

user-level config に次が観測された。

```toml
[notice.model_migrations]
# Historical model-routing-history allowlist; not active repository routing.
"gpt-5.4" = "gpt-5.5"
```

これは通知・移行確認済み状態の可能性があるが、`model = "gpt-5.4"` の custom agent が実際に `gpt-5.5` へ移行されるかは未確認だった。

### 対応

本番修正とは別に、次の最小実験を行う。

```text
1. model = "gpt-5.4" の sentinel agent を作る（歴史実験）
2. App/Desktop 経路で起動する
3. Hook log の hook_model を確認する
4. gpt-5.4 / gpt-5.5 のどちらになるか記録する
```

### 未解決2: CLI 経路で `agent_type = default` になる問題

CLI の natural-language delegation では、`slice-prep` を起動したつもりでも `agent_type = default` となった。

### 対応

CLI経路は、App/Desktop経路と同じcustom agent typeを deterministic に起動できる手段が確認できるまで、3層運用の主対象からは分ける。

文書上は次のように扱う。

```text
App/Desktop thread path:
  3層運用の primary path

CLI non-interactive / codex exec path:
  separate compatibility path
  deterministic custom agent invocation が確認できるまで同等扱いしない
```

## 10. 反映後の期待状態

修正後、次が満たされること。

### custom agent定義

- `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-prep.agent.md` に top-level `model` / `model_reasoning_effort` / `sandbox_mode` がある
- `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md` に top-level `model` / `model_reasoning_effort` / `sandbox_mode` がある
- `developer_instructions` に model設定値を重複記載していない
- sentinel marker が本番agentから削除されている

### Skill

- `DELEGATED_IMPLEMENTATION` では親が production code / tests を直接編集しない
- READY slice は `slice-impl` に必ず委譲する
- Agent Usage Ledger で delegation compliance を確認する

### Agent Usage Ledger

- `configured_model`
- `hook_model`
- `effective_model`
- `ExecutionMode`
- `DelegationRequired`
- `EditOwner`
- `DelegationViolation`

を区別して記録できる。

### 未解決事項

- 歴史記録（model-routing-history allowlist）として `gpt-5.4` migration notice の実影響は別実験として残す
- CLI custom agent invocation の deterministic path は別実験として残す

## 変更対象の優先順位

### Priority 1: 必須修正

- `slice-prep.toml` / `slice-impl.toml` の top-level settings 明示
- developer_instructions 内の誤解を招く model/reasoning/sandbox説明の削除
- output template の `Model:` 固定値を `Configured model` / `Hook model` / `Effective model` に分離
- Skill に `ExecutionMode` と delegation violation ルールを追加

### Priority 2: 強く推奨

- Agent Usage Ledger template の追加
- `slice-impl` の parent authorization requirement 強化
- logger推奨項目の文書化
- App/Desktop と CLI の対象範囲を文書上で分ける

### Priority 3: 別タスク

- 歴史記録（model-routing-history allowlist）として `gpt-5.4` migration notice の実験
- CLIで `slice-prep` / `slice-impl` を deterministic に起動する方法の調査
- diagnostics sentinel agent の整備
- Hook logger のC#化・OTEL連携

## Codexへ渡す実装指示の要約

```text
このリポジトリの Codex 3層運用定義について、実験リポジトリで判明した custom agent model 設定問題を反映してください。

主な修正:
1. slice-prep / slice-impl の model / model_reasoning_effort / sandbox_mode を top-level field として明示。
2. developer_instructions 内の「推奨実行境界」など、実行設定と誤認される説明を削除または明確化。
3. 出力テンプレートで `Configured model` / `Hook model` / `Effective model` を分離。
4. Skill に ExecutionMode を導入し、DELEGATED_IMPLEMENTATION では READY slice の実装を必ず slice-impl に委譲する。
5. 親が production code / tests を直接編集した場合は delegation violation として Agent Usage Ledger に記録する。
6. 本番agentに diagnostics sentinel marker を残さない。
7. 歴史記録（model-routing-history allowlist）として gpt-5.4 migration notice と CLI agent_type=default 問題は未解決事項として別タスクに残す。
```

## 完了条件

- TOML構文が正しい
- Codex custom agent仕様に沿って top-level field が置かれている
- 本番agentに diagnostics marker がない
- Skill上で PREP_ONLY / DELEGATED_IMPLEMENTATION / PARENT_DIRECT_IMPLEMENTATION が区別されている
- Agent Usage Ledgerで `configured_model` / `hook_model` / `effective_model` を混同しない
- 未解決事項が明示されている
