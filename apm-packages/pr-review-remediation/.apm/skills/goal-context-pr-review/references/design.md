# Goal Context PR review design

## Package decision

Goal Context対応版は、別packageではなく`pr-review-remediation` package内の別Skillとして提供します。

理由は、基礎版とGoal Context対応版がPR identity確定、Copilot待機・収集、remote patch、`local-reviewer`、統合`review-planner`、Adaptive handoffを共有するためです。別packageにするとcollector、template、agent、validationの複製または複雑な相互依存が生じます。同じSkillへ暗黙modeを追加するとGoal Context欠落時の基礎版fallbackが見えにくくなるため、入口は次の二つへ明示分離します。

- `$pr-review-remediation`: Goal Contextを使わない基礎版
- `$goal-context-pr-review`: 選択・検証済みGoal Contextと`purpose-reviewer`を必須とする対応版

Goal Context対応版は基礎版Skillのrelative collector/templateを参照し、実装資産を複製しません。`purpose-reviewer`だけを追加し、既存`review-planner`をGoal Context awareに拡張します。

## Responsibility boundaries

- selector: 候補の一意選択、命名、frontmatter、lifecycle、必須章の構造検証
- `local-reviewer`: code、test、運用・保守性risk
- `purpose-reviewer`: Original problem、Desired outcome、user scenario、MVP/Non-goals、棄却案、否定条件
- `review-planner`: Copilot、local、purpose、comments、checksの採否・重複・競合・順序の統合
- Adaptive Implementation: Review Threadとは別の長寿命Implementation Thread内の明示ターンで行うproduction変更と検証
- completion notification decorator: terminal verdictを変えず、通知と直接リンクだけを追加

selectorはGoal Context Authoring Skillのcanonical validatorを再利用し、path、validation contract version、mode、正規化SHA-256をselection artifactへ残します。そのPASSは文書contractの証明ですが、Goal Contextの意味的忠実性やprivacy safetyを証明しません。`status: human-reviewed`を既定要件とし、draftを使う場合は利用者がexact pathと`--allow-draft`を明示し、そのoverrideをartifactへ残します。

## Multi-round state machine

multi-round modeは同じSkillの明示的な追加modeです。既存single-round modeのpath、verdict、handoffは変更しません。

schema version 2の`review-cycle.json`はrepository、PR、Goal Context path/hash、既定上限3、有効上限、override、人間判断、round一覧、finding ledgerに加え、Review／Implementation role taskを保持します。round 1に初回実装を行ったImplementation Threadと、それとは異なるReview Threadを固定し、同じroleの後続工程をそのtaskの新しい明示ターンとして開始します。role taskを再開できない場合はcycle内でbindingを変更せず、`BLOCKED`としてcycle外の手動対応へ戻します。各roundは`reviewMode`を持ち、round 1は`full`、round 2以降は`purpose-only`に固定します。schema version 1は履歴検証だけを許可します。各`round-NNN/`はbase/head OID、Review Thread ID、前round、前Adaptive result referenceとImplementation Thread ID、review artifact、finding delta、source coverage、round番号付きnotificationを保持し、過去roundを上書きしません。

`review-result.json`はplanner結果のmachine-readable projectionです。repository/PR/round/base/head、Goal Context path/hash、verdict、finding delta、source coverage、入力・plan artifact hash bindingを保持します。cycle managerはreview-context、Goal Context selection、local/purpose findingsをparseし、このprojectionとround-resultを相互照合します。`review-context.artifacts.remotePatch`が指すcollector正本pathは、manifestの`remote-patch` role pathと一致させます。したがってhashが整合していても、別PRのcontext、別Goal Context、別patch、未追跡source、異なるverdict/finding deltaは受理しません。

round 1ではCopilot、local、purposeを統合します。round 2以降はCopilotを開始・待機せず、local reviewも再実行しません。collectorは`--no-wait-for-copilot`でidentityと正本patchを更新し、過去headや想定外のconnector／人間reviewを含む全remote sourceを保持しますが、それらは理由付き`noAction`の監査証跡に限定します。目的上のactionable findingは現在roundの`PUR-*`だけです。purpose findingsの`Prior Finding Assessment`が全active tracking IDの`persistent | resolved`遷移を根拠付きで示します。

Adaptiveへ渡すplanでは、ordered remediationの`SI-*`／`AC-*`集合と`implementation_intent.scope`／`acceptance`の集合を双方向に完全一致させます。intentだけへ未追跡scopeやacceptanceを追加できません。cycleの時刻は、明示的な`Z`またはUTC offsetを持つISO-8601だけを受理します。

verdict遷移は次のとおりです。

- actionableなし -> `REVIEW_COMPLETE`
- actionableあり、round < effective maximum -> `READY_FOR_ADAPTIVE_IMPLEMENTATION`
- actionableあり、round >= effective maximum -> `HUMAN_DECISION_REQUIRED`。実行可能planとAdaptive handoffは生成しない
- 必須証拠不足または明示的blocked reason -> `BLOCKED`

`HUMAN_DECISION_REQUIRED`では`HD-NNN`形式のdecision IDを一件発行し、round manifestへ`review-plan` roleを含めません。人間が継続を明示した後、plannerは`APPROVED_FOR_ADAPTIVE_IMPLEMENTATION`と`round-NNN/approved-review-plan.md`を参照する候補を返します。cycle managerの`resolve`は候補のidentity、active finding mapping、SI/AC完全一致、handoffを検証し、canonical planへ非上書きコピーしたうえでdecisionのresolution、承認者、承認時刻、plan path/hashを記録します。この記録前はAdaptive result referenceがあっても次roundを開始できません。上限到達後の第4round以降では、同じ`resolve`にmaximum-round overrideも要求し、Adaptive実行前に記録します。

`READY_FOR_ADAPTIVE_IMPLEMENTATION`は固定Implementation Threadの新しい明示ターンへのAdaptive handoffだけを許可します。Adaptive完了後の再reviewは、利用者が同じReview Threadを再開して新しい明示ターンとして開始します。親Review Threadの文脈は維持しますが、read-only子agentは各round artifactを正本として独立実行します。Completion Notification Decoratorは各roundのterminal verdictとPR／現在taskへのリンクを通知するだけで、state transitionや次工程を起動しません。

findingはagentが割り当てた安定tracking IDで`new | persistent | resolved | reopened`を追跡します。`persistent`と`resolved`は直前までactiveだったfinding、`reopened`は過去に`resolved`となったfindingだけに許可し、文面の類似だけで同一性を推測しません。
