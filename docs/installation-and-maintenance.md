# Installation and Maintenance

この文書は、複数packageやrepository-local toolにまたがる導入入口と、変更後の検証方法をまとめたmaintainer向けreferenceです。各processの利用方法は、それぞれのpackage READMEを先に参照してください。

## Choose an installation entrypoint

| Entrypoint | Use when | Installs or verifies |
| --- | --- | --- |
| `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs` | always-on Codex callback runtimeをuser-level設定へ導入する | canonical runtime、Local Spool provider、user-level `notify` |
| `apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs` | PR Review Remediation導入後にconcrete Codex reviewer profilesを同期する | `.codex/agents/local-reviewer.toml`、`purpose-reviewer.toml`、`review-planner.toml` |
| `apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs` | APM導入後にAdaptive Implementationのconcrete Codex profilesを補完する | `.codex/agents/high-implementation-starter.toml`、`standard-implementation-completer.toml` |
| `scripts/provision-work-repo-agents.cs` | 既存のPlan Coverage / full-coverage packageをAPM経由で導入し、Codex向け配置を補正する | `apm install`、agent TOML補正、full-coverage templates |
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

`scripts/provision-work-repo-agents.cs`は、Plan Coverageやfull-coverage packagesを対象repositoryへ導入し、APM変換後のCodex TOMLとtemplate配置を補正します。Adaptive Implementationは専用packageのinstallerを使い、Design PairとPR Review Remediationは各packageのREADMEにある導入・同期手順を使います。

```powershell
dotnet run --file .\scripts\provision-work-repo-agents.cs -- C:\path\to\target --dry-run
dotnet run --file .\scripts\provision-work-repo-agents.cs -- C:\path\to\target
dotnet run --file .\scripts\provision-work-repo-agents.cs -- C:\path\to\target --check
```

`--dry-run`と`--check`はAPM実行やfile書き込みを行いません。canonical Adaptive agentのmodel mapping不一致など、既存値の補正を明示的に許可する場合だけ`--force`を使用します。

## Documentation ownership

- repository root `README.md`は目的別navigationだけを所有する。
- APM processとhelperの利用契約は`apm-packages/<name>/README.md`を入口にする。
- non-APM applicationとruntimeは、それぞれ`apps/<name>/README.md`と`scripts/<name>/README.md`を正本にする。
- long-form design、requirements、validation results、historical notesは`docs/`に残し、利用者向けREADMEからreferenceとして分離する。
- `plans/**`は実行artifactとhistorical recordであり、一般ドキュメント再編の対象にしない。

## Notification runtime mirrors

canonical notification runtime assetsは`scripts/codex-notification-runtime/`にあります。Completion Notification Decoratorは、installed Skillだけでruntimeを導入できるように、同じassetsを次へmirrorします。

```text
apm-packages/completion-notification-decorator/
  .apm/skills/completion-notification-decorator/assets/codex-notification-runtime/
```

runtime source、schema、producer / consumer contract、decision record、manual verificationを変更した場合はmirrorを同時に更新し、contract validatorとpackage install smokeでhash一致を確認します。

READMEは利用コンテキストごとに責務を分けます。canonical READMEはsource repository rootからの導入・検証を案内し、asset READMEは導入先repositoryの`.agents/skills/completion-notification-decorator/assets/codex-notification-runtime/`から実行できる手順を案内します。README同士はhash一致の対象にせず、asset READMEがsource repository固有の`scripts/codex-notification-runtime/`を要求しないことをvalidatorで確認します。

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
./apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
```

外部modelへpayloadを送るagent smokeは通常の文書変更では実行しません。必要な場合は先に`-DescribePayload`で対象を確認し、明示承認後だけ`-ConfirmExternalModelPayload`を使います。

### Plan Coverage and full-coverage

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow-copilot.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-copilot-full-package-install.ps1 -PackageName plan-coverage-residual-flow -Repository suusanex/coding_agent_plan_and_verify_process -Ref <full-commit-sha>
./scripts/validate-full-coverage-slice-flow.ps1
./apm-packages/token-aware-full-coverage-3layer/scripts/validate-token-aware-full-coverage-3layer-copilot.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-copilot-full-package-install.ps1 -PackageName token-aware-full-coverage-3layer -Repository suusanex/coding_agent_plan_and_verify_process -Ref <full-commit-sha>
./scripts/validate-architecture-slice-readiness.ps1
```

### Common checks

```powershell
git diff --check
```

READMEやMarkdown linkを変更した場合は、相対linkのtargetが存在することも確認します。local static validatorのPASSは、real model independence、real GitHub mutation、Windows packaged app、Codex callback、remote APM installの実行証拠を意味しません。

## CI trigger policy

README navigation workflowは、リンク先だけの削除やrenameも検出するためpath filterを設けず、すべてのpull requestと`main`へのpushで実行します。package固有workflowでpath filterを使う場合は、READMEだけでなく、そのREADMEから参照するpackage-owned docs、scripts、schemaも起動対象へ含めます。documentation ownershipを移した場合は、validatorのassertion targetとworkflow triggerを同じ変更で確認します。
