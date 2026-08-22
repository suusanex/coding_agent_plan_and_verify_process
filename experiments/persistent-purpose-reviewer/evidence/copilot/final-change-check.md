# Copilot 最終変更分類

## 実測

- `git diff --check`: 問題なし。
- 実験開始時の Copilot `run-start-pre-git-snapshot.json` と最終 `git status --porcelain --untracked-files=all` を比較した。
- production tree（`apps`、`apm-packages`、`apm_modules`、`tests`、`.github`、`docs`、`scripts`、tracked files）の追加・変更は `0`。
- Copilot evidence と専用 runner は許可範囲内。
- baseline-to-current の status 差分は `118` 件、production outside `experiments` は `0` 件、Copilot/Grok evidence と runner は `45` 件。
- 実験開始後に `experiments\persistent-purpose-reviewer\evidence\codex\` の別系統 evidence が増えた。ユーザー指示どおり内容を変更・revert していない。

## 推測

- Codex evidence の増加は本 Copilot/Grok runner が生成したものではなく、実験開始時点から独立した別プロセスの変更と判断する。

## 未実施

- 競合する別 Codex 実験の責任主体・内容の検証は実施していない。
