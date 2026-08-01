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
    var errors = ValidateReadableFreeForm(content);
    var output = new ValidationOutput(
        ContractVersion: 2,
        Status: errors.Count == 0 ? "PASS" : "FAIL",
        Mode: options.Mode,
        ValidationContract: "readable-free-form",
        ContentSha256: Sha256(content),
        Errors: errors);
    WriteOutput(output, options.Format);
    return errors.Count == 0 ? 0 : 2;
}
catch (Exception ex)
{
    var output = new ValidationOutput(2, "ERROR", options.Mode, "readable-free-form", "", [ex.Message]);
    WriteOutput(output, options.Format);
    return 1;
}

static List<string> ValidateReadableFreeForm(string content)
{
    var errors = new List<string>();
    if (string.IsNullOrWhiteSpace(content))
    {
        errors.Add("Goal Context must contain readable non-whitespace text");
    }
    if (content.IndexOf('\0') >= 0)
    {
        errors.Add("Goal Context contains NUL characters and is not readable text");
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
            break;
        }
    }
    return errors;
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

    Console.WriteLine($"Goal Context validation: {output.Status} ({output.ValidationContract})");
    foreach (var error in output.Errors)
    {
        Console.Error.WriteLine($"- {error}");
    }
}

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file .agents/skills/goal-context-authoring/scripts/validate-goal-context.cs -- --goal-context <path> [--mode basic|draft|strict] --format json|text

The validator accepts Goal Context as free-form natural-language text. It does not require a filename pattern, frontmatter, headings, provenance tags, lifecycle state, approval record, or a particular creation source.
The draft and strict mode names remain accepted as compatibility aliases; they perform the same readable-text and high-confidence credential checks as basic mode.

Exit codes:
  0  The file is readable, non-empty text and no high-confidence credential pattern was found.
  1  The validator could not read or process the input.
  2  The input is empty, binary-like, credential-bearing, or the arguments are invalid.
""");
}

sealed record ValidationOutput(
    int ContractVersion,
    string Status,
    string Mode,
    string ValidationContract,
    string ContentSha256,
    IReadOnlyList<string> Errors);

sealed record Options(string? GoalContextPath, string Mode, string Format, bool ShowHelp, bool Valid)
{
    public static Options Parse(string[] args)
    {
        string? goalContext = null;
        var mode = "basic";
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
        if (mode is not ("basic" or "strict" or "draft")) valid = false;
        if (format is not ("json" or "text")) valid = false;
        return new Options(goalContext, mode, format, help, valid);
    }
}
