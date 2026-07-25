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
- state / audit artifact templates
- predefined routing agents / subagents
- Routing Plan / Edit Permission / Agent Usage Ledger / DelegationCompliance
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
TOML の top-level field は Codex が解釈する configured execution defaults であり、本文中の自然言語や output template は source of truth ではない。

repository-local な継続運用のためには `apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs` も追加しておく。
このインストーラは `AGENTS.md` の managed section、`.codex/config.toml`、`.codex/agents/*.toml`、Codex-first / Adaptive / Design Pair skills、Adaptive completion handoff reference、Design Pair Target Map / tracked handoff reference、canonical HIGH / STANDARD implementation agent contracts、`templates/*.md` を安全に追加・マージする。
`templates/*.md` には `codex-first-state.md` と `codex-first-audit.md` の両方が含まれる。
標準 Codex-first route に必要な runtime はこのインストーラだけで揃え、別途 APM 実行を前提にしない。

`.github/instructions/plan-coverage-shared.instructions.md` は APM 経由で `.github/agents/*.agent.md` と一緒に配布する shared instruction である。repository-local installer は現時点では `.github/instructions` をコピーしないため、`profiles/codex-first/agents/*.toml` はこの shared instruction を直接参照しない。local profile に必要な Plan Coverage invariant や lite / standard 互換条件は、profile `AGENTS.md` と各 TOML に明示する。

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

ただし、実行可能な初期値がないと導入検証できないため、`profiles/codex-first/agents/*.toml` には configured defaults を置く。
具体値は TOML の top-level `model` / `model_reasoning_effort` を確認する。docs 本文へ自然言語の固定推奨として複製しない。

現行 default では、抽象 tier と実モデルは一対一対応ではなく、agent ごとの責務に応じて model / reasoning effort を設定する。

- `high-implementation-starter`: Terra / high
- `standard-implementation-completer`: Luna / high
- `standard-implementer`: Luna / high（legacy compatibility only）
- `standard-verifier`: Terra / medium
- `HIGH_MODEL` agents: 原則 Terra。reasoning effort は agent ごとに medium または high

この値は公式推奨、利用可能モデル、価格、品質要求の変化に合わせて見直す。

## Sandbox defaults

Codex-first profile agents should use the smallest practical sandbox boundary:

| Agent role | Default `sandbox_mode` | Reason |
| --- | --- | --- |
| cheap repo scan / docs consistency / artifact format check | `read-only` | evidence collection and suggestions only |
| high planning / contract / closure review | `read-only` | judgment and artifact review, not implementation |
| high risk triage | `workspace-write` | creates or updates `plans/<slug>-change-risk-triage.md` and state risk fields, but does not implement |
| high implementation starter | `workspace-write` | non-trivial READY implementation start and structural decisions own edits |
| standard implementation completer | `workspace-write` | valid handoff の decision-free bounded completion owns edits |
| standard implementer | `workspace-write` | legacy compatibility only; standard route does not select it |
| standard verifier | `workspace-write` | tests, build artifacts, and verification artifacts may write locally |

If an agent omits `sandbox_mode`, document the reason in this guide before rollout. For Codex-first defaults, omission should be treated as a maintainer action item.

## Delegation evidence and hooks

process の成功条件は repository-tracked な audit artifact の Agent Usage Ledger を主証跡にする。Codex hooks は補助証跡として使えるが、hook payload の詳細だけに依存して close 判定を行わない。

補助ログを取りたい場合は、project-local または profile-local hooks で `SubagentStart` / `SubagentStop` を JSONL に保存する。例:

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File .codex/hooks/log-subagent-event.ps1 start",
            "timeout": 30
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File .codex/hooks/log-subagent-event.ps1 stop",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

hook の raw JSONL は audit artifact の Agent Usage Ledger の補助 evidence として参照する。ledger には、expected agent、observed run、model tier、configured model、configured reasoning effort、hook model、reported model、effective model、edit owner、changed files、checks run、outcome、parent direct exception、delegation violation の有無を必ず残す。

`configured_model` は custom agent TOML の top-level `model`、`configured_reasoning_effort` は top-level `model_reasoning_effort` を指す。`hook_model` は hook payload から観測できた場合だけ、`reported_model` は agent 自己申告、`effective_model` は課金・実行実体として独立確認できた場合だけ記録する。通常 `effective_model` は `unknown` でよい。

Cost-saving delegation は、単に `CHEAP_MODEL` や `STANDARD_MODEL` を選んだだけでは評価しない。対応する delegated run evidence があり、想定 owner が編集し、`delegation_violation = No` の場合だけ countable とする。親が直接実行した `PARENT_DIRECT_WORK` や `TRIVIAL_PARENT_FIX` は、明示的に必要だったとしても cost-saving delegation 成功ではない。

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
- `docs/examples/lite-standard-validation.md`

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
- existing skills or APM package files
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
- high-risk-triage が `plans/<slug>-change-risk-triage.md` を作成し、handoff review の必須入力として扱われている。
- Routing Plan、Edit Permission、audit artifact、Agent Usage Ledger、DelegationCompliance が template / skill / docs に揃っている。
- implementation-handoff-review が standard implementation 前の parent authorization と Behavior Case Coverage Ledger gate として定義されている。
- READY implementation は `high-implementation-starter` から開始し、valid handoff 後だけ `standard-implementation-completer`、re-entry は HIGH_MODEL、READY verification は `standard-verifier` への serial delegation として定義されている。
- implementation route はdurable route、resume、Design Pair evidenceがないfresh intakeだけ`adaptive / default`で初期化される。resumeでは両route fieldが必須であり、欠落または矛盾はAdaptiveへ補完せず停止する。唯一の互換例外はcanonical `Legacy Adaptive handoff normalization`を満たすexact pre-Design-Pair Adaptive completion handoffである。Design Pairはexplicit user selectionの場合だけhandoff review後かつHIGH start前に実行される。Design Pair phaseのproduction code / tests editは禁止され、Locked Decisionsだけがbindingである。
- close gate が delegation evidence missing を成功扱いしない。
- `profiles/codex-first/agents/*.toml` に `model` と `model_reasoning_effort` の実行可能な初期値がある。
- `profiles/codex-first/agents/*.toml` に role-appropriate `sandbox_mode` がある。
- `apply-codex-first-local.cs` が Codex-first / Adaptive / Design Pair skills、complete handoff references、canonical HIGH / STANDARD implementation agent contracts、`templates/*.md` を配置し、`--check` で対象 repository の実ファイル一致を検証する。
- `apply-codex-first-local.cs` の `--dry-run` / `--check`（`--check-only` 互換 alias）がファイルやディレクトリを作成しない。
- audit artifact の Agent Usage Ledger が configured / hook / reported / effective model と delegation violation を分離している。
- parent direct work と trivial parent fix が cost-saving delegation success として数えられない。
- maintainer guide が agent-specific model / effort mapping と、設定値の確認責務を説明している。
- advanced guide が full-coverage 3層運用を標準ルートから分離している。
- bootstrap policy が `AGENTS.override.md` と size limit risk を説明している。
- examples が novice request、resume、simple local fix、ambiguous high-risk change、existing AGENTS layering を示している。
- `docs/examples/lite-standard-validation.md` が VAL-001 から VAL-010、artifact count / sections read 比較、negative scan を示している。
- `documentation_level` は `lite` / `standard` のみで、`strict` が enum として残っていない。
- full-coverage は documentation level ではなく advanced route として説明されている。
- Codex-first profile TOML が `.github/instructions/plan-coverage-shared.instructions.md` を直接参照していない。
- 既存 `plan-coverage-residual-flow` と `full-autonomous-plan-first-flow` を壊していない。
