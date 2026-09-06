# Agent Plugin runtime qualification matrix

## Status model

各process packageの`tests/agent-plugin/qualification.json`が、APM projectionとAgent Plugin direct deploymentを分離して記録する。

- status: `PASS | FAIL | HOLD | NOT_RUN | UNOBSERVABLE`
- evidence mode: `LIVE | REUSED | PARTIAL | NONE`
- `PASS`にはevidence referenceが必要で、`NONE`を指定できない。
- canonical fingerprint、package-local runtime入力のdistribution fingerprint、candidate commitを保持し、別snapshotへPASSを移植しない。PASS evidenceはcandidate commitとdistribution fingerprintの両方を明記する。

通常CIは形式、current canonical fingerprint、status/evidence invariantだけを検査する。外部model実行は手動qualificationであり、通常CIへ入れない。

## Current package assessment

| Package | APM / Copilot | Agent Plugin direct | Boundary |
| --- | --- | --- | --- |
| Adaptive Implementation | NOT_RUN / NONE | HOLD / NONE | 0.6.0でownership contractとagent identityを刷新したため再認定待ち。0.4.0 / 0.5.0 evidenceは再利用しない |
| Design Pair | NOT_RUN / NONE | HOLD / NONE | Adaptive 0.6.0へのpost-READY routeを再認定待ち。過去のmulti-turn evidenceは履歴として保持 |
| Goal Context Authoring | PASS / LIVE | PASS / LIVE | free-form生成とbundle validatorを確認 |
| PR Review Remediation | PASS / LIVE | PASS / LIVE | PR #131のremote reviewをplanner停止点まで確認 |
| Persistent Purpose Review | NOT_RUN / NONE | HOLD / NONE | Runner 0.3.0 / protocol v3とSkill 0.4.0の組合せは実モデル評価未実施。旧LIVE証拠は再利用しない |
| Plan Coverage | PASS / PARTIAL | HOLD / PARTIAL | immutable behavior evidenceを維持し、direct gapは未解消 |

repository-wide baseline candidate `0ff5900beb62d8c42226a5cad2779c56747d50c2`と、PR Review follow-up candidate `3b21a9e6dfa6f6e5123f2ad2ff5cceac6926c79a`の実行結果は[`tests/agent-plugins/results/2026-08-23-runtime-qualification.md`](../tests/agent-plugins/results/2026-08-23-runtime-qualification.md)に記録する。

## Manual qualification rules

- repo-owned disposable fixtureまたは明示されたReady PRだけを外部modelへ送る。
- APM fixtureとdirect-plugin fixtureを分離し、同じprocessを二重導入しない。
- direct discoveryだけをbehavior PASSにしない。
- review timeout、permission failure、dependency不足、client capability不足は具体的なHOLD/FAIL理由として残し、他packageのdeterministic完成を止めない。
- semantic/runtime relevant changeがないpackageは、fingerprintとevidence identityを確認して既存evidenceを再利用できる。versionやdocsの変更だけで高コストな全面再実行を要求しない。
