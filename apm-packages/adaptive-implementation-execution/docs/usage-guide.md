# Usage Guide

## Suitable tasks

- scopeとacceptanceが決まっているnon-trivial implementation
- 実装中にresponsibility、contract、wiring、state、error、test seam等が判明し得る変更
- decision surface解消後にbounded residual workを別modelへtransferできる可能性がある変更

## Unsuitable tasks

- goal、scope、acceptanceを判断できないrequest
- final code reviewや総合architecture reviewだけを行うrequest
- write-heavy ownerを並列実行したいrequest
- requested modelを利用できず、adapter mapping変更も記録できない運用

## Start

skillは利用者が`/adaptive-implementation-execution`で明示起動した場合だけ選択します。

```text
/adaptive-implementation-execution plans/issue-123.md を実装してください。
```

Copilotではagent pickerから`decision-surface-implementation-owner`を選びます。fresh intakeで`bounded-residual-implementation-owner`から開始しません。

## Ownership loop

Decision-Surface Implementation Ownerは次を繰り返します。

```text
read relevant code
  -> implement production code / tests needed to exercise decisions
  -> run focused verification
  -> inspect consequences
  -> reassess remaining decision surfaces
```

少なくとも次を`Resolved`または理由付き`N/A`にします。

- responsibility / ownership
- cross-file ownership
- public / shared internal contract
- dependency direction / new dependency
- production sequence
- DI / factory / entrypoint structure
- state / error / cancellation / retry semantics
- test architecture / seam / harness
- Design Pair / upstream binding compliance

単に案を説明できるだけでは`Resolved`ではありません。implementationやverificationで覆る合理的可能性がある場合は、ownerが実装を続けます。

## Transfer

次を満たす場合だけ`READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION`を返します。

- Decision surface assessmentに`Open`がない
- actual code、今回のimplementation、verification evidenceがassessmentを裏付ける
- 残作業がlocked contract / semanticsの適用だけで完了できる
- Work Package、Allowed edit surface、acceptance mappingが完全
- 残る不確実性がlocalかつreversible

code editなしのtransferも許容しますが、既存patternから答えが実質一意で、新しいdecision surfaceが開かないことをactual code evidenceで示す必要があります。

transfer rateやowner別LOC shareは成功指標ではありません。自然なtransfer pointがなければ最初のownerが`IMPLEMENTATION_COMPLETED`を返します。

## Bounded residual completion

Bounded-Residual Implementation Ownerはvalid handoffのWork PackageとAllowed edit surface内だけを実装します。locked contractに従うclass/interface、method body、wiring、tests、fixtures等を実装できます。

作業中に新しい非局所decision surfaceが判明した場合は推測せず`NEEDS_DECISION_SURFACE_REENTRY`を返します。単に新規fileやwiring editが必要という理由ではre-entryしません。

## Re-entry

Decision-Surface Re-entry Handoffには、invalidating evidenceではなく「新しいdecision surfaceを開いたevidence」、current worktree、completed work、files、validation、required decision、route identityを記録します。

re-entry後はDecision-Surface Implementation Ownerが必要なimplementation / verificationを含めて所有します。再transferでは、`reentry_count`を直前のre-entry handoffと一致させ、そのtriggerを`previous_reentry_trigger`と`reentry_progress_evidence.trigger`へ伝播し、`resolution`、`verification`、`same_unresolved_cause_rehanded_off: false`を記録した上で通常のtransfer gateを再度満たします。shared abstraction追加等でRemaining workやAllowed edit surfaceが広がっても、それ自体ではtransferを拒否しません。

## Runtime topology and model mapping

| Semantic role | Portable agent | Default adapter model |
| --- | --- | --- |
| Decision-Surface Implementation Owner | `decision-surface-implementation-owner` | Terra |
| Bounded-Residual Implementation Owner | `bounded-residual-implementation-owner` | Luna |

この表はadapter mappingです。parent / subagent、別process、VS Code handoff button、Copilot CLI `--agent`のどれを使ってもsemantic ownershipは変わりません。dedicated routerはimplementation editを行いませんが、runtime adapterがtop-level parent自身へDecision-Surface Implementation Ownerを割り当て、orchestrationとimplementation ownershipを兼務させる構成は許容します。

## Route identity

fresh Adaptive intake:

```yaml
implementation_route: adaptive
implementation_route_source: default
design_pair_handoff: N/A
```

Design Pair:

```yaml
implementation_route: design-pair
implementation_route_source: explicit-user-selection
design_pair_handoff: plans/<slug>-design-pair-implementation-handoff.md
```

resumeではdurable stateを維持します。欠落や矛盾をAdaptive defaultへ補完しません。旧0.5 handoffや旧agent名もmigrationせずfail closedにします。

## Completion boundary

どちらのownerも、全acceptance itemがCompleteでimplementationまたはvalidation evidenceがある場合だけ`IMPLEMENTATION_COMPLETED`を返します。

これはimplementation completionだけを表します。final code review、architecture review、independent verificationの完了ではありません。
