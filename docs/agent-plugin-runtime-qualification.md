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
| Adaptive Implementation | existing evidenceをfingerprint一致時だけ再利用 | candidate discoveryと代表routeを別途記録 | Codex model mappingはfinalizer |
| Design Pair | existing multi-turn evidenceを再利用可能 | Adaptive pluginとの明示compositionが未達ならHOLD | Adaptiveをinlineしない |
| Goal Context Authoring | free-form authoring smoke対象 | direct discoveryと代表authoring対象 | human reviewは自動PASSにしない |
| PR Review Remediation | remote-only processのlive smoke対象 | GitHub auth/review evidenceが得られる場合だけPASS | local reviewerなし |
| Persistent Purpose Review | Runner boundaryを含むlive smoke対象 | Runnerが別配布のためplugin単体はHOLD | Runner 0.2.2以上 |
| Plan Coverage | immutable full baselineとtargeted deltaを維持 | Adaptive/shared instruction gapが残る間HOLD | rich evidenceはpackage側 |

## Manual qualification rules

- repo-owned disposable fixtureまたは明示されたReady PRだけを外部modelへ送る。
- APM fixtureとdirect-plugin fixtureを分離し、同じprocessを二重導入しない。
- direct discoveryだけをbehavior PASSにしない。
- review timeout、permission failure、dependency不足、client capability不足は具体的なHOLD/FAIL理由として残し、他packageのdeterministic完成を止めない。
- semantic/runtime relevant changeがないpackageは、fingerprintとevidence identityを確認して既存evidenceを再利用できる。versionやdocsの変更だけで高コストな全面再実行を要求しない。
