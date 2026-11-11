# Design Pair Implementation Handoff

- Verdict: DRAFT / AWAITING_USER_INPUT / READY_FOR_ADAPTIVE_IMPLEMENTATION / HUMAN_DECISION_REQUIRED / REPLAN_REQUIRED / BLOCKED
- Interaction stage: target-map-building / target-selection / disposition-confirmation / upstream-decision / complete / artifact-repair
- Route: design-pair
- implementation_route: design-pair
- implementation_route_source: explicit-user-selection
- Plan / Implementation Intent reference:
- Upstream artifacts:
- Handoff review reference, when present:
- Tracked handoff path: plans/<slug>-design-pair-implementation-handoff.md
- Worktree / revision evidence:
- Target Map presentation evidence: Pending / <assistant turn, presented Target IDs, material sections and versions>
- Target selection request evidence: Pending / <assistant turn inviting direct questions, decisions and skips>
- Latest user response reference: Pending / <user message or turn reference>
- User response occurred after Target Map presentation: Pending / Yes / No
- Selected Target IDs: Pending / None / <DP-Txx list>
- Delegated-to-Adaptive Target IDs: Pending / None / <DP-Txx list>
- No-Change Target IDs: Pending / None / <DP-Txx list>
- Upstream-Decision-Required Target IDs: Pending / None / <DP-Txx list>
- Explicit all-Adaptive delegation: Pending / Yes / No
- Pending human-owned Target IDs: Pending / None / <DP-Txx list>
- Selected Target discussion evidence: Pending / None / <Target IDs and assistant turn references>
- Finalization status: Pending / Validated
- Parent / resume state reference: N/A / <artifact path and field references>
- Adaptive implementation behavior: unchanged
- Locked decision policy: binding-only-for-explicit-entries
- Production code / tests edited during Design Pair: No

## Design Pair Target Map

`map.md` の Investigation boundary、問い一覧、ID別判断資料、Coverage checkをこのsection内へ展開する。各IDは独立して判断・委任できる問いであり、1ファイル＝1IDにしない。

| Target ID | Decision question / why now | Main trade-off / unknown | Decision materials | Disposition |
| --- | --- | --- | --- | --- |
| DP-T01 | <問いと必要性> | <違い・不明点> | <このartifact内の資料節・版> | Pending-User-Selection / Pending-User-Disposition / Locked / Discussed-Unlocked / Adaptive-Owned / No-Change / Upstream-Decision-Required |

各資料節に問い・必要性、具体的code location / responsibility / invariantと関連構造、調査済み事実・制約、実在する選択肢と因果的trade-off、非binding proposalまたはNo proposal理由、未確認事項・変更範囲・validation expectationを一続きで記す。Material version、Evidence revision、Presented at、対話差分も記録する。説明を別ファイルへ多重転記しない。

Target Map の file / symbol は調査範囲と decision の適用対象を示す。Adaptive Implementation の allowed edit surface ではない。

`Target Map presentation evidence`は資料節・版・全Target IDを、資料への導線と各問いの判断入口を示した実際のassistant turnへ結び付ける。資料があるだけ、artifact linkまたはTarget IDと論点名だけではpresentation evidenceにならない。参照不能なら必要な説明を会話で提供する。

`Target selection request evidence`は直接質問・反論・案・確定・部分／残件／全部スキップを案内したturnであり、ID選択専用の工程を要求しない。既出の説明の全面再掲は不要。初回提示後は必ず `AWAITING_USER_INPUT / target-selection` で停止する。

## Upstream Binding Constraints

| Constraint ID | Constraint | Source artifact | Evidence | Relation to Target IDs |
| --- | --- | --- | --- | --- |

この section は Plan / Issue / acceptance criteria / repository policy / public contract に既存の binding requirement を記録する。Design Pair Decision ID を付けず、今回の Design Pair interaction の confirmation として計上しない。

## Upstream User Initial Positions

| Position ID | Initial position | Source user message / turn | Relation to Target IDs | Status |
| --- | --- | --- | --- | --- |

Target Map 提示前の技術案はここに保存できるが、Design Pair Locked Decision へ自動昇格しない。

## Locked Decisions

| Decision ID | Target ID | Decision | Affected files / symbols | Rationale | Validation expectations | Conflict conditions | User message / turn reference | Confirmed content quote or faithful summary | Confirmation occurred after Target Map presentation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-D01 | DP-T01 | | | | | | | | Yes |

この section に Decision ID、presented Target ID、実際の user message / turn reference、確認内容、`Confirmation occurred after Target Map presentation: Yes` がある entry だけが binding である。upstream Plan / Issue / acceptance criteria / gold document / repository docs、AI summary、過去会話からの推測、利用者の沈黙は explicit human confirmation ではない。

判断資料の節・版と提示turnは下の `Selected Target Discussion Evidence` を参照する。初回資料に対する直接の明示的確定も有効であり、選択→再説明→再確認を強制しない。判断に影響する資料変更後は旧confirmationを流用せず、旧証拠を対話履歴へ残してpendingに戻し、新しい明示的確定を得る。

各 Locked Decision の Target ID は `Selected Target IDs` に含まれ、対応する Target Map row の Disposition は `Locked` でなければならない。`Locked` row には一件以上の valid Locked Decision が必要である。

## Target Disposition Evidence

| Target ID | Final disposition | User message / turn reference | Confirmed content quote or faithful summary | Confirmation after Target Map |
| --- | --- | --- | --- | --- |
| DP-T01 | Locked / Discussed-Unlocked / Adaptive-Owned | | | Yes |

`Locked`、`Discussed-Unlocked`、`Adaptive-Owned`の各Targetに一件だけrowを作る。Target IDはTarget Mapに実在し、Final dispositionはTarget Map rowおよびsummary分類と一致し、actual user message / turn referenceと`Confirmation after Target Map: Yes`を持たなければならない。`Locked`は対応するLocked Decisionのconfirmation evidenceを参照または同じ内容で記録できる。明示的な複数Target委任またはall-Adaptive委任では同じuser turn referenceを複数rowに使用できるが、Targetごとのrowは省略しない。AIの推奨、Target Map、Plan、Issue、repository docs、過去会話、AI summary、利用者の沈黙はevidenceにならない。

スキップはDesign Pairで議論せず判断をAdaptiveへ委ねる `Adaptive-Owned` であり、実装省略や `No-Change` ではない。部分・残件・全件の対象を具体的IDへ展開する。「残り」は未確定・未委任のTarget。「全部」が既存Locked等も含む場合、撤回の意図が明示されなければ確認する。

全Targetへの個別明示委任が揃った場合も `Explicit all-Adaptive delegation: Yes` にできる。全Targetを覆う実際の委任証拠が必要で、Selectedが空であるだけではYesにしない。

## Selected Target Discussion Evidence

| Target ID | Material section / version | Presentation assistant turn | Actual post-map user turn | Discussion delta references |
| --- | --- | --- | --- | --- |

初回資料への参照と実際のuser responseを受け入れる。参照先には具体的code location、current invariant、関連構造、alternatives / trade-offs、非binding proposalまたはNo proposal理由、validation expectationが必要で、版と提示turnを辿れることを確認する。Target名や抽象的なリンクだけは証拠にならない。

対話が追加された場合は論点節の質問・回答・根拠差分を参照する。初回資料への直接確定なら追加対話はNoneでよい。説明内容の複製や固定blockの再掲は要求しない。

## Discussed but Unlocked

| Topic / Target ID | Observations | Notes for Adaptive Implementation |
| --- | --- | --- |

## Adaptive-Owned

| Topic / Target ID | Why left to decision-surface-implementation-owner | Useful evidence |
| --- | --- | --- |

## No-Change

| Target ID | Reason | Verification expectation |
| --- | --- | --- |

## Known Evidence

-

## Known Assumptions

-

## Upstream Decisions Required

| Item | Blocking? | Required owner / decision | Evidence |
| --- | --- | --- | --- |

## Knowledge Candidates

| Candidate | Generalization value | Promotion owner / next step |
| --- | --- | --- |

Knowledge Candidates は自動的に knowledge card または repository policy へ昇格しない。

## Readiness Check

対話中は `Finalization status: Pending`、summaryの5集合とSelected Target discussion evidenceのsummary、下記checkは `Pending` のままとする。正本は論点節・Target Map row・実際の人間の証拠であり、各turnは更新した論点と必須進行状態だけを差分更新する。完了直前に全summary/checkを同じ現行証拠から生成・照合する。Validated後の変更ではREADYを解除し、派生summary/checkをPendingへ戻す。PendingをPASSとして受理しない。

| Check | Status | Evidence |
| --- | --- | --- |
| Goal, scope, and acceptance support implementation start | PASS / FAIL | |
| Target Map was presented to the user | PASS / FAIL | <assistant message / turn reference and Target IDs> |
| Target Map presentation includes concrete code structure for every Target | PASS / FAIL | <assistant turn, file/symbol, invariant, decision candidate, evidence> |
| Direct questions, decisions and explicit skips were invited | PASS / FAIL | <assistant message / turn reference> |
| A user response occurred after Target Map presentation | PASS / FAIL | <user message / turn reference> |
| Non-empty user participation or explicit all-Adaptive delegation exists | PASS / FAIL | <selected Target IDs or explicit all-Adaptive response> |
| User-selected discussion targets have final dispositions | PASS / FAIL | |
| Selected Targets have concrete presented materials and actual response evidence | PASS / FAIL / N/A | <Target IDs, material sections/versions, presentation turns, actual user turns, discussion deltas> |
| Locked Decisions have valid post-map confirmation evidence | PASS / FAIL / N/A | |
| Every Locked, Discussed-Unlocked, and Adaptive-Owned Target has matching post-map Target Disposition Evidence | PASS / FAIL / N/A | <Target IDs, dispositions, actual user turn references> |
| Locked Decisions do not conflict with upstream contracts | PASS / FAIL / N/A | |
| No pending human-owned Target remains | PASS / FAIL | |
| No blocking Upstream-Decision-Required remains | PASS / FAIL | |
| Target Map covers the bounded planned change surface | PASS / FAIL | |
| Target Map IDs are unique and every summary ID exists in the Target Map | PASS / FAIL | <set comparison evidence> |
| Summary Target sets are pairwise disjoint and exactly cover the Target Map | PASS / FAIL | <union / intersection evidence> |
| Summary classifications match every Target Map row Disposition | PASS / FAIL | <per-class comparison evidence> |
| Locked Decision Target IDs are selected and their Target Map rows are Locked | PASS / FAIL / N/A | <Decision ID / Target ID evidence> |
| Explicit all-Adaptive delegation has None selected/pending, no Locked Decisions, and every Target is Adaptive-Owned | PASS / FAIL / N/A | <all Target IDs and dispositions> |

READY前に、`Locked` / `Discussed-Unlocked` / `Adaptive-Owned`のTarget集合と`Target Disposition Evidence`のTarget集合を完全一致させる。各Targetは一件だけ、Final dispositionはTarget Map rowとsummary分類に一致し、confirmationはTarget Map提示後のactual user turnを参照する。欠落、架空ID、重複Target、row / evidence不一致、pre-map evidence、AI summaryによる補完が一件でもあればFAILとする。all-Adaptiveでも全Targetのevidence rowが必要である。

Target が一件も選択されず、全 Target の Adaptive delegation も明示されていない状態を空集合として PASS にしない。READY 判定では `Selected Target IDs`、`Delegated-to-Adaptive Target IDs`、`No-Change Target IDs`、`Upstream-Decision-Required Target IDs`、`Pending human-owned Target IDs` の5集合を Target Map と照合し、架空 ID、重複 ID、未分類 Target、row / summary 不一致を一件でも許可しない。全 row が PASS または有効な N/A で、`Interaction stage: complete` の場合だけ `READY_FOR_ADAPTIVE_IMPLEMENTATION` を設定する。

Target Mapに実在するTarget IDだけでも選択成立である。既存資料の判断上の違いを短く示し、最終判断を求めて`Interaction stage: disposition-confirmation`へ進む。初期案は任意で、同じTarget選択を再要求しない。直接質問には該当根拠で答え、直接確定は明示した内容を記録する。未指示Targetはpendingのまま保持し、必要な最終dispositionと合わせて確認する。`design-discussion`等の独自stageを作らない。

新しいsessionでは資料版・提示証拠・正本rowと人間の証拠を再読する。派生集合/checkがPendingであるだけなら待機再開できるが、正本の不整合は `BLOCKED / artifact-repair`。完了時はheaderとReadinessのpost-map user referenceも一致させる。全条件が成立した場合だけ `Finalization status: Validated` と `Interaction stage: complete`、READYを同時に設定する。

`target-map-building`はTarget Map提示前の`DRAFT`だけ、`artifact-repair`は不整合を報告する`BLOCKED`だけに使用する。Target Map提示後の通常経路では`target-selection`、`disposition-confirmation`、`upstream-decision`、`complete`以外へ遷移しない。

## Adaptive Implementation Result

- Status: Pending / Completed / Stopped
- Route used: design-pair -> adaptive-implementation-execution
- Target Map: this artifact / Design Pair Target Map
- Locked Decision IDs:
- Discussed-Unlocked / Adaptive-Owned items:
- Adaptive Implementation verdict sequence:
- Implementation owner sequence:
- Locked Decision compliance evidence:
- Locked Decision conflict: None / <Decision ID and stop evidence>
- Validation performed:
- Files changed:
- Remaining work / human-required work:
- Final review status: Not performed by this flow / <actual separate review status>
