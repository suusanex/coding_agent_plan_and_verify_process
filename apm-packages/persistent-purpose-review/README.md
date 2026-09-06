# Persistent Purpose Review

`$persistent-purpose-review`は、元のimplementation parentが独立purpose reviewerのfindingを自分で修正し、同じreviewer sessionへ再reviewを依頼するAPM Skillです。session lifecycleは別配布の`purpose-review-runner`が決定的に管理します。

## Ownership boundary

| Component | Installation scope | Responsibility |
| --- | --- | --- |
| `purpose-review-runner` | 開発PCのOS userごとに一度 | provider CLI起動、same-session、non-modifying reviewer、最大3round、state、machine-readable result |
| `$persistent-purpose-review` | 利用するwork repositoryごと | purpose context選択、parent-owned remediation、terminal reporting |
| `$pr-review-remediation` | baseline PR reviewが必要なrepositoryごと | Goal Contextを使わないPR review plan作成 |

SkillはRunner binaryを内包、複製、自動download、installしません。このSkillは`purpose-review-runner` 0.2.3以上とprotocol v2を要求します。0.2.3で調査用shellの許可と、修正による目的逸脱・前回指摘の訂正を含むレビュー依頼を導入しました。0.2.2以前にはこの契約がありません。Runner未導入、0.2.3未満、またはprotocol非互換ならfail closedで停止します。

## Install

先に[Purpose Review Runner](../../apps/PurposeReviewRunner/README.md)のversioned GitHub ReleaseをOS user単位で導入し、configを作成します。その後、対象repository rootでSkillを導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/persistent-purpose-review --target copilot,codex,agent-skills
purpose-review-runner version
```

## Use

通常の実装指示へ次を加えます。

```text
実装完了後は $persistent-purpose-review に従ってpurpose reviewを完了してください。
```

Goal Contextやaccepted decision documentが会話で明示済みなら、そのpathも指定できます。補完関係にある複数文書はすべてcontextとして渡せます。現在のsourceが競合する場合だけ、parentがreview開始前に質問します。

contextは元の問題・期待成果、承認されたscope・採用判断、実装方針を区別して選びます。新しい計画であることだけを理由に当初目的を置き換えません。明示されたbaseやPRがある場合はcontext内に比較対象を記載しますが、PRやレビュー専用commitの作成は不要です。

reviewerはshellでGit差分・履歴と現在の実装を調査し、目的の未達成、表面的な充足、周辺機構への偏り、修正による逸脱を毎round評価します。前回指摘も訂正・撤回の対象です。parentは指摘された方式へ無条件に追従せず、目的に必要な振る舞いと制約に照合して修正します。削除・縮小も修正候補です。変更禁止はshell経由にも適用する役割契約です。

`start`と`continue`は短時間でjobを登録するだけです。結果は同じ`runId`の`status`をpollingして取得します。`FINDINGS`では元のparentだけが修正とvalidationを行い、同じ`runId`で`continue`します。`COMPLETE`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`で終了します。polling中のCLI失敗では`status`だけをやり直します。

## Update and remove

```powershell
apm update
apm uninstall persistent-purpose-review
```

APM packageの更新・削除はRunner binary、user-level config、既存run stateを変更しません。`apm update`だけではreviewerのshell許可やレビュー依頼文は更新されません。Runner 0.2.3以上への更新はGitHub Release側で別に行います。進行中のrunの途中でRunnerを差し替えず、更新後の新しい作業から利用します。

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
