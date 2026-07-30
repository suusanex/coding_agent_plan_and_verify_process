# Goal Context same-parent PR review usage

## Normal path

初回実装、validation、Ready PR作成を担当した同じ親taskで、次だけを依頼します。

```text
$goal-context-pr-review

この実装のReady PRをGoal Contextに照らしてreviewし、必要な修正と再reviewを同じtask内で完了してください。
```

Goal Context候補が複数ある場合は、開始promptへexact repository-relative pathを一つ添えます。Goal Contextはfree-form textであり、特定の文書構造や作成経路は不要です。PRはcurrent branchのReady PRを優先し、fallbackも曖昧な場合だけ番号またはURLを短く指定します。thread ID、artifact path、hash、JSON、result referenceは入力しません。

親agentはSkillの`start` commandを実行し、自動生成されたrun rootを内部で使用します。`start`はGitHub Copilot reviewを明示要求してからcollectorで待機します。collector-completeな`reviewOnly`と`reviewAndInline`をどちらも正常系として受理します。round 1のread-only reviewersを独立に起動し、raw outputsを保存してassessmentを記録します。findingがあれば親自身が修正・検証・current PR head更新を行い、`next-round`でpurpose-only reviewへ進みます。

installed Skillのcommand pathはrepository rootから`.agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs`です。source checkoutの`apm-packages/...` pathはpackage開発時だけ使います。

## Stop behavior

- `Complete`: mandatory evidenceが揃いactive findingなし
- `HumanDecisionRequired`: product/risk判断、またはround 3でactive findingあり
- `Blocked`: Ready PR/Goal Context/Copilot review要求/reviewer/current head/validation/pushが安全に成立しない

terminal responseでは、親agentがrun rootの`completion-notification.txt`を読み、その内容を最終assistant message末尾へverbatimで一度だけ追加します。fenced blockの後に文章を置きません。

Blocked理由を解消できる場合も同じ親taskへ戻ります。別top-level review taskやimplementation taskを作るnormal recoveryはありません。複雑な長期resumeはMVP外です。

## Development and validation

```powershell
dotnet publish apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -o <temporary-output>
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/validate-same-parent-review.ps1
dotnet run --file apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- --help
```

## Historical fixed two-task artifacts

過去のPRR-003または既存cycleを監査するときだけ`manage-review-cycle.cs validate`を使います。新しいnormal runの開始や利用者向け操作例には使いません。
