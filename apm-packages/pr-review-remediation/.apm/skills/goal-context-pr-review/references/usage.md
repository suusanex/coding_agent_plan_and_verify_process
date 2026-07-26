# Goal Context PR review usage

## Phase 1 with notification

```text
$completion-notification-decorator
$goal-context-pr-review

owner/repository#123を、docs/goal-context-example.mdを使って目的達成レビューしてください。
統合review-plan.mdを作成したらproduction codeを編集せず停止してください。
```

最終応答のterminal statusを通知envelopeへコピーし、`result_uri`には対象PRの直接URLを指定します。`READY_FOR_ADAPTIVE_IMPLEMENTATION`でもAdaptiveをこの親ターンから起動しません。

## Phase 2 with notification

利用者が通知から対象へ戻り、別の親ターンで開始します。

```text
$completion-notification-decorator
$adaptive-implementation-execution

.review/pr-123/review-plan.mdを実装してください。
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
