# Process Feedback

Process Feedbackを利用者が明示選択し、upstream-suspected又はunknownの対象がある場合だけ作成します。親が既存証拠を分析するための記録であり、新しいレビュー工程や変更許可ではありません。

- PR / reviewed base・head OID:
- Selection evidence: 利用者指示の原文と出典
- Review plan: review-plan.md
- 対象source ID（duplicateを含む）:

## Findingごとの分析

以下を対象findingごとに記録します。代表findingで統合した場合も全source IDを対応付けます。

- Finding / source IDs:
- Triage / 根拠 / 候補layer:
- 分析結果: Analyzed / Insufficient evidence

### 証拠の逆追跡

| 順序 / 関係 | Artifact path / revision | 該当箇所・本文 | 確認事実 / 欠落・誤変換 / 不明 |
| --- | --- | --- | --- |
| finding → 実装記録 → contract / Plan → Goal Context・設計・関連SKILL（存在する範囲） |  |  |  |

- 探索範囲と不足artifact・情報（revision不明も明記）:
- 確認できた原因発生地点 / 原因仮説 / 代替説明:
- 証拠から言えないこと・次に必要な確認:

### 修正と改善候補

| 区分 | 提案 / 不要・不明の理由 | 対象artifact・layer / 根拠 | 今回のApply・acceptance・validation参照 / follow-up候補 | Authority / 必要な判断 / 実施状況 |
| --- | --- | --- | --- | --- |
| immediate correction |  |  |  |  |
| upstream correction |  |  |  |  |
| reusable process improvement candidate |  |  |  |  |

- 共通改善を一般化できる根拠 / 未立証の理由:
- 期待効果・追加負担・より小さい対処:

単発findingだけで共通プロセス欠陥を断定せず、候補提示を変更許可と扱いません。証拠不足や候補未実施だけでPR修正を止めません。今回のacceptanceが未決定ならreview-planの人間判断へ戻します。他Skillを自動起動せず、同一source・証拠の分析は再利用し、根拠の変更箇所だけを更新します。
