# Codex handoff: 「Plan網羅チェック・残件判定フロー」への改訂仕様

対象 repository: `suusanex/coding_agent_plan_and_verify_process`

作成日: 2026-06-03

## 0. この handoff の目的

現行の `Token-aware guardrail kernel flow` を、当初目的に沿って **「Plan網羅チェック・残件判定フロー」** に再設計する。

この改善の目的は、parent Plan のゴールを最初から狭めてトークンを節約することではない。

目的は次のとおり。

- parent Plan を実装・検証の source of truth として維持する。
- 各 phase は bounded に実行する。
- 普通に実装・検証可能な項目は parent Plan に沿って進める。
- 高コスト、手動検証妥当、人間判断必要、前提不明などの項目を、無限に修正し続けずに residual として分類する。
- residual を許容して次へ進むか、追加 bounded pass で直すか、手動検証へ委譲するか、re-plan / abort するかを判定する gate を置く。
- ただし、agent が人間判断なしに parent Plan の scope を縮小してはいけない。

## 1. 背景: 現行 flow の問題

現行 README では `Token-aware guardrail kernel flow` が「選択した runtime contract・テストポイント・ギャップだけを bounded に扱う」ものとして説明されている。また、`change-risk-triage.agent.md` の役割説明には「対象の runtime contract を 1〜3 件程度に絞る」が含まれる。

さらに README の実装 handoff では `selected implementation scope と non-goals` が入力として明示され、prompt pattern には `implementation-execution.agent.md を使って、selected scope だけを実装してください` という文がある。

これらは、本来の目的である「parent Plan を維持しながら、完了困難な項目を bounded に残件判定する」方向ではなく、「最初から一部 scope だけを実装ゴールにする」方向へ読まれやすい。

## 2. 新しい flow 名

日本語名:

> Plan網羅チェック・残件判定フロー

英語補助名:

> Plan Coverage Check and Residual Decision Flow

旧称:

> Token-aware guardrail kernel flow

旧称は README の migration note または互換説明にだけ残す。通常の説明、prompt 例、agent description では新名称を使う。

## 3. 中核の不変条件

以下を README と関連 agent に埋め込むこと。

### 3.1 Parent Plan は縮小しない

`plan-kernel.agent.md` が作成した bounded Plan は、実装・検証の source of truth である。

`change-risk-triage`、`runtime-contract-kernel`、`test-design-kernel` が扱う範囲を限定しても、それは **guardrail focus の限定** であり、parent Plan の実装 scope 縮小ではない。

### 3.2 selected implementation scope を廃止する

廃止する概念:

- selected implementation scope
- selected scope ready
- selected scope only implementation
- selected scope pass を final completion とみなすこと

代替概念:

- parent Plan pass
- guardrail focus
- residual candidate
- accepted residual
- residual decision gate
- parent Plan coverage ledger

### 3.3 guardrail focus は残す

高リスクな runtime contract / test point だけを深掘りすることは許可する。

ただし、それは以下の意味に限定する。

- 深い runtime contract / production binding / wiring 検証を行う重点対象。
- parent Plan 全体の実装 scope ではない。
- guardrail focus に含まれない parent Plan item も、Parent Plan Coverage Ledger では必ず分類する。
- guardrail focus 外の parent Plan item が未実装・未検証なら、`Done` と書かず residual / unmapped / manual / needs decision として扱う。

### 3.4 residual は agent が勝手に承認しない

agent は residual を分類・推奨できるが、次のような判断を人間の明示判断なしに行ってはいけない。

- scope 外として完了扱いにする
- deferred として final pass にする
- manual verification へ委譲して完了扱いにする
- cost too high として中止する

agent は `ResidualDecisionCandidate` または `NeedsHumanDecision` として提示し、decision gate に渡す。

### 3.5 Done 条件

この flow の最終 done は次のどちらか。

1. parent Plan のすべての FR / AC が implemented / verified であり、blocking residual が 0。
2. parent Plan の未完了・未検証項目がすべて explicit human decision により `AcceptedResidual` / `ManualVerificationDelegated` / `DeferredWithOwner` / `AbortedWithReason` のいずれかに分類済みで、blocking residual が 0。

単に residual を記録しただけでは done ではない。

## 4. 新しい flow の典型手順

README の `Token-aware guardrail kernel flow` セクションは、次の構造に置き換える。

1. `plan-kernel.agent.md`
   - parent Plan の source of truth を作る。
   - FR / AC / Non-goals / constraints / residual policy を明記する。
   - high-risk boundary candidates は候補として出すが、実装 scope を絞らない。

2. `change-risk-triage.agent.md`
   - parent Plan 全体の risk inventory を作る。
   - implementation-realization risk を分類する。
   - deep guardrail が必要な `Guardrail Focus RC/TP candidates` を推奨する。
   - residual risk candidate を記録する。
   - 実装 scope を縮小しない。

3. `implementation-contract-kernel.agent.md`（必要な場合）
   - dependency / API / provider / substitution risk を確認する。
   - unresolved implementation-realization items を guessed address に変換せず保持する。

4. `implementation-contract-review-kernel.agent.md`（必要な場合）
   - source-of-truth drift / evidence 不足 / unjustified substitution を gate する。

5. `runtime-contract-kernel.agent.md`
   - `Guardrail Focus` に選ばれた high-risk runtime contracts だけを深く固定する。
   - parent Plan の代替仕様を作らない。
   - focus 外の parent Plan item を out-of-scope 扱いにしない。

6. `test-design-kernel.agent.md`
   - guardrail focus RC を観測可能な TP に落とす。
   - stub/fake/mock/in-memory を使う場合、production binding check を必須にする。

7. `implementation-handoff-review.agent.md`
   - 実装前 gate。
   - Plan → guardrail focus RC → TP → production binding requirement の接続を確認する。
   - Parent Plan Coverage Ledger を作る。
   - `selected scope ready` ではなく、`READY_FOR_BOUNDED_PARENT_PLAN_PASS` 系の verdict を出す。
   - residual candidates / unmapped parent AC / human decision needs を明示する。

8. `implementation-execution.agent.md`
   - parent Plan に対する 1 bounded implementation pass を行う。
   - 普通に可能な FR / AC は実装する。
   - 詰まった項目は `Blocked` / `NeedsHumanDecision` / `ManualVerificationRequired` / `TooCostlyForBoundedPass` / `ImplementationEvidenceMissing` として記録する。
   - selected scope だけを実装して停止してはいけない。

9. `code-review-focus-kernel.agent.md`（optional）
   - human review 用の重点 surface を整理する。
   - changed files 全体と guardrail focus の対応を分ける。
   - `selected scope の changed files だけ` ではなく、parent Plan item に影響する changed files を見落とさない。

10. `verification-kernel.agent.md`
    - parent Plan coverage ledger を更新する。
    - guardrail focus RC/TP については production binding / wiring / contract representation を深く確認する。
    - focus 外の parent Plan item も、実装・検証・manual-only・residual candidate・unmapped のいずれかに分類する。
    - `PASS_FOR_SELECTED_SCOPE` を final verdict として使わない。

11. `coverage-gap-triage.agent.md`
    - unresolved items を分類する。
    - fix candidates、manual decision candidates、residual decision candidates を分ける。
    - fix slice を提案してよいが、defer / abort / manual delegation を承認してはいけない。

12. `residual-decision-gate.agent.md`（新規追加推奨）
    - coverage-gap-triage の後に実行する docs-only gate。
    - explicit human decision がある項目だけ `AcceptedResidual` 等として扱う。
    - human decision がない場合は `NEEDS_HUMAN_RESIDUAL_DECISION` で停止する。
    - 次の bounded fix pass、manual verification、re-plan、abort、close-with-accepted-residuals のいずれかを verdict として出す。

13. `coverage-gap-resolution-slice.agent.md`
    - decision gate または coverage-gap-triage が明示した FixNow slice だけを修正する。
    - これは main flow の scope 縮小ではなく、post-verification の repair subflow。
    - 修正後は verification / residual decision gate に戻る。

## 5. 用語置換表

| 現行語彙 | 新語彙 | 備考 |
| --- | --- | --- |
| Token-aware guardrail kernel flow | Plan網羅チェック・残件判定フロー | README の旧称注記以外では置換 |
| selected implementation scope | bounded parent Plan pass / parent Plan implementation scope | 廃止。実装 scope を最初から狭めない |
| selected scope | guardrail focus / repair slice / accepted residual scope | 文脈に応じて分ける。曖昧なまま残さない |
| selected runtime contract | guardrail focus runtime contract | runtime deep check の対象であって実装 scope ではない |
| selected test point | guardrail focus test point | 同上 |
| selected high-risk slice | guardrail focus surface | 実装 slice と混同しない |
| target slice | repair slice / decomposition slice | post-verification repair か plan decomposition の場合のみ |
| PASS_FOR_SELECTED_SCOPE | GUARDRAIL_FOCUS_VERIFIED / PARENT_PLAN_* verdict | final verdict には使わない |
| READY_FOR_SELECTED_SCOPE_IMPLEMENTATION | READY_FOR_BOUNDED_PARENT_PLAN_PASS | selected scope ready を廃止 |
| ParentPlanCoverageGap | ParentPlanCoverageGap | 意味を「未実装・未検証・未承認 residual の parent Plan item」に更新 |
| OutOfScopeForThisPass | ResidualCandidate / DeferredByHumanDecision / GuardrailFocusOutOfFocus | `out of scope` を agent が勝手に完了承認しない |

## 6. 推奨 verdict 語彙

### 6.1 implementation-handoff-review

既存の `READY_FOR_SELECTED_SCOPE_IMPLEMENTATION` / `SelectedScopeOnly` を廃止する。

推奨 verdict:

- `READY_FOR_BOUNDED_PARENT_PLAN_PASS`
  - parent Plan の FR / AC がすべて coverage ledger に載っている。
  - guardrail focus RC/TP の接続が実装前に確認できている。
  - blocking artifact mismatch がない。

- `READY_FOR_BOUNDED_PARENT_PLAN_PASS_WITH_DECLARED_RESIDUAL_RISKS`
  - 実装前に高コスト・手動確認・人間判断が必要になりそうな候補がある。
  - ただし、まだ residual accepted ではない。
  - 実装者は bounded pass で通常可能な範囲を進め、詰まった項目を residual candidate として残す。

- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
  - parent Plan の FR / AC が coverage ledger に載っていない。

- `BLOCKED_BY_ARTIFACT_MISMATCH`
  - Plan / triage / implementation contract / runtime contract / test design の source-of-truth が矛盾している。

- `BLOCKED_BY_HUMAN_DECISION`
  - 実装前に人間判断なしには進められない。

- `BLOCKED`
  - その他の blocking issue。

Output scope field は次に置換する。

- `Scope`: `ParentPlanPass / ParentPlanPassWithResidualRisk / Blocked`
- `Guardrail focus ready?`: `Yes / No / NotApplicable`
- `Parent Plan coverage ledger complete?`: `Yes / No`

### 6.2 verification-kernel

既存の `PASS_FOR_SELECTED_SCOPE` は廃止または migration note のみに残す。

推奨 verdict:

- `PARENT_PLAN_VERIFIED`
  - parent Plan のすべての FR / AC が implemented + verified。
  - blocking residual なし。

- `PARENT_PLAN_VERIFIED_WITH_ACCEPTED_RESIDUALS`
  - 未完了・未検証項目は存在するが、すべて explicit human decision により accepted residual / manual delegation / deferred with owner として分類済み。
  - blocking residual なし。

- `PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES`
  - blocking mismatch はないが、FixNow として次 bounded pass で直すべき item がある。

- `PARENT_PLAN_NEEDS_RESIDUAL_DECISION`
  - agent が defer / manual / abort を推奨できるが、人間の explicit decision がない。

- `BLOCKED_BY_PRODUCTION_BINDING_GAP`
  - production implementation / concrete implementation / wiring / entrypoint の欠落がある。

- `BLOCKED_BY_CONTRACT_MISMATCH`
  - runtime contract または parent Plan の明示要求と production behavior が一致しない。

- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
  - parent Plan FR / AC が implementation / verification / residual candidate のどれにも mapping されていない。

- `BLOCKED_BY_HUMAN_DECISION`
  - human decision なしに安全な verdict を出せない。

### 6.3 residual-decision-gate

新規 agent の推奨 verdict:

- `READY_TO_CLOSE_WITH_NO_RESIDUALS`
- `READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS`
- `READY_FOR_NEXT_BOUNDED_FIX_PASS`
- `READY_FOR_MANUAL_VERIFICATION_HANDOFF`
- `NEEDS_HUMAN_RESIDUAL_DECISION`
- `REPLAN_REQUIRED`
- `ABORT_RECOMMENDED`

重要:

`READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS` は、入力 artifact または user prompt に explicit human decision がある場合にのみ出す。agent が独自判断で出してはいけない。

## 7. 新規 agent: residual-decision-gate.agent.md

新規作成を推奨する。

### 7.1 役割

`coverage-gap-triage` 後、または `verification-kernel` 後に、未解決項目を「次にどう扱うか」に変換する gate。

この agent は実装も修正もテストも行わない。

### 7.2 入力

- `plans/<ticket-or-slug>.md`
- `plans/<ticket-or-slug>-implementation-execution.md`
- `plans/<ticket-or-slug>-verification-kernel.md`
- `plans/<ticket-or-slug>-coverage-gap-triage.md`
- optional: human decision notes / issue comment / PR comment / user prompt

### 7.3 出力ファイル

`plans/<ticket-or-slug>-residual-decision-gate.md`

### 7.4 出力構造案

```markdown
# Residual Decision Gate 結果

## Decision context

| Field | Value |
| --- | --- |
| Parent Plan | plans/<ticket-or-slug>.md |
| Human decision source | <issue comment / prompt / none> |
| Explicit human decisions present? | Yes / No |

## Parent Plan completion ledger

| Plan item | Type | Implementation status | Verification status | Evidence | Residual status | Blocking? |
| --- | --- | --- | --- | --- | --- | --- |

## Residual decision table

| Residual ID | Source item | Residual type | Options | Recommended option | Explicit human decision | Decision status | Owner / next step |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Human decisions required

| Residual ID | Question | Why human decision is required | Safe default |
| --- | --- | --- | --- |

## Verdict

`<verdict>`

## Handoff Packet

- Source artifacts:
- Decisions made:
- Decisions not made:
- Accepted residuals:
- FixNow items:
- Manual verification handoff:
- Re-plan required:
- Remaining blocking items:
- Recommended next step:
```

### 7.5 Must not do

- production code を読まない。
- production/test code を修正しない。
- Plan を勝手に変更しない。
- human decision がない residual を accepted 扱いしない。
- `ManualVerificationRequired` を「確認済み」と扱わない。
- residual を記録しただけで close verdict を出さない。

## 8. ファイル別変更指示

### 8.1 `README.md`

必須変更:

- プロセス一覧の 2 系統目を `Plan網羅チェック・残件判定フロー` に変更する。
- 旧称 `Token-aware guardrail kernel flow` は migration note として残してよい。
- 「対象 slice を絞る」「プロセスの広さを削る」「選択した危険な contract だけ」という説明を、次に置換する。
  - parent Plan は維持する。
  - deep guardrail focus は絞ってよい。
  - 通常可能な作業は parent Plan に沿って進める。
  - 高コスト・手動妥当・人間判断が必要な項目は residual decision gate に渡す。
- `selected implementation scope` を削除する。
- `implementation-execution` の prompt から「selected scope だけを実装してください」を削除する。
- Flow 選択基準を更新する。
- 成果物一覧に `plans/<ticket-or-slug>-residual-decision-gate.md` を追加する。
- 運用原則に次を追加する。
  - parent Plan を agent が勝手に縮小しない。
  - guardrail focus は implementation scope ではない。
  - residual は explicit decision なしに accepted 扱いしない。
  - final done は parent Plan coverage ledger と residual decision ledger によって判定する。

### 8.2 `plan-kernel.agent.md`

必須変更:

- description / process intent から `token-aware` 中心の語りを新名称に変更。
- output に `Residual policy` を追加する。
- high-risk boundary candidates は `Guardrail focus candidates` と呼ぶ。
- expected implementation scope が scope narrowing に読める場合は、`Implementation surface / affected components` に置換する。
- `final runtime contracts の選択はしない` は維持。
- parent Plan FR / AC を省略しないことを強化。

### 8.3 `change-risk-triage.agent.md`

必須変更:

- 役割を「対象 runtime contract を 1〜3 件程度に絞る」から「parent Plan 全体の risk inventory を作り、guardrail focus を推奨する」に変更。
- 実装 scope を縮小しないことを must not に追加。
- 出力に次の表を追加する。
  - `Parent Plan risk inventory`
  - `Guardrail focus recommendation`
  - `Residual risk candidates`
  - `Implementation-realization risk`
  - `Recommended process path`
- `full-coverage` の意味を変更。
  - 旧: 1 pass 実装には広すぎるので slice decomposition。
  - 新: parent Plan coverage を縮めずに、bounded pass / decomposition / re-plan / human decision のいずれかが必要。
- `DesignTooBroadForBoundedPass` のような gap/status を導入してよい。

### 8.4 `plan-slice-decomposition.agent.md`

必須変更:

- 「Token-aware flow で実装可能な slice に分解」を、「parent Plan coverage を維持したまま bounded execution slice に分解」に変更。
- slice decomposition は scope shrink ではないと明記。
- 各 slice は parent Plan item mapping を必須にする。
- cross-slice verification と residual decision gate を最後に必須化する。

### 8.5 `runtime-contract-kernel.agent.md`

必須変更:

- `selected high-risk runtime contract` を `guardrail focus runtime contract` に変更。
- この agent が扱う RC は deep guardrail 対象であり、parent Plan の実装 scope ではないと明記。
- output に `Guardrail focus scope note` を追加する。
- `対象外 contract を追加しない` は、「focus 外 contract を深掘りしない。ただし parent Plan 外扱いにしない」と書き換える。

### 8.6 `test-design-kernel.agent.md`

必須変更:

- `selected RC / selected test point` を `guardrail focus RC / guardrail focus TP` に変更。
- focus 外 parent Plan item の verification responsibility は消えないと明記。
- production binding check は維持。

### 8.7 `implementation-handoff-review.agent.md`

必須変更:

- description から `selected scope` 中心の説明を削除。
- verdict 語彙を 6.1 に置換。
- `READY_FOR_SELECTED_SCOPE_IMPLEMENTATION`、`SelectedScopeOnly` を廃止。
- Parent Plan Coverage Ledger を維持・強化する。
- `Guardrail focus ready?` と `Parent Plan coverage ledger complete?` を分ける。
- `selected scope traceability だけを根拠に parent Plan ready と書くな` は、より広く「guardrail focus traceability だけを根拠に parent Plan complete と書くな」に変更。
- docs-only review policy は維持。

### 8.8 `implementation-execution.agent.md`

必須変更:

- 「selected implementation scope 全体を実装する」を「parent Plan に対する 1 bounded implementation pass を行う」に変更。
- 実装者は bounded Plan の FR / AC を通常可能な範囲で満たしに行く。
- 実装不能・不明・高コスト・手動確認妥当は residual candidate として記録する。
- `Implementation Self-Map` に parent Plan item ごとの status を必須化する。
- status vocabulary を追加する。
  - `Done`
  - `PartiallyDone`
  - `NotStarted`
  - `Blocked`
  - `NeedsHumanDecision`
  - `ManualVerificationRequired`
  - `TooCostlyForBoundedPass`
  - `ImplementationEvidenceMissing`
- `selected scope 外へ広げない` ではなく、`parent Plan 外へ広げない` とする。
- 無限 test-fix loop 禁止は維持。

### 8.9 `code-review-focus-kernel.agent.md`

必須変更:

- `selected scope に関係する changed files だけ` を削除。
- parent Plan item に影響する changed files と guardrail focus surface を分けて出す。
- human review order は次の優先度にする。
  - P0: parent Plan AC / production binding / source-of-truth drift / unsafe residual
  - P1: guardrail focus RC/TP / fake-stub false confidence
  - P2: residual documentation clarity

### 8.10 `verification-kernel.agent.md`

必須変更:

- description を「selected runtime contracts and test points」から「parent Plan coverage と guardrail focus contracts/test points」に変更。
- `PASS_FOR_SELECTED_SCOPE` を廃止または legacy note のみにする。
- verdict 語彙を 6.2 に置換。
- `Parent Plan coverage ledger` を required output に追加する。
- focus RC/TP deep verification は維持。
- focus 外 parent Plan item を省略しない。`NotVerifiedInThisPass` / `ResidualCandidate` / `ManualVerificationRequired` などに分類する。
- `Parent Plan smoke scan` は「selected production addresses」ではなく「guardrail focus production addresses」に置換。
- Must not に「guardrail focus pass を parent Plan pass と表現してはいけない」を追加。

### 8.11 `coverage-gap-triage.agent.md`

必須変更:

- unresolved items は selected scope ではなく parent Plan coverage ledger から抽出する。
- gap type の意味を更新する。
  - `ParentPlanCoverageGap`: parent Plan item が implemented / verified / accepted residual のいずれにも分類されていない。
  - `ScopeVerdictAmbiguity`: verdict が parent Plan completion か guardrail focus completion か曖昧。
- `Human decisions required` を強化する。
- output に `Residual decision candidates` を追加する。
- `coverage-gap-resolution-slice` は FixNow items の修復用であり、defer/manual/abort の承認には使わないと明記する。

### 8.12 `coverage-gap-resolution-slice.agent.md`

必須変更:

- この agent は **post-verification repair subflow** であると明記。
- main flow の初期 scope 縮小に使ってはいけない。
- 入力は `coverage-gap-triage` または `residual-decision-gate` が出した explicit FixNow selector に限定する。
- repair 後は verification-kernel と residual-decision-gate の再実行を推奨する。
- `選択スコープ外へ広げない` は `FixNow selector 外へ広げない。ただし parent Plan との整合は崩さない` に変更する。

### 8.13 `cross-slice-verification-kernel.agent.md`

必須変更:

- cross-slice verification 後に residual-decision-gate へ渡すことを明記。
- slice ごとの pass は parent Plan completion ではない。
- parent acceptance conditions / cross-slice contracts / residual decisions をまとめる。

### 8.14 implementation contract 系 agents

対象:

- `implementation-contract-kernel.agent.md`
- `implementation-contract-review-kernel.agent.md`
- full flow の `implementation-contract-generation.agent.md`
- `implementation-contract-review.agent.md`

必須変更:

- 新 flow 名への参照更新。
- implementation-realization unresolved item を residual candidate として保持できることを明記。
- ただし unresolved item を accepted residual として扱うのは residual-decision-gate まで禁止。

## 9. grep / review checklist

Codex は編集後に次を実行し、結果を PR description に記載すること。

```bash
rg -n "Token-aware guardrail kernel flow|Token-aware flow|selected implementation scope|selected scope|SelectedScope|READY_FOR_SELECTED_SCOPE_IMPLEMENTATION|PASS_FOR_SELECTED_SCOPE|対象 slice を絞|高リスク slice だけ|selected high-risk slice" README.md .github/agents docs apm-packages
```

許容される残存:

- 旧称の migration note。
- `coverage-gap-resolution-slice.agent.md` の `slice`。
- `plan-slice-decomposition.agent.md` の `slice`。
- 「deprecated term」として明示的に扱っている説明。

許容されない残存:

- selected scope を実装 scope として扱う文。
- selected scope pass を parent Plan pass と誤読できる文。
- `implementation-execution` に selected scope だけを実装させる prompt。
- parent Plan item を未分類のまま省略してよい文。
- residual を記録すれば done と読める文。

追加で次を確認すること。

```bash
rg -n "Parent Plan Coverage Ledger|Residual Decision|Guardrail Focus|AcceptedResidual|NeedsHumanDecision|ManualVerificationRequired|TooCostlyForBoundedPass" README.md .github/agents
```

期待:

- 新名称と新語彙が README と relevant agents に一貫して現れる。
- Parent Plan Coverage Ledger と residual decision gate の接続が説明されている。
- `Guardrail Focus` が implementation scope ではないことが複数箇所で明示されている。

## 10. PR 作成指示

推奨 branch:

```text
docs/plan-coverage-residual-gate-flow
```

推奨 PR title:

```text
Replace token-aware kernel flow with Plan網羅チェック・残件判定フロー
```

推奨 PR description:

```markdown
## Summary

- Reframes the former Token-aware guardrail kernel flow as 「Plan網羅チェック・残件判定フロー」.
- Keeps parent Plan as the source of truth instead of selecting an implementation scope upfront.
- Renames selected runtime/test scope concepts to Guardrail Focus where they only mean deep verification focus.
- Adds / documents residual decision gating so costly, manual-only, or human-decision items can stop bounded passes without being silently accepted.
- Updates verdicts and prompt examples to avoid confusing guardrail focus pass with parent Plan completion.

## Key policy changes

- Agents must not shrink parent Plan scope automatically.
- Guardrail Focus is not implementation scope.
- Residuals are not accepted unless there is an explicit human decision.
- Final done requires parent Plan coverage ledger + residual decision ledger.

## Review focus

- Check that no prompt still tells implementation-execution to implement only selected scope.
- Check that `PASS_FOR_SELECTED_SCOPE` / `READY_FOR_SELECTED_SCOPE_IMPLEMENTATION` are removed or only mentioned as deprecated legacy terms.
- Check that residual-decision-gate cannot accept residuals without explicit human decision.
- Check that coverage-gap-resolution-slice remains a post-verification repair subflow, not the main process.

## Validation

- [ ] Ran legacy-term grep.
- [ ] Ran new-term grep.
- [ ] Confirmed README prompt examples use the new flow.
- [ ] Confirmed all relevant agents distinguish parent Plan coverage from Guardrail Focus.
```

## 11. Ready-to-paste Codex prompt

```text
You are working in repository suusanex/coding_agent_plan_and_verify_process.

Create a branch named docs/plan-coverage-residual-gate-flow.

Goal:
Replace the current “Token-aware guardrail kernel flow” concept with the new Japanese process name 「Plan網羅チェック・残件判定フロー」.

This is a documentation / custom-agent prompt rewrite task, not production code implementation.

Core intent:
The old flow drifted toward selecting a narrow implementation scope upfront. The new flow must keep the parent Plan as the source of truth, run bounded passes, and use explicit residual decision gates for items that are too costly, manual-only, blocked, ambiguous, or require human decision. Do not let any agent automatically shrink the parent Plan scope.

Use this handoff as the source of truth:
- Parent Plan is never reduced by change-risk-triage, runtime-contract-kernel, test-design-kernel, or implementation-handoff-review.
- “Guardrail Focus” may be narrowed for deep runtime/production-binding verification, but it is not implementation scope.
- “selected implementation scope”, “selected scope ready”, and “PASS_FOR_SELECTED_SCOPE” must be removed or converted to deprecated legacy notes.
- Residuals are not accepted merely because they are recorded. They require an explicit residual decision gate.
- Add a new docs-only agent `residual-decision-gate.agent.md` unless you find a stronger reason to fold the gate into an existing agent. If folded, explain why in the PR description.
- Keep `coverage-gap-resolution-slice.agent.md` as a post-verification repair subflow only. It must not be used to narrow the main parent Plan scope upfront.
- Keep existing agent file names unless renaming is necessary. Prefer updating semantics over disruptive file moves.

Update at least:
- README.md
- .github/agents/plan-kernel.agent.md
- .github/agents/change-risk-triage.agent.md
- .github/agents/plan-slice-decomposition.agent.md
- .github/agents/runtime-contract-kernel.agent.md
- .github/agents/test-design-kernel.agent.md
- .github/agents/implementation-handoff-review.agent.md
- .github/agents/implementation-execution.agent.md
- .github/agents/code-review-focus-kernel.agent.md
- .github/agents/verification-kernel.agent.md
- .github/agents/coverage-gap-triage.agent.md
- .github/agents/coverage-gap-resolution-slice.agent.md
- .github/agents/cross-slice-verification-kernel.agent.md
- implementation-contract related agents if they reference the old flow or selected-scope semantics

Add or update:
- `.github/agents/residual-decision-gate.agent.md`

Important terminology:
- Japanese process name: Plan網羅チェック・残件判定フロー
- English helper name: Plan Coverage Check and Residual Decision Flow
- Deep-check subset: Guardrail Focus
- Final unresolved decision point: Residual Decision Gate
- Parent Plan coverage artifact: Parent Plan Coverage Ledger
- Decision artifact: Residual Decision Ledger

Required verdict replacement:
- Replace `READY_FOR_SELECTED_SCOPE_IMPLEMENTATION` with `READY_FOR_BOUNDED_PARENT_PLAN_PASS` or `READY_FOR_BOUNDED_PARENT_PLAN_PASS_WITH_DECLARED_RESIDUAL_RISKS`.
- Replace `PASS_FOR_SELECTED_SCOPE` final use with parent Plan verdicts such as:
  - `PARENT_PLAN_VERIFIED`
  - `PARENT_PLAN_VERIFIED_WITH_ACCEPTED_RESIDUALS`
  - `PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES`
  - `PARENT_PLAN_NEEDS_RESIDUAL_DECISION`
  - `BLOCKED_BY_PRODUCTION_BINDING_GAP`
  - `BLOCKED_BY_CONTRACT_MISMATCH`
  - `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
  - `BLOCKED_BY_HUMAN_DECISION`

Residual decision gate verdicts:
- `READY_TO_CLOSE_WITH_NO_RESIDUALS`
- `READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS`
- `READY_FOR_NEXT_BOUNDED_FIX_PASS`
- `READY_FOR_MANUAL_VERIFICATION_HANDOFF`
- `NEEDS_HUMAN_RESIDUAL_DECISION`
- `REPLAN_REQUIRED`
- `ABORT_RECOMMENDED`

Hard constraints:
- Do not say or imply that Guardrail Focus is the implementation scope.
- Do not say or imply that selected guardrail verification completes the parent Plan.
- Do not allow residuals to be accepted without explicit human decision.
- Do not remove the guardrail chain for production implementation / wiring / stub-to-production binding.
- Do not remove bounded-pass behavior.
- Do not blindly replace every word “slice”: repair slices and plan decomposition slices may remain where they are post-verification or decomposition concepts.
- Keep the output language policy of the agents: Japanese explanatory text, English agent/status/verdict/table-key terms where already used.

After editing, run:

rg -n "Token-aware guardrail kernel flow|Token-aware flow|selected implementation scope|selected scope|SelectedScope|READY_FOR_SELECTED_SCOPE_IMPLEMENTATION|PASS_FOR_SELECTED_SCOPE|対象 slice を絞|高リスク slice だけ|selected high-risk slice" README.md .github/agents docs apm-packages

Explain any intentional remaining matches. Unintentional matches must be fixed.

Also run:

rg -n "Plan網羅チェック・残件判定フロー|Guardrail Focus|Residual Decision|Parent Plan Coverage Ledger|AcceptedResidual|NeedsHumanDecision|ManualVerificationRequired|TooCostlyForBoundedPass" README.md .github/agents

Create a PR with title:
Replace token-aware kernel flow with Plan網羅チェック・残件判定フロー

In the PR description, include:
- Summary
- Key policy changes
- Files changed
- Legacy-term grep result summary
- New-term grep result summary
- Review focus
```

## 12. Codex に任せるべきでない判断

Codex は次を勝手に判断しないこと。

- 旧 flow を完全削除するか、互換注記として残すか。
  - 推奨は「旧称として README に短く残す」。
- `residual-decision-gate.agent.md` を作るか既存 agent に統合するか。
  - 推奨は「新規 agent として作る」。
- residual を accepted 扱いする条件。
  - explicit human decision が必要。
- Full autonomous Plan-first flow の意味変更。
  - 今回の対象外。比較説明の更新だけに留める。
- repository の production code / test code 変更。
  - 対象は docs / agent markdown のみ。

## 13. ChatGPT Pro 側のレビュー観点

Codex PR 作成後、ChatGPT Pro で PR diff をレビューするときは以下を見る。

- `selected scope` の残骸が実装 scope として残っていないか。
- `Guardrail Focus` が implementation scope と混同されていないか。
- `ResidualDecisionCandidate` が `AcceptedResidual` と混同されていないか。
- final done 条件が parent Plan coverage ledger + residual decision ledger になっているか。
- `coverage-gap-resolution-slice` が main flow の scope narrowing として使われていないか。
- `verification-kernel` が guardrail focus deep verification と parent Plan coverage classification を分けているか。
- `implementation-execution` が parent Plan に対する bounded pass になっているか。
- README の prompt examples をそのまま使っても、agent が selected scope だけを実装しないか。
