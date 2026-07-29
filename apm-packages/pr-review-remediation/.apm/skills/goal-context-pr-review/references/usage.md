# Goal Context same-parent PR review usage

## Normal path

初回実装、validation、Ready PR作成を担当した同じ親taskで、次だけを依頼します。

```text
$goal-context-pr-review

この実装のReady PRをGoal Contextに照らしてreviewし、必要な修正と再reviewを同じtask内で完了してください。
```

Goal Context候補が複数ある場合は、開始promptへexact repository-relative pathを一つ添えます。thread ID、PR番号、artifact path、hash、JSON、result referenceは入力しません。

親agentはSkillの`start` commandを実行し、自動生成されたrun rootを内部で使用します。round 1のread-only reviewersを独立に起動し、raw outputsを保存してassessmentを記録します。findingがあれば親自身が修正・検証・current PR head更新を行い、`next-round`でpurpose-only reviewへ進みます。

## Stop behavior

- `Complete`: mandatory evidenceが揃いactive findingなし
- `HumanDecisionRequired`: product/risk判断、またはround 3でactive findingあり
- `Blocked`: Ready PR/Goal Context/reviewer/current head/validation/pushが安全に成立しない

Blocked理由を解消できる場合も同じ親taskへ戻ります。別top-level review taskやimplementation taskを作るnormal recoveryはありません。複雑な長期resumeはMVP外です。

## Development and validation

```powershell
dotnet publish scripts/manage-same-parent-review.cs -o <temporary-output>
pwsh -NoProfile -File ../../../scripts/validate-same-parent-review.ps1
dotnet run --file scripts/manage-same-parent-review.cs -- --help
```

## Historical fixed two-task artifacts

過去のPRR-003または既存cycleを監査するときだけ`manage-review-cycle.cs validate`を使います。新しいnormal runの開始や利用者向け操作例には使いません。
