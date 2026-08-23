# Agent Plugins 採用方針

## 目的と判断

この文書は、Issue #107 の Agent Plugins direct-load PoC と Issue #106 の APM 経由 GitHub Copilot qualification を基にした repository-level policy を定義する。PoC の観測事実は [Agent Plugins PoC](./plan-coverage-agent-plugin-poc.md) に、runtime qualification の実行証拠は [runtime qualification matrix](./plan-coverage-runtime-qualification.md) に記録する。

現時点の判断は次のとおりである。

| 対象 | 判断 | 意味 |
| --- | --- | --- |
| Agent Plugins-compatible canonical/package architecture | **GO** | package-local canonical source から plugin artifact を生成し、継続的に build / validate する |
| APM distribution / materialization / runtime adapter | **GO** | 現在の利用者向け supported installation path として APM を維持する |
| Agent Plugins direct runtime deployment as primary/supported installation | **HOLD** | qualification target として維持するが、現時点の通常導入方法にはしない |

この HOLD は PoC の失敗を意味しない。portable bundle の生成・適合性・Copilot discovery は確認できた一方、shared instruction materialization、Adaptive の推移依存、runtime/client 固有機能で APM baseline と同等の運用境界を満たしていないためである。APM を廃止する判断でもない。

## 責務境界

- `.apm/**` が process semantics の唯一の canonical source である。Agent Plugins 用に Skill、agent、process semantics の第二実装を作らない。
- Agent Plugin artifact は canonical source から `apm pack --format plugin` で生成する検証対象である。package root に `plugin.json` を常設せず、APM source install と plugin bundle を混同しない。
- APM は dependency resolution、transitive materialization、runtime-specific projection、shared instruction / agent 配置、multi-target distribution を担当する。
- runtime adapter は client 固有の invocation、agent、model、handoff、instruction path の差異を閉じ込める。adapter に canonical semantics を複製しない。
- qualification は runtime-specific evidence であり、deterministic source/pack validation の代替ではない。

## 通常 CI と runtime qualification

通常の PR CI は外部モデルや有料 GitHub Copilot 実行に依存せず、次の deterministic contract を必須にする。

- canonical source から bundle を生成できること。
- Agent Plugins manifest schema、naming、containment、bundle provenance / lock を検証すること。
- generated Skill、owned agent、shared instruction と canonical source の等価性および drift を検出すること。
- duplicate Skill / duplicate process semantics と package root の不正な plugin projection を拒否すること。
- APM source/install 経路、Adaptive attestation、dependency boundary を壊していないこと。
- committed qualification / PoC result の schema、invariant、fingerprint 比較を検証すること。

次の項目は通常 regression CI ではなく、明示的な runtime qualification evidence として扱う。

- 実 GitHub Copilot CLI と model を使う authorization A–H。
- STD-001、FULL-001、Adaptive connection / handoff の実観測。
- client/version 固有の plugin direct-load capability。

workflow 名、`validate-*` / `run-*` script 名、この文書、qualification matrix からこの境界を判別できる状態を保つ。`UNOBSERVABLE` や `NOT_RUN` を PASS に昇格させない。

## Qualification の再実行トリガー

External-model qualificationの要否と範囲は、fingerprintやpackage versionの変化ではなく、変更内容のruntime regression riskで決める。

- documentation、wording、metadata、behaviorへ影響しないcanonical整理はlow / normalとし、deterministic CIを実行して次回実運用で観測する。
- 特定agent behavior、decision rule、bounded contractの変更はtargeted runtime riskとし、必要に応じて影響scenarioだけを実行する。無関係なauthorization、standard/full routeを再実行しない。
- authorization、route orchestration、runtime adapter/projection、Skill・agent discovery/materialization、Adaptive handoff、shared routing semantics、runtime/client compatibilityの変更はfull runtime riskとし、full qualificationを要求または強く推奨する。Strict gateではPlan Coverageだけでなく、Adaptiveとprofile finalizerのruntime-relevant input identityも一致させる。
- 新runtimeやdirect pluginをsupported installation pathへ昇格するpromotion reviewではfull qualificationを要求する。
- historical baselineを合理的にcarry forwardできない広範なsemantics変更もfull qualification対象とする。

`.apm/**`変更はrisk評価の入力だが、それ単独ではexternal-model qualificationの再実行理由にならない。通常PR CIと外部modelを常時消費するscheduled CIは分離し、再qualificationはrisk評価またはpromotion reviewに結び付いた明示的な作業とする。

## Supported deployment への昇格条件

特定 runtime の direct deployment を APM 経路の正式な置換候補にするには、全条件を fail-closed で満たす必要がある。

1. canonical fingerprint と process semantics が APM baseline と比較可能で、fingerprint mismatch を parity PASS としない。
2. explicit-invocation-only authorization A–H が baseline 相当で PASS する。
3. representative standard-slice が residual close まで PASS する。
4. full-coverage が必要な process では Architecture Slice Readiness、decomposition、implementation、independent/cross-slice verification、residual decision を含む FULL baseline 相当が PASS する。
5. その process が必要とする Adaptive / handoff などの transitive runtime capability が PASS する。
6. shared instructions、agents、dependencies が fixture の手作業補正なしに direct deployment 経路だけで materialize される。
7. runtime-specific adapter の責務と限界が記録され、Agent Plugins 用の duplicate semantics を作っていない。
8. APM projection と direct plugin を同一 runtime/project に重ねて PASS を作っていない。

条件を満たした runtime は `APM install + projection` から `Agent Plugin direct deployment` へ置換する。二重導入を恒久的な標準運用にはしない。条件未達、未観測、または判断未確定の場合は HOLD / qualification pending とし、supported installation へ昇格させない。

## 利用者向け導線

現時点の通常導入は APM である。root README と package README は APM provision/install を案内し、`copilot plugin install` などの direct install を supported installation として案内しない。Agent Plugins 関連の build / validation は maintainer と qualification のために継続する。

この方針は、#107 の PoC evidence、#106 の APM/Copilot baseline、現在の deterministic validators と矛盾しないように更新する。既存 evidence を都合よく書き換えて direct deployment を GO にすることはしない。

## Non-goals

- APM の廃止または現行 supported path の置換。
- Agent Plugins direct-load の即時昇格。
- 全 package の一括移行。
- Agent Plugins 未対応 capability の portable core への押し込み。
- Plan Coverage の process semantics の再設計。
- 通常 CI での外部 model 実行の必須化。
