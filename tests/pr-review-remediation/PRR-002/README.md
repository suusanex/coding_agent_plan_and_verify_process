# PRR-002 Goal Context review cycle fixture

Issue #55のsafe fixtureです。live PR、外部model、production codeを変更せず、次のcontractを固定します。

1. human-reviewed Goal Contextをselectorで一意に選択できる
2. Copilot review待機・収集状態が`review-context.json`に保持される
3. local reviewとpurpose reviewが独立したread-only resultを持つ
4. plannerがlocal、purpose、Copilot、comments、checksを採否・重複付きで統合する
5. Adaptive-compatible `implementation_intent`を生成してPhase 1を停止する
6. notification envelopeが対象PRの直接linkを持つ
7. 別親ターンinputが同じplanを既存Adaptiveへ渡す

`validate-pr-review-remediation.ps1`はselectorを実行してselection artifactを再生成し、zero/multiple/invalid/draft lifecycleのnegative scenarioも確認します。live notification providerとCodex thread deep linkは共通notification runtimeのmanual evidenceを再利用し、このfixtureでは複製しません。
