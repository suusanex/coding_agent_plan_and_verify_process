# Installation and Maintenance

この文書は、複数packageやrepository-local toolにまたがるinstaller details、maintainer手順、変更後のvalidation matrixをまとめたreferenceです。目的別の選択と簡潔なQuickstartはroot README、package固有の利用契約は各package READMEを先に参照してください。

## Choose an installation entrypoint

| Entrypoint | Use when | Installs or verifies |
| --- | --- | --- |
| `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs` | always-on Codex callback runtimeをuser-level設定へ導入する | canonical runtime、Local Spool provider、user-level `notify` |
| `apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs` | PR Review Remediation導入後にconcrete Codex reviewer profilesを同期する | `.codex/agents/local-reviewer.toml`、`purpose-reviewer.toml`、`review-planner.toml` |
| Goal Context Skill `scripts/execute-reviewer.cs` | typed設定でCodex exec / GitHub Copilot CLI reviewerを決定的に起動・待機・raw保存する | `round-NNN/{role}.raw.md`、`{role}.execution.json` |
| `apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs` | APM導入後にAdaptive Implementationのconcrete Codex profilesを補完する | `.codex/agents/high-implementation-starter.toml`、`standard-implementation-completer.toml` |
| `scripts/provision-work-repo-agents.cs` | 既存のPlan Coverage packageをAPM経由で導入し、Codex向け配置を補正する | `apm install`、HIGH / STANDARD agent TOML補正 |
| Goal Context validators | Goal Context authoring packageやfree-form文書を確認する | readability、package structure、APM install smoke |
| `scripts/validate-architecture-slice-readiness.ps1` | architecture readinessのagents、manifest、templates、routingを確認する | ASR contractとfixture evidence |

## Safe local installation pattern

File-based installerは、対応している場合に`--dry-run`、適用、`--check`の順で実行します。

```powershell
dotnet run --file <installer.cs> -- <target> --dry-run
dotnet run --file <installer.cs> -- <target>
dotnet run --file <installer.cs> -- <target> --check
```

同名fileの上書きが必要な場合だけ、内容とownershipを確認して`--force`を使います。installerごとの対象file、collision policy、`AGENTS.md`へのアクセス有無は各package READMEを参照してください。

## Existing APM provisioning helper

`scripts/provision-work-repo-agents.cs`は、Plan Coverage packageを`copilot,codex,agent-skills` targetで対象repositoryへ`apm install --update`し、APM変換後のHIGH / STANDARD Codex TOMLを補正します。Plan Coverage manifestはpackage-owned `.apm` primitivesを`includes: auto`で配布し、Adaptive Implementation package（`apm-packages/adaptive-implementation-execution`）へpackage boundary dependencyするため、この入口ではAdaptive packageを重ねてinstallしません。HIGH / STANDARD agentsとAdaptive SkillのownershipはAdaptive package側に残り、Codex concrete profile overlayだけがexisting provisioner ownershipです。Adaptive単独利用は専用packageのinstallerを使い、Design PairとPR Review Remediationは各package READMEの導入・同期手順を使います。

Plan Coverageのcanonical authoring sourceは`apm-packages/plan-coverage-residual-flow/.apm/`です。source repository rootにpackage runtime projection（`.github/agents/`、`.github/instructions/`、`.codex/agents/`、`.agents/skills/`）をchecked-inしません。canonical contractを修正するときは`.apm`を修正し、runtime projectionの正しさはAPM install smokeで検証します。

```powershell
dotnet run --file .\scripts\provision-work-repo-agents.cs -- C:\path\to\target --dry-run
dotnet run --file .\scripts\provision-work-repo-agents.cs -- C:\path\to\target
dotnet run --file .\scripts\provision-work-repo-agents.cs -- C:\path\to\target --check
```

`--dry-run`と`--check`はAPM実行やfile書き込みを行いません。canonical Adaptive agentのmodel mapping不一致など、既存値の補正を明示的に許可する場合だけ`--force`を使用します。

## Documentation ownership

- repository root `README.md`はpurpose-oriented selection、簡潔なQuickstart、package relationship overview、repository-local / user-level / local application installation scopeを所有する。
- APM package READMEはpackage固有のusage、install、update、remove、collision contractを所有する。
- non-APM applicationとruntimeは、それぞれ`apps/<name>/README.md`と`scripts/<name>/README.md`を正本にする。
- `docs/installation-and-maintenance.md`はcross-package installer details、maintainer procedures、validation matrix、runtime mirror maintenanceを所有する。
- その他のlong-form design、requirements、validation results、historical notesは`docs/`に残し、利用者向けREADMEからreferenceとして分離する。
- `plans/**`は実行artifactとhistorical recordであり、一般ドキュメント再編の対象にしない。

## Notification runtime mirrors

canonical notification runtime assetsは`scripts/codex-notification-runtime/`にあります。Completion Notification Decoratorは、installed Skillだけでruntimeを導入できるように、同じassetsを次へmirrorします。

```text
apm-packages/completion-notification-decorator/
  .apm/skills/completion-notification-decorator/assets/codex-notification-runtime/
```

runtime source、schema、producer / consumer contract、decision record、manual verificationを変更した場合はmirrorを同時に更新し、contract validatorとpackage install smokeでhash一致を確認します。

READMEは利用コンテキストごとに責務を分けます。canonical package READMEはsource checkoutのpackage pathからtarget repositoryへ導入する手順とsource側の検証を案内し、asset READMEは導入先repositoryの`.agents/skills/completion-notification-decorator/assets/codex-notification-runtime/`から実行できる手順を案内します。README同士はhash一致の対象にせず、asset READMEがsource repository固有の`scripts/codex-notification-runtime/`を要求しないことをvalidatorで確認します。

## Validation matrix

repository rootから、変更したownership surfaceに対応するcheckを実行します。

### Notification runtime and decorator

```powershell
./scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1
./apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator-contract.ps1
./apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1
./apm-packages/completion-notification-decorator/scripts/test-apm-package-install.ps1
```

### Goal Context Authoring

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1
./apm-packages/goal-context-authoring/scripts/test-apm-package-install.ps1
```

### Adaptive Implementation and Design Pair

```powershell
./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
./apm-packages/design-pair-implementation-execution/scripts/validate.ps1
```

### PR Review Remediation

```powershell
./apm-packages/pr-review-remediation/scripts/validate-same-parent-review.ps1
./apm-packages/pr-review-remediation/scripts/validate-execute-reviewer.ps1
./apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
```

外部modelへpayloadを送るagent smokeは通常の文書変更では実行しません。必要な場合は先に`-DescribePayload`で対象を確認し、明示承認後だけ`-ConfirmExternalModelPayload`を使います。

### Plan Coverage

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-full-coverage-e2e.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow-apm-smoke.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-runtime-qualification.ps1
./scripts/validate-architecture-slice-readiness.ps1
```

GitHub Copilot CLI runtime qualification (external model) is manual. See [Plan Coverage runtime qualification](plan-coverage-runtime-qualification.md). Do not add paid model invocation to ordinary pull_request CI.

### Common checks

```powershell
git diff --check
```

READMEやMarkdown linkを変更した場合は、相対linkのtargetが存在することも確認します。local static validatorのPASSは、real model independence、real GitHub mutation、Windows packaged app、Codex callback、remote APM installの実行証拠を意味しません。

## CI trigger policy

README navigation workflowは、リンク先だけの削除やrenameも検出するためpath filterを設けず、すべてのpull requestと`main`へのpushで実行します。package固有workflowでpath filterを使う場合は、READMEだけでなく、そのREADMEから参照するpackage-owned docs、scripts、schemaも起動対象へ含めます。documentation ownershipを移した場合は、validatorのassertion targetとworkflow triggerを同じ変更で確認します。
