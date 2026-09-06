# Persistent Purpose Review

`$persistent-purpose-review`は、元のimplementation parentが独立purpose reviewerのfindingを自分で修正し、同じreviewer sessionへ再reviewを依頼するAPM Skillです。session lifecycleは別配布の`purpose-review-runner`が決定的に管理します。

## Ownership boundary

| Component | Installation scope | Responsibility |
| --- | --- | --- |
| `purpose-review-runner` | 開発PCのOS userごとに一度 | provider CLI起動、same-session、non-modifying reviewer、最大3round、state、machine-readable result |
| `$persistent-purpose-review` | 利用するwork repositoryごと | purpose context選択、parent-owned remediation、terminal reporting |
| `$pr-review-remediation` | baseline PR reviewが必要なrepositoryごと | Goal Contextを使わないPR review plan作成 |

SkillはRunner binaryを内包、複製、自動download、installしません。このSkillは`purpose-review-runner` 0.3.0以上とprotocol v3を要求します。0.3.0ではfindingの必須項目を`requiredChange`から`requiredOutcome`へ変更しました。reviewerは必要成果を示し、具体的な修正設計はparentが所有します。0.2.3で導入したshell調査と目的逸脱レビューは維持します。Runner未導入、0.3.0未満、またはprotocol非互換ならfail closedで停止します。

## Install

先に[Purpose Review Runner](../../apps/PurposeReviewRunner/README.md)のversioned GitHub ReleaseをOS user単位で導入し、configを作成します。その後、対象repository rootでSkillを導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/persistent-purpose-review --target copilot,codex,agent-skills
purpose-review-runner version
```

### Reviewer configuration

`$persistent-purpose-review`はreviewerのprovider、model、reasoning effortを選択しません。これらはOS user単位の`purpose-review-runner` configで指定します。Windowsでは通常`%APPDATA%\purpose-review-runner\config.json`です。configの`provider`、`model`、`reasoningEffort`と、必要に応じて`executable`、optional `profile`を設定します。利用可能なproviderと設定例は[Purpose Review Runner](../../apps/PurposeReviewRunner/README.md)とその`config.example.json`を参照してください。

`start`にはreview単位の`--model`や`--effort` overrideはありません。Runnerは`start`時のprovider設定をrun stateへsnapshotするため、その後にuser-level configを変更しても既存runへは反映されません。同じ`runId`で`continue`する再reviewは、同じreviewer sessionと同じprovider/model/reasoning effortで継続します。

## Use

通常の実装指示へ次を加えます。

```text
実装完了後は $persistent-purpose-review に従ってpurpose reviewを完了してください。
```

Goal Contextやaccepted decision documentが会話で明示済みなら、そのpathも指定できます。補完関係にある複数文書はすべてcontextとして渡せます。現在のsourceが競合する場合だけ、parentがreview開始前に質問します。

contextは元の問題・期待成果、承認されたscope・採用判断、実装方針を区別して選びます。新しい計画であることだけを理由に当初目的を置き換えません。明示されたbaseやPRがある場合はcontext内に比較対象を記載しますが、PRやレビュー専用commitの作成は不要です。

reviewerはshellでGit差分・履歴と現在の実装を調査し、目的の未達成、表面的な充足、周辺機構への偏り、修正による逸脱を毎round評価します。前回指摘も訂正・撤回の対象です。parentは指摘された方式へ無条件に追従せず、目的に必要な振る舞いと制約に照合して修正します。削除・縮小も修正候補です。変更禁止はshell経由にも適用する役割契約です。

`requiredOutcome`は目的達成のために成立すべき状態・振る舞い・制約を示します。例えば「ユーザーが確定した構成が下流生成のauthorityとなり、LLMの生成outlineに上書きされないこと」で十分です。関数単位の修正指示は不要であり、複数componentにまたがる責務・authorityの逆転もfindingとして扱います。実装方式が未確定という理由だけでは却下しません。

`start`と`continue`は短時間でjobを登録するだけです。結果は同じ`runId`の`status`をpollingして取得します。`FINDINGS`では元のparentだけが修正とvalidationを行い、同じ`runId`で`continue`します。`COMPLETE`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`で終了します。polling中のCLI失敗では`status`だけをやり直します。

## Update and remove

```powershell
apm update
apm uninstall persistent-purpose-review
```

APM packageの更新・削除はRunner binary、user-level config、既存run stateを変更しません。`apm update`だけではRunnerの結果形式やレビュー依頼文は更新されません。Runner 0.3.0以上への更新はGitHub Release側で別に行います。v2のrunは開始時のRunnerで完了させ、更新後の新しい作業からv3を利用します。旧findingの自動変換、進行中runの移行、移行のためのsession再作成は行いません。

## Validation

```powershell
pwsh -NoProfile -File apm-packages/persistent-purpose-review/scripts/validate-persistent-purpose-review.ps1
pwsh -NoProfile -File apm-packages/persistent-purpose-review/scripts/test-apm-package-install.ps1
```

## Agent Plugin artifact

process semanticsの正本はこのpackageの`.apm/**`です。Agent Plugin artifactはpackage rootへchecked-inせず、repository共通builderでtemporary stageへ生成します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package persistent-purpose-review
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package persistent-purpose-review
```

APMがsupported distributionです。direct deploymentのstatusとevidenceは`tests/agent-plugin/qualification.json`に記録し、未観測のbehaviorをPASSへ昇格させません。
