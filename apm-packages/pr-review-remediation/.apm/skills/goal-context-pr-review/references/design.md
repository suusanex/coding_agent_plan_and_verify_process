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
