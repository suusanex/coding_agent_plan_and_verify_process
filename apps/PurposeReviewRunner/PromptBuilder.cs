using System.Text;

namespace PurposeReviewRunner;

public static class PromptBuilder
{
    public static string BuildStart(string repository, IReadOnlyList<(string Path, string Content)> contexts)
    {
        var builder = new StringBuilder();
        AppendRole(builder);
        builder.AppendLine("これはreview round 1です。下記のrepository workspaceにある現在の実装を調査してください。");
        builder.AppendLine($"Repository: {repository}");
        builder.AppendLine("提供されたpurpose contextを、元の問題・期待成果、承認されたscope・採用判断、実装方針に区別して理解してください。ユーザーが明示したsourceと目的・scopeの変更判断を優先し、新しいplanやhandoffであることだけを理由に当初目的、優先順位、棄却理由を上書きしないでください。");
        builder.AppendLine("補完文書は合わせて使い、実装方針への適合だけで目的達成と判定しないでください。目的判断に必要な情報の不足やsource間の未解決の競合は推測で埋めず、messageへ記載してください。");
        builder.AppendLine("比較基準は明示されたbaseを優先し、なければtaskとGit履歴から根拠を持って特定してください。mainやHEADを無条件にbaseとせず、確認したbaseのcommit IDと現在のHEAD、未コミット変更の有無をsession内に保持してください。Gitがない場合やbaseが特定できない場合も、現在の実装を調査し、差分比較の限界を明示してください。");
        AppendReviewCriteria(builder);
        builder.AppendLine();
        builder.AppendLine("PURPOSE CONTEXTS");
        foreach (var context in contexts)
        {
            builder.AppendLine($"--- BEGIN CONTEXT: {context.Path} ---");
            builder.AppendLine(context.Content);
            builder.AppendLine($"--- END CONTEXT: {context.Path} ---");
        }
        AppendOutputContract(builder);
        return builder.ToString();
    }

    public static string BuildContinue(int round)
    {
        var builder = new StringBuilder();
        AppendRole(builder);
        builder.AppendLine($"これは同一reviewer session内のreview round {round}です。");
        builder.AppendLine("parentによるremediation後の、現在のrepository実装を再確認してください。");
        builder.AppendLine("purpose、rejected alternatives、およびprior findingsは、このsessionに保持されたものを利用してください。初回のpurpose contextと前回のreviewer outputは、意図的に再送していません。");
        builder.AppendLine("初回baseからの累積差分と前回roundで確認した状態からの変更を調査し、今回確認したHEADと未コミット変更の有無をsession内に保持してください。以前の未コミット内容が失われた場合、HEAD間のdiffで前回との差分を完全に復元できたと扱わず、比較できた範囲と限界をmessageへ記載してください。比較のためにcommit、stash、checkoutや独自snapshotを作成しないでください。");
        builder.AppendLine("前回findingの解消だけでなく、その解釈によって別の仕組みを作り込み始めていないか、新しい抜け道や棄却案を導入していないかを確認してください。前回findingも再評価の対象です。元の目的と明示的な採用判断を自分の過去の提案より優先し、誤り・過剰要求・曖昧な指摘は訂正または撤回してください。");
        builder.AppendLine("同じ問題のfinding IDは維持し、解消・訂正・撤回したIDと理由をmessageに記載してください。撤回を実装修正による解消と混同せず、現在actionableなpurpose findingだけをfindingsへ返してください。");
        builder.AppendLine("parentの修正理由やfindingへの疑義が既存の作業記録にある場合は、その根拠も調査してください。parentの解釈を目的のauthorityへ昇格させず、コードとpurpose sourceから独立に判断してください。");
        AppendReviewCriteria(builder);
        AppendOutputContract(builder);
        return builder.ToString();
    }

    private static void AppendRole(StringBuilder builder)
    {
        builder.AppendLine("あなたは独立したpurpose reviewerです。単なるコード品質ではなく、実装が意図されたproduct purposeを達成しているかを評価してください。");
        builder.AppendLine("purpose判断はimplementation parentから独立して行ってください。repositoryへのアクセスは、変更を伴わない調査にのみ使ってください。");
        builder.AppendLine("shellによる調査を利用できます。git diff、git log、git show、git statusなどで変更と経緯を確認してください。ファイルを変更しないでください。shell経由でもsource、tests、docs、Git状態、設定、外部サービスを変更せず、reviewを別agentへ委任しないでください。変更を伴う修正・validationはparentの責務です。");
    }

    private static void AppendReviewCriteria(StringBuilder builder)
    {
        builder.AppendLine("毎round、差分と関連する現在の実装全体を次の観点で評価してください。未コミット変更はstaged、unstaged、関連するuntracked fileも含めて調査し、現在のworkspaceへの判定とPRへ含まれる変更への判定を区別してください。");
        builder.AppendLine("- 元の問題が利用者の実際の利用経路で解消され、intended outcomesが達成されるか。文言、schema、テスト、補助機構だけが整い、productionの接続や必要な成果が欠けるなど、表面的には妥当に見えるがpurposeを損なうbehaviorがないか。");
        builder.AppendLine("- 優先順位、non-goals、MVPと将来課題の境界、rejected alternativesと棄却理由を守っているか。主要成果が未達のまま周辺機構を厚くしていないか、目的にない要求や責務を追加していないか。");
        builder.AppendLine("- 各findingを目的の根拠と具体的な実装・差分の証拠へ結び付けられるか。変更量の多さ、抽象化の有無、設計の好みだけをfindingにせず、目的・制約への具体的な悪影響を示してください。目的達成に必要な補助機構や承認済みの手動工程・対象外事項を、過剰実装や未達成と誤認しないでください。");
    }

    private static void AppendOutputContract(StringBuilder builder)
    {
        builder.AppendLine();
        builder.AppendLine("以下の形式のblockを正確に1つだけ返してください。JSONはvalidでなければならず、このblock以外の出力を含めないでください。");
        builder.AppendLine("BEGIN_PURPOSE_REVIEW");
        builder.AppendLine("{\"status\":\"FINDINGS|COMPLETE|HUMAN_DECISION_REQUIRED|BLOCKED\",\"findings\":[{\"id\":\"PUR-001\",\"severity\":\"CRITICAL|HIGH|MEDIUM|LOW\",\"title\":\"...\",\"summary\":\"...\",\"evidence\":\"...\",\"requiredOutcome\":\"...\"}],\"message\":\"...\"}");
        builder.AppendLine("END_PURPOSE_REVIEW");
        builder.AppendLine("FINDINGSの場合はfindingを1件以上含めてください。COMPLETEの場合はfindingを含めないでください。HUMAN_DECISION_REQUIREDまたはBLOCKEDの場合は、空でないmessageが必要です。");
        builder.AppendLine("summaryには目的への影響、evidenceにはpurpose sourceの該当箇所と実装のpath・位置または観測結果を記載してください。requiredOutcomeには目的達成のために成立すべき状態・振る舞い・制約を記載してください。修正する関数、patch、promptの書換え、チェックの追加などの実装方式まで決める必要はありません。具体的な修正設計と実装はimplementation parentの責任です。");
        builder.AppendLine("複数componentにまたがる責務やauthorityの逆転もpurpose findingです。単一の局所的なバグへ分解できないことや、具体的な修正方法が未確定であることを理由にfindingを省略しないでください。actionableとは、目的との不一致と満たすべき成果が根拠付きで特定され、parentが修正方針を判断できることです。既に承認された実装上の制約はsourceの根拠とともに保持し、reviewer自身の方式提案を必須成果へ混入させないでください。");
        builder.AppendLine("messageには確認した比較基準と対象、目的達成の判断根拠、未検証事項・比較の限界を簡潔に記載してください。COMPLETEはactionableなfindingがなく、今回のscopeの主要成果と否定条件を評価する十分な証拠がある場合だけ選んでください。テスト成功や指摘の不在だけを達成の証拠にしないでください。");
        builder.AppendLine("必要な証拠を取得できず判断不能な場合はBLOCKED、目的やscopeの競合・選択にユーザー判断が必要な場合はHUMAN_DECISION_REQUIREDとし、理由をmessageへ記載してください。コードから確定できる未実装や目的違反はFINDINGSであり、証拠不足と混同しないでください。既に承認された対象外事項や、判定を左右しない未検証事項まで新しいblockerにしないでください。");
    }
}
