# Design Pair Implementation Execution

利用者が明示的に選択した場合だけ、実装前に予定変更面を既存 code の file / symbol 単位で確認し、対話で明示的に確定した `Locked Decisions` を Adaptive Implementation へ渡す APM package です。

通常経路は `adaptive-implementation-execution` です。この package は課題の難易度、risk、規模から Design Pair を自動選択、推奨、提案しません。

## Flow

```text
ordinary Plan / Implementation Intent
  -> design-pair-implementation-execution [explicit selection only]
  -> tracked Design Pair handoff
  -> adaptive-implementation-execution
       -> high-implementation-starter
       -> optional standard-implementation-completer
       -> high-implementation-starter on re-entry
```

Plan Coverage Flow では `implementation-handoff-review` または同等の Inline Ready Gate が implementation を許可した後に Design Pair を開始します。Design Pair は upstream guardrails、Adaptive orchestration、verification、residual decision を置き換えません。

## Package contents

| Content | Path |
| --- | --- |
| Design Pair orchestration skill | `.apm/skills/design-pair-implementation-execution/SKILL.md` |
| Target Map reference | skill の `map.md` |
| Tracked handoff reference | skill の `handoff.md` |
| Usage guide | `docs/usage-guide.md` |
| Validation scenarios | `docs/examples/design-pair-validation.md` |
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
直前の Plan の予定変更面を調査し、私が選んだ論点だけを対話してから Adaptive Implementation へ渡してください。
```

Plan Coverage Flow で使う場合は、この package と Plan Coverage package の両方を Codex / agent-skills target へ導入し、flow 開始時に Design Pair を明示選択します。

## Validation

```powershell
./apm-packages/design-pair-implementation-execution/scripts/validate.ps1
./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs
git diff --check
```
