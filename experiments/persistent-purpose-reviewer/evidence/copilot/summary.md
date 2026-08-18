# Copilot CLI 実機検証サマリー

## 実測

- CLI: GitHub Copilot CLI 1.0.80（`setup/static-help-and-version.json`）。
- headless: `-p/--prompt`。新規 session は `--session-id=<UUID>`、継続は同じ特定 ID の `--resume=<UUID>`。Round 1 のプロセス終了後に Round 2/3 を別プロセスで実行した（各 round の開始・終了時刻は各 `sanitized-raw-output.json`）。
- model: CLI の非対話 text 出力から runtime model 名は独立取得できなかったため、`CLI default` と記録した。
- cwd: `experiments\persistent-purpose-reviewer`。`--no-custom-instructions`、`--disable-builtin-mcps`、`--no-remote`、`--available-tools=view,grep`、write/shell/task/edit の deny を指定した。
- Round 1 は `purpose-context.md` 全文と round-1 candidate を送信した。Round 2/3 の manifest は context 全文、前回 output 全文、semantic secret の再送なしを示す（`rounds\round-2\input-manifest.json`、`rounds\round-3\input-manifest.json`）。
- Semantic transition:
  - Round 1: unknown を `"steady"` に丸めるため active finding。`PUR-001`/`PUR-002`、`unknown_handling_assertion: FAIL`。
  - Round 2: `safeFallback` と warning に変えただけの再発を同一 session が active と判定。`PUR-001`、resolution `FAIL`。
  - Round 3: explicit mapping、unknown の可視 pending/error、データ保持を全て PASS、active finding なし。
- Session identity: 3 round とも同じ session hash `b3f6796ce180`。Round 2/3 の semantic 判定が Round 1 の目的を再送せずに継続したため、context persistence は意味的に PASS。
- Worktree: 各 round の pre/post snapshot で production tree（tracked source/Skill/agent/script）の変更は検出なし。実験開始後に別系統の既存 Codex evidence が増えており、revert せず `final-change-check.md` に分離記録した。

## 推測

- 出力と同一 session の特定 resume 成功から、Copilot CLI の会話履歴がプロセス終了後も復元されたと推測できる。
- `available-tools` と deny flags により、今回の reviewer は読み取り系以外を利用しなかったと推測できる。ただし CLI 外部のネットワーク payload を層別に監査した結果ではない。

## 未実施・制約

- `--output-format text` では runtime model の実名、内部 callback、ネットワーク送信 payload は未取得。
- CLI の OS sandbox を別途有効化した検証ではない。read-only は CLI tool availability/deny flags と prompt 単位で実測した。
- session ID 原文、credential、環境変数、ホーム内容は保存・表示していない。session ID は SHA-256 短縮値のみ保存した。
- 許可範囲外の `evidence\codex\` は別実験の変更であり、本検証の production 変更とは分類していない。

## 結論

**Complete** — semantic persistence（Round 2 の deceptive default mapping 棄却、Round 3 の解消）を実機出力で確認し、production tree の変更も検出されなかった。
