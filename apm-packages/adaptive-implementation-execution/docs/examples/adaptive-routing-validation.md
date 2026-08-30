# Adaptive Routing Validation

## Common evidence

- Original Implementation Intent
- route identity
- semantic owner sequence
- files changed by each owner
- implementation / verification evidence
- Decision surface assessment
- Bounded Residual / Decision-Surface Re-entry handoff
- acceptance status
- final review status

## VAL-001: Implementation evidence before transfer

Decision-Surface Implementation Ownerがproduction sequence、wiring、test seamを実装・検証して初めて解消できるscenario。

Expected:

```text
READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION
  -> IMPLEMENTATION_COMPLETED
```

Checks:

- ownerが必要なproduction/test implementationを避けない
- Decision surface assessmentがactual codeとverification evidenceへ接続される
- Remaining workがlocked semanticsの同型展開だけになる

## VAL-002: Inspection-only transfer

既存implementation、wiring、tests、同型patternから残作業が実質一意であるscenario。

Checks:

- code editなしでもtransfer可能
- inspection-onlyをdefaultまたは目標として表現しない
- build/testを残Work Packageへ渡す理由が具体的

## VAL-003: Natural first-owner completion

実装中にdecision surfaceが最後まで残り、自然なtransfer pointがないscenario。

Expected:

```text
IMPLEMENTATION_COMPLETED
```

Checks:

- transfer例外理由やcode quotaを要求しない
- 不自然なscaffoldやTODOを作らない
- 全acceptance itemにevidenceがある

## VAL-004: Bounded residual completion

locked contractの適用だけでclass/interface、wiring、testsを完成できるscenario。

Checks:

- 作業種別ではなくboundednessでauthorizationする
- local choiceを自律判断できる
- locked decisionを変更しない

## VAL-005: Decision-surface re-entry

bounded residual実装中にshared signature、production sequence、state semantics、test seam等を再判断する必要が判明するscenario。

Expected:

```text
READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION
  -> NEEDS_DECISION_SURFACE_REENTRY
  -> IMPLEMENTATION_COMPLETED
```

Checks:

- re-entryは通常制御フロー
- edit typeだけではre-entryしない
- original intent、両handoff、route identity、worktree stateを保持する

## VAL-006: Reject open transfer

Decision surface assessmentに`Open`があるhandoffを拒否し、同じownerがimplementationを続ける。

## VAL-007: Progress-based retransfer

re-entry後の再transferは、直前のhandoffと一致する`reentry_count`、そのtriggerと一致する`previous_reentry_trigger` / `reentry_progress_evidence.trigger`、code上の`resolution`、`verification`、`same_unresolved_cause_rehanded_off: false`、通常transfer gateの再充足を要求する。fixtureはRemaining workとAllowed edit surfaceを実際に拡大して許容を確認し、非空のevidenceがあっても同じ未解決原因を再handoffする場合やcountが一致しない場合は拒否する。

## VAL-008: Route identity

欠落・矛盾・Design Pair evidence不一致は`BLOCKED / BlockedByInvalidCompletionHandoff`で停止する。Adaptive defaultを推測しない。

## VAL-009: Design Pair

valid Locked Decision IDを維持し、それ以外のTarget情報でDecision-Surface Implementation OwnerのauthorityやAllowed edit surfaceを狭めない。

## VAL-010: Runtime topology independence

parent / subagent、別process、VS Code button、Copilot CLI `--agent`の違いがsemantic role、transfer gate、verdictを変更しない。

## Automated oracle

`tests/routing-scenarios.json` schema v4と`tests/validate-routing-scenarios.ps1`は、上記の正負routingを実行可能なstate machineとして検証します。

## Historical evidence

- `copilot-cli-real-model-e2e-2026-07-31.md`: 0.4.0 historical evidence
- `copilot-cli-real-model-e2e-2026-08-09.md`: 0.5.0 historical / uncompleted evidence
- `copilot-cli-real-model-e2e-2026-08-30.md`: 0.6.0 qualification template

旧recordは0.6.0のPASS根拠にしません。
