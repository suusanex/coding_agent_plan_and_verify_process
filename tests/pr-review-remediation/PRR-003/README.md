# PRR-003 multi-round Goal Context review fixture

PRR-003は、記録済みfinding deltaとartifactを入力にしてmulti-round state contractを再現する決定論的fixtureです。外部model、Adaptive Implementation、次review round、Completion Notification deliveryを実行しません。

`validate-prr-003-contract.ps1`はFile-based `manage-review-cycle.cs`をpublishし、別々の明示commandとしてroundを開始・完了します。次を検証します。

- review -> fix reference -> re-review -> fix reference -> `REVIEW_COMPLETE`
- 第3roundでもactionable findingが残る場合の`HUMAN_DECISION_REQUIRED`
- identity、承認時刻、理由、上限を記録したhuman overrideによる第4round
- 同一head OIDの重複review拒否とround別directoryの非上書き
- `new | persistent | resolved | reopened`のfinding ledger遷移
- 各round通知のverdictと対象PR直接リンク
- review-context、Goal Context selection、local/purpose findings、machine-readable review-result、round-resultのidentity/source/verdict/delta/hash binding相互照合
- Adaptiveへ渡すreview planのcanonical `implementation_intent`、SI/AC、active finding mapping、別親ターンhandoffの相互照合
- finding deltaから導出したsource-to-tracking mappingとsource coverageの双方向完全一致
- pending human decisionの明示resolutionと上限到達decisionに紐付く第4round override
- artifact hash改変、hashを合わせたartifact内容不一致、plan契約欠落、source mapping入れ替え、finding遷移欠落、誤ったverdict、空plan、通知不一致のfail-closed mutation
- cycle root、cycle file、round directory、artifact fileのsymlink/junction escape拒否。Linux CIをsymlink作成の必須証拠とする
- multi-round modeを選ばない既存single-round Skill契約の後方互換性

実行方法:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-prr-003-contract.ps1
```

fixtureのPASSはstate machineとartifact contractの証拠であり、本物のreviewer modelがfindingを正しく判断した証拠ではありません。
