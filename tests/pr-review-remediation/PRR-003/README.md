# PRR-003 multi-round Goal Context review fixture

PRR-003は、記録済みfinding deltaとartifactを入力にしてmulti-round state contractを再現する決定論的fixtureです。外部model、Adaptive Implementation、次review round、Completion Notification deliveryを実行しません。

`validate-prr-003-contract.ps1`はFile-based `manage-review-cycle.cs`をpublishし、別々の明示commandとしてroundを開始・完了します。次を検証します。

- round 1のCopilot／local／purpose full reviewから、round 2/3のpurpose-only reviewへ移るreview -> fix reference -> purpose re-review -> fix reference -> `REVIEW_COMPLETE`
- round 2/3ではCopilot待機を無効化し、local findingsを生成せず、旧head、新規connector、人間review/comment/checkを理由付き`noAction`の監査証跡として保持
- purpose findingsの`Prior Finding Assessment`とfinding deltaによる全active tracking IDの遷移
- 第3roundでもactionable findingが残る場合の`HUMAN_DECISION_REQUIRED`と、実行可能Adaptive plan／handoffの不在
- 人間の継続判断後に`resolve`が承認済みplan path/hashとoverrideをAdaptive前に記録する第4round gate
- 同一head OIDの重複review拒否とround別directoryの非上書き
- `new | persistent | resolved | reopened`のfinding ledger遷移
- 各round通知のverdictと対象PR直接リンク
- review-context、Goal Context selection、round別に必要なlocal/purpose findings、machine-readable review-result、round-resultのidentity/source/verdict/delta/hash binding相互照合
- review-contextが指定するremote patch正本とmanifestの`remote-patch` role pathの一致
- Adaptiveへ渡すreview planのcanonical `implementation_intent`、SI/AC完全一致、active finding mapping、別親ターンhandoffの相互照合
- round 1〜3を同一Review Thread、全remediationを同一Implementation Threadとして固定し、二つのrole task IDが異なること
- review planの対象Implementation Thread／return Review Thread ID、manager導出URI、plan path/hashとcycle bindingの相互照合
- task紛失時の承認済み`rebind-thread`が旧bindingを履歴へ保持し、未承認rebind、履歴改変、role ID衝突を拒否すること
- 初回実装taskがないround 1で、actionable plan完了前に承認済み`bind-thread`でImplementation Threadを登録できること
- 理由、承認者、timezone付き承認時刻を伴う明示`portable-handoff`だけがartifact-only cold-startを許可し、通常経路へ暗黙fallbackしないこと
- finding deltaから導出したsource-to-tracking mappingとsource coverageの双方向完全一致
- 明示的なtimezoneを持つISO-8601 cycle timestamp
- pending human decisionの明示resolution、承認済みplan path/hash、上限到達decisionに紐付く第4round override
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
| 明示overrideによる第4round | handoffなしのpending decision、`resolve`による承認plan/hashとround 4 override evidence |
| review後の停止、Adaptive非起動 | managerのevidence-only contractとprocess-orchestration静的検査 |
| Adaptive後の次round非自動起動 | round 2以降の明示startとAdaptive result reference gate |
| PR単位の二つのrole task | convergenceのReview Thread `R`とImplementation Thread `I`、`R != I`、round間ID continuity |
| role task紛失・移管 | approved rebind scenario、旧binding履歴、未承認・不完全rebind mutation |
| artifact-only portability | 明示portable cold-start scenarioとapproval欠落mutation |
| notificationの直接リンク | 各round notificationとnotification PR/status mutations |
| round 1だけのfull review | round 1の`reviewMode: full`とlocal/purpose artifact |
| round 2以降のpurpose-only review | `reviewMode: purpose-only`、Copilot wait disabled、local artifact禁止、外部source audit-only coverage |
| finding遷移根拠 | `Prior Finding Assessment`完全性と欠落mutation |
| 修正・再review後の収束 | collector-realistic-convergence scenario |
| 第3round後も非収束 | round-limit-and-override scenario |

`HUMAN_DECISION_REQUIRED`のround manifestへ`review-plan` roleを含めるmutation、decision記録前のAdaptive result、承認時刻より前の次round、approved plan欠落、handoff欠落、承認済みplan改変を個別に失敗させます。正常系ではcycle stateが`HUMAN_DECISION_REQUIRED`から`APPROVED_FOR_ADAPTIVE_IMPLEMENTATION`へ移ったことを確認してから、別工程のAdaptive resultを使って次roundを開始します。
