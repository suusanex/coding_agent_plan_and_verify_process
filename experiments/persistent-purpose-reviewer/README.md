# Persistent Purpose Reviewer 実機検証準備

このフォルダは、`Persistent Purpose Reviewer` の context persistence を意味的に検証するための、架空 fixture・固定 prompt・証拠保存規約だけを置く実験境界です。production package、Skill、script、テスト、設定、GitHub の状態は変更しません。実験 agent はこのフォルダの配下だけを読み書きし、リポジトリの外側を読みません。

## 現行方式の確認

検証対象の現行 canonical flow は `apm-packages\pr-review-remediation\README.md` と、同 package の `.apm\skills\goal-context-pr-review\SKILL.md` / `references\design.md` に記載されています。

- Round 1 は Copilot source、local reviewer、purpose reviewer を収集します。
- Round 2/3 は新しい `purpose-reviewer` だけを起動します。
- したがって、現在方式は **purpose reviewer を各 round ごとに新規起動する** 方式です。前 round の reviewer process を再利用する方式ではありません。
- この実験はこの挙動を検証するだけで、現行方式を変更しません。

## 境界と安全条件

- 変更・新規作成は `experiments\persistent-purpose-reviewer\` 配下だけです。
- 意味データとして外部モデルへ送る対象は `fixtures\` の架空データだけです。固定 prompt は命令文として同時送信しますが、production source、他のドキュメント、Git metadata、環境変数、credential、実在の利用者データは送信しません。
- fixture 内の名称・値・会話はすべて架空です。実在の token、API key、password、個人情報、顧客情報を追加しません。
- credential は保存、表示、prompt への埋め込みをしません。モデル CLI の認証確認やネットワーク実行はこの準備作業では行いません。
- 外部モデル実行、GitHub 操作、commit、push、production tree の編集は実施しません。
- prompt は agent に、リポジトリの外側を読まないこと、fixture 以外を送らないこと、production を変更しないこと、後述の機械可読な semantic assertion を守ることを要求します。

## 必要な CLI

準備と証拠整理に必要なのは次です。

- PowerShell 7 以降（`pwsh`）
- Git（作業 tree の pre/post snapshot 用）
- 実機検証時に選ぶ reviewer CLI（例: `codex` または `copilot`）。この成果物作成時点では存在確認だけに留め、model/network は実行しません。

CLI の存在、`--version`、`--help` の静的 evidence は、credential を出力しない helper で保存できます。

```powershell
pwsh -NoProfile -File .\experiments\persistent-purpose-reviewer\scripts\capture-cli-static-evidence.ps1 `
  -CliName codex -CliPath codex

pwsh -NoProfile -File .\experiments\persistent-purpose-reviewer\scripts\capture-cli-static-evidence.ps1 `
  -CliName copilot -CliPath copilot
```

helper は `--version` と `--help` だけを起動し、結果を `evidence\setup\` に保存します。任意の prompt、model、network command は起動しません。実行前後の作業 tree を比較し、`worktree-change-summary` に記録します。CLI が未インストールの場合も、失敗を sanitized evidence として記録します。

## 実機検証手順

1. `git status --short` を確認し、実験開始時点の状態を記録します。
2. `fixtures\purpose-context.md` と Round 1/2/3 の candidate を読み、semantic secret が架空データであることを確認します。
3. 必要な reviewer CLI ごとに上記 helper を実行します。credential の入力・表示・保存は行いません。
4. Round 1 は `prompts\round-1.md` を使い、`fixtures\purpose-context.md` の全文と `fixtures\round-1-candidate.md` だけを実験 agent に渡します。
5. Round 2 は `prompts\round-2.md` を使い、Round 2 candidate と前 round の finding 解消確認だけを渡します。Goal Context 全文や Round 1 reviewer output 全文を prompt に再掲しません。
6. Round 3 は `prompts\round-3.md` を使い、Round 3 candidate と前 round の finding 解消確認だけを渡します。
7. 各 round の agent は、機械的に識別できる出力を `BEGIN_PURPOSE_REVIEW` から `END_PURPOSE_REVIEW` までで返します。raw output は内容を変えずに保存し、sanitized copy を共有用に作ります。
8. 実験後に `evidence\README.md` の manifest、command、version、pre/post snapshot、failure 記録を埋め、`report-template.md` で実測・推測・未実施を分離して評価します。

実機検証の prompt 入力例（外部モデル実行は本成果物作成時には行いません）:

```powershell
# Round 1: 固定 prompt と fixture だけを入力として使用
Get-Content .\experiments\persistent-purpose-reviewer\prompts\round-1.md -Raw
Get-Content .\experiments\persistent-purpose-reviewer\fixtures\purpose-context.md -Raw
Get-Content .\experiments\persistent-purpose-reviewer\fixtures\round-1-candidate.md -Raw

# Round 2/3: candidate と finding 解消確認だけ。全文 context/output は再送しない
Get-Content .\experiments\persistent-purpose-reviewer\prompts\round-2.md -Raw
Get-Content .\experiments\persistent-purpose-reviewer\fixtures\round-2-remediation.md -Raw
```

## raw evidence の命名

raw evidence は次の形式で `evidence\raw\` に保存します。

```text
YYYYMMDDTHHMMSSZ-round-<NN>-purpose-reviewer-<cli>-session-<hash-or-last4>.raw.md
```

例: `20260819T001500Z-round-02-purpose-reviewer-copilot-session-a1b2.raw.md`

session ID は原文を保存せず、承認済みの salt を使った SHA-256 の短縮値、または末尾 4 文字だけを使います。credential、authorization header、環境変数値、未 sanitise の CLI error を raw evidence に含めません。原文を保存できない場合は、その理由を `evidence\README.md` の failure 記録へ書きます。

## 評価基準

各 round の結果を次の観点で評価します。

| 観点 | 合格条件 |
| --- | --- |
| 目的の再現 | 利用者の手入力・作り直しを避け、安全に継続利用する目的を明示する |
| 棄却案の識別 | 旧値を黙って一律 default 化する案と、データ消失・意図喪失の理由を識別する |
| 形式と目的の分離 | schema validation 合格でも unknown 値を丸める案は目的未達と判定する |
| mapping の安全性 | 対象 3 既知値は明示 mapping、unknown は保留または明示 error とする |
| MVP 境界 | UI 刷新・自動推測を実装範囲に含めない |
| 優先順位 | データ保持と可視失敗を速度より優先する |
| context persistence | Round 2 の deceptive candidate を再受理せず、Round 3 の解決版を受理する |
| 非変更 | production tree を変更しない |

`report-template.md` の matrix では、各 assertion を `実測`、`推測`、`未実施` のいずれかに分類します。prompt の文章だけで「実機検証済み」とは判定しません。

## 期待する fixture 判定

- Round 1: unknown old value を default v2 にするため、少なくとも 1 件の purpose finding（例: `PUR-001`）が出る。
- Round 2: 修正に見えるが同じ危険な丸めを再導入するため、finding が persistent または reopened と判定される。
- Round 3: 3 つの明示 mapping と unknown の explicit error/pending が揃い、MVP 境界も守るため、active purpose finding はない。

この期待値は fixture の設計契約であり、まだ外部 model の実測結果ではありません。
