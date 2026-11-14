# Installation and Maintenance

この文書は、複数packageやrepository-local toolにまたがるinstaller details、maintainer手順、変更後のvalidation matrixをまとめたreferenceです。目的別の選択と簡潔なQuickstartはroot README、package固有の利用契約は各package READMEを先に参照してください。

## Choose an installation entrypoint

| Entrypoint | Use when | Installs or verifies |
| --- | --- | --- |
| `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs` | always-on Codex callback runtimeをuser-level設定へ導入する | canonical runtime、Local Spool provider、user-level `notify` |
| `apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs` | APM global導入後にportable contractを照合し、対象profile fieldsだけを補完する | 親のprofile継承検査と子の3profile fields。本文はAPMが配布する |
| `apps/PurposeReviewRunner` | OS user単位のconfigでpurpose reviewerを起動し、同じsessionを最大3roundまで維持する。長時間reviewはworkerへ分離し、`status`で結果を取得する | versioned Runner binary、user-level config、minimal run/job state |
| `apm-packages/persistent-purpose-review` | 元のimplementation parentへcontext選択、修正、同一runの再reviewを教える | 実行環境へ`--global`で導入する `$persistent-purpose-review` Skill |
| `apm-packages/*/codex-profile-overlays.json` | owning packageごとのprofile推奨値を宣言する | agent、model、reasoning、sandbox |
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

対象の6 process packageは`apm install --global`を正式な導入本体とします。Adaptiveは共通finalizer packageへ依存し、Plan CoverageとDesign Pairは既存のAdaptive Implementation package boundary dependencyを通じて同じfinalizerを利用します。PR Review RemediationとPersistent Purpose Review Skillはprofileを持たず、PR Review RemediationはSkillとcollectorだけを導入し、Persistent Purpose ReviewはRunnerをAPMに含めません。source repository checkoutは通常導入に不要です。

Plan Coverageのcanonical authoring sourceは`apm-packages/plan-coverage-residual-flow/.apm/`です。source repository rootにpackage runtime projection（`.github/agents/`、`.github/instructions/`、`.codex/agents/`、`.agents/skills/`）をchecked-inしません。canonical contractを修正するときは`.apm`を修正し、runtime projectionの正しさはAPM install smokeで検証します。

同じownershipを7つのprocess packageへ適用します。Agent Plugin artifactはpackage rootへchecked-inせず、共通builderがtemporary stageで`apm pack --format plugin`を実行します。

user-global導入のあとは、OSのユーザーホーム配下の`~/.apm`と`CODEX_HOME`（未設定時は`~/.codex`）を使います。

```powershell
$apmUserHome = if ($env:OS -eq 'Windows_NT') { $env:USERPROFILE } else { $env:HOME }
$apmHome = Join-Path $apmUserHome '.apm'
$moduleRoot = Join-Path $apmHome 'apm_modules\suusanex\coding_agent_plan_and_verify_process'
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- --global --dry-run
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- --global
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- --global --check
```

`--dry-run`と`--check`はAPM実行やfile書き込みを行いません。Finalizerが変更するのは子の3profile fieldsだけです。親のprofile不在とportable contractを検査します。本文、独自key、commentは保持し、不一致・衝突・欠落は上書きせず失敗します。異なる明示済みprofile値を推奨値へ更新するときだけ`--force`を使用します。

## Global lifecycle

global配布の検証対象はAPM v0.26.0です。この版のglobal storeはWindowsの`USERPROFILE`、他OSの`HOME`を基準とする`~/.apm`であり、`APM_HOME`はglobal storeのoverrideとして扱われません。Codexの`CODEX_HOME`は別に解決します。後続APM版の追加home overrideやtarget変更を、この検証結果から保証しません。

検証版は[公式v0.26.0 Release](https://github.com/microsoft/apm/releases/tag/v0.26.0)から取得し、`apm --version`で版を確認してください。開発用のglobal smokeもこの版を要求します。

v0.26.0のagent配布先は`~/.codex/agents`と`~/.copilot/agents`、Skill配布先は`~/.agents/skills`です。別の`CODEX_HOME` / `COPILOT_HOME`を指定してもAPMのagent出力先は変わりません。この版の正式運用は標準runtime homeを利用する構成です。非標準runtime homeへのAPM導入はサポート対象外とし、一時repositoryや手動TOMLコピーによる補完は案内しません。Finalizer自体は`CODEX_HOME`を解決し、そこにAPM投影がなければ失敗します。

APMは管理外の同名agentを上書きせずskipしますが、その場合もinstallの終了コードは0になります。出力の`local files exist, not managed by APM`を確認し、衝突が残ったままprocessを開始しないでください。元の所有者と内容を確認して既存agentを別名で保持するなど、利用者が衝突を解消した後に再installします。APMの`--force`で無関係なagentを上書きする手順は案内しません。CodexではFinalizerもportable contract不一致を拒否します。

APMの再installがCodex profile補完をリセットする場合があるため、再install後もFinalizerの適用と`--check`を行います。Finalizer単独の再実行は差分を作りません。

Adaptive、Design Pair、Plan Coverage、PR Review Remediation、Goal Context Authoring、Persistent Purpose ReviewはOSユーザー単位で導入します。正式なscopeは`--global`のみです。依存packageはAPMが解決するため、Design Pair / Plan CoverageのためにAdaptiveやFinalizerをwork repositoryへ追加installしません。

```powershell
apm update --global
```

Codexを利用する場合は更新後に上記Finalizerを再実行し、`--check`を成功させます。Runner binary、通知Runtime、InboxはAPM更新の対象ではありません。

削除するpackageを指定してglobal uninstallします。例えばPR Review Remediationだけを削除する場合は次を実行します。

```powershell
apm uninstall pr-review-remediation --global
```

他のprocessが依存するAdaptive / Finalizerは依存元の利用状況を確認してから削除します。APMがユーザー編集として保持した生成物は、内容とownershipを確認して整理します。無関係なagent、設定、`AGENTS.md`、他packageのファイルをまとめて削除しません。

### 旧local配置からの切替

1. 各work repositoryの`apm.yml` / lockfileと生成物を確認し、対象packageの独自編集を退避します。旧dependencyをAPM uninstallで外します。この整理操作は旧local配置に対して行い、global uninstallと混同しません。
2. 残った対象package由来の`.agents/skills`、`.github/agents`、`.codex/agents`、Plan Coverage共有instructionsを差分で確認して手動整理します。他dependency・独自agent・一般設定・`AGENTS.md`を保持します。ディレクトリ全体の一括削除は行いません。
3. 必要なprocess packageを`--global`で導入し、CodexではFinalizerの適用と`--check`を成功させます。本文不一致は自動修復せず、APM配布と独自編集の衝突を解消します。
4. 任意の2つのwork repositoryで、追加APM installやlocal projectionなしに同じglobal Skill / agentを利用できることを確認します。Plan Coverage agent内に共有guardrailが含まれ、通常のCopilot instructionsへ追加されていないことも確認します。これを切替完了条件とします。

local互換経路や自動削除は提供しません。global installの検証は隔離HOME / USERPROFILE / APM_HOME / CODEX_HOME等で実行し、実ユーザー領域を変更しません。

## Documentation ownership

- repository root `README.md`はpurpose-oriented selection、簡潔なQuickstart、package relationship overview、repository-local / user-level / local application installation scopeを所有する。
- APM package READMEはpackage固有のusage、install、update、remove、collision contractを所有する。
- non-APM applicationとruntimeは、それぞれ`apps/<name>/README.md`と`scripts/<name>/README.md`を正本にする。
- Persistent Purpose Reviewの文書役割は次で分ける。`apm-packages/persistent-purpose-review/README.md`は利用者の入口とSkill利用、`apps/PurposeReviewRunner/README.md`はRunnerのインストール・設定・update・troubleshooting、`docs/purpose-review-runner-technical-reference.md`はprotocol / state / worker / provider adapter、`docs/purpose-review-runner-maintenance.md`はbuild / release / validation、`docs/purpose-review-runner-compatibility.md`はversion履歴と非互換。
- PR Review Remediationの文書役割は、`apm-packages/pr-review-remediation/README.md`が利用者の入口とSkill利用、`docs/pr-review-remediation-technical-reference.md`がworkflow / artifact / trust boundary / Git contract / terminal semantics / maintainer validation、Skill内の`references/troubleshooting.md`と`references/migration.md`がfailure別対応とversion境界を所有する。
- `docs/installation-and-maintenance.md`はcross-package installer details、maintainer procedures、validation matrix、global lifecycleと通知runtimeの保守を所有する。
- その他のlong-form design、requirements、validation results、historical notesは`docs/`に残し、利用者向けREADMEからreferenceとして分離する。
- `plans/**`は実行artifactとhistorical recordであり、一般ドキュメント再編の対象にしない。

## Notification runtime

通知runtimeの正本は`scripts/codex-notification-runtime/`です。APM packageへのmirrorは提供しません。Runtime、Codex Local Inbox、PurposeReviewRunnerは独立した配布・検証を維持します。

## Validation matrix

repository rootから、変更したownership surfaceに対応するcheckを実行します。

| Check owner | Trigger input | Proves | Does not prove |
| --- | --- | --- | --- |
| package-local validator | owning packageのcanonical contract、manifest、owned docs、fixture | package自身のsemanticsとowned assetの整合 | dependency package内部やremote materialization |
| `validate-process-package-boundaries.cs` | Adaptive / Design Pair / Plan Coverage / Codex profile finalizerの公開境界 | manifest dependency direction、route・handoff・re-entry・profile mappingの互換性 | provider validator内部実装や具体package version一致 |
| Process Package Compatibility distribution matrix | `.apm/**`、manifest、profile overlay、finalizer、install smoke | Adaptive単体、Design Pair transitive closure、Plan Coverage installed-root lifecycleの該当failure mode | external-model runtime semantics |
| Agent Plugin package matrix | package-local Agent Plugin input | 変更packageのbundle、provenance、qualification record | 他packageの同一検査 |
| Repository Layout workflow | 全pull request | source rootにruntime projectionが存在しないこと | package semantics |

Goal Context AuthoringとSolution Shape Authoringはauthoring promptを中心資産とし、独立したruntime実行器を持ちません。promptや生成結果の意味品質は、このvalidation matrixの対象には含めません。

cross-package compatibilityと変更scopeはBCLだけのFile-based Appで検証します。

```powershell
dotnet run --file ./scripts/validate-process-package-boundaries.cs -- validate
dotnet run --file ./scripts/validate-process-package-boundaries.cs -- self-test
```

GitHub Actionsにはjob単位のpath filterがないため、このアプリが`git diff`から必要なdistribution closureとAgent Plugin packageだけを選択します。分類器自身を変更した場合は、分類漏れを自己検証できないため全distribution closure、全Agent Plugin package、Plan Coverageの全専門jobを実行します。一般的なglob engineは実装せず、repositoryで公開しているpackage pathと共有validator pathだけをordinal比較します。第三者path-filter Actionは追加のsupply-chain dependencyになるため採用しません。

### Notification runtime

```powershell
./scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1
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

利用者向け手順は[Persistent Purpose Review README](../apm-packages/persistent-purpose-review/README.md)と[Purpose Review Runner README](../apps/PurposeReviewRunner/README.md)です。Releaseとlocal buildは[Runner maintainer reference](purpose-review-runner-maintenance.md)を正本とします。

```powershell
dotnet test ./tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj
./apm-packages/persistent-purpose-review/scripts/validate-persistent-purpose-review.ps1
./apm-packages/persistent-purpose-review/scripts/test-apm-package-install.ps1 -Repository suusanex/coding_agent_plan_and_verify_process -Ref '<candidate-branch>'
dotnet publish ./apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r win-x64 --self-contained true
dotnet publish ./apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r linux-x64 --self-contained true
```

外部providerを使うsemantic persistence qualificationはManualOnlyです。Codex/Grokはsame-sessionとfresh control、Copilotはsession/resume成立までを別々に記録し、deterministic CIのPASSを実model evidenceとして扱いません。

### Plan Coverage

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-full-coverage-e2e.ps1
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow-apm-smoke.ps1 -Repository suusanex/coding_agent_plan_and_verify_process -Ref '<candidate-branch>'
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

global配布smokeの`<candidate-branch>`は検証対象のremote branchに置き換えてください。APM v0.26.0を使用し、実ユーザーのhomeを変更しない隔離環境で実行します。

検証用wrapperで候補をSHA指定する場合は、`-Ref <40桁の候補SHA>`と`-UpdateRef <同じSHAを指すbranch>`を併用します。共通C# smokeの対応引数は`--ref`と`--update-ref`です。branch先端の一致を検査したうえで、独立targetの導入はSHA、正常なupdate lifecycleはbranchで確認します。これはAPMの追加optionではありません。
