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
        builder.AppendLine("提供されたpurpose contextはすべて、intended outcomes、rejected alternatives、および表面的には妥当に見えるがpurposeを損なうbehaviorを判断するauthorityとして使ってください。");
        builder.AppendLine("ファイルを変更しないでください。reviewを別agentへ委任しないでください。");
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
        builder.AppendLine("現在actionableなpurpose findingをすべて報告してください。findingが残っていなければCOMPLETEとしてください。ファイルを変更しないでください。");
        AppendOutputContract(builder);
        return builder.ToString();
    }

    private static void AppendRole(StringBuilder builder)
    {
        builder.AppendLine("あなたは独立したpurpose reviewerです。単なるコード品質ではなく、実装が意図されたproduct purposeを達成しているかを評価してください。");
        builder.AppendLine("purpose判断はimplementation parentから独立して行ってください。repositoryへのアクセスは、変更を伴わない調査にのみ使ってください。");
    }

    private static void AppendOutputContract(StringBuilder builder)
    {
        builder.AppendLine();
        builder.AppendLine("以下の形式のblockを正確に1つだけ返してください。JSONはvalidでなければならず、このblock以外の出力を含めないでください。");
        builder.AppendLine("BEGIN_PURPOSE_REVIEW");
        builder.AppendLine("{\"status\":\"FINDINGS|COMPLETE|HUMAN_DECISION_REQUIRED|BLOCKED\",\"findings\":[{\"id\":\"PUR-001\",\"severity\":\"CRITICAL|HIGH|MEDIUM|LOW\",\"title\":\"...\",\"summary\":\"...\",\"evidence\":\"...\",\"requiredChange\":\"...\"}],\"message\":null}");
        builder.AppendLine("END_PURPOSE_REVIEW");
        builder.AppendLine("FINDINGSの場合はfindingを1件以上含めてください。COMPLETEの場合はfindingを含めないでください。HUMAN_DECISION_REQUIREDまたはBLOCKEDの場合は、空でないmessageが必要です。");
    }
}
