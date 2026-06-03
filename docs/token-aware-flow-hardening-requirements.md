# Plan網羅チェック・残件判定フロー: Hardening Requirements

この file path は互換性のために残しています。内容は、Plan網羅チェック・残件判定フローの hardening requirements です。

## Hard constraints

- Parent Plan is never reduced by change-risk-triage, runtime-contract-kernel, test-design-kernel, implementation-handoff-review, verification-kernel, or coverage-gap-triage.
- Guardrail Focus may be narrowed for deep runtime / production-binding verification, but it is not implementation scope.
- Residuals are not accepted merely because they are recorded.
- `AcceptedResidual` requires explicit human decision.
- `ManualVerificationRequired` is not verification evidence.
- `TooCostlyForBoundedPass` requires Residual Decision Gate or re-plan, not silent closure.
- `NeedsHumanDecision` is blocking until a decision source exists.
- Source evidence is required for field / state / identifier mapping.
- A test substitute never proves production binding by itself.

## Required ledgers

### Parent Plan Coverage Ledger

Required before implementation and after verification.

Each parent Plan item must have:

- implementation status
- verification status
- evidence
- residual status
- blocking flag

### Residual Decision Ledger

Required when unresolved items remain.

Each residual candidate must have:

- source item
- candidate type
- options
- recommended option
- explicit human decision source
- decision status
- owner / next step

## Blocker examples

- `ParentPlanCoverageGap`: parent Plan item is not implemented, verified, or covered by accepted residual.
- `ScopeVerdictAmbiguity`: verdict wording makes it unclear whether the result applies to parent Plan completion or Guardrail Focus only.
- `ProductionImplementationMissing`: required production implementation is absent.
- `ProductionWiringMissing`: production wiring / entrypoint is absent.
- `ContractMismatch`: runtime contract or parent Plan behavior does not match production behavior.
- `ImplementationEvidenceMissing`: required API / symbol / provider / address evidence is missing.

## Required verdict replacements

Implementation handoff uses:

- `READY_FOR_BOUNDED_PARENT_PLAN_PASS`
- `READY_FOR_BOUNDED_PARENT_PLAN_PASS_WITH_DECLARED_RESIDUAL_RISKS`
- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
- `BLOCKED_BY_ARTIFACT_MISMATCH`
- `BLOCKED_BY_HUMAN_DECISION`
- `BLOCKED`

Verification uses:

- `PARENT_PLAN_VERIFIED`
- `PARENT_PLAN_VERIFIED_WITH_ACCEPTED_RESIDUALS`
- `PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES`
- `PARENT_PLAN_NEEDS_RESIDUAL_DECISION`
- `BLOCKED_BY_PRODUCTION_BINDING_GAP`
- `BLOCKED_BY_CONTRACT_MISMATCH`
- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
- `BLOCKED_BY_HUMAN_DECISION`

Residual Decision Gate uses:

- `READY_TO_CLOSE_WITH_NO_RESIDUALS`
- `READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS`
- `READY_FOR_NEXT_BOUNDED_FIX_PASS`
- `READY_FOR_MANUAL_VERIFICATION_HANDOFF`
- `NEEDS_HUMAN_RESIDUAL_DECISION`
- `REPLAN_REQUIRED`
- `ABORT_RECOMMENDED`

## Must not approve

- residual without explicit human decision
- manual verification without owner / method / required evidence
- unknown API surface rewritten as guessed implementation address
- Guardrail Focus verification represented as parent Plan verification
- repair slice used as initial scope reduction
