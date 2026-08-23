# Agent Plugin runtime qualification matrix

## Status model

各process packageの`tests/agent-plugin/qualification.json`が、APM projectionとAgent Plugin direct deploymentを分離して記録する。

- status: `PASS | FAIL | HOLD | NOT_RUN | UNOBSERVABLE`
- evidence mode: `LIVE | REUSED | PARTIAL | NONE`
- `PASS`にはevidence referenceが必要で、`NONE`を指定できない。
- canonical fingerprintとcandidate commitを保持し、別snapshotへPASSを移植しない。

通常CIは形式、current canonical fingerprint、status/evidence invariantだけを検査する。外部model実行は手動qualificationであり、通常CIへ入れない。

## Current package assessment

| Package | APM / Copilot | Agent Plugin direct | Boundary |
| --- | --- | --- | --- |
| Adaptive Implementation | PASS / PARTIAL | HOLD / PARTIAL | candidate installはPASS。direct代表routeは未実行 |
| Design Pair | PASS / PARTIAL | HOLD / PARTIAL | Adaptiveをinlineせず、direct compositionは未実行 |
| Goal Context Authoring | PASS / LIVE | PASS / LIVE | free-form生成とbundle validatorを確認 |
| PR Review Remediation | PASS / LIVE | PASS / LIVE | PR #131のremote reviewをplanner停止点まで確認 |
| Persistent Purpose Review | PASS / LIVE | HOLD / PARTIAL | Runner 0.2.2は別配布。Copilot same-run flowは確認 |
| Plan Coverage | PASS / PARTIAL | HOLD / PARTIAL | immutable behavior evidenceを維持し、direct gapは未解消 |

candidate `0ff5900beb62d8c42226a5cad2779c56747d50c2`の実行結果は[`tests/agent-plugins/results/2026-08-23-runtime-qualification.md`](../tests/agent-plugins/results/2026-08-23-runtime-qualification.md)に記録する。

## Manual qualification rules

- repo-owned disposable fixtureまたは明示されたReady PRだけを外部modelへ送る。
- APM fixtureとdirect-plugin fixtureを分離し、同じprocessを二重導入しない。
- direct discoveryだけをbehavior PASSにしない。
- review timeout、permission failure、dependency不足、client capability不足は具体的なHOLD/FAIL理由として残し、他packageのdeterministic完成を止めない。
- semantic/runtime relevant changeがないpackageは、fingerprintとevidence identityを確認して既存evidenceを再利用できる。versionやdocsの変更だけで高コストな全面再実行を要求しない。
