# Grok Build CLI 実機検証サマリー

## 実測

- CLI: Grok Build CLI 1.0.4 (d846eb93d9) stable（`setup/static-help-and-version.json`）。
- headless: `-p/--single` と `--output-format plain`。新規 session は `--session-id <UUID>`、継続は同じ特定 ID の `--resume <UUID>`。Round 1 のプロセス終了後に Round 2/3 を別プロセスで実行した（各 round の開始・終了時刻は各 `sanitized-raw-output.json`）。
- model: `grok models` の静的確認で default は `grok-4.6`（runtime model の独立 metadata は未取得）。
- cwd: `experiments\persistent-purpose-reviewer`。`--permission-mode plan`、`--sandbox read-only`、`--tools=read,view,grep`、write/shell/task/edit_file/run_shell_command の disallow、`--disable-web-search`、`--no-memory`、`--no-subagents` を指定した。
- Round 1 は `purpose-context.md` 全文と round-1 candidate を送信した。Round 2/3 の manifest は context 全文、前回 output 全文、semantic secret の再送なしを示す（`rounds\round-2\input-manifest.json`、`rounds\round-3\input-manifest.json`）。
- Semantic transition:
  - Round 1: unknown の default 丸め、形式的 success、データ消失を active finding と判定。`PUR-1`/`PUR-2`/`PUR-3`。
  - Round 2: `CreateDefault()` と warning を使った同じ危険な fallback を `PUR-1 active` として再発判定。
  - Round 3: explicit mapping、unknown の Pending/error、データ保持、MVP 境界を全て PASS、finding resolved。
- Session identity: 3 round とも同じ session hash `057dd4d83ed7`。Round 2/3 の semantic 判定が Round 1 の目的を再送せずに継続したため、context persistence は意味的に PASS。
- Worktree: 各 round の pre/post snapshot で production tree（tracked source/Skill/agent/script）の変更は検出なし。実験開始後に別系統の既存 Codex evidence が増えており、revert せず `final-change-check.md` に分離記録した。

## 推測

- 特定 ID の `--resume` がプロセス終了後に成功し、Round 2/3 が期待された finding transition を返したため、Grok の session conversation persistence は実用上確認できたと推測できる。
- `plan`、`read-only` sandbox、tool allow/disallow の指定は CLI enforcement として受理され、今回の出力に write/shell/tool実行は現れなかったと推測できる。

## 未実施・制約

- `grok inspect --json` の静的確認では global rule path の存在が検出されたが、規則本文・credential・ホーム内容は開かず保存もしなかった。`--system-prompt-override` を併用したが、CLI 内部での system prompt 組み立てをネットワーク層まで監査していないため、外部 payload の完全な fixture-only 性は未証明。
- `--sandbox read-only` は CLI に指定して実行したが、sandbox backend の低レベル監査は未実施。
- runtime callback、ネットワーク payload、credential、session ID 原文は未取得。session ID は SHA-256 短縮値のみ保存した。
- 許可範囲外の `evidence\codex\` は別実験の変更であり、本検証の production 変更とは分類していない。
- CLI の shared leader がクライアント終了後も残存したかどうかは確認していないため、完全な backend process isolation は未実施。

## 結論

**HumanDecisionRequired** — semantic persistence と非変更は実測 PASS。ただし Grok の global rule/system prompt が外部 payload に含まれないこと、sandbox の低レベル enforcement は実機層別監査をしていないため、完全な fixture-only 安全保証は人手判断が必要。
