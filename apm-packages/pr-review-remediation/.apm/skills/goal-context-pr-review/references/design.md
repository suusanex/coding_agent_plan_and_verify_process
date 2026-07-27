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
- Adaptive Implementation: 別親ターンでのproduction変更と検証
- completion notification decorator: terminal verdictを変えず、通知と直接リンクだけを追加

selectorはGoal Context Authoring Skillのcanonical validatorを再利用し、path、validation contract version、mode、正規化SHA-256をselection artifactへ残します。そのPASSは文書contractの証明ですが、Goal Contextの意味的忠実性やprivacy safetyを証明しません。`status: human-reviewed`を既定要件とし、draftを使う場合は利用者がexact pathと`--allow-draft`を明示し、そのoverrideをartifactへ残します。

## Multi-round state machine

multi-round modeは同じSkillの明示的な追加modeです。既存single-round modeのpath、verdict、handoffは変更しません。

`review-cycle.json`はrepository、PR、Goal Context path/hash、既定上限3、有効上限、override、人間判断、round一覧、finding ledgerを保持します。各`round-NNN/`はbase/head OID、前round、前Adaptive result reference、review artifact、finding delta、source coverage、round番号付きnotificationを保持し、過去roundを上書きしません。全source IDはfinding tracking IDまたは理由付き`noAction`へ対応させます。

`review-result.json`はplanner結果のmachine-readable projectionです。repository/PR/round/base/head、Goal Context path/hash、verdict、finding delta、source coverage、入力・plan artifact hash bindingを保持します。cycle managerはreview-context、Goal Context selection、local/purpose findingsをparseし、このprojectionとround-resultを相互照合します。したがってhashが整合していても、別PRのcontext、別Goal Context、未追跡source、異なるverdict/finding deltaは受理しません。

verdict遷移は次のとおりです。

- actionableなし -> `REVIEW_COMPLETE`
- actionableあり、round < effective maximum -> `READY_FOR_ADAPTIVE_IMPLEMENTATION`
- actionableあり、round >= effective maximum -> `HUMAN_DECISION_REQUIRED`
- 必須証拠不足または明示的blocked reason -> `BLOCKED`

`HUMAN_DECISION_REQUIRED`では`HD-NNN`形式のdecision IDを一件発行します。次roundの開始には、そのID、resolution、承認者、承認時刻の一致が必要です。上限到達後の第4round以降では、このdecision resolutionに加えてmaximum-round overrideを要求します。

`READY_FOR_ADAPTIVE_IMPLEMENTATION`は別親ターンのAdaptive handoffだけを許可します。Adaptive完了後の再reviewも、利用者がさらに別の親ターンで明示開始します。Completion Notification Decoratorは各roundのterminal verdictとPR直接リンクを通知するだけで、state transitionや次工程を起動しません。

findingはagentが割り当てた安定tracking IDで`new | persistent | resolved | reopened`を追跡します。`persistent`と`resolved`は直前までactiveだったfinding、`reopened`は過去に`resolved`となったfindingだけに許可し、文面の類似だけで同一性を推測しません。
