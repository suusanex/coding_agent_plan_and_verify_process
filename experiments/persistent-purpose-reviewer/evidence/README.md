# Evidence 保存規約

このフォルダは実機検証の証拠を保存する場所です。まだ外部 model の実行結果はありません。`setup\` は CLI の static evidence、`raw\` は reviewer の raw output、`sanitized\` は共有用の加工済み evidence を置きます。

## raw output の sanitization

- 外部サービスへ送った入力は、固定 prompt と `fixtures\` 内の架空データだけであることを manifest で確認する。
- raw output を保存する前に credential、authorization header、cookie、環境変数、path に含まれる秘密、実在の利用者データを除外する。
- session ID は原文を保存せず、承認済み salt の SHA-256 短縮値または末尾 4 文字だけにする。例: `session-a1b2`。
- token や credential が混入した場合は、該当ファイルを共有せず、漏えいしていない sanitized 記録と failure 記録だけを残す。
- raw output は reviewer の出力本文を意味変更せず保存する。ただし安全に保存できない場合は `raw_unavailable` として理由を記録する。
- exception を記録する場合は、credential を除去した `Exception.ToString()` 相当の trace を保存し、秘密値を含む原文は保存しない。

## 必須 evidence

各 CLI・各 round について、次を揃えます。

1. 実行 command（入力本文ではなく、fixture path と固定 prompt path の manifest）
2. CLI 名、解決した version、`--help` の static evidence
3. 実行時刻（UTC）、round、reviewer role、model 名（実行した場合のみ）
4. session ID の hash または末尾 4 文字
5. pre/post の `git status --porcelain` snapshot
6. production tree の変更検出結果。変更があれば path、時刻、失敗理由、修復または中止判断を記録する
7. raw output の保存 path と sanitization 実施者・時刻
8. failure、timeout、non-zero exit、empty output、入力 manifest 不一致の記録

`setup\` に保存する static evidence は `capture-cli-static-evidence.ps1` の命名に従います。helper は credential を表示せず、evidence 配下を除いた worktree 変更を pre/post で比較します。

## 命名

```text
setup\YYYYMMDDTHHMMSSZ-<cli>-<kind>.txt
raw\YYYYMMDDTHHMMSSZ-round-<NN>-purpose-reviewer-<cli>-session-<hash-or-last4>.raw.md
sanitized\YYYYMMDDTHHMMSSZ-round-<NN>-purpose-reviewer-<cli>-session-<hash-or-last4>.md
```

session の完全な ID、credential、command line の secret-bearing argument はファイル名にも入れません。

## Input manifest の最小形

```yaml
round: 1
role: purpose-reviewer
prompt: prompts/round-1.md
fixtures:
  - fixtures/purpose-context.md
  - fixtures/round-1-candidate.md
goal_context_replayed: false
prior_reviewer_output_replayed: false
external_model_execution: false
```

Round 2/3 では `fixtures\purpose-context.md` と前 round raw output の全文を manifest の `fixtures` に入れず、`goal_context_replayed: false`、`prior_reviewer_output_replayed: false` を明示します。

## Failure 記録

failure ごとに、UTC 時刻、round、CLI、safe command descriptor、失敗分類（未導入・認証・timeout・non-zero・empty・sanitization・worktree change）、sanitized error、次の判断（再実行・中止・HumanDecisionRequired）を記録します。認証失敗では credential の値、header、環境変数を記録しません。
