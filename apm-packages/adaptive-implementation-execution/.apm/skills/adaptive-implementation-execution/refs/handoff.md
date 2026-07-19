# Implementation Completion Handoff

- Verdict: READY_FOR_STANDARD_COMPLETION
- Handoff persistence: inline / tracked
- Plan reference:
- implementation_route: adaptive / design-pair
- implementation_route_source: default / explicit-user-selection
- Design Pair handoff: N/A / plans/<slug>-design-pair-implementation-handoff.md
- Validation performed:
- reentry_count: 0
- previous_reentry_trigger: N/A
- delegation_surface_reduced: N/A

初回 handoff は上記の初期値を使用する。`implementation_route` と `implementation_route_source` はincoming durable route pairを変更せず伝播し、`adaptive / default`または`design-pair / explicit-user-selection`の組み合わせだけを許可する。current-schema handoffで片方が欠ける、矛盾する、またはDesign Pair evidenceと一致しない場合は`BLOCKED` / `BlockedByInvalidCompletionHandoff`として停止し、下記のlegacy normalizationで補完しない。re-entry 後に再委譲する場合は、re-entry handoff の `reentry_count` を維持し、`previous_reentry_trigger` にその `Trigger` を設定し、`delegation_surface_reduced: Yes` とする。

## Acceptance status

| Acceptance item | Status | Evidence | Remaining work mapping (Work ID) |
| --- | --- | --- | --- |
| | Complete / Incomplete | | |

`READY_FOR_STANDARD_COMPLETION` では `Blocked` を許可しない。blocked item がある場合は handoff を作らず、適切な stop verdict を返す。すべての `Incomplete` item は1件以上の Work ID に対応し、すべての Remaining work row は1件以上の `Incomplete` item に対応する。`Complete` item には implementation または validation evidence を記録する。

## Applicability evidence

| Concern | Applicability | Evidence or N/A reason |
| --- | --- | --- |
| Production path and wiring | Applicable / N/A | |
| Test harness | Applicable / N/A | |
| Test seam | Applicable / N/A | |
| Mock boundary | Applicable / N/A | |

## Implemented

- 実装済みの production code、tests、wiring、代表経路

## Locked decisions

| Origin | Decision ID | Decision | Affected files / symbols | Validation expectation | Compliance evidence |
| --- | --- | --- | --- | --- | --- |
| Design Pair / HIGH_MODEL | DP-D01 / HIGH-D01 | | | | Pending / evidence |

Design Pair 由来の entry は origin と Design Pair Decision ID を維持する。HIGH_MODEL が実装中に確定した decision は別 ID で追加する。`Affected files / symbols` は decision の適用範囲であり、Allowed edit surface ではない。

## Remaining work

| Work ID | Acceptance item(s) | File | Symbol | Expected behavior | Completion check |
| --- | --- | --- | --- | --- | --- |
| RW-1 | | | | | |

## Allowed edit surface

| File | Allowed symbols or region | Allowed change |
| --- | --- | --- |
| | | |

## Validation commands

```text
<build / focused test / lint / format / type check>
```

## High-model re-entry triggers

- 新しい production class / interface / module / dependency が必要
- locked decision、public API、schema、config surface の変更が必要
- DI / entrypoint / production wiring の変更が必要
- test seam / mock boundary / test harness の変更が必要
- allowed edit surface 外の構造変更が必要
- 複数の設計案から選択する必要がある
- Plan と actual code が矛盾する

## Known assumptions / unresolved observations

-

## Design Pair Decision compliance

| Design Pair Decision ID | Status | Implementation evidence | Validation evidence | Conflict |
| --- | --- | --- | --- | --- |
| DP-D01 | Compliant / Conflict / Pending | | | None / evidence |

## Review boundary

- Final code review performed: No
- Independent verification performed: No

## Legacy Adaptive handoff normalization

Design Pair導入前のtracked handoffをresumeする場合は、旧schemaの必須fieldがすべて存在し、`Design Pair handoff`、`Design Pair Decision compliance`、Origin / Decision ID columnsがすべて欠け、Design Pair evidenceが一切ないことを確認する。条件を満たす場合だけ、次をtracked artifactへ追記してから現行schemaとして検証する。

- `implementation_route: adaptive`
- `implementation_route_source: default`
- `route_metadata_normalization: legacy-adaptive-handoff`
- `Design Pair handoff: N/A`
- `Design Pair Decision compliance: N/A (legacy Adaptive handoff)`
- 旧Locked decisionsを出現順の`LEGACY-HIGH-D01`から始まるdeterministic IDで`Origin: HIGH_MODEL`へ正規化
- 欠けていたdecision columnsは`Affected files / symbols: Not specified in legacy handoff`、`Validation expectation: Inherit handoff validation commands`、`Compliance evidence: Pending legacy resume completion`とする

Design Pair selection、Decision ID、Target Map、handoff pathのevidenceがある場合、または新旧schemaが部分的に混在する場合はnormalizationせずfail closedにする。Affected files / symbolsの補完値はAllowed edit surfaceではない。
