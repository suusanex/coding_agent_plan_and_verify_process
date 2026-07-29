#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

var options = Options.Parse(args);
if (options.ShowHelp)
{
    ShowUsage();
    return 0;
}

if (!options.Valid)
{
    ShowUsage();
    return 2;
}

try
{
    var path = Path.GetFullPath(options.GoalContextPath!);
    if (!File.Exists(path))
    {
        throw new FileNotFoundException("Goal Context does not exist.", path);
    }

    var content = Normalize(File.ReadAllText(path));
    var result = GoalContextContract.Validate(content, Path.GetFileName(path), options.Mode);
    var output = new ValidationOutput(
        ContractVersion: 1,
        Status: result.Errors.Count == 0 ? "PASS" : "FAIL",
        Mode: options.Mode,
        LifecycleStatus: result.LifecycleStatus,
        SensitiveReview: result.SensitiveReview,
        ContentSha256: Sha256(content),
        Errors: result.Errors);
    WriteOutput(output, options.Format);
    return result.Errors.Count == 0 ? 0 : 2;
}
catch (Exception ex)
{
    var output = new ValidationOutput(1, "ERROR", options.Mode, "", "", "", [ex.Message]);
    WriteOutput(output, options.Format);
    return 1;
}

static string Normalize(string value) => value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');

static string Sha256(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

static void WriteOutput(ValidationOutput output, string format)
{
    if (format == "json")
    {
        Console.WriteLine(JsonSerializer.Serialize(output, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true
        }));
        return;
    }

    Console.WriteLine($"Goal Context validation: {output.Status}");
    foreach (var error in output.Errors)
    {
        Console.Error.WriteLine($"- {error}");
    }
}

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file scripts/validate-goal-context.cs -- --goal-context <path> --mode strict|draft --format json|text

Exit codes:
  0  The Goal Context satisfies the selected contract mode.
  1  The validator could not read or process the input.
  2  The Goal Context violates the contract or the arguments are invalid.
""");
}

static class GoalContextContract
{
    private static readonly string[] RequiredHeadings =
    [
        "## Document control and source boundary",
        "## Original problem",
        "## Desired outcome",
        "## Concrete user situation and user scenarios",
        "## Scope and boundaries",
        "### MVP scope",
        "### Non-goals",
        "### Future work",
        "## Decisions and reasoning",
        "### Accepted decisions",
        "### Rejected alternatives",
        "## Constraints and invariants",
        "## Success scenarios",
        "## Acceptance evidence",
        "## Superficially compliant but wrong",
        "## Review questions",
        "## Open questions and assumptions",
        "## Conversation corrections and priority changes",
        "## Provenance and inference ledger",
        "## Human review record"
    ];

    private static readonly string[] ProvenanceListHeadings =
    [
        "## Document control and source boundary",
        "## Original problem",
        "## Desired outcome",
        "## Concrete user situation and user scenarios",
        "### MVP scope",
        "### Non-goals",
        "### Future work",
        "## Constraints and invariants",
        "## Success scenarios",
        "## Superficially compliant but wrong",
        "## Review questions",
        "## Open questions and assumptions"
    ];

    private static readonly TableContract[] ProvenanceTables =
    [
        new("### Accepted decisions", ["Provenance", "Decision", "Reason", "Consequence"], 0),
        new("### Rejected alternatives", ["Provenance", "Alternative", "Rejection reason", "Revisit condition"], 0),
        new("## Acceptance evidence", ["Provenance", "Outcome to demonstrate", "Required evidence", "Evidence type"], 0),
        new("## Conversation corrections and priority changes", ["Provenance", "Earlier statement", "Current statement or priority", "Evidence of supersession"], 0),
        new("## Provenance and inference ledger", ["Claim or section", "Classification", "Source evidence or reasoning", "Confidence / required follow-up"], 1)
    ];

    private static readonly string[] RequiredConfirmations =
    [
        "Desired outcome confirmed",
        "Rejected alternatives confirmed",
        "Superficially compliant but wrong outcomes confirmed",
        "MVP / Non-goals / Future work boundary confirmed",
        "Corrections and priority changes confirmed",
        "Provenance and unknowns confirmed",
        "Sensitive-data review confirmed"
    ];

    public static ContractResult Validate(string content, string fileName, string mode)
    {
        var errors = new List<string>();
        if (!Regex.IsMatch(fileName, "^goal-context-[a-z0-9]+(?:-[a-z0-9]+)*\\.md$", RegexOptions.CultureInvariant))
        {
            errors.Add($"Filename must use lowercase kebab-case goal-context-<topic-summary>.md: {fileName}");
        }
        if (Regex.IsMatch(fileName, "^goal-context-(?:issue|pr|pull-request|ticket|task|work-item)(?:-|$)|^goal-context-\\d", RegexOptions.CultureInvariant))
        {
            errors.Add($"Filename is centered on an Issue, PR, ticket, task, or number instead of durable content: {fileName}");
        }

        var frontmatterMatch = Regex.Match(content, "\\A---\\s*\\n(?<frontmatter>.*?)\\n---\\s*\\n", RegexOptions.Singleline | RegexOptions.CultureInvariant);
        var frontmatter = frontmatterMatch.Success ? frontmatterMatch.Groups["frontmatter"].Value : string.Empty;
        if (!frontmatterMatch.Success)
        {
            errors.Add("Missing YAML frontmatter at the beginning of the Goal Context");
        }

        var values = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["document_type"] = FrontmatterValue(frontmatter, "document_type"),
            ["status"] = FrontmatterValue(frontmatter, "status"),
            ["topic"] = FrontmatterValue(frontmatter, "topic"),
            ["created_at"] = FrontmatterValue(frontmatter, "created_at"),
            ["source_scope"] = FrontmatterValue(frontmatter, "source_scope"),
            ["sensitive_data_review"] = FrontmatterValue(frontmatter, "sensitive_data_review")
        };
        foreach (var pair in values.Where(pair => string.IsNullOrWhiteSpace(pair.Value)))
        {
            errors.Add($"Missing or empty frontmatter field: {pair.Key}");
        }

        var documentType = values["document_type"];
        var status = values["status"];
        var sensitiveReview = values["sensitive_data_review"];
        if (documentType.Length > 0 && documentType != "goal-context")
        {
            errors.Add($"document_type must be goal-context, found: {documentType}");
        }
        if (status.Length > 0 && status is not ("draft" or "human-reviewed"))
        {
            errors.Add($"status must be draft or human-reviewed, found: {status}");
        }
        if (sensitiveReview.Length > 0 && sensitiveReview is not ("pending" or "passed"))
        {
            errors.Add($"sensitive_data_review must be pending or passed, found: {sensitiveReview}");
        }
        if (status is "draft" or "human-reviewed" && sensitiveReview is "pending" or "passed")
        {
            var validPair = status == "draft" && sensitiveReview == "pending" || status == "human-reviewed" && sensitiveReview == "passed";
            if (!validPair)
            {
                errors.Add($"Only lifecycle pairs draft/pending and human-reviewed/passed are allowed; found: {status}/{sensitiveReview}");
            }
        }
        if (values["created_at"].Length > 0 && !Regex.IsMatch(values["created_at"], "^\\d{4}-\\d{2}-\\d{2}$", RegexOptions.CultureInvariant))
        {
            errors.Add($"created_at must use YYYY-MM-DD, found: {values["created_at"]}");
        }
        if (!Regex.IsMatch(content, "(?m)^# Goal Context:\\s+\\S.+$", RegexOptions.CultureInvariant))
        {
            errors.Add("Missing non-empty title: # Goal Context: <Topic>");
        }

        foreach (var heading in RequiredHeadings)
        {
            var body = SectionBody(content, heading);
            if (body is null)
            {
                errors.Add($"Missing required heading: {heading}");
            }
            else if (string.IsNullOrWhiteSpace(Regex.Replace(body, "(?s)<!--.*?-->", string.Empty)))
            {
                errors.Add($"Required section is empty: {heading}");
            }
        }

        foreach (var heading in ProvenanceListHeadings)
        {
            AddProvenanceListErrors(errors, content, heading);
        }
        foreach (var table in ProvenanceTables)
        {
            AddProvenanceTableErrors(errors, content, table);
        }

        foreach (var pattern in new[] { "<!--", "<durable topic summary>", "<available conversation range", "(?m)^created_at:\\s*YYYY-MM-DD\\s*$" })
        {
            if (Regex.IsMatch(content, pattern, RegexOptions.CultureInvariant))
            {
                errors.Add("Unresolved template placeholder detected");
            }
        }

        foreach (var pattern in new[]
        {
            "AKIA[0-9A-Z]{16}",
            "gh[pousr]_[A-Za-z0-9]{20,}",
            "sk-[A-Za-z0-9_-]{20,}",
            "-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
            "(?im)^\\s*(?:password|api[_-]?key|client[_-]?secret|accountkey)\\s*[:=]\\s*(?!<redacted:)[^#\\r\\n]+$"
        })
        {
            if (Regex.IsMatch(content, pattern, RegexOptions.CultureInvariant))
            {
                errors.Add("Potential exposed secret or credential matched a high-confidence pattern");
            }
        }

        var humanReviewBody = SectionBody(content, "## Human review record") ?? string.Empty;
        if (status == "human-reviewed")
        {
            if (sensitiveReview != "passed") errors.Add("status human-reviewed requires sensitive_data_review: passed");
            if (!Regex.IsMatch(humanReviewBody, "(?im)^- Review status:\\s*Complete\\s*$")) errors.Add("status human-reviewed requires Review status: Complete");
            if (!Regex.IsMatch(humanReviewBody, "(?im)^- Reviewer:\\s*(?!Pending\\s*$)\\S.+$")) errors.Add("status human-reviewed requires a non-pending Reviewer");
            if (!Regex.IsMatch(humanReviewBody, "(?im)^- Reviewed at:\\s*\\d{4}-\\d{2}-\\d{2}\\s*$")) errors.Add("status human-reviewed requires Reviewed at in YYYY-MM-DD format");
            if (Regex.IsMatch(humanReviewBody, "(?im):\\s*Pending\\s*$")) errors.Add("status human-reviewed cannot retain Pending fields in Human review record");
            foreach (var confirmation in RequiredConfirmations)
            {
                if (!Regex.IsMatch(humanReviewBody, $"(?im)^- {Regex.Escape(confirmation)}:\\s*Yes\\s*$"))
                {
                    errors.Add($"status human-reviewed requires '{confirmation}: Yes'");
                }
            }
        }

        if (mode == "strict")
        {
            if (status != "human-reviewed") errors.Add("Strict validation requires status: human-reviewed");
            if (sensitiveReview != "passed") errors.Add("Strict validation requires sensitive_data_review: passed");
        }

        return new ContractResult(status, sensitiveReview, errors.Distinct(StringComparer.Ordinal).ToList());
    }

    private static string FrontmatterValue(string frontmatter, string key)
    {
        var match = Regex.Match(frontmatter, $"(?m)^{Regex.Escape(key)}:\\s*(?<value>.+?)\\s*$", RegexOptions.CultureInvariant);
        return match.Success ? match.Groups["value"].Value.Trim().Trim('"', '\'') : string.Empty;
    }

    private static string? SectionBody(string content, string heading)
    {
        var marker = heading.Split(' ', 2)[0];
        var match = Regex.Match(content, $"(?ms)^{Regex.Escape(heading)}\\s*\\n(?<body>.*?)(?=^#{{1,{marker.Length}}}\\s|\\z)", RegexOptions.CultureInvariant);
        return match.Success ? match.Groups["body"].Value : null;
    }

    private static void AddProvenanceListErrors(List<string> errors, string content, string heading)
    {
        var body = SectionBody(content, heading);
        if (body is null) return;
        var entries = Regex.Matches(body, "(?m)^\\s*(?:-\\s+|\\d+\\.\\s+)(?<entry>.*?)\\s*$", RegexOptions.CultureInvariant)
            .Select(match => match.Groups["entry"].Value)
            .ToList();
        if (entries.Count == 0)
        {
            errors.Add($"Section must contain at least one list entry: {heading}");
            return;
        }

        foreach (var entry in entries)
        {
            var match = Regex.Match(entry, "^\\[(?:Explicit|Inferred|Unknown)\\](?<remainder>.*)$", RegexOptions.CultureInvariant);
            if (!match.Success)
            {
                errors.Add($"List entry must start with exactly one [Explicit], [Inferred], or [Unknown] tag: {heading}");
                continue;
            }
            var remainder = match.Groups["remainder"].Value;
            var text = remainder.Trim();
            if (!Substantive(text)) errors.Add($"List entry must contain substantive text after its provenance tag: {heading}");
            else if (!Regex.IsMatch(remainder, "^\\s+", RegexOptions.CultureInvariant)) errors.Add($"List entry must separate its provenance tag from substantive text: {heading}");
            else if (Regex.IsMatch(text, "^\\[[^\\]]+\\]", RegexOptions.CultureInvariant)) errors.Add($"List entry must contain exactly one provenance tag: {heading}");
        }
    }

    private static void AddProvenanceTableErrors(List<string> errors, string content, TableContract contract)
    {
        var body = SectionBody(content, contract.Heading);
        if (body is null) return;
        var lines = body.Split('\n').Where(line => Regex.IsMatch(line, "^\\s*\\|.*\\|\\s*$", RegexOptions.CultureInvariant)).ToList();
        if (lines.Count < 2)
        {
            errors.Add($"Section must contain a Markdown table with a header and separator: {contract.Heading}");
            return;
        }

        var headers = Cells(lines[0]);
        var separators = Cells(lines[1]);
        if (!headers.SequenceEqual(contract.Headers, StringComparer.Ordinal)) errors.Add($"Table header must be exactly '{string.Join(" | ", contract.Headers)}': {contract.Heading}");
        if (separators.Count != contract.Headers.Length || separators.Any(cell => !Regex.IsMatch(cell, "^:?-{3,}:?$", RegexOptions.CultureInvariant)))
        {
            errors.Add($"Table separator must contain {contract.Headers.Length} valid Markdown separator cells: {contract.Heading}");
        }
        if (lines.Count < 3)
        {
            errors.Add($"Table must contain at least one data row: {contract.Heading}");
            return;
        }
        foreach (var line in lines.Skip(2))
        {
            var cells = Cells(line);
            if (cells.Count != contract.Headers.Length)
            {
                errors.Add($"Table data row must contain {contract.Headers.Length} columns: {contract.Heading}");
                continue;
            }
            if (!Regex.IsMatch(cells[contract.ProvenanceColumn], "^\\[(?:Explicit|Inferred|Unknown)\\]$", RegexOptions.CultureInvariant))
            {
                errors.Add($"Table provenance cell must be exactly [Explicit], [Inferred], or [Unknown]: {contract.Heading}");
            }
            for (var index = 0; index < cells.Count; index++)
            {
                if (index != contract.ProvenanceColumn && !Substantive(cells[index])) errors.Add($"Table data cell must contain substantive text in column {index + 1}: {contract.Heading}");
            }
        }
    }

    private static List<string> Cells(string line)
    {
        var trimmed = line.Trim();
        if (!trimmed.StartsWith('|') || !trimmed.EndsWith('|')) return [];
        return Regex.Split(trimmed[1..^1], "(?<!\\\\)\\|", RegexOptions.CultureInvariant).Select(cell => cell.Trim()).ToList();
    }

    private static bool Substantive(string value) => !string.IsNullOrWhiteSpace(value) && Regex.IsMatch(value, "[\\p{L}\\p{N}]", RegexOptions.CultureInvariant);
}

sealed record TableContract(string Heading, string[] Headers, int ProvenanceColumn);
sealed record ContractResult(string LifecycleStatus, string SensitiveReview, List<string> Errors);
sealed record ValidationOutput(int ContractVersion, string Status, string Mode, string LifecycleStatus, string SensitiveReview, string ContentSha256, IReadOnlyList<string> Errors);

sealed record Options(string? GoalContextPath, string Mode, string Format, bool ShowHelp, bool Valid)
{
    public static Options Parse(string[] args)
    {
        string? goalContext = null;
        var mode = "strict";
        var format = "text";
        var help = false;
        var valid = true;
        for (var index = 0; index < args.Length; index++)
        {
            string? Next()
            {
                if (++index >= args.Length) { valid = false; return null; }
                return args[index];
            }
            switch (args[index])
            {
                case "--goal-context": goalContext = Next(); break;
                case "--mode": mode = Next() ?? mode; break;
                case "--format": format = Next() ?? format; break;
                case "--help":
                case "-h": help = true; break;
                default: valid = false; break;
            }
        }
        if (!help && string.IsNullOrWhiteSpace(goalContext)) valid = false;
        if (mode is not ("strict" or "draft")) valid = false;
        if (format is not ("json" or "text")) valid = false;
        return new Options(goalContext, mode, format, help, valid);
    }
}
