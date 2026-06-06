# Maintainer Guide

## Package ownership

この package は Codex-first cost-aware routing layer を所有する。
既存 kernel agent の source of truth は root の `.github/agents/*.agent.md` と既存 APM package の参照に残す。

二重管理を避けるため、既存 kernel agent の本文をこの package にコピーしない。
この package は次を追加する。

- beginner-friendly entrypoint
- `codex-first-cost-router`
- Codex-first model tier labels
- close / stop vocabulary
- state artifact templates
- predefined routing agents / subagents
- advanced full-coverage boundary
- examples and maintainer notes

## Team profile / launcher

導入時は `codex-first` または `codex-first-start` のような team profile / launcher を用意する。
この launcher は、既存 repo を直接書き換えなくても global `AGENTS.md`、instructions、skills、agents、templates を `CODEX_HOME` 側から読ませる。

global guidance は短く保つ。
詳細は Skill、docs、templates へ逃がす。

この package では最小例として `profiles/codex-first/` と `scripts/codex-first-start.ps1` を持つ。
`profiles/codex-first/agents/*.toml` は Codex custom agent file として使える形にし、`model` と `model_reasoning_effort` のデフォルト例を入れる。
組織の契約や利用枠に合わせて、これらの TOML を編集してから配布する。

repository-local な継続運用のためには `scripts/install-codex-first-local.cs` も追加しておく。  
このインストーラは `AGENTS.md` の managed section、`.codex/config.toml`、`.codex/agents/*.toml`、`templates/codex-first-state.md` を安全に追加・マージする。

## AGENTS layering

Codex は global から作業ディレクトリへ向かって `AGENTS.md` 系の instruction chain を読む前提で設計する。
team profile の global `AGENTS.md` は repo-local `AGENTS.md` を置き換えない。

注意点:

- 同じ階層に `AGENTS.override.md` がある場合、その階層の通常 `AGENTS.md` は無視される可能性がある。
- combined guidance の size limit によって後続 instruction が入らない可能性がある。
- 既存 repo instruction が大きい場合、bootstrap / dry-run merge が必要になる。
- repo 固有の build/test/security ルールは常に優先する。

## Model mapping

`HIGH_MODEL`、`STANDARD_MODEL`、`CHEAP_MODEL` は抽象ラベルである。
実名モデル対応表は組織ごとに作る。

| Label | Maintainer decision |
| --- | --- |
| `HIGH_MODEL` | Plan quality and high-risk reasoning model |
| `STANDARD_MODEL` | implementation and verification model |
| `CHEAP_MODEL` | formatting and lightweight consistency model |

この対応表は package に固定しない。
契約、利用枠、品質要求、時期によって変わるため、team profile 側で保守する。

ただし、実行可能な初期値がないと導入検証できないため、`profiles/codex-first/agents/*.toml` には次のようなデフォルト例を置く。

- high 系: `model = "gpt-5.5"`、`model_reasoning_effort = "xhigh"` または `"high"`
- standard 系: `model = "gpt-5.5"`、`model_reasoning_effort = "medium"`
- cheap 系: `model = "gpt-5.4-mini"`、`model_reasoning_effort = "low"`

この値は公式推奨や利用可能モデルの変化に合わせて見直す。

## Updating route policy

Route policy を変えるときは、次を一緒に確認する。

- `AGENTS.md`
- `.apm/instructions/codex-first-ai-development-process.instructions.md`
- `.apm/skills/codex-first-cost-router/SKILL.md`
- `.apm/skills/codex-plan-coverage/SKILL.md`
- `.apm/skills/codex-full-coverage-3layer/SKILL.md`
- `docs/user-guide.md`
- `docs/cost-router-goals.md`
- `docs/team-profile-launcher.md`
- `docs/bootstrap-and-merge-policy.md`

## Copilot fallback

GitHub Copilot fallback は第2優先である。
この package の artifacts と vocabulary を再利用しつつ、VS Code custom instructions / prompt files / custom agents へ移す。

fallback package を作る場合も、Codex-first package の source をコピーして二重管理しない。
共通化できる語彙は shared docs に寄せ、環境固有の入口だけ分ける。

## Bootstrap / merge support

team profile だけで repo-local guidance に届かない場合は、bootstrap / dry-run merge を使う。
自動で既存 `AGENTS.md` や `.codex` を破壊しない。

最低限、次を検出する。

- `AGENTS.md`
- `AGENTS.override.md`
- `.codex`
- existing scripts
- large instruction risk
- build/test/security rule conflicts

変更が必要な場合は dry-run report と追記案を提示し、ユーザー承認後だけ適用する。

## Advanced full-coverage route

full-coverage 3層運用は advanced route である。
標準 user guide には「full-coverage を指定して」といった依頼例を載せない。
熟練 operator 向けの詳細は `advanced-full-coverage-3layer.md` に分離する。

## Release checklist

- `apm.yml` が package intent と既存 agent dependencies を説明している。
- `apm.yml` または maintainer guide が標準 route dependency と advanced / compatibility dependency の違いを説明している。
- user guide が process 名、agent 名、model tier、full-coverage 分岐を利用者へ要求していない。
- `codex-first-cost-router` が state artifact、model tier、READY、close 不可条件を定義している。
- `profiles/codex-first/agents/*.toml` に `model` と `model_reasoning_effort` の実行可能な初期値がある。
- maintainer guide がモデル実名を固定していない。
- advanced guide が full-coverage 3層運用を標準ルートから分離している。
- bootstrap policy が `AGENTS.override.md` と size limit risk を説明している。
- examples が novice request、resume、simple local fix、ambiguous high-risk change、existing AGENTS layering を示している。
- 既存 `token-aware-guardrail-kernel-flow` と `full-autonomous-plan-first-flow` を壊していない。
