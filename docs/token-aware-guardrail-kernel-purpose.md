# Plan網羅チェック・残件判定フロー: Purpose and Policy

この file path は互換性のために残しています。内容は Plan網羅チェック・残件判定フロー（Plan Coverage Check and Residual Decision Flow）の目的と policy を説明します。

## Primary objective

Plan-first process を bounded に進めつつ、parent Plan を実装・検証の source of truth として維持します。

目的は、最初から狭い実装範囲を選ぶことではありません。通常可能な parent Plan items は実装・検証し、高コスト、manual-only、blocked、ambiguous、human decision が必要な項目は residual candidate として明示し、Residual Decision Gate で扱います。

## Failure modes prevented

1. Cross-process または cross-component の sequence contract mismatch。
2. stub / fake / mock / in-memory test は通るが production implementation / wiring が欠けている状態。
3. Guardrail Focus の deep verification を parent Plan completion と誤認する状態。
4. residual を記録しただけで accepted と扱う状態。

## Core policy

- Parent Plan is the source of truth.
- Guardrail Focus is a deep-check subset, not implementation scope.
- Parent Plan Coverage Ledger is required before implementation and after verification.
- Residual Decision Ledger is required before unresolved items can be treated as accepted, delegated, deferred, or aborted.
- `AcceptedResidual` requires explicit human decision.
- `ManualVerificationRequired` is not confirmation; it is a decision / handoff state.
- Bounded pass behavior is preserved.

## Guardrail chain

```text
Plan requirement / acceptance condition
  -> Guardrail Focus runtime contract
  -> Guardrail Focus test point
  -> stub/fake usage
  -> production implementation
  -> production wiring / entrypoint
  -> explicit unresolved status
  -> Residual Decision Gate
```

## Done conditions

Done means one of the following:

1. Every parent Plan FR / AC is implemented and verified, with no blocking residual.
2. Every unresolved parent Plan item has an explicit human decision and is classified as `AcceptedResidual`, `ManualVerificationDelegated`, `DeferredWithOwner`, or `AbortedWithReason`, with no blocking residual.

Recording a residual candidate is not enough.

## Non-goals

- Skip Plan creation.
- Start implementation from risk triage alone.
- Treat Guardrail Focus as implementation scope.
- Treat test success as production binding proof.
- Accept residuals without explicit human decision.
- Use repair slices as the main flow's initial scope reduction.
