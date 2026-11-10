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
  -> compare existing paths and choose the requirement-driven delta
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

## 既存方式との比較を小さく残す

実装前に既存処理を出発点として要求差分と採用方式を決め、実装後に参照処理とactual diffを照合します。記録先は既存の計画またはimplementation evidenceです。担当交代時はその内容をhandoffのImplementation and verification evidenceへ引き継ぎます。最初のownerが完了しても省略しません。

短い記録例（以下のfile / symbolは説明用の架空例であり、実行時は実際に読んだものへ置き換えます）:

> 参照: `Orders/Cancel.cs:CancelAsync → OrderStore.UpdateAsync`と兄弟の`Orders/Approve.cs:ApproveAsync`。状態更新と失敗の返却はOrderStoreが所有し、保存成功後に通知する。今回の差分は新しい取消理由の受け渡しだけなので既存APIを呼ぶ。照合: diffは引数mappingとtestのみ。独自cache、保存順序の制御、storeを迂回するDB直接呼び出しは追加していない。

新しい経路・状態管理を追加／変更する際は、近傍だけでなく同じデータの更新箇所、同じinterface実装、兄弟機能から関連処理を探します。固定件数や全repository精読は不要です。局所修正は関連参照と差分を短く記録します。別方式は既存方式が要求を満たせない根拠と例外範囲を示します。既存の不具合への追従、共通化のための共通化、新しい承認待ちは要求しません。

### 分岐の確認例

この表は契約の机上確認用であり、実modelの実行結果ではありません。具体名は説明用です。各例で変更前の参照と実装後diffを照合します。

| ケース | 比較・採用判断 | 完了／引継ぎ時に確認すること |
| --- | --- | --- |
| 既存APIを使える | `CancelAsync → OrderStore.UpdateAsync`の状態所有と保存後通知が要求に適合。理由引数だけ追加 | Store経由を維持し、二重状態保持やDB直接呼び出しを追加しない |
| 拡張点を使える | `Exporter.Export → IFormatter.Format`と既存formatterを読み、新形式も同じ入力・失敗契約で実装可能 | 新formatterを既存登録箇所へ追加し、別export pipelineを作らない |
| 共通化せず構造を揃える | 兄弟handlerの検証→service呼び出し→結果変換に合わせる。共通APIはなく、業務mappingだけ異なる | handler内の局所実装で足り、新しい共通managerを作らない |
| 要求上の別方式 | 既存batch保存は途中反映されるが、今回の要求は全件atomic。既存call siteとtransaction境界から不適合を確認 | atomic対象だけtransaction対応APIを使用。既存batch全体への変更や新基盤は不要か確認 |
| 類似処理なし | 対象データ更新箇所、関連interface実装、兄弟機能を検索・読解した範囲と未発見事実を記す | 不在証明の探索を続けず新規実装。捏造した参照で正当化せず、要求と追加状態・順序の必要性を確認 |
| 局所修正 | 既存validatorの境界値だけ修正。関連関数と要求差分を短く記す | 関連testとdiffで確認し、全体調査や大きな比較書を要求しない |
| 最初のownerが完了 | 上記比較と実装後照合をimplementation evidenceに残す | routerが直接完了時にも記録を確認。transferのための作業分割はしない |
| 担当交代 | 参照・採用方式・例外理由、実装済みの照合結果をhandoffへ渡す | 未実装部分はCompletion checkに置き、bounded ownerが実装後照合する。inspection-onlyを照合済みにしない |
| 新事実で判断更新 | 拡張点で要求を満たせる想定だったが共有状態のlifetime不一致が判明 | bounded ownerは比較と新事実を既存re-entryへ渡す。元ownerが再比較し、必要な実装・検証を行う |

### マージ後の観察

実装・静的検査・マージだけで実運用効果を確認済みとはしません。[Issue #154](https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/154)またはリンクした既存作業記録へ、実際に試した際に次を短く追記できます。評価期間や数値閾値は設けません。

| 対象作業・変更version | 発見した参照／発見できなかった範囲 | 採用方式と不採用理由 | 不要な別経路・共通化の有無 | 調査負担・人間への確認回数 | 継続・修正・差し戻しの判断 |
| --- | --- | --- | --- | --- | --- |
| 未実施 | 未確認 | 未確認 | 未確認 | 未確認 | 実運用後に記録 |

参照を発見できない問題と、発見しても採用しない問題を区別します。副作用が多い場合はIssue #154の変更commitを特定してrevertします。恒久採用や新しいfeature flagは前提にしません。

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
