# Bounded Residual Implementation Handoff

- Verdict: READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION
- Schema: adaptive-structure-0.7
- Handoff persistence: tracked (standalone file / existing Living Record section)
- Original Implementation Intent: <tracked path or goal / scope / acceptance / constraints / validation snapshot>
- Plan reference:
- implementation_route: adaptive / design-pair
- implementation_route_source: default / explicit-user-selection
- Design Pair handoff: N/A / plans/<slug>-design-pair-implementation-handoff.md
- Ownership transfer basis: human-approved-structure
- reentry_count: 0
- previous_reentry_trigger: N/A
- reentry_progress_evidence:
  - trigger: N/A
  - resolution: N/A
  - verification: N/A
  - same_unresolved_cause_rehanded_off: N/A

route identityはincoming durable stateから変更せず伝播する。current schemaの欠落、矛盾、Design Pair evidence不一致、旧agent名・旧0.5 schema、新旧混在schemaはnormalizationせず`BLOCKED / BlockedByInvalidCompletionHandoff`とする。

## Acceptance status

| Acceptance item | Status | Evidence | Remaining work mapping (Work ID) |
| --- | --- | --- | --- |
| | Complete / Incomplete | | |

`Blocked`を許可しない。すべての`Incomplete` itemは一件以上のWork IDに対応し、すべてのRemaining work rowは一件以上の`Incomplete` itemに対応する。`Complete` itemにはimplementationまたはvalidation evidenceを記録する。

## Structure review（待機時から保存する）

- Status: AWAITING_STRUCTURE_REVIEW / APPROVED / CHANGES_REQUESTED
- Structure version: <単調増加する版>
- Code snapshot: <base commit + 保存したdiffのpath/hash、untrackedを含む対象fileごとのSHA256>
- Reviewed files / symbols: <契約・依存・主要シーケンスが読める実コード>
- Unimplemented leaves: <子が実装する末端、既存再利用時は残る検証>
- Production builds: <変更/影響project、選定根拠、command、exit code、結果、snapshotへの対応>
- Presentation reference: <この版とコード状態を実際に示したassistant turn>
- User response reference: Pending / <提示後の実際の利用者turn>
- User response quote: Pending / <原文>
- Approved structure version: Pending / <承認対象版>
- Resume comparison: <現在コードと提示snapshotの差分、構造影響の有無と根拠>

提示後はそのターンを終了する。実応答が来るまで実装・子起動は禁止。保存前にはPresentation referenceをPendingとしてよいが、実提示後のturn参照を再開時に確定し、Pendingを承認扱いしない。参照だけでなくquoteと対象版を照合する。事前の包括実装指示・Design Pair承認・AIの推測応答は代用不可。

承認は構造合意でありコード凍結ではない。提示から承認/初回委譲までに差分があれば実コードで確認し、構造を実質変更する場合だけ新版を提示して実応答を待つ。子の局所的な詳細変更は承認を失効させない。再引受けで構造を変える場合は旧版の承認を流用しない。元snapshotと承認履歴を上書きせず版ごとに保持する。旧schema・欠落・矛盾を補完して承認を作らない。

## Structure readiness

| Concern | Status | Code / contract evidence or N/A reason |
| --- | --- | --- |
| Responsibility / ownership | Ready / N/A | |
| Shared types / signatures / XML contracts / guarantee ownership | Ready / N/A | |
| Dependencies / creation / registration | Ready / N/A | |
| Main cross-class sequence / arguments / results / await | Ready / N/A | |
| Upstream / Design Pair binding compliance | Ready / N/A | |

構造の未決はReadyにしない。required production build成功と上表をhandoff readinessとして確認し、人の承認とは別に判定する。buildで動作・契約の意味を証明した扱いにしない。

入力検査実装、メソッド本体、private helper、局所分岐/loop、内部error / cancellation / retry制御、test architecture / seam / mock / harness / 詳細検証は **Deferred to child**。これらの未決をreadiness不成立としない。要件がクラス間連携を必要とする場合だけ連携構造・外部契約・保証責務を上表に含める。旧全decision surfaceのResolved条件は使用しない。

## Implementation and verification evidence

| Decision surface | Code / test / wiring / inspection evidence | Verification and observed consequence |
| --- | --- | --- |
| | | |

code edit有無や量をtransfer条件にしない。inspection-onlyの場合は、残作業が新しい非局所判断を必要としない根拠を記録する。

上記evidenceへ既存処理との比較も含める。実際に読んだ参照file / symbolと呼び出し関係、関連する順序・状態所有・失敗等の扱い、要求差分、採用方式（API呼び出し / 拡張点利用 / 構造追従 / 別方式）、別方式の具体的根拠と例外範囲を簡潔に引き継ぐ。類似処理がなければ探索範囲と未発見事実、局所修正なら短い比較でよい。既存記録への参照でもよいが、次ownerが読める内容を保持する。

実装済み部分のactual diffと参照処理の照合結果を記す。追加状態・順序制御・既存serviceを迂回する直接呼び出しの必要性を確認し、未実装部分の照合はRemaining workのCompletion checkへ置く。inspection-onlyでは照合未実施を明記する。比較記録のために新しいartifactや承認待ちを作らない。

re-entry後の再transferでは、`reentry_count`を直前のDecision-Surface Re-entry Handoffの値と一致させ、`previous_reentry_trigger`と`reentry_progress_evidence.trigger`をそのhandoffの`trigger`へ一致させる。`resolution`へdecision surfaceを解消したcode evidence、`verification`へ確認結果、`same_unresolved_cause_rehanded_off`へ`false`を記録する。Remaining workまたはAllowed edit surfaceの縮小は要求しない。

## Implemented

- 親が作成/再利用した構造code、XML契約、依存・sequenceとproduction build結果
- 既存再利用のみなら変更なしの事実を記す。子に渡すためだけのTODOを作らない

## Locked decisions

| Origin | Decision ID | Decision | Affected files / symbols | Validation expectation | Compliance evidence |
| --- | --- | --- | --- | --- | --- |
| Design Pair / Decision-Surface Implementation Owner | DP-D01 / DSI-D01 | | | | Pending / evidence |

`Affected files / symbols`はdecisionの適用範囲であり、Allowed edit surfaceではない。

## Remaining work

| Work ID | Acceptance item(s) | Responsibility | Authorized surface | Expected behavior | Locked boundaries | Local freedom | Completion check |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RW-1 | | | | | | | |

## Allowed edit surface

| Directory / file group | Allowed change envelope |
| --- | --- |
| | |

## Validation commands

```text
<build / focused test / lint / format / type check>
```

## Decision-surface re-entry triggers

- locked responsibility、placement、signatureでは成立せず、新しいshared abstraction / contract / dependency decisionが必要
- public / shared internal API、schema、config surfaceの変更が必要
- production sequence、DI lifetime / location、wiring architectureの変更が必要
- 外部から見えるstate ownership / error / cancellation / retryの保証責務・連携の実質変更が必要
- 局所test設計だけでは戻さず、承認済み構造・保証責務の実質変更が必要な場合だけ戻す
- Allowed edit surface外へのresponsibility移動が必要
- Planとactual codeが矛盾する

## Known assumptions / unresolved observations

-

## Design Pair Decision compliance

| Design Pair Decision ID | Status | Implementation evidence | Validation evidence | Conflict |
| --- | --- | --- | --- | --- |
| DP-D01 | Compliant / Conflict / Pending | | | None / evidence |

## Review boundary

- Final code review performed: No
- Independent verification performed: No
