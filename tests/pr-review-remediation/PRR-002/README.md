# PRR-002 Goal Context review cycle fixture

Issue #55のsafe fixtureです。live PR、外部model、production codeを変更せず、shared collectorの正規出力と記録済みreviewer出力から後続artifactを決定論的にreplayし、次のcontractを固定します。`run.json`の`expectedVerdict`は期待値であり、実際のPASSはcontract validatorの出力だけが宣言します。

1. human-reviewed Goal Contextをselectorで一意に選択できる
2. shared collectorの`schemaVersion: "1.0"`、`target`、`sources`契約が`review-context.json`に保持される
3. local reviewとpurpose reviewが独立したread-only resultを持つ
4. plannerがlocal、purpose、Copilot、comments、checksを採否・重複付きで統合する
5. Adaptive-compatible `implementation_intent`を生成してPhase 1を停止する
6. notification envelopeが対象PRの直接linkを持つ
7. 別親ターンinputが同じplanを既存Adaptiveへ渡す

`validate-pr-review-remediation.ps1`はfake `gh`入力からshared collectorを実行し、時刻フィールドだけを除いたcanonical projectionとremote patchがcommitted snapshotへ一致することを検証します。selectorでselection artifactを再生成し、`validate-prr-002-contract.cs`でcollectorの`target`／`sources`を直接解析してrepository／PR／OID identity、正規化SHA-256、全review source coverage、decision mapping、Goal Context boundary、notification、別親turn handoffを相互検証します。さらに、collector schema、identity、source、mapping、duplicate、hash、plan path、notificationのnegative mutationがfail closedになることを確認します。

外部modelを実行した証拠ではありません。live notification providerとCodex thread deep linkは共通notification runtimeのmanual evidenceを再利用し、このfixtureでは複製しません。
