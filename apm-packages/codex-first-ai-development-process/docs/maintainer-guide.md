# Maintainer Guide

## Package ownership

この package は応用運用 layer を所有する。
既存 agent の source of truth は root の `.github/agents/*.agent.md` と既存 APM package の参照に残す。

二重管理を避けるため、既存 agent の本文をこの package にコピーしない。
この package は次を追加する。

- beginner-friendly entrypoint
- Codex-first model labels
- close / stop vocabulary
- Skills for normal route and full-coverage branch
- examples and maintainer notes

## Model mapping

`HIGH_MODEL`、`STANDARD_MODEL`、`CHEAP_MODEL` は抽象ラベルである。
実名モデル対応表は組織ごとに作る。

| Label | Maintainer decision |
| --- | --- |
| `HIGH_MODEL` | Plan quality and high-risk reasoning model |
| `STANDARD_MODEL` | implementation and verification model |
| `CHEAP_MODEL` | formatting and lightweight consistency model |

## Updating route policy

Route policy を変えるときは、次を一緒に確認する。

- `AGENTS.md`
- `.apm/instructions/codex-first-ai-development-process.instructions.md`
- `.apm/skills/codex-plan-coverage/SKILL.md`
- `.apm/skills/codex-full-coverage-3layer/SKILL.md`
- `docs/user-guide.md`

## Copilot fallback

GitHub Copilot fallback は第2優先である。
この package の artifacts と vocabulary を再利用しつつ、VS Code custom instructions / prompt files / custom agents へ移す。

fallback package を作る場合も、Codex-first package の source をコピーして二重管理しない。
共通化できる語彙は shared docs に寄せ、環境固有の入口だけ分ける。

## Release checklist

- `apm.yml` が必要 agent を参照している。
- user guide が通常ルートと full-coverage 分岐を説明している。
- maintainer guide がモデル実名を固定していない。
- examples が close してよい場合と止める場合を示している。
- 既存 `token-aware-guardrail-kernel-flow` と `full-autonomous-plan-first-flow` を壊していない。
