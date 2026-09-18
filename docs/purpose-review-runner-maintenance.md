# Purpose Review Runner Maintenance

この文書は、Purpose Review Runnerの開発、Release、validationを所有するmaintainer向けです。通常利用の導入・設定・更新は[Purpose Review Runner README](../apps/PurposeReviewRunner/README.md)を正本とします。

## Version source of truth

Runner versionの正本は次の2箇所です。Release前に両者を一致させます。

- `apps/PurposeReviewRunner/Contracts.cs` の `Protocol.RunnerVersion`
- `apps/PurposeReviewRunner/PurposeReviewRunner.csproj` の `<Version>`

protocol versionの正本は `apps/PurposeReviewRunner/Contracts.cs` の `Protocol.Version` です。現在はprotocol v3です。

## Release

既存のtag contractに従い、`purpose-review-runner-v<runner-version>` tagを作成してpushします。例えばversionが`0.3.0`なら次です。

```powershell
git tag purpose-review-runner-v0.3.0
git push origin purpose-review-runner-v0.3.0
```

`purpose-review-runner-v*` tag pushで`.github/workflows/release-purpose-review-runner.yml`が起動します。workflowは次を担当します。

- test
- Windows `win-x64` / Linux `linux-x64` のself-contained publish
- tagとRunner versionの整合確認
- sample configの同梱
- archive、checksum、GitHub Release作成

tagとRunner versionが一致しない場合は検証で失敗し、Releaseは作成されません。同じversionのtagまたはReleaseが既に存在する場合は、重複発行せず既存の状態を調査します。

Releaseには次のassetが生成されます。

- `purpose-review-runner-win-x64.zip`
- `purpose-review-runner-linux-x64.tar.gz`
- `config.example.json`
- `SHA256SUMS`

通常利用者の配布経路はGitHub Releaseです。`dotnet publish`の成果物を手動配布する用途ではありません。

## Build locally

以下は開発・検証用、またはRelease前のローカルbuild／unreleased buildの手動検証用です。

```powershell
dotnet test tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj
dotnet publish apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r win-x64 --self-contained true
dotnet publish apps/PurposeReviewRunner/PurposeReviewRunner.csproj -c Release -r linux-x64 --self-contained true
```

通常のunit / CI testはJob ObjectとWMIをスタブします。Linux CIはdetached workerのprocess-level寿命確認を維持します。Windowsの実Job Object / 実WMI経路はopt-in qualificationです。

```powershell
$env:PURPOSE_REVIEW_RUNNER_WINDOWS_JOB_QUALIFICATION = '1'
dotnet test tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj --filter "FullyQualifiedName~RestrictiveJobObjectDoesNotKillDurableWorker|FullyQualifiedName~DetachedStartReturnsBeforeProviderAndStatusReadsDurableResult"
```

## Validation

repository rootから、RunnerとSkillの所有surfaceに対応するcheckを実行します。

```powershell
dotnet test ./tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj
./apm-packages/persistent-purpose-review/scripts/validate-persistent-purpose-review.ps1
./apm-packages/persistent-purpose-review/scripts/test-apm-package-install.ps1
```

外部providerを使うsemantic persistence qualificationはManualOnlyです。Codex/Grokはsame-sessionとfresh control、Copilotはsession/resume成立までを別々に記録し、deterministic CIのPASSを実model evidenceとして扱いません。

実モデルでの追加評価は[評価シナリオ](../tests/PurposeReviewRunner.Tests/purpose-review-scenarios.md)を使い、結果をdeterministic testとは分けて記録します。Codex CLIとGrok Build CLIはsemantic persistenceをfresh control付きで確認済みです。GitHub Copilot CLIはsession/resumeの成立を確認済みですが、fresh controlが正解を推測したため同じ強さのsemantic qualificationは与えていません。これらは過去のsession継続実験の証拠であり、現在のshell許可と`requiredOutcome`を含むレビュー依頼文による逸脱検出力を実測したことは意味しません。
