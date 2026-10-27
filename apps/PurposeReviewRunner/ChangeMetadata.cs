namespace PurposeReviewRunner;

public interface IChangeMetadataCollector
{
    Task<string> CollectAsync(string repository, CancellationToken cancellationToken);
}

/// <summary>Git の変更情報を同じプロセス実行境界で収集する。</summary>
public sealed class GitChangeMetadataCollector(IProcessRunner processRunner, IExecutableResolver executableResolver) : IChangeMetadataCollector
{
    public async Task<string> CollectAsync(string repository, CancellationToken cancellationToken)
    {
        try
        {
            var git = executableResolver.Resolve("git");
            var head = await Run(git, repository, ["rev-parse", "HEAD"], cancellationToken);
            var status = await Run(git, repository, ["status", "--short", "--branch", "-uall"], cancellationToken);
            var names = await Run(git, repository, ["--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--name-status", "HEAD"], cancellationToken);
            var stat = await Run(git, repository, ["--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--stat", "HEAD"], cancellationToken);
            return $"Git metadata (base: unknown; no base was inferred)\nHEAD: {head}\nStatus:\n{status}\nName-status:\n{names}\nStat:\n{stat}";
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            System.Diagnostics.Trace.TraceError(exception.ToString());
            return $"Git metadata unavailable. Base: unknown. Reason: {exception.Message}";
        }
    }

    private async Task<string> Run(string git, string repository, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await processRunner.RunAsync(new(git, arguments, repository, null), cancellationToken);
        if (result.TimedOut || result.ExitCode != 0)
            throw new RunnerException("GIT_METADATA_UNAVAILABLE", $"Git command failed: {string.Join(' ', arguments)}");
        return result.StandardOutput.TrimEnd();
    }
}

public static class InvestigatorReportValidator
{
    private const string BeginMarker = "BEGIN_PURPOSE_INVESTIGATION";
    private const string EndMarker = "END_PURPOSE_INVESTIGATION";

    public static InvestigatorReport ParseAndValidate(string json)
    {
        json = ExtractJson(json);
        try
        {
            using var document = System.Text.Json.JsonDocument.Parse(json, new System.Text.Json.JsonDocumentOptions { CommentHandling = System.Text.Json.JsonCommentHandling.Disallow });
            var root = document.RootElement;
            RejectDuplicateProperties(root);
            RequireProperties(root, "schemaVersion", "evidence", "checked_scope", "unchecked_scope", "uncertainties", "candidate_findings");
            foreach (var evidence in root.GetProperty("evidence").EnumerateArray())
            {
                RejectDuplicateProperties(evidence);
                RequireProperties(evidence, "id", "path", "description");
            }
            foreach (var finding in root.GetProperty("candidate_findings").EnumerateArray())
            {
                RejectDuplicateProperties(finding);
                RequireProperties(finding, "id", "title", "summary", "evidence_ids");
            }
        }
        catch (Exception exception) when (exception is System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException)
        {
            throw new RunnerException("INVESTIGATOR_INVALID", "Investigator report is missing required fields or has invalid JSON shape.", ExitCodes.ContractError, exception);
        }
        InvestigatorReport report;
        try
        {
            report = System.Text.Json.JsonSerializer.Deserialize<InvestigatorReport>(json, JsonDefaults.Options)
                ?? throw new System.Text.Json.JsonException("Report was null.");
        }
        catch (Exception exception) when (exception is System.Text.Json.JsonException or ArgumentException)
        {
            throw new RunnerException("INVESTIGATOR_INVALID", "Investigator returned invalid JSON.", ExitCodes.ContractError, exception);
        }
        static void Need(bool value, string message)
        {
            if (!value) throw new RunnerException("INVESTIGATOR_INVALID", message, ExitCodes.ContractError);
        }
        if (report.SchemaVersion != 1 || report.Evidence is null || report.CheckedScope is null || report.UncheckedScope is null || report.Uncertainties is null || report.CandidateFindings is null)
            throw new RunnerException("INVESTIGATOR_INVALID", "Investigator report fields are invalid.", ExitCodes.ContractError);
        var evidenceRows = report.Evidence;
        var checkedScope = report.CheckedScope;
        var uncheckedScope = report.UncheckedScope;
        var uncertainties = report.Uncertainties;
        var candidateFindings = report.CandidateFindings;
        Need(checkedScope.Count > 0 && checkedScope.All(static item => !string.IsNullOrWhiteSpace(item)), "checked_scope must contain at least one non-empty item.");
        Need(uncheckedScope.All(static item => !string.IsNullOrWhiteSpace(item)) && uncertainties.All(static item => !string.IsNullOrWhiteSpace(item)), "Scope and uncertainty entries must be non-empty strings.");
        var evidenceIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var evidence in evidenceRows)
        {
            if (evidence is null) throw new RunnerException("INVESTIGATOR_INVALID", "Evidence entries must not be null.", ExitCodes.ContractError);
            Need(!string.IsNullOrWhiteSpace(evidence.Id) && evidenceIds.Add(evidence.Id), "Evidence ids must be unique and non-empty.");
            Need(!string.IsNullOrWhiteSpace(evidence.Path) && !string.IsNullOrWhiteSpace(evidence.Description), "Evidence path and description are required.");
            Need((evidence.StartLine is null && evidence.EndLine is null) || (evidence.StartLine is > 0 && (evidence.EndLine is null or > 0) && (evidence.EndLine is null || evidence.EndLine >= evidence.StartLine)), "Evidence line range is invalid.");
            Need(evidence.StartLine is > 0 || !string.IsNullOrWhiteSpace(evidence.Symbol), "Evidence must identify a line range or symbol.");
        }
        var findingIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var finding in candidateFindings)
        {
            if (finding is null) throw new RunnerException("INVESTIGATOR_INVALID", "Candidate findings must not be null.", ExitCodes.ContractError);
            var evidenceReferences = finding.EvidenceIds;
            if (evidenceReferences is null) throw new RunnerException("INVESTIGATOR_INVALID", "Candidate finding evidence_ids is required.", ExitCodes.ContractError);
            Need(!string.IsNullOrWhiteSpace(finding.Id) && findingIds.Add(finding.Id) && !string.IsNullOrWhiteSpace(finding.Title) && !string.IsNullOrWhiteSpace(finding.Summary), "Candidate finding fields are invalid.");
            Need(evidenceReferences.Count > 0 && evidenceReferences.All(evidenceIds.Contains), "Candidate finding references unknown evidence.");
        }
        return report;
    }

    private static string ExtractJson(string output)
    {
        if (string.IsNullOrWhiteSpace(output))
            throw new RunnerException("INVESTIGATOR_INVALID", "Investigator returned an empty response.", ExitCodes.ContractError);
        if (output.AsSpan().TrimStart().StartsWith("{", StringComparison.Ordinal)) return output;

        var lines = output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries);
        var beginLines = Enumerable.Range(0, lines.Length).Where(index => lines[index].EndsWith(BeginMarker, StringComparison.Ordinal)).ToArray();
        var endLines = Enumerable.Range(0, lines.Length).Where(index => lines[index] == EndMarker).ToArray();
        if (beginLines.Length == 0 && endLines.Length == 0)
            return output;
        if (beginLines.Length != 1 || endLines.Length != 1 || beginLines[0] >= endLines[0])
        {
            throw new RunnerException("INVESTIGATOR_INVALID", "Investigator must return exactly one complete, ordered investigation block.", ExitCodes.ContractError);
        }
        return string.Join(Environment.NewLine, lines[(beginLines[0] + 1)..endLines[0]]).Trim();
    }

    private static void RequireProperties(System.Text.Json.JsonElement element, params string[] properties)
    {
        if (element.ValueKind != System.Text.Json.JsonValueKind.Object || properties.Any(property => !element.TryGetProperty(property, out _)))
            throw new System.Text.Json.JsonException("Required report property is missing.");
    }

    private static void RejectDuplicateProperties(System.Text.Json.JsonElement element)
    {
        if (element.ValueKind != System.Text.Json.JsonValueKind.Object) return;
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in element.EnumerateObject())
            if (!names.Add(property.Name)) throw new System.Text.Json.JsonException("Duplicate report property.");
    }
}
