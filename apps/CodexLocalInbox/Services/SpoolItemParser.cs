using System.Globalization;
using System.Text.Json;
using CodexLocalInbox.Models;

namespace CodexLocalInbox.Services;

public sealed class SpoolItemParser
{
    private static readonly HashSet<string> FieldNames = new(StringComparer.Ordinal)
    {
        "schema_version", "source", "source_event_id", "primary_process",
        "observed_status", "occurred_at", "title", "repository",
        "resume_uri", "result_uri"
    };

    public InboxEntry Parse(string filePath, string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return Error(filePath, "The JSON root is not an object.");
            }

            var properties = root.EnumerateObject().ToArray();
            if (properties.Length != FieldNames.Count ||
                properties.Any(property => !FieldNames.Contains(property.Name)) ||
                properties.Select(property => property.Name).Distinct(StringComparer.Ordinal).Count() != FieldNames.Count)
            {
                return Error(filePath, "The file does not contain exactly the ten spool-item-v1 fields.");
            }

            if (!root.TryGetProperty("schema_version", out var version) ||
                version.ValueKind != JsonValueKind.Number ||
                !version.TryGetInt32(out var schemaVersion) ||
                schemaVersion != 1)
            {
                return Error(filePath, "Unsupported spool schema version.");
            }

            var source = RequiredText(root, "source");
            if (source is not "codex.agent-turn-complete")
            {
                return Error(filePath, "Unsupported spool source.");
            }

            var sourceEventId = RequiredText(root, "source_event_id");
            var primaryProcess = RequiredText(root, "primary_process");
            var observedStatus = RequiredText(root, "observed_status");
            var title = RequiredText(root, "title");
            var repository = RequiredText(root, "repository");
            var occurredText = RequiredText(root, "occurred_at");
            if (!DateTimeOffset.TryParse(
                    occurredText,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out var occurredAt))
            {
                return Error(filePath, "The occurred_at value is not a valid RFC 3339 timestamp.");
            }

            var resumeUri = RequiredText(root, "resume_uri");
            if (!UriLaunchPolicy.TryGetResumeUri(resumeUri, out _))
            {
                return Error(filePath, "The resume_uri value is not an allowed codex thread URI.");
            }

            var resultElement = root.GetProperty("result_uri");
            string? resultUri = resultElement.ValueKind switch
            {
                JsonValueKind.Null => null,
                JsonValueKind.String => resultElement.GetString(),
                _ => string.Empty
            };
            if (resultElement.ValueKind != JsonValueKind.Null &&
                !UriLaunchPolicy.TryGetResultUri(resultUri, out _))
            {
                return Error(filePath, "The result_uri value is not an allowed HTTPS URI.");
            }

            return new InboxEntry(filePath, new SpoolItemV1(
                schemaVersion,
                source,
                sourceEventId,
                primaryProcess,
                observedStatus,
                occurredAt.ToUniversalTime(),
                title,
                repository,
                resumeUri,
                resultUri), null);
        }
        catch (JsonException)
        {
            return Error(filePath, "The file contains malformed JSON.");
        }
        catch (KeyNotFoundException)
        {
            return Error(filePath, "The file is missing a required field.");
        }
        catch (InvalidOperationException)
        {
            return Error(filePath, "A spool field has an invalid JSON type.");
        }
    }

    private static string RequiredText(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var property) ||
            property.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(property.GetString()))
        {
            throw new InvalidOperationException($"Missing or empty {name}.");
        }

        return property.GetString()!;
    }

    private static InboxEntry Error(string filePath, string message) => new(filePath, null, message);
}
