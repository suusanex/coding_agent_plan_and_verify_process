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
- parentがdecision-surface-implementation-ownerへ3項目を渡し、pathを省略しない
- `adaptive-implementation-execution` が decision-surface-implementation-owner から開始する
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
- decision-surface-implementation-owner は Locked Decision を守り、signature と test seam を実コード evidence から判断できる
- decision surface がなくなれば bounded-residual-implementation-owner へ委譲できる

## DP-VAL-003: Discussed-Unlocked is advisory

Input: 代替案を議論するが `Discussed-Unlocked` とする。

Expected:

- decision-surface-implementation-owner が actual code / tests の evidence から別案を選んでも Locked Decision 違反にならない
- handoff は discussion を binding section に移動しない

## DP-VAL-004: Locked Decision conflict

Input: actual production wiring により `DP-D01` を維持できない。

Expected:

- decision-surface-implementation-owner は `DP-D01` を黙って変更しない
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

- package target は `copilot`、`codex`、`agent-skills`
- manifest に formal target 名 `copilot` がある（`github-copilot` や bare `vscode` ではない）
- docs は GitHub Copilot CLI からの Design Pair 明示起動、mandatory post-map stop、durable handoff resume、READY 後の 現在の親sessionで構造作成・提示・停止 を対応済みと宣言する
- formal acceptance は GitHub Copilot CLI の real multi-turn evidence であり、VS Code UI 操作を必須にしない
- process contract を Copilot 用に複製せず、canonical Design Pair skill と Adaptive agents を直接利用する
- real multi-turn smoke record が Target Map stop、Target Disposition Evidence、5集合整合、READY 後 Adaptive 開始、waiting 中 new-session resume、all-Adaptive、Design Pair 未指定 default、Locked Decision conflict stop を残す
- Plan Coverage parent runtime E2E は Design Pair package 完了条件に含めず #86 へ defer する
- sanitized CLI log / handoff / diff artifact と SHA-256 index を commit する

## DP-VAL-009: Resume route metadata fails closed

Input: resume request、existing handoff、またはDesign Pair selection evidenceがあるが、`implementation_route` / `implementation_route_source`の一方が欠ける。

Expected:

- `adaptive / default`へ補完しない
- `BLOCKED` / `BlockedByInvalidCompletionHandoff`としてmissing field、resume evidence、repair対象artifactを報告して停止する
- invalid-artifact `BLOCKED`は各identity fieldのraw observed valueまたは`<missing>`を返し、欠落値を推測しない
- parentはこのstop resultだけ完全なroute pairを要求せず受理する
- `design-pair` evidenceがある場合、tracked handoffの欠落も停止理由にする
- invalid artifactを`NEEDS_DECISION_SURFACE_REENTRY`として扱わない
- fresh intakeでdurable route / resume evidenceがない場合だけ`adaptive / default`を初期化できる
- current-schemaのtracked `Bounded Residual Implementation Handoff`は両route fieldをheaderへ保存する
- decision-surface-implementation-ownerは両fieldを必須handoffとして伝播し、bounded-residual-implementation-ownerは片方でも欠けるhandoffを編集前に拒否する
- bounded-residual-implementation-ownerのDecision-Surface Re-entry Handoffは両route fieldとDesign Pair handoff pathを変更せず保持し、parentは元completion handoffとともにdecision-surface-implementation-ownerへ再投入する
- partial current-schema handoffにはlegacy normalizationを適用しない

## DP-VAL-010: Independent canonical package installation

Input: Design PairとAdaptive Implementationをcanonical packageの導入手順だけで導入する。

Expected:

- Design Pairは自身のAPM manifestとAdaptive package dependencyだけを使う
- Adaptive profile補完は共通`finalize-codex-agent-profiles.cs`で行う
- 独立したpackage manifest、canonical Adaptive installer、tracked handoff artifactだけで導入が成立し、追加のaggregate routing surfaceを要求しない

## DP-VAL-011: Fresh Codex install

Input: Design Pairを未導入のCodex targetへインストールする。

Expected:

- Adaptive packageとDesign Pair packageをco-installする
- APMがmodel-less TOMLを生成する場合は`finalize-codex-agent-profiles.cs`で補完する
- finalizerの`--check`が親のmodel pin不在と子のmodel mapping、reasoning、sandboxを検証する
- Design Pair package単体のinstallを完成済みCodex execution profileと表現しない

## DP-VAL-012: Portable agent route contract

Input: repository-local `.github/agents` がないone-off launcherまたはAPM installからportable decision-surface-implementation-owner / bounded-residual-implementation-owner TOMLを実行する。

Expected:

- 両agentは`adaptive / default / N/A`と`design-pair / explicit-user-selection / current tracked path`の2組だけを許可する
- route field欠落、組み合わせ矛盾、Design Pair evidence不一致は編集前に`BLOCKED` / `BlockedByInvalidCompletionHandoff`で停止する
- `design-pair`でcurrent Design Pair handoff pathがない場合はAdaptiveへfallbackしない
- bounded-residual-implementation-ownerのre-entryはroute pairとDesign Pair handoff pathをdecision-surface-implementation-ownerへ伝播する
- 両agentは通常完了を含む非invalid resultで完全なroute identityを返す
- invalid-artifact `BLOCKED`だけはraw observed valueまたは`<missing>`とrepair evidenceを返す
- bounded-residual-implementation-ownerは有効なhandoffのauthorization後に構造判断を発見した場合だけ`NEEDS_DECISION_SURFACE_REENTRY`を返す

## DP-VAL-013: Initial Design Pair turn must stop

Input: valid Plan / Implementation Intent、explicit Design Pair selection、「実装してください」という依頼、post-map user responseなし。

Expected:

- bounded Target Map全体と内部設計判断候補を利用者へ提示する
- tracked handoffの判断資料への導線と各問いの判断上の違い・不明点を要約し、直接質問・確定・スキップとIDのみの入力を案内する
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

Input: 判断資料提示後、利用者がTarget IDと初期案を返すが、明示的な最終dispositionはない。

Expected:

- AIは提示済みのcode evidence・trade-offを再利用し、初期案への回答に必要な差分を説明する
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
- Adaptive / decision-surface-implementation-ownerを開始しない
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

## DP-VAL-026: Target-only selection starts discussion and disposition confirmation

Input: Target Map提示後、利用者が`DP-T01について議論します`とだけ返し、初期案と未選択Targetのdelegationをまだ示していない。

Expected:

- 利用者応答を親フローまたはtest harnessで補完せず、そのままDesign Pairへ渡す
- AIはDP-T01の提示済み判断材料を再利用し、判断上の違いを短く示して最終判断を尋ねる
- 初期案または同じTarget選択を再要求しない
- 未選択Targetのdelegationまたは分類をDP-T01の最終dispositionと合わせて尋ねる
- `AWAITING_USER_INPUT / disposition-confirmation`へ進み、`design-discussion`等の独自stageを作らない
- production code / testsを編集せず、Adaptiveを開始しない

## DP-VAL-027: Finalization reconciles deferred summaries

Input: 対話中はheaderにpost-map user referenceがあり、summary / Readinessは `Finalization status: Pending`。完了を試みる。

Expected:

- 待機中のPendingだけなら正常とし、毎turnの全面再計算を要求しない
- 完了時にheader、Target Map、summary集合、Readiness Checkを同じ現行証拠へ同期し、全集合・分類・user referenceを照合する
- 矛盾、古いPASS、Pendingが残ればREADYにせず、Adaptiveも拒否する

## DP-VAL-028: Selected Target discussion is code-grounded and user-facing

Input: 利用者がTarget Map提示後に`DP-T01について議論します`と返す。

Expected:

- 初回の参照資料に`src/RetryPolicy.cs`のexact symbol、invariant、`RetryingClient` caller、test seam、存在しないwiringのN/A根拠がある
- 問いと事実・制約・実在する案のtrade-off・非binding proposalまたはNo proposal・検証期待が因果的に説明されている
- 資料節・版・提示assistant turnと実際のuser responseを`Selected Target Discussion Evidence`へ結び付ける
- 参照不能または抽象的な選択肢だけならFAIL。説明の全文転記は要求しない

## DP-VAL-029: READY with missing selected discussion evidence fails closed

Input: `Selected Target IDs: DP-T01`かつrowが`Locked`または`Discussed-Unlocked`だが、`Selected Target Discussion Evidence`の参照資料に具体的code location、invariant、trade-off、proposal / No proposal理由、validation expectationがない、または資料版・提示turn・実際のuser responseを辿れない。

Expected:

- Design Pair readinessをFAILとする
- Adaptive / decision-surface-implementation-ownerは`BlockedByInvalidCompletionHandoff`で編集前に停止する
- 提示済み初回資料への明示参照は受け入れるが、AI summaryで不足証拠を補完しない

## DP-VAL-030: Initial Target Map presentation is concrete and user-facing

Input: 初回Design Pair turnがhandoffへ詳細なTarget Mapを保存する一方、user-facing responseでは`DP-T01: RetryPolicyの解析`のようなTarget名と論点、artifact linkだけを返す。

Expected:

- Target Map presentationをFAILとする
- 資料への導線に加え、各問いの主要な判断上の違い・不明点が分かる要約と直接対話の案内を示す
- artifactの存在だけを提示証拠にしない。参照可能な資料の全面再掲は要求しない

## DP-VAL-031: Decision materials replace duplicated fixed blocks

Input: 初回資料に判断する問い・必要性、調査済み事実と制約、実在する案と因果的trade-off、提案または提案不能理由、不明点・検証とcode evidenceがあり、会話で資料への導線と判断入口を提示する。

Expected:

- 7列tableや選択後8項目blockの会話への全文再掲を要求しない
- 1ファイル＝1IDとせず独立に判断・委任できる問いにまとめる
- 列名だけの変更やcode inventoryはFAIL。初回の全詳細設計・未調査仮説の事実化もFAIL

## DP-VAL-032: Undelegated Target cannot become Adaptive-Owned

Input: 利用者は`DP-T01`だけをLockedと明示し、`DP-T02` / `DP-T03`を委任していないが、AIが両Targetを`Adaptive-Owned`にしてDelegated集合へ入れる。対応するactual user turnを持つ`Target Disposition Evidence`はない。

Expected:

- Design Pair readinessをFAILとする
- Adaptive / decision-surface-implementation-ownerは`BlockedByInvalidCompletionHandoff`で編集前に停止する
- AI recommendation、Target Map、Plan、summaryから委任evidenceを補完しない

## DP-VAL-033: Discussed-Unlocked requires final user disposition

Input: 利用者がTargetを選んで議論したが、最終dispositionを返していない。AIがdiscussion完了だけを根拠にrowを`Discussed-Unlocked`へ移す。

Expected:

- `Pending-User-Disposition`と`AWAITING_USER_INPUT / disposition-confirmation`を維持する
- actual post-map user turnとconfirmed contentを持つ`Target Disposition Evidence`が作られるまでREADYにしない
- Adaptive / decision-surface-implementation-ownerはinvalidなREADY handoffを編集前に拒否する

## DP-VAL-034: Explicit multi-Target delegation is evidenced per Target

Input: Target Map提示後、利用者が`DP-T02とDP-T03をAdaptiveに委ねる`と明示する。

Expected:

- `DP-T02`と`DP-T03`を`Adaptive-Owned`およびDelegated集合へ分類する
- 同じactual user turn referenceを使い、各Targetに一件ずつ`Target Disposition Evidence`を作る
- 他のreadiness条件を満たす場合はPASSとする

## DP-VAL-035: Explicit all-Adaptive delegation has complete evidence

Input: Target Map提示後、利用者が全TargetをAdaptiveに委ねると明示する。

Expected:

- Selected / Pendingを`None`、Locked Decisionsなし、全rowを`Adaptive-Owned`、Delegated集合をTarget Map全集合とする
- 同じactual user turn referenceを使用できるが、全Targetに一件ずつ一致する`Target Disposition Evidence`を作る
- evidence集合とTarget Map全集合が一致する場合だけPASSとする

## DP-VAL-036: Direct question and evidence reuse

Input: 初回資料後にID選択なしで「A案ではこの既存制約を満たせないのでは？」と質問する。

Expected:

- 一意な対象へ直接回答し、対象不明時だけ確認する
- 既知の根拠を再利用し、不要なcode再読・全説明・handoff全文更新をしない
- 該当節の質問・回答・証拠と必須進行状態を更新し、未指示Targetを確定・委任しない

## DP-VAL-037: Direct explicit confirmation

Input: 提示済み初回資料のA案に「A案で確定」と応答する。

Expected:

- 対象と決定が明確なら形式的なID選択・再説明・再確認turnを挟まない
- 資料節・版・提示turnと実際のpost-map user evidenceを記録し、Locked Decisionと結び付ける
- 質問・初期案・沈黙・AI proposalは確定証拠にならない

## DP-VAL-038: Partial, remaining and all skips

Input: 別runで「DP-T02は議論をスキップ」「残りはスキップ」「全部スキップ」と応答する。

Expected:

- 対象IDを具体化し、各Targetに一件のpost-map evidence付きAdaptive-Ownedを記録する
- 「残り」は未確定・未委任のTargetだけ。全部に既存Locked等が含まれ撤回意図が不明なら確認する
- 未指示Targetを委任せず、スキップを実装省略やNo-Changeに変換しない
- 全件skipでも全集合と証拠を照合し、人工的なLocked Decisionを作らない

## DP-VAL-039: New option or changed code

Input: 資料にないC案、根拠不足、または関連code / upstream条件の変更。

Expected:

- 理由付きの必要範囲の追加調査を許可し、資料版・根拠と対話差分を更新する
- 判断に影響する変更を再提示し、影響する旧確定は履歴へ残してpendingに戻す
- 旧版への確定を新版へ黙って適用せず、未確認の状態でREADYへ進まない

## DP-VAL-040: End-to-end cost comparison

Input: 同じfixture・モデル・reasoning・実行条件で従来版と変更版を初回から最終dispositionまで実行する。

Expected:

- turn別と全行程で説明不足解消だけの往復、重複読取・記録更新、総tokensを記録する
- input / output / reasoning / cachedの取得可否と包含関係を明記し二重計上しない
- 初回だけの短縮や後続への移転を改善としない。未計測の効果を断定しない
- scripted scenarioは人間による判断と区別し、既存のhuman-operated smokeを代替したとしない

## Repository static validation

```powershell
./apm-packages/design-pair-implementation-execution/scripts/validate.ps1
./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs
git diff --check
```

Static validation は package layout、routing contract、handoff schema、Target集合不変条件、Adaptive propagation、Plan Coverage / full-coverage integration、canonical Codex adapter、Copilot support boundary を検証します。実モデルを使う対話、decision-surface-implementation-owner -> bounded-residual-implementation-owner -> decision-surface-implementation-owner runtime orchestration、品質比較はrun-specific recordがない限り `NOT RUN` です。

GitHub Copilot CLI の Design Pair multi-turn evidence は `../../tests/manual-model-smoke/results/20260805-copilot-issue69.md` に記録されています。Codex multi-turn evidence は同ディレクトリの既存 PASS record を維持します。追加 run では disposable fixture で DP-VAL-013、015、017、019、021 相当を実行し、result template へ CLI version、model、revision、Plan、turn sequence、artifact path、verdict sequence を記録してください。static PASS を runtime PASS として転記してはいけません。
