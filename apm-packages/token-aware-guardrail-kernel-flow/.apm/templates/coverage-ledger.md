# Coverage Ledger

この artifact は、Plan Coverage Check and Residual Decision Flow の canonical parent Plan coverage ledger です。

`plans/<slug>-coverage-ledger.md` は parent Plan の FR / AC を source of truth として保持します。handoff、implementation、verification、residual decision、coverage gap resolution の各中間 artifact は、必要な場合だけ `Coverage Ledger Delta` を出力し、この canonical ledger を読み替えたり縮小したりしてはいけません。

## Source of truth

| Field | Value |
| --- | --- |
| Parent Plan | `plans/<slug>.md` |
| Documentation level | `lite / standard` |
| Selected process / route | `standard / full-coverage / other` |
| Last full ledger update | `<artifact path and timestamp>` |
| Last delta applied | `<artifact path and delta ID>` |

## Parent Plan Coverage Ledger

| Plan item | Type | Implementation status | Verification status | Evidence | Residual status | Blocking? |
| --- | --- | --- | --- | --- | --- | --- |

全 parent Plan FR / AC を省略せず記録してください。対象外、別 slice、manual verification、residual decision candidate も空欄にせず、根拠付き status として残します。

## Behavior Case Coverage Ledger

| Case ID | Source IDs | FR / AC | Coverage route | Slice / RC / TP | Status | Residual / reason |
| --- | --- | --- | --- | --- | --- | --- |

Behavior Spec が不要な場合は `N/A` と記録します。Behavior Case が存在する場合は、current pass に含まれない Case ID も explicit disposition なしに消してはいけません。

## Residual Decision Ledger

| Residual ID | Source item | Residual type | Decision status | Human decision source | Owner / next step |
| --- | --- | --- | --- | --- | --- |

accepted / delegated / deferred / aborted は explicit human decision がある場合だけ記録できます。記録しただけの residual candidate は close-compatible ではありません。

## Coverage Ledger Delta

中間 gate は full ledger を再掲しなくてもよいですが、ledger に影響する変更は次の delta として記録してください。

| Delta ID | Source artifact | Plan item / Case ID / Residual ID | Previous status | New status | Evidence / reason | Blocking? |
| --- | --- | --- | --- | --- | --- | --- |

Delta rules:

- `Previous status` は、canonical ledger または直前 delta から分かる値を記録する。
- `New status` は source-backed な status だけを記録する。推測で `Done`、`Verified`、`AcceptedResidual` にしない。
- parent Plan FR / AC の新規 item を発見した場合は、delta に追加し、次の full ledger update で canonical ledger に反映する。
- `UnmappedBlocking`、`NeedsHumanDecision`、`ManualVerificationRequired`、`BehaviorCaseWithoutEvidence`、`ReplanRequired` は close blocker として扱う。
- full ledger と delta が矛盾する場合は、矛盾を `SourceOfTruthDrift` として記録し、勝手に片方を優先して close しない。

## Close readiness summary

| Check | Status | Evidence |
| --- | --- | --- |
| All parent Plan FR / AC classified |  |  |
| All implementation-required items implemented |  |  |
| All verification-required items verified or explicitly dispositioned |  |  |
| Behavior Case coverage complete or N/A |  |  |
| Residual decisions explicit |  |  |
| No fake-only completion |  |  |
| No unclassified delta remains |  |  |

Close readiness can be claimed only when this canonical ledger plus all relevant deltas show no unclassified, blocking, or undecided item.
