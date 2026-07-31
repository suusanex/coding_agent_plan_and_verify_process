# Usage Guide

## Suitable tasks

- 通常 Plan Mode で scope と acceptance は決まったが、実装中の責務配置や wiring 判断が残り得る変更
- small-bounded または medium-bounded な production implementation
- existing pattern を確認してから、同型 case や tests を STANDARD_MODEL へ渡せる可能性がある変更
- HIGH_MODEL が代表経路を実装した後に残存 decision surface を評価すべき変更

## Unsuitable tasks

- goal、scope、acceptance が判断できない request
- Plan Coverage Flow が必要な広い requirement coverage / runtime boundary / residual decision work
- final code review や総合 architecture review だけを行いたい request
- write-heavy agent を並列実行したい request
- CHEAP_MODEL に一般的な production implementation を任せたい request
- organization policyやmodel pickerでrequested modelを利用できず、明示的な代替判断も記録できないCopilot運用

## Start after ordinary Plan Mode

APM install で skill と portable custom agents を導入します。この skill は、利用者が明示指定した場合、または現在の task がこの package の HIGH_MODEL → STANDARD_MODEL 直列 workflow を明確に必要とする場合に選択します。導入されているだけで repository 内の実装作業へ自動適用しません。

現行 APM が model 未設定の custom agent TOML を生成した場合は、補助スクリプトで concrete model 設定を補完し、`--check` で確認します。この補完は runtime configuration の互換処理であり、skill の選択や使用を強制しません。

## Start in GitHub Copilot Chat in VS Code

1. Adaptive packageを`--target copilot,agent-skills`、またはCodex併用なら`--target copilot,codex,agent-skills`で導入する。
2. VS CodeでCopilot Chatを開き、agent pickerから`high-implementation-starter`を選ぶ。
3. ordinary Plan / Implementation Intent、fresh route identity、必要ならtracked Design Pair handoff pathを渡す。
4. HIGHがvalidなtracked `READY_FOR_STANDARD_COMPLETION`を返した場合だけhandoff buttonで`standard-implementation-completer`へ移る。
5. STANDARDがtracked `NEEDS_HIGH_MODEL_REENTRY`を返した場合だけ、両handoff pathを渡して`high-implementation-starter`へ戻る。

model mappingはHIGH start / re-entryが`GPT-5.6 Terra (copilot)`、bounded STANDARD completionが`GPT-5.6 Luna (copilot)`です。Lunaからfresh intakeを開始しません。`COMPLETED_BY_HIGH_MODEL`またはstop verdictではhandoff buttonを使わず停止します。buttonが表示されていること自体はauthorizationではありません。

Copilot plan、organization policy、extension version、model pickerによりrequested modelを利用できない場合は、別tierへ黙って実行しません。mapping変更を明示的に決めるかpolicy管理者へ確認し、requested / observed modelと差異をmanual evidenceへ記録します。

```text
$adaptive-implementation-execution を使って、直前の Plan を実装してください。
Plan の scope / non-goals / acceptance を維持し、final review は別工程として残してください。
```

repository-tracked Plan の例:

```text
$adaptive-implementation-execution を使って plans/issue-123.md を実装してください。
```

Design Pair route の例:

```text
$design-pair-implementation-execution で作成した plans/issue-123-design-pair-implementation-handoff.md を追加 input として、$adaptive-implementation-execution を開始してください。
Locked Decisions だけを binding とし、その他の実装判断は actual code と verification evidence から行ってください。
```

Design Pair route は利用者が明示選択した場合だけ使います。Design Pair handoff の Target Map や `Affected files / symbols` は allowed edit surface ではありません。Copilot経路でもvalidなtracked handoffをAdaptive inputとして保持しますが、Design Pair package自体のCopilotでの対話・handoff生成は正式E2E対応済みとは扱いません。

durable routeやresume evidenceがない通常Adaptiveのfresh intakeは、`implementation_route: adaptive`、`implementation_route_source: default`、`design_pair_handoff: N/A`の3項目を初期化します。parentはHIGH_MODELへ3項目を常に渡し、Design Pair handoff pathを省略しません。

短い caller intent の例:

```text
$adaptive-implementation-execution を使って進めてください。
Goal: CSV import の空行を無視する。
Scope: ImportService と既存 tests。
Non-goals: parser library の交換、public API 変更。
Acceptance: 空行を含む既存形式が成功し、invalid row の既存 error は維持される。
Validation: focused unit tests と solution build。
```

## What HIGH_MODEL does

`high-implementation-starter` は relevant code、tests、production wiring を読み、実際に編集し、focused checks を実行します。

事前に `direct implementation` / `shape-then-complete` を固定分類しません。actual code と verification の結果から、残っている decision surface を繰り返し評価します。

次が残る間は HIGH_MODEL が続行します。

- responsibility placement
- API / signature / schema
- dependency / module / interface choice
- DI / entrypoint / production wiring
- error / cancellation / retry / state ownership
- test seam / mock boundary / harness
- implementation trade-off

安全な delegation point がない場合は `COMPLETED_BY_HIGH_MODEL` で完了して構いません。完了 verdict は、scope 内の acceptance item がすべて `Complete` で、実装または validation evidence がある場合だけ返します。

## What STANDARD_MODEL does

`standard-implementation-completer` は handoff の `Remaining work` と `Allowed edit surface` だけを扱います。

適した残作業:

- established pattern に沿った追加 case
- validation / mapping の局所追加
- tests / fixtures / test data
- locked decisions を変えない focused failure 修正

有効なhandoffで実装または検証を開始した後にlocked decisionsを変える必要が判明した場合は、局所的にねじ込まず `NEEDS_HIGH_MODEL_REENTRY` を返します。handoffの欠落・矛盾・evidence不一致は構造判断ではなくinvalid artifactとして`BLOCKED` / `BlockedByInvalidCompletionHandoff`で停止します。

## Acceptance mapping in a handoff

`READY_FOR_STANDARD_COMPLETION` handoff は、`Incomplete` acceptance item と `Remaining work` row を Work ID で双方向に対応させます。`Blocked` item を含む handoff は STANDARD_MODEL へ渡しません。`Complete` item には implementation または validation evidence が必要です。

## Re-entry example

HIGH_MODEL が validation branches と tests を委譲した後、STANDARD_MODEL が production entrypoint の registration 変更を必要と判断した例:

```text
READY_FOR_STANDARD_COMPLETION
  -> standard-implementation-completer starts
  -> existing test cannot reach the production registration path
  -> NEEDS_HIGH_MODEL_REENTRY
  -> high-implementation-starter resumes with the original intent, original completion handoff, and re-entry handoff
```

STANDARD_MODEL は registration を暗黙変更しません。re-entry handoff にoriginal Implementation Intent、invalidating evidence、変更済み files、実行した checks、必要な decision、current worktree state、incomingの`implementation_route`、`implementation_route_source`、Design Pair handoff pathを変更せず記録します。parentは元のcompletion handoffも保持し、両handoffのroute identityが一致することを確認してからHIGH_MODELを再実行します。HIGH_MODELとSTANDARD_MODELは通常完了を含むresultで同じ3項目を返し、parentはincoming identityとの一致を検証します。

例外は`Verdict: BLOCKED`かつ`Stop reason: BlockedByInvalidCompletionHandoff`だけです。欠落したidentityを捏造せず、各fieldのraw observed valueまたは`<missing>`とrepair evidenceを返します。parentはこのresultに完全なpairを要求せず受理して停止します。外部blockerを理由とする`BLOCKED`では完全なunchanged identityが必要です。

一度 re-entry した後は HIGH_MODEL が完了まで担当します。再委譲は、前回より `Remaining work` と `Allowed edit surface` がともに厳密に縮小し、同じ trigger が再発していない場合だけ許可します。

初回 HIGH_MODEL handoff は `reentry_count: 0` とします。STANDARD_MODEL は re-entry 時に incoming value へ1を加え、今回の `Trigger` と incoming `previous_reentry_trigger` を返します。HIGH_MODEL が再委譲する場合は count を維持し、今回の `Trigger` を新しい `previous_reentry_trigger` に設定します。

## Inline and tracked handoff

### inline

同一 run / 同一 parent orchestration / 同一model内でagentを直列実行できるCodex通常経路です。repository fileを増やしません。

### tracked

次の場合に `plans/<slug>-implementation-completion-handoff.md` を作成します。

- session boundary または resume が必要
- 別 thread / 別 model / 別作業者へ移行する
- GitHub Copilot Chat in VS CodeでTerra -> LunaまたはLuna -> Terraへagent handoffする
- execution time limit により同一 run で続けられない

tracked handoff は実コードの代替設計書ではありません。ただしCopilotのmodel間遷移では会話履歴だけをstate sourceにせず、Original Implementation Intent、route identity、Design Pair handoff path / Decision IDs、Locked Decisions、remaining work、allowed surface、validation、re-entry trigger、current worktree stateを保持します。completionは`plans/<slug>-implementation-completion-handoff.md`、re-entryは`plans/<slug>-high-model-reentry-handoff.md`を使います。

### pre-Design-Pair tracked handoffのresume

旧schemaの必須fieldをすべて持ち、`Design Pair handoff`、`Design Pair Decision compliance`、Origin / Decision ID columnsがすべてなく、Design Pair evidenceも一切ないhandoffだけを互換normalizationできます。

- routeは`adaptive / default`とし、`route_metadata_normalization: legacy-adaptive-handoff`を記録する
- 旧Locked decisionsへ出現順の`LEGACY-HIGH-D01`形式でIDを付ける
- originは`HIGH_MODEL`とする
- 補完したAffected files / symbolsはAllowed edit surfaceに使わない
- normalization recordをtracked handoffへ追記してからSTANDARD_MODELへ渡す

部分的に新しいDesign Pair fieldを持つ、Design Pair selection evidenceがある、または旧必須fieldが不足するhandoffはnormalizationしません。production code / testsを編集せず、`BLOCKED` / `BlockedByInvalidCompletionHandoff`としてartifact repairを要求します。fixtureは`docs/examples/legacy-adaptive-handoff.md`です。

## Verification and final review

HIGH_MODEL と STANDARD_MODEL は、それぞれの変更に関連する build、focused test、lint、format、type check を可能な範囲で実行します。

この flow の `COMPLETED_BY_HIGH_MODEL` または `COMPLETED` は、acceptance status table の全 in-scope item が evidence 付きで `Complete` になった implementation scope の完了を表します。final code review、human review、総合 architecture review、独立 verification の完了は表しません。

最終報告は次を分けます。

- 完了済み implementation
- 実行済み checks
- 未検証事項
- 人手での作業が必要な項目
- final review status

## Changing model assignment

Codexの抽象tierと具体的modelの対応は`codex-agents/*.toml`で変更します。

- `model`: runtime で利用可能な model
- `model_reasoning_effort`: role に必要な reasoning
- `sandbox_mode`: implementation agent では `workspace-write`

Copilotのconcrete modelはcanonical root `.github/agents/*.agent.md`のfrontmatterで指定します。fallback側の同名templateは既存利用者向けの短いmirrorであり、validatorが重要契約の同期を検証します。skill選択後の実行契約は`SKILL.md`とcanonical agentsをsource of truthとします。
