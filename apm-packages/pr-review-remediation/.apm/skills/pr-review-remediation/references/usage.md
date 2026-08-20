# Usage

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- . --dry-run
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- . --check
```

この導入はbaseline PR reviewに必要なSkill、agent、profileだけを導入します。

## Start Phase 1

これはbaseline PR reviewの入口です。継続的な目的達成reviewが必要な場合は、別packageの`$persistent-purpose-review`を明示指定します。

```text
$pr-review-remediation を使って、このbranchのPRをレビュー反映プロセスで処理してください。
base/headとPRを成立させ、Codex/Copilot reviewを収集し、review-plan.mdを作成したところで親ターンを停止してください。
```

PRを明示する場合:

```text
$pr-review-remediation を使って owner/name#123 を処理してください。
出力先は .review/pr-123 としてください。
```

## Start Phase 2

Phase 1が`READY_FOR_ADAPTIVE_IMPLEMENTATION`になり、利用者が別の親ターンでの実装を選んだ場合だけ、Adaptiveをoptional add-onとして別途導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- . --check
```

Adaptiveのmodel mapping、agent validation、installation policyは既存Adaptive helperをsource of truthとして使います。その後、別の親ターンで開始します。

```text
$adaptive-implementation-execution を使って .review/pr-123/review-plan.md を実装してください。
review-plan.md の implementation_intent を source of truth とし、既存 Adaptive Implementation の router、agents、verdict、handoff、validation contract を変更または複製しないでください。
```

Phase 1の停止は全体完了ではありません。Phase 2の`COMPLETED_BY_HIGH_MODEL`または`COMPLETED`も、既存Adaptive contractどおりfinal code reviewや独立verificationの完了を意味しません。

## Artifacts

| Artifact | Owner | Purpose |
| --- | --- | --- |
| `review-context.json` | collector | machine-readable PR/review/check context |
| `review-context.md` | collector | human-readable context |
| `pr-diff.patch` | collector | confirmed remote base/head patch |
| `local-review-findings.md` | parent from local-reviewer output | local Codex findings |
| `review-plan.md` | parent from review-planner output | Adaptive-ready remediation plan |

`$persistent-purpose-review`は別run、別stateを所有し、このartifact集合へ目的review結果を混在させません。

## Reproduce validation

実agent chainの固定証跡は`tests/pr-review-remediation/PRR-001/`に保存します。認証済みCodex環境で更新する場合:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -DescribePayload

pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -ConfirmExternalModelPayload
```

`-DescribePayload`は外部modelへ送信せず対象一覧を表示します。内容を確認して送信を明示承認した場合だけ、`-ConfirmExternalModelPayload`を付けて実行します。許可optionがない実行は`HUMAN_DECISION_REQUIRED`で停止します。

固定証跡を含むlocal validation:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
```

APM 0.26.0でPR headまたは指定commitから別の一時repositoryへ実導入するremote smoke:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1 `
  -Repository owner/repository `
  -Ref <commit-sha>
```

remote smokeはtransitive `git: parent`依存、baseline Skill、2 canonical agents、relative assets、2 concrete profilesを検証し、`AGENTS.md`と`.codex/config.toml`のsentinelが不変であることを確認します。一時directoryは成否にかかわらず削除されます。
