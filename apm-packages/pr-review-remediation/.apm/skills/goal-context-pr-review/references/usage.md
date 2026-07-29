# Goal Context PR review usage

## Phase 1 with notification

```text
$completion-notification-decorator
$goal-context-pr-review

owner/repository#123を、docs/goal-context-example.mdを使って目的達成レビューしてください。
統合review-plan.mdを作成したらproduction codeを編集せず停止してください。
```

最終応答のterminal statusを通知envelopeへコピーし、`result_uri`には対象PRの直接URLを指定します。`READY_FOR_ADAPTIVE_IMPLEMENTATION`でもAdaptiveをこの親ターンから起動しません。

## Explicit multi-round review

複数roundを開始する場合は、最初のpromptでmulti-round modeとcycle pathを明示します。

```text
$completion-notification-decorator
$goal-context-pr-review

owner/repository#123をGoal Context multi-round modeのround 1としてレビューしてください。
cycleは.review/pr-123/review-cycle.json、artifactはround-001へ保存し、通知後に停止してください。
```

通常運用ではPRごとにReview ThreadとImplementation Threadを一つずつ用意します。修正は同じImplementation Threadを再開した新しい明示ターンで実行し、その完了後は同じReview Threadへ戻って次roundを新しい明示ターンとして開始します。工程間の自動起動は行いません。

round 1の`start`へ`--review-thread-id`と、既存実装taskがある場合は`--implementation-thread-id`を渡します。実装taskがまだない場合は、actionable planの`complete`前に`bind-thread --thread-role implementation`で登録します。threadを失った場合は`rebind-thread`へ新ID、理由、承認者、timezone付き時刻を渡し、旧bindingを履歴へ残します。異なるtaskでのcold-startは`--thread-mode portable-handoff`と同じ承認情報を明示した場合だけ許可します。

```text
$completion-notification-decorator
$goal-context-pr-review

owner/repository#123のGoal Context multi-round review round 2を開始してください。
このTaskはround 1と同じReview Threadです。前roundのAdaptive resultは<path-or-uri>、実行したImplementation Thread IDは<task-id>です。最新headを収集し、round-002へ保存して通知後に停止してください。
このroundはpurpose-onlyです。Copilotレビューを開始・待機せず、local-reviewerも実行しないでください。
```

同じheadの再review、前Adaptive resultなしのround 2以降、固定role threadと異なるtask、過去round directoryの再利用は拒否します。`HUMAN_DECISION_REQUIRED`では実行可能planとAdaptive handoffを出しません。利用者が継続を選んだ場合、別の明示工程で承認plan候補を作り、`manage-review-cycle.cs resolve`へdecision ID、resolution、承認者、承認時刻、候補pathを渡します。`resolve`が`round-NNN/approved-review-plan.md`を保存して`APPROVED_FOR_ADAPTIVE_IMPLEMENTATION`を返した後だけ、同じImplementation Threadの新しいターンでAdaptiveを開始します。既定上限は3です。第3roundから継続する`resolve`には、利用者のidentity、承認時刻、理由、新しい上限もCLI overrideへ明示します。

```powershell
dotnet run --file scripts/manage-review-cycle.cs -- resolve `
  --cycle .review/pr-123/review-cycle.json `
  --resolve-decision HD-003 --decision-resolution "Continue after review" `
  --decision-approved-by <identity> --decision-approved-at <ISO-8601> `
  --approved-plan <approved-plan-candidate> `
  --override-maximum-rounds 4 --override-approved-by <identity> `
  --override-approved-at <ISO-8601> --override-reason <reason>
```

round 2以降のcollectorは`--no-wait-for-copilot`を使用します。snapshotに残る旧head、新規connector、人間review/comment、checkは削除せず、reason付き`noAction`の監査証跡としてsource coverageへ渡します。これらから新規remediation findingを作りません。cycle managerへ渡す時刻は、`2026-07-28T09:00:00Z`または`2026-07-28T09:00:00+09:00`のようにtimezoneを明示します。

## Phase 2 with notification

利用者が通知から対象へ戻り、固定Implementation Threadを再開して新しい親ターンを開始します。review planのpath/hashを正本としつつ、そのImplementation Threadに残る探索・設計コンテキストを利用できます。

```text
$completion-notification-decorator
$adaptive-implementation-execution

<cycle-root>/round-NNN/review-plan.mdを実装してください。
implementation_intentをsource of truthとし、Goal Context Boundaryを保持してください。
```

## Development entry examples

どの開発入口から始めても、PRがReady for reviewになった後のPhase 1/2は同じです。

### Lightweight development

小さな通常実装を完了してPRを作成した後、`$completion-notification-decorator`と`$goal-context-pr-review`を同じ親ターンで指定します。

### Plan Coverage

`$plan-coverage-residual-flow`で実装と残件判定を完了してPRを作成した後、別親ターンで通知付き`$goal-context-pr-review`を開始します。review plan生成後に停止し、修正はさらに別親ターンの通知付きAdaptiveで行います。

### Design Pair

利用者が明示選択したDesign Pair routeで実装を完了してPRを作成した後も、review入口は通知付き`$goal-context-pr-review`です。Design Pairをreview Skillから自動選択・再起動せず、修正実装はcanonical Adaptiveへ渡します。

## Explicit baseline fallback

Goal Contextがない、不正、または複数候補から選べない場合、Goal Context対応版のままIssue本文だけで目的レビューを続行しません。Goal Contextを修正・選択するか、目的レビューを行わない基礎版`$pr-review-remediation`を利用者が明示選択します。
