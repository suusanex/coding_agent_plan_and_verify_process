# PRR-003 multi-round Goal Context review fixture

PRR-003は、記録済みfinding deltaとartifactを入力にしてmulti-round state contractを再現する決定論的fixtureです。外部model、Adaptive Implementation、次review round、Completion Notification deliveryを実行しません。

`validate-prr-003-contract.ps1`はFile-based `manage-review-cycle.cs`をpublishし、別々の明示commandとしてroundを開始・完了します。次を検証します。

- collectorに近い全件source snapshotによるreview -> fix reference -> re-review -> fix reference -> `REVIEW_COMPLETE`
- round 2/3に残る旧head review／inline commentと、current／historical／unknown source関係の共存
- 第3roundでもactionable findingが残る場合の`HUMAN_DECISION_REQUIRED`
- identity、承認時刻、理由、上限を記録したhuman overrideによる第4round
- 同一head OIDの重複review拒否とround別directoryの非上書き
- `new | persistent | resolved | reopened`のfinding ledger遷移
- 各round通知のverdictと対象PR直接リンク
- review-context、Goal Context selection、local/purpose findings、machine-readable review-result、round-resultのidentity/source/verdict/delta/hash binding相互照合
- review-contextが指定するremote patch正本とmanifestの`remote-patch` role pathの一致
- Adaptiveへ渡すreview planのcanonical `implementation_intent`、SI/AC完全一致、active finding mapping、別親ターンhandoffの相互照合
- finding deltaから導出したsource-to-tracking mappingとsource coverageの双方向完全一致
- 明示的なtimezoneを持つISO-8601 cycle timestamp
- pending human decisionの明示resolutionと上限到達decisionに紐付く第4round override
- artifact hash改変、hashを合わせたartifact内容不一致、plan契約欠落、source mapping入れ替え、finding遷移欠落、誤ったverdict、空plan、通知不一致のfail-closed mutation
- cycle root、cycle file、round directory、artifact fileのsymlink/junction escape拒否。Linux CIをsymlink作成の必須証拠とする
- multi-round modeを選ばない既存single-round Skill契約の後方互換性

実行方法:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-prr-003-contract.ps1
```

fixtureのPASSはstate machineとartifact contractの証拠であり、本物のreviewer modelがfindingを正しく判断した証拠ではありません。

## Issue #61 acceptance coverage

| Acceptance criterion | Deterministic evidence |
| --- | --- |
| round別保存と非上書き | collector-realistic convergenceの`round-001`〜`003`、existing-round-directory mutation |
| roundごとのbase/head OID | start/complete/validate identity cross-checkとidentity drift mutation |
| 同一headの重複拒否 | duplicate-head mutation |
| `new / persistent / resolved / reopened` | convergence、reopened scenario、invalid transition mutations |
| `REVIEW_COMPLETE`で空planなし | convergence round 3、review-complete-with-plan mutation |
| 上限未満だけ`READY_FOR_ADAPTIVE_IMPLEMENTATION` | convergenceとround-limit verdict mutation |
| 第3roundの`HUMAN_DECISION_REQUIRED` | round-limit-and-override scenario |
| 明示overrideによる第4round | decision resolutionとround 4 override evidence |
| review後の停止、Adaptive非起動 | managerのevidence-only contractとprocess-orchestration静的検査 |
| Adaptive後の次round非自動起動 | round 2以降の明示startとAdaptive result reference gate |
| notificationの直接リンク | 各round notificationとnotification PR/status mutations |
| local／purpose／reviews／comments／checksのsource追跡 | collector-realistic全件snapshot、source coverage、finding ledger |
| 修正・再review後の収束 | collector-realistic-convergence scenario |
| 第3round後も非収束 | round-limit-and-override scenario |
