# Agent Plugin runtime qualification 2026-08-23

## Identity

- Repository-wide baseline candidate: `0ff5900beb62d8c42226a5cad2779c56747d50c2`
- PR Review follow-up candidate: `3b21a9e6dfa6f6e5123f2ad2ff5cceac6926c79a`
- Pull request: `#131`
- GitHub Copilot CLI: `1.0.80`
- APM: `0.26.0`
- Purpose Review Runner: `0.2.2`
- Runtime fixtures: repository-owned sourceだけをsystem temporary directoryへ複製した。APM projectionとdirect pluginを同じfixtureへ重ねていない。

### Distribution fingerprints

| Package | Candidate | Distribution fingerprint |
| --- | --- | --- |
| Adaptive Implementation | `0ff5900beb62d8c42226a5cad2779c56747d50c2` | `295ccbddf8a5f6a28d48cce0e80a2b3b8c773d3ab042d0874ff1f948dfcc6269` |
| Design Pair | `0ff5900beb62d8c42226a5cad2779c56747d50c2` | `a154cb67bd26d7e435818777afd197459774151b5a3e88dcef38f1af886cbd94` |
| Goal Context Authoring | `0ff5900beb62d8c42226a5cad2779c56747d50c2` | `a8ef088971524fa075633b678b8c5d27ebfed051d1fe683be4641d98d792c7e1` |
| PR Review Remediation | `3b21a9e6dfa6f6e5123f2ad2ff5cceac6926c79a` | `c3ee0c0dab5b30cf8d177b4b3ce0117a2b2980f6bcf2da9e11924dc673c06f26` |
| Persistent Purpose Review | `0ff5900beb62d8c42226a5cad2779c56747d50c2` | `87c06ae17f1d4d2f21c084e6b4fe6c565ebe23da6ac2c751988fa47c0291c733` |
| Plan Coverage | `0ff5900beb62d8c42226a5cad2779c56747d50c2` | `b5d961cd96f2102e276ba1fd6c2d5213c81a261db9ae04a0ca9e995a48eaaf8a` |

## Deterministic baseline

- 6 packageのcommon builder/validator、manifest、containment、reparse point、provenance/lock、canonical equivalence、dependency attestation、negative mutation: PASS
- root projection prevention、package既存validator/install smoke、Plan Coverage full-coverage/runtime evidence suite、PurposeReviewRunner tests、Finalizer、Completion Notification、README navigation、`git diff --check`: PASS
- GitHub ActionsのAgent Plugin matrixを含む29 checks: PASS

## Runtime observations

| Package | APM | Agent Plugin direct | Evidence |
| --- | --- | --- | --- |
| Adaptive Implementation | PASS / PARTIAL | HOLD / PARTIAL | candidate SHAからのremote installとdependency closureはPASS。canonical fingerprint一致の既存HIGH→handoff→STANDARD evidenceを再利用。direct bundle discoveryはPASSしたが代表routeは未実行。 |
| Design Pair | PASS / PARTIAL | HOLD / PARTIAL | candidate SHAからDesign Pair、Adaptive、Finalizerのremote dependency closureはPASS。fingerprint一致のmulti-turn evidenceを再利用。direct bundle discoveryはPASSしたが別Adaptive pluginとのcompositionは未実行。 |
| Goal Context Authoring | PASS / LIVE | PASS / LIVE | 3 targetのfresh APM installがPASS。direct bundleからSkillを呼び、repo-owned sourceからfree-form Goal Contextを生成。bundle内validatorはcontent SHA-256 `2070f1d2f89d8349309bab3f77660939b2d0218e32cd31f17af7a62c6b5a0bbb`でPASS。 |
| PR Review Remediation | PASS / LIVE | PASS / LIVE | candidate SHAからremote APM installがPASS。Ready PR #131でreview request、collector、remote patch、review-plannerを実行。head一致、wait `completed`、review `5002634485`、inline 4件、stable samples 2/2。plannerは4 source IDをduplicate groupとして保持し、PowerShell `-MemberName`位置引数の実行証拠により全件Reject、Apply 0、production変更なし、Adaptive別turn不要で停止。 |
| Persistent Purpose Review | PASS / LIVE | HOLD / PARTIAL | 3 targetのfresh APM installがPASS。Copilot providerとRunner 0.2.2でrun `ea4847d4-9d63-4933-8625-06db6d222445`を実行し、Round 1 `FINDINGS`から同じrun-idのRound 2 `COMPLETE`へ遷移。direct bundle discoveryはPASSしたがRunnerを内包しないためcomplete deploymentはHOLD。 |
| Plan Coverage | PASS / PARTIAL | HOLD / PARTIAL | candidate SHAからremote installとstandalone full-coverage smokeがPASS。immutable full baselineとtargeted deltaを再利用。direct bundle discoveryはPASSしたが既存Adaptive composition/shared instruction gapは未解消。 |

## PR review finding decision

Copilot reviewの4件は、`ForEach-Object Name`、`ForEach-Object distribution`、`ForEach-Object agent`を無効とする同一論点だった。PowerShell 7.5.2で各式が`-MemberName`の位置引数として期待値を返すこと、`Get-Command ForEach-Object -Syntax`が`[-MemberName] <string>`を示すこと、対象validatorとCIがPASSすることを再確認した。review-plannerは次の全sourceを`Reject`とした。

- `inline-comment:3838775269`
- `inline-comment:3838775283`
- `inline-comment:3838775297`
- `inline-comment:3838775311`

## HOLD reasons

- Adaptive direct: representative HIGH→handoff→STANDARD behaviorをdirect pluginで未実行。
- Design Pair direct: separate Adaptive pluginとの明示compositionを未実行。
- Persistent Purpose direct: independent Runner distributionをplugin単体で表現しない。
- Plan Coverage direct: Adaptive compositionとshared instruction materializationの既知gapが残る。

discoveryだけをbehavior PASSへ昇格していない。HOLD packageもcanonical artifactのdeterministic validationはPASSしている。

## PR Review follow-up qualification

review指摘を反映したcandidate `3b21a9e6dfa6f6e5123f2ad2ff5cceac6926c79a`、canonical fingerprint `340913aecbb90c5abfcb2146f66b64217e934b5daa6f1df2b6944d32d17f210b`を対象に再実行した。

- APM: candidate SHAからfresh temporary repositoryへ`copilot,codex,agent-skills` install、Finalizer apply/check、collector helpを実行してPASSした。APM 0.26.0のsubprocess readerにcp932 decode tracebackが出たが、installはexit code 0で完了し、projectionとlockの検証もPASSした。
- Agent Plugin direct: candidateから生成したbundleをCopilot CLI 1.0.80へ`--plugin-dir`で読み込み、repo-owned deterministic scenario `REMOTE-002`を`pr-review-remediation:review-planner`へ送信した。plannerは`review:fixture-remote-002`をnoActionとして保持し、verdict `REVIEW_COMPLETE`、Apply 0、`implementation_intent`なし、Adaptive開始promptなし、`Production code changed: No`で停止した。
- Fail-closed: 同candidate headのPR #131で再reviewを要求してcollectorを実行したところ、180秒以内にterminal reviewを取得できず、`waitStatus: timeout`、`timedOut: true`、`isComplete: false`を記録した。これを「指摘なし」または`REVIEW_COMPLETE`へ変換せず、direct no-action scenarioとは分離した。
