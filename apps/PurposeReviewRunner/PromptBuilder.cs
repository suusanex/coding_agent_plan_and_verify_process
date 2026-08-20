using System.Text;

namespace PurposeReviewRunner;

public static class PromptBuilder
{
    public static string BuildStart(string repository, IReadOnlyList<(string Path, string Content)> contexts)
    {
        var builder = new StringBuilder();
        AppendRole(builder);
        builder.AppendLine("This is review round 1. Inspect the current implementation in the read-only repository workspace below.");
        builder.AppendLine($"Repository: {repository}");
        builder.AppendLine("Use every supplied purpose context as the authority for intended outcomes, rejected alternatives, and superficially valid but purpose-defeating behavior.");
        builder.AppendLine("Do not modify files. Do not ask another agent to perform the review.");
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
        builder.AppendLine($"This is review round {round} in the same reviewer session.");
        builder.AppendLine("Re-inspect the current repository implementation after the parent remediation.");
        builder.AppendLine("Use the purpose, rejected alternatives, and prior findings retained in this session. The initial context and previous output are intentionally not repeated.");
        builder.AppendLine("Report all currently actionable purpose findings, or COMPLETE when none remain. Do not modify files.");
        AppendOutputContract(builder);
        return builder.ToString();
    }

    private static void AppendRole(StringBuilder builder)
    {
        builder.AppendLine("You are an independent purpose reviewer. Evaluate whether the implementation achieves the intended product purpose, not merely whether code is well formed.");
        builder.AppendLine("Keep purpose judgment independent from the implementation parent. Use repository access only for read-only inspection.");
    }

    private static void AppendOutputContract(StringBuilder builder)
    {
        builder.AppendLine();
        builder.AppendLine("Return exactly one block in this form, with valid JSON and no other block:");
        builder.AppendLine("BEGIN_PURPOSE_REVIEW");
        builder.AppendLine("{\"status\":\"FINDINGS|COMPLETE|HUMAN_DECISION_REQUIRED|BLOCKED\",\"findings\":[{\"id\":\"PUR-001\",\"severity\":\"CRITICAL|HIGH|MEDIUM|LOW\",\"title\":\"...\",\"summary\":\"...\",\"evidence\":\"...\",\"requiredChange\":\"...\"}],\"message\":null}");
        builder.AppendLine("END_PURPOSE_REVIEW");
        builder.AppendLine("FINDINGS requires at least one finding. COMPLETE requires no findings. HUMAN_DECISION_REQUIRED or BLOCKED requires a non-empty message.");
    }
}
