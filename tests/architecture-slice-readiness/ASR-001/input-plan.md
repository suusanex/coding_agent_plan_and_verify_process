# ASR-001 Input Plan

## Goal

Control plane、worker、observer、human return gateが協調するstateful orchestrationを追加する。

## Functional requirements

- FR-001: durable desired stateからworkerをactivationできる。
- FR-002: retry / resumeはrunをまたいでidentityを保持する。
- FR-003: shared capacityを超えてworkerをactivationしない。
- FR-004: terminal resultまたはReturn Gate後にcapacityをreleaseする。

## Acceptance conditions

- AC-001: derived observationだけでcanonical desired stateを書き換えない。
- AC-002: retry後も同じrun identityで処理を継続する。
- AC-003: capacityはterminal outcomeまで二重取得されない。

## Known gap

state owner、source precedence、release sequence、cross-run identityは未定義。

## Plan readiness

`ReadyForRiskTriage`
