# Installation and Maintenance

この文書は、複数packageやrepository-local toolにまたがるinstaller details、maintainer手順、変更後のvalidation matrixをまとめたreferenceです。目的別の選択と簡潔なQuickstartはroot README、package固有の利用契約は各package READMEを先に参照してください。

## Choose an installation entrypoint

| Entrypoint | Use when | Installs or verifies |
| --- | --- | --- |
| `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs` | always-on Codex callback runtimeをuser-level設定へ導入する | canonical runtime、Local Spool provider、user-level `notify` |
| `apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs` | APM導入後にpackage-owned concrete Codex profilesを補完する | `.codex/agents/*.toml`のprofile fields |
| `apps/PurposeReviewRunner` | OS user単位のconfigでpurpose reviewerを起動し、同じsessionを最大3roundまで維持する。長時間reviewはworkerへ分離し、`status`で結果を取得する | versioned Runner binary、user-level config、minimal run/job state |
| `apm-packages/persistent-purpose-review` | 元のimplementation parentへcontext選択、修正、同一runの再reviewを教える | repository-local `$persistent-purpose-review` Skill |
| `apm-packages/*/codex-profile-overlays.json` | owning packageごとのprofile推奨値を宣言する | agent、model、reasoning、sandbox |
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

## APM installation and Codex profile finalizer

各 package は `apm install` を導入本体とします。Adaptive と PR Review Remediation は共通 finalizer packageへ依存し、Plan Coverage と Design Pairは既存のAdaptive Implementation package boundary dependencyを通じて同じ finalizerを利用します。Persistent Purpose Review Skillはprofileを持たず、RunnerをAPMに含めません。source repository checkoutは通常導入に不要です。

Plan Coverageのcanonical authoring sourceは`apm-packages/plan-coverage-residual-flow/.apm/`です。source repository rootにpackage runtime projection（`.github/agents/`、`.github/instructions/`、`.codex/agents/`、`.agents/skills/`）をchecked-inしません。canonical contractを修正するときは`.apm`を修正し、runtime projectionの正しさはAPM install smokeで検証します。

同じownershipを6つのprocess packageへ適用します。Agent Plugin artifactはpackage rootへchecked-inせず、共通builderがtemporary stageで`apm pack --format plugin`を実行します。

```powershell
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target --dry-run
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- C:\path\to\target --check
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

| Check owner | Trigger input | Proves | Does not prove |
| --- | --- | --- | --- |
| package-local validator | owning packageのcanonical contract、manifest、owned docs、fixture | package自身のsemanticsとowned assetの整合 | dependency package内部やremote materialization |
| `validate-process-package-boundaries.cs` | Adaptive / Design Pair / Plan Coverage / Codex profile finalizerの公開境界 | manifest dependency direction、route・handoff・re-entry・profile mappingの互換性 | provider validator内部実装や具体package version一致 |
| Process Package Compatibility distribution matrix | `.apm/**`、manifest、profile overlay、finalizer、install smoke | Adaptive単体、Design Pair transitive closure、Plan Coverage installed-root lifecycleの該当failure mode | external-model runtime semantics |
| Agent Plugin package matrix | package-local Agent Plugin input | 変更packageのbundle、provenance、qualification record | 他packageの同一検査 |
| Repository Layout workflow | 全pull request | source rootにruntime projectionが存在しないこと | package semantics |

cross-package compatibilityと変更scopeはBCLだけのFile-based Appで検証します。

```powershell
dotnet run --file ./scripts/validate-process-package-boundaries.cs -- validate
dotnet run --file ./scripts/validate-process-package-boundaries.cs -- self-test
```

GitHub Actionsにはjob単位のpath filterがないため、このアプリが`git diff`から必要なdistribution closureとAgent Plugin packageだけを選択します。一般的なglob engineは実装せず、repositoryで公開しているpackage pathと共有validator pathだけをordinal比較します。第三者path-filter Actionは追加のsupply-chain dependencyになるため採用しません。

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
dotnet run --file ./scripts/validate-process-package-boundaries.cs -- validate
```

### PR Review Remediation

```powershell
./apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
```

外部modelへpayloadを送るagent smokeは通常の文書変更では実行しません。必要な場合は先に`-DescribePayload`で対象を確認し、明示承認後だけ`-ConfirmExternalModelPayload`を使います。

### Persistent Purpose Review

```powershell
dotnet test ./tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj
./apm-packages/persistent-purpose-review/scripts/validate-persistent-purpose-review.ps1
./apm-packages/persistent-purpose-review/scripts/test-apm-package-install.ps1
dotnet publish ./apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r win-x64 --self-contained true
dotnet publish ./apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r linux-x64 --self-contained true
```

外部providerを使うsemantic persistence qualificationはManualOnlyです。Codex/Grokはsame-sessionとfresh control、Copilotはsession/resume成立までを別々に記録し、deterministic CIのPASSを実model evidenceとして扱いません。

### Plan Coverage

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-full-coverage-e2e.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow-apm-smoke.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-runtime-qualification.ps1
./scripts/agent-plugins/validate-agent-plugin-packages.ps1
./scripts/agent-plugins/validate-agent-plugin-qualification.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-agent-plugin.ps1
./scripts/validate-architecture-slice-readiness.ps1
```

Agent Plugins bundle conformance / provenance validation is deterministic and belongs to ordinary CI. GitHub Copilot CLI runtime qualification and Agent Plugins direct-load qualification (external model) are manual, explicit re-runs. See [repository-wide runtime qualification](agent-plugin-runtime-qualification.md)、[Plan Coverage runtime qualification](plan-coverage-runtime-qualification.md)、[Agent Plugins adoption strategy](agent-plugin-adoption-strategy.md). Do not add paid model invocation to ordinary pull_request CI.

### Common checks

```powershell
git diff --check
./scripts/validate-no-root-projections.ps1
```

`validate-no-root-projections.ps1`はsource repository rootにpackage runtime projection（`.github/agents/`、`.codex/agents/`、`.agents/skills/`、package-owned `.github/instructions/`）が再導入されていないことを全PRで検証します。CI workflow `.github/workflows/validate-repository-layout.yml`が全PRで無条件起動し、このcheckを実行します。

READMEやMarkdown linkを変更した場合は、相対linkのtargetが存在することも確認します。local static validatorのPASSは、real model independence、real GitHub mutation、Windows packaged app、Codex callback、remote APM installの実行証拠を意味しません。

## CI trigger policy

README navigation workflowは、リンク先だけの削除やrenameも検出するためpath filterを設けず、すべてのpull requestと`main`へのpushで実行します。package固有workflowはowning packageだけを起動対象とし、別packageの変更を理由にpackage-local validatorを再実行しません。公開境界の変更はProcess Package Compatibility workflow、distribution inputの変更は同workflowの該当closure、Agent Plugin inputの変更は変更packageだけを起動します。純粋な説明変更やroot README変更からremote install smokeを起動しません。documentation ownershipを移した場合は、validatorのassertion targetとworkflow triggerを同じ変更で確認します。
