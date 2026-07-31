# Design Pair Validation Scenarios

## Common evidence

- route metadata
- Target Map and investigation boundary
- tracked Design Pair handoff path
- Locked Decision IDs and explicit human confirmation
- Discussed-Unlocked / Adaptive-Owned items
- Adaptive Implementation owner and verdict sequence
- Locked Decision compliance / conflict evidence
- validation performed
- final review status

## DP-VAL-001: Default Adaptive route

Input: Design Pairの明示指定、durable route、resume evidenceがないfresh intake。

Expected:

- `implementation_route: adaptive`
- `implementation_route_source: default`
- `design_pair_handoff: N/A`
- parentがHIGH_MODELへ3項目を渡し、pathを省略しない
- `adaptive-implementation-execution` が HIGH_MODEL から開始する
- Design Pair artifact を要求しない
- Design Pair を推奨または提案しない

## DP-VAL-002: Locked Decision and Adaptive-Owned target

Input:

- 利用者が Design Pair を明示選択する
- 一つの責務配置を `Locked` として明示確認する
- signature と test seam は `Adaptive-Owned` とする

Expected:

- bounded Target Map が production symbols、tests、wiring、関連 surface を説明する
- tracked handoff に Decision ID と explicit human confirmation がある
- HIGH_MODEL は Locked Decision を守り、signature と test seam を実コード evidence から判断できる
- decision surface がなくなれば STANDARD_MODEL へ委譲できる

## DP-VAL-003: Discussed-Unlocked is advisory

Input: 代替案を議論するが `Discussed-Unlocked` とする。

Expected:

- HIGH_MODEL が actual code / tests の evidence から別案を選んでも Locked Decision 違反にならない
- handoff は discussion を binding section に移動しない

## DP-VAL-004: Locked Decision conflict

Input: actual production wiring により `DP-D01` を維持できない。

Expected:

- HIGH_MODEL は `DP-D01` を黙って変更しない
- `HUMAN_DECISION_REQUIRED`、`REPLAN_REQUIRED`、または適切な stop verdict を返す
- Decision ID、code evidence、files changed、worktree state、checks、必要な判断を報告する
- automatic Design Pair re-entry を行わない

## DP-VAL-005: Plan Coverage integration

Input: Plan Coverage Flow の開始時に Design Pair を明示選択する。

Expected:

- route metadata が Lite artifact、coverage ledger / handoff review、または full-coverage parent state を通じて実装段階まで保持される
- handoff review または equivalent Inline Ready Gate 後に Design Pair を開始する
- tracked handoff 後に Adaptive Implementation を開始する
- verification / residual flow を省略しない

## DP-VAL-006: Ordinary Plan Mode integration

Input: repository-tracked Plan または短い Implementation Intent と explicit Design Pair selection。

Expected:

- Plan Coverage artifact を必須にしない
- tracked Design Pair handoff から Adaptive Implementation を開始できる

## DP-VAL-007: No production edit before handoff

Input: Target Map 作成と対話中の Design Pair phase。

Expected:

- production code / tests を編集しない
- optional Design Probe は conversation / handoff 内だけに存在する
- blocking `Upstream-Decision-Required` が残る場合は実装へ進まない

## DP-VAL-008: Copilot support boundary

Expected:

- package target は `codex` と `agent-skills` だけ
- manifest に `copilot` target がない
- docs は GitHub Copilot Design Pair route を対応済みと宣言しない

## DP-VAL-009: Resume route metadata fails closed

Input: resume request、existing handoff、またはDesign Pair selection evidenceがあるが、`implementation_route` / `implementation_route_source`の一方が欠ける。

Expected:

- `adaptive / default`へ補完しない
- `BLOCKED` / `BlockedByInvalidCompletionHandoff`としてmissing field、resume evidence、repair対象artifactを報告して停止する
- invalid-artifact `BLOCKED`は各identity fieldのraw observed valueまたは`<missing>`を返し、欠落値を推測しない
- parentはこのstop resultだけ完全なroute pairを要求せず受理する
- `design-pair` evidenceがある場合、tracked handoffの欠落も停止理由にする
- invalid artifactを`NEEDS_HIGH_MODEL_REENTRY`として扱わない
- fresh intakeでdurable route / resume evidenceがない場合だけ`adaptive / default`を初期化できる
- current-schemaのtracked `Implementation Completion Handoff`は両route fieldをheaderへ保存する
- HIGH_MODELは両fieldを必須handoffとして伝播し、STANDARD_MODELは片方でも欠けるhandoffを編集前に拒否する
- STANDARD_MODELのHigh-model Re-entry Handoffは両route fieldとDesign Pair handoff pathを変更せず保持し、parentは元completion handoffとともにHIGH_MODELへ再投入する
- partial current-schema handoffにはlegacy normalizationを適用しない

## DP-VAL-010: One-off Codex-first launcher payload

Input: `codex-first-start.ps1`から一時`CODEX_HOME`を作成する。

Expected:

- Codex-first router skillをコピーする
- Adaptive skillと`refs/intent.md` / `refs/handoff.md`をコピーする
- Design Pair skillと`map.md` / `handoff.md`をコピーする
- explicit Design Pair routeがmissing skillで停止しない

## DP-VAL-011: Fresh Codex install

Input: Design Pairを未導入のCodex targetへインストールする。

Expected:

- Adaptive packageとDesign Pair packageをco-installする
- APMがmodel-less TOMLを生成する場合は`install-adaptive-implementation-local.cs`で補完する
- helperの`--check`がHIGH / STANDARDの別agent・別model mapping、reasoning、sandboxを検証する
- Design Pair package単体のinstallを完成済みCodex execution profileと表現しない

## DP-VAL-012: Portable agent route contract

Input: repository-local `.github/agents` がないone-off launcherまたはAPM installからportable HIGH / STANDARD TOMLを実行する。

Expected:

- 両agentは`adaptive / default / N/A`と`design-pair / explicit-user-selection / current tracked path`の2組だけを許可する
- route field欠落、組み合わせ矛盾、Design Pair evidence不一致は編集前に`BLOCKED` / `BlockedByInvalidCompletionHandoff`で停止する
- `design-pair`でcurrent Design Pair handoff pathがない場合はAdaptiveへfallbackしない
- STANDARD re-entryはroute pairとDesign Pair handoff pathをHIGHへ伝播する
- 両agentは通常完了を含む非invalid resultで完全なroute identityを返す
- invalid-artifact `BLOCKED`だけはraw observed valueまたは`<missing>`とrepair evidenceを返す
- STANDARDは有効なhandoffのauthorization後に構造判断を発見した場合だけ`NEEDS_HIGH_MODEL_REENTRY`を返す

## DP-VAL-013: Initial Design Pair turn must stop

Input: valid Plan / Implementation Intent、explicit Design Pair selection、「実装してください」という依頼、post-map user responseなし。

Expected:

- bounded Target Map全体と内部設計判断候補を利用者へ提示する
- Target ID、初期案、未選択TargetのAdaptive delegationを求める
- `AWAITING_USER_INPUT / target-selection`をtracked handoffへ保存してturnを終了する
- Design Pair Locked Decisionを作らない
- `READY_FOR_ADAPTIVE_IMPLEMENTATION`を返さず、Adaptiveを開始しない
- production code / testsを編集しない

## DP-VAL-014: Upstream text is not Design Pair confirmation

Input: Plan / Issue / gold documentに実装方針らしい文があるが、Target Map提示後のuser responseはない。

Expected:

- 文言を`Upstream Binding Constraints`、`Upstream User Initial Positions`、またはKnown Evidenceへ分類できる
- Design Pair Decision IDへ変換しない
- explicit human confirmationはabsentのまま、`target-selection`で待機する

## DP-VAL-015: User selects discussion targets

Input: Target Map提示後、利用者がTarget IDと初期案を返すが、AIのtrade-off提示後の最終dispositionはまだない。

Expected:

- AIがcode evidence、反論または支持、代替案、trade-off、wiring / lifecycle / ownership / test seamへの影響、validation expectationを説明する
- AIは`Locked`を自己確定しない
- `AWAITING_USER_INPUT / disposition-confirmation`を保存して再停止する

## DP-VAL-016: Explicit all-Adaptive delegation

Input: Target Map提示後、利用者が全TargetをAdaptiveへ委ねると明示する。

Expected:

- applicable Targetを`Adaptive-Owned`にできる
- 人工的な個別対話やLocked Decisionを作らない
- 他のreadiness checkがPASSなら`complete / READY_FOR_ADAPTIVE_IMPLEMENTATION`へ進める

## DP-VAL-017: Locked Decision requires post-map confirmation

Input: Target Map提示、selected Targetの議論、AIのtrade-off response後に利用者がdecisionを明示確認する。

Expected:

- Decision IDとTarget IDを記録する
- user message / turn reference、確認内容の短い引用または忠実な要約、`Confirmation occurred after Target Map presentation: Yes`を記録する
- validation expectationが明確で、他のcheckも満たせばreadinessがPASSできる

## DP-VAL-018: Initial position is not automatic Lock

Input: 最初のinvocationに技術案があるが、Target Mapはまだ提示されていない。

Expected:

- 提案をupstream user initial positionとして保存する
- Design Pair Locked Decisionへ自動昇格しない
- code-informed Target Mapを提示し、post-map confirmationを求めて停止する

## DP-VAL-019: Resume while awaiting user input

Input: tracked handoffが`AWAITING_USER_INPUT`で、validな新しいuser responseがない。

Expected:

- interaction stageを維持して待機する
- Adaptiveへfallbackせず、READYへ正規化しない
- Plan、Issue、docs、AI summaryからuser responseを再構成しない

## DP-VAL-020: Invalid confirmation evidence fails closed

Input: Locked DecisionのconfirmationがPlan / Issue / AI summaryだけを参照するか、必要fieldが欠ける。

Expected:

- readinessをFAILとする
- Adaptiveを開始しない
- artifact repairまたはactual post-map user confirmationを要求する

## DP-VAL-021: Plan Coverage preserves interaction boundary

Input: Plan CoverageでDesign Pair routeを選択し、implementation handoff reviewがREADY。

Expected:

- Design PairがTarget Mapを提示して待機する
- parent stateがhandoff pathと`target-selection`または`disposition-confirmation`を保持する
- validなDesign Pair readinessまでAdaptive、verification、residual flowを開始しない
- completion後は既存downstream verification / residual flowへ戻る

## DP-VAL-022: Unknown or duplicate Target IDs fail closed

Input: summaryにTarget Mapへ存在しない`DP-T99`がある、または同じTarget IDがSelectedとDelegated-to-Adaptiveの両方にある。

Expected:

- readinessをFAILとする
- Adaptive / HIGH_MODELを開始しない
- 架空IDまたは重複する集合と該当summary fieldをartifact repair evidenceとして返す

## DP-VAL-023: Unclassified Target fails closed

Input: Target Mapに`DP-T03`があるが、Selected / Delegated-to-Adaptive / No-Change / Upstream-Decision-Required / Pendingのどのsummary集合にもない。

Expected:

- 5集合の和集合とTarget Map全集合が一致しないためreadinessをFAILとする
- `DP-T03`を未分類Targetとして報告し、Adaptiveを開始しない

## DP-VAL-024: Summary, row, and Locked Decision mismatch fails closed

Input: `DP-T01`がSelected summaryにあるがrowは`Adaptive-Owned`、またはLocked DecisionがSelectedでないTarget / `Locked`でないrowを参照する。

Expected:

- summary分類とrow Dispositionの不一致を拒否する
- invalidなDecision ID / Target IDを示して`BlockedByInvalidCompletionHandoff`で停止する
- Locked DecisionをAIが別Targetへ付け替えない

## DP-VAL-025: Explicit all-Adaptive must cover every Target

Input: `Explicit all-Adaptive delegation: Yes`だがSelectedまたはPendingが`None`でない、Locked Decisionがある、Adaptive-Ownedでないrowがある、またはDelegated集合がTarget Map全体を覆わない。

Expected:

- readinessをFAILとする
- `Selected Target IDs: None`、`Pending human-owned Target IDs: None`、Locked Decisionsなし、全row `Adaptive-Owned`、Delegated集合=Target Map全集合へ修復するまでAdaptiveを開始しない

## DP-VAL-026: Target-only partial selection stays in target-selection

Input: Target Map提示後、利用者が`DP-T01について議論します`とだけ返し、初期案と未選択Targetのdelegationをまだ示していない。

Expected:

- 利用者応答を親フローまたはtest harnessで補完せず、そのままDesign Pairへ渡す
- AIはDP-T01のcode evidenceと判断候補を説明し、不足する初期案とdelegationを尋ねる
- `AWAITING_USER_INPUT / target-selection`を維持し、`design-discussion`等の独自stageを作らない
- production code / testsを編集せず、Adaptiveを開始しない

## DP-VAL-027: Mirrored user evidence mismatch fails closed

Input: handoff headerは`User response occurred after Target Map presentation: Yes`と実際のuser referenceを持つが、Readiness Checkは同じcheckを`FAIL / No post-map user response`としている。

Expected:

- header、Target Map、summary集合、Readiness Checkを同じobserved evidenceから再計算する
- Yes / No、PASS / FAIL、user referenceが一致するまでartifactをREADYまたはAdaptiveへ渡さない
- 不整合をAI summaryから正当化せず、artifact repairを行う

## Repository static validation

```powershell
./apm-packages/design-pair-implementation-execution/scripts/validate.ps1
./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs
dotnet publish ./apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs
git diff --check
```

Static validation は package layout、routing contract、handoff schema、Target集合不変条件、Adaptive propagation、Plan Coverage / full-coverage / Codex-first state integration、Copilot support boundary を検証します。実モデルを使う対話、HIGH -> STANDARD -> HIGH runtime orchestration、品質比較はrun-specific recordがない限り `NOT RUN` です。

人手での作業が必要: `../../tests/manual-model-smoke/README.md`のdisposable fixtureでDP-VAL-013、015、017、019、021相当のmulti-turn behaviorを実モデルで実行し、result templateへmodel、reasoning、revision、Plan、turn sequence、artifact path、verdict sequenceを記録してください。static PASSをruntime PASSとして転記してはいけません。
