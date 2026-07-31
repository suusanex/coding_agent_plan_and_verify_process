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
- Target Map presentation evidence: Pending / <assistant message or turn reference and presented Target IDs>
- Target selection request evidence: Pending / <assistant message or turn reference>
- Latest user response reference: Pending / <user message or turn reference>
- User response occurred after Target Map presentation: Pending / Yes / No
- Selected Target IDs: Pending / None / <DP-Txx list>
- Delegated-to-Adaptive Target IDs: Pending / None / <DP-Txx list>
- No-Change Target IDs: Pending / None / <DP-Txx list>
- Upstream-Decision-Required Target IDs: Pending / None / <DP-Txx list>
- Explicit all-Adaptive delegation: Pending / Yes / No
- Pending human-owned Target IDs: Pending / None / <DP-Txx list>
- Selected Target discussion evidence: Pending / None / <Target IDs and assistant turn references>
- Parent / resume state reference: N/A / <artifact path and field references>
- Adaptive implementation behavior: unchanged
- Locked decision policy: binding-only-for-explicit-entries
- Production code / tests edited during Design Pair: No

## Design Pair Target Map

| Target ID | File / Symbol | Current responsibility | Current invariant | Relation to requested change | Internal design decision candidate | Expected modification or verification | Relevant evidence | Open question | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-T01 | | | | | | | | | Pending-User-Selection / Pending-User-Disposition / Locked / Discussed-Unlocked / Adaptive-Owned / No-Change / Upstream-Decision-Required |

Target Map の file / symbol は調査範囲と decision の適用対象を示す。Adaptive Implementation の allowed edit surface ではない。

`Target Map presentation evidence`は、この表の各TargetについてTarget ID、具体的file / symbol、current responsibility / invariant、requested changeとの関係、内部設計判断候補、expected modification or verification、relevant evidence、open questionをuser-facingに提示したassistant turnを参照する。artifact linkまたはTarget IDと論点名だけの要約はpresentation evidenceにならない。

user-facing responseは`Design Pair Target Map`の7列Markdown table、Coverage evidence、Selection requestを含む。handoff内だけに詳細がある状態、またはfinal responseがTarget名と論点の短い箇条書きだけの場合、Readiness CheckのTarget Map presentation rowsをPASSにしてはいけない。

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

各 Locked Decision の Target ID は `Selected Target IDs` に含まれ、対応する Target Map row の Disposition は `Locked` でなければならない。`Locked` row には一件以上の valid Locked Decision が必要である。

## Selected Target Discussion Evidence

| Target ID | Assistant turn reference | Concrete file / symbol / line evidence | Current responsibility / invariant | Caller / wiring / lifecycle / test-seam evidence | Alternatives and trade-offs | Non-binding AI proposal or No proposal reason | Validation expectation | Open questions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

選択Targetの初期案または最終dispositionを求める前に、この内容をuser-facing responseにも提示する。artifactへのlink、Target名、抽象的な選択肢だけではdiscussion evidenceにならない。

user-facing responseでは`<DP-Txx> Internal design discussion` blockにCode location、Current responsibility / invariant、Callers / wiring / lifecycle / state / test seam、Internal design decision needed、Alternatives and trade-offs、Non-binding AI proposalまたはNo proposal理由、Validation expectations、Open questionsを明示する。

## Discussed but Unlocked

| Topic / Target ID | Observations | Notes for Adaptive Implementation |
| --- | --- | --- |

## Adaptive-Owned

| Topic / Target ID | Why left to HIGH_MODEL | Useful evidence |
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

| Check | Status | Evidence |
| --- | --- | --- |
| Goal, scope, and acceptance support implementation start | PASS / FAIL | |
| Target Map was presented to the user | PASS / FAIL | <assistant message / turn reference and Target IDs> |
| Target Map presentation includes concrete code structure for every Target | PASS / FAIL | <assistant turn, file/symbol, invariant, decision candidate, evidence> |
| Target selection was requested and optional initial positions were invited | PASS / FAIL | <assistant message / turn reference> |
| A user response occurred after Target Map presentation | PASS / FAIL | <user message / turn reference> |
| Non-empty user participation or explicit all-Adaptive delegation exists | PASS / FAIL | <selected Target IDs or explicit all-Adaptive response> |
| User-selected discussion targets have final dispositions | PASS / FAIL | |
| Selected Targets have concrete user-facing discussion evidence | PASS / FAIL / N/A | <Target IDs, assistant turn references, code locations, trade-offs, proposal, validation> |
| Locked Decisions have valid post-map confirmation evidence | PASS / FAIL / N/A | |
| Locked Decisions do not conflict with upstream contracts | PASS / FAIL / N/A | |
| No pending human-owned Target remains | PASS / FAIL | |
| No blocking Upstream-Decision-Required remains | PASS / FAIL | |
| Target Map covers the bounded planned change surface | PASS / FAIL | |
| Target Map IDs are unique and every summary ID exists in the Target Map | PASS / FAIL | <set comparison evidence> |
| Summary Target sets are pairwise disjoint and exactly cover the Target Map | PASS / FAIL | <union / intersection evidence> |
| Summary classifications match every Target Map row Disposition | PASS / FAIL | <per-class comparison evidence> |
| Locked Decision Target IDs are selected and their Target Map rows are Locked | PASS / FAIL / N/A | <Decision ID / Target ID evidence> |
| Explicit all-Adaptive delegation has None selected/pending, no Locked Decisions, and every Target is Adaptive-Owned | PASS / FAIL / N/A | <all Target IDs and dispositions> |

Target が一件も選択されず、全 Target の Adaptive delegation も明示されていない状態を空集合として PASS にしない。READY 判定では `Selected Target IDs`、`Delegated-to-Adaptive Target IDs`、`No-Change Target IDs`、`Upstream-Decision-Required Target IDs`、`Pending human-owned Target IDs` の5集合を Target Map と照合し、架空 ID、重複 ID、未分類 Target、row / summary 不一致を一件でも許可しない。全 row が PASS または有効な N/A で、`Interaction stage: complete` の場合だけ `READY_FOR_ADAPTIVE_IMPLEMENTATION` を設定する。

Target Mapに実在するTarget IDだけが返った場合も選択成立である。実際のuser response referenceと`User response occurred after Target Map presentation: Yes`を保存し、選択Targetのminimum discussion surfaceをuser-facingに提示したうえで`Interaction stage: disposition-confirmation`へ進む。初期案は任意であり、不足を理由に同じTargetの選択を再要求しない。未選択Targetのdelegationまたは分類はpendingのまま保持し、選択Targetの最終dispositionと同じ確認で求める。`design-discussion`等の独自stageを作ってはいけない。各turnの保存前にheaderとReadiness Checkを同じevidenceから同期し、同名checkのYes / No、PASS / FAIL、user referenceを矛盾させない。

Target IDだけの選択でも、選択Targetについて具体的file / symbol、current responsibility / invariant、caller / wiring / lifecycle / test seam、alternatives / trade-offs、非binding proposalまたはNo proposal理由、validation expectationをuser-facingに提示し、`Selected Target Discussion Evidence`へ同じassistant turn referenceで保存する。論点名だけの応答はFAILである。

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
