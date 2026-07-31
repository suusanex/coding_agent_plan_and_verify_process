# Design Pair Implementation Execution

利用者が明示的に選択した場合だけ、実装前に予定変更面を既存 code の file / symbol 単位で確認し、対話で明示的に確定した `Locked Decisions` を Adaptive Implementation へ渡す APM package です。

通常経路は `adaptive-implementation-execution` です。この package は課題の難易度、risk、規模から Design Pair を自動選択、推奨、提案しません。

## Flow

```text
ordinary Plan / Implementation Intent
  -> design-pair-implementation-execution [explicit selection only]
  -> bounded Target Map presentation
  -> AWAITING_USER_INPUT / target-selection [mandatory turn stop]
  -> user-selected discussion and disposition
  -> AWAITING_USER_INPUT / disposition-confirmation [when needed]
  -> tracked Design Pair handoff / READY_FOR_ADAPTIVE_IMPLEMENTATION
  -> adaptive-implementation-execution
       -> high-implementation-starter
       -> optional standard-implementation-completer
       -> high-implementation-starter on re-entry
```

Plan Coverage Flow では `implementation-handoff-review` または同等の Inline Ready Gate が implementation を許可した後に Design Pair を開始します。parent state は interaction stage と tracked handoff path を保持し、waiting 中に Adaptive / verification へ進みません。Design Pair は upstream guardrails、Adaptive orchestration、verification、residual decision を置き換えません。

## Package contents

| Content | Path |
| --- | --- |
| Design Pair orchestration skill | `.apm/skills/design-pair-implementation-execution/SKILL.md` |
| Target Map reference | skill の `map.md` |
| Tracked handoff reference | skill の `handoff.md` |
| Usage guide | `docs/usage-guide.md` |
| Validation scenarios | `docs/examples/design-pair-validation.md` |
| Real-model multi-turn smoke fixture | `tests/manual-model-smoke/` |
| Static validator | `scripts/validate.ps1` |

Adaptive Implementation の HIGH / STANDARD orchestration と portable agent 定義は、この package へ複製しません。manifest dependency で既存 `adaptive-implementation-execution` skill と canonical agents を導入します。

## Fresh Codex install

Design Pair は Adaptive Implementation の前段です。fresh Codex target では両 package を導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target codex,agent-skills
```

APM が concrete model / reasoning / sandbox 設定を持たない custom agent TOML を生成する環境では、source repository checkout にある Adaptive 補助スクリプトで HIGH / STANDARD profile を完成させます。

```powershell
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- . --dry-run
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- .
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- . --check
```

`--check` は HIGH / STANDARD が別agent・別model mappingを持ち、reasoning と `workspace-write` sandbox が設定済みであることを確認します。APM が同等のconcrete設定を直接生成した場合、write stepは不要ですが `--check` は実行します。詳細は Adaptive package の `docs/install-guide.md` を参照してください。

現行の正式 target は `codex` と `agent-skills` です。Design Pair package単体のinstallだけでは、CodexのHIGH / STANDARD concrete model mappingが完成した証拠になりません。GitHub Copilot の Design Pair -> Adaptive end-to-end route は未検証であり、対応済みとは扱いません。

通常 Plan Mode 後の起動例:

```text
$design-pair-implementation-execution を明示的に選びます。
直前の Plan の予定変更面を調査し、Target Map と内部設計判断候補を提示してください。
私が議論対象と初期案を回答するため、そこで停止してください。
対話で disposition が確定した後に Adaptive Implementation へ進んでください。
```

利用者が毎回「停止してください」と補足する必要はありません。最初の依頼が単に「実装してください」であっても、Skill は Target Map を提示し、`AWAITING_USER_INPUT / target-selection` を保存してその turn を終了します。Target Map 提示前の Plan / Issue / gold document や利用者の技術案は upstream constraint / initial position であり、Design Pair Locked Decision ではありません。

Plan Coverage Flow で使う場合は、この package と Plan Coverage package の両方を Codex / agent-skills target へ導入し、flow 開始時に Design Pair を明示選択します。

## Validation

```powershell
./apm-packages/design-pair-implementation-execution/scripts/validate.ps1
./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs
git diff --check
```

static validator は mandatory turn stop、waiting schema、post-map user evidence、空集合 readiness の禁止、Plan Coverage / resume 伝播を確認します。実モデルの multi-turn behavior を static validation の PASS だけで証明済みとは扱いません。`tests/manual-model-smoke/README.md` の disposable fixture を使い、初回停止から disposition 後の Adaptive 開始までを別途記録します。

## Troubleshooting

- 初回 turn で `READY_FOR_ADAPTIVE_IMPLEMENTATION` が返った場合: handoff を READY として使用せず、`AWAITING_USER_INPUT / target-selection` へ修復し、Target Map 提示後の利用者応答を取り直します。
- upstream Plan の文言が `DP-Dxx` へ変換された場合: entry を `Upstream Binding Constraints` または `Upstream User Initial Positions` へ戻し、post-map confirmation evidence が得られるまで Locked Decision を作りません。
- resume で interaction stage、presentation evidence、user response evidence が欠ける場合: AI が補完せず `BLOCKED` / artifact repair とします。
- 利用者が全 Target を Adaptive に委ねたい場合: Target Map 提示後の明示応答を記録すれば、個別対話や人工的な Locked Decision は不要です。
