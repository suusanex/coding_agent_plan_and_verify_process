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

            var source = RequiredText(root, "source");
            return source switch
            {
                "codex.agent-turn-complete" => ParseCodex(filePath, root),
                "agent-execution-broker.run-terminal" => ParseBroker(filePath, root),
                _ => Error(filePath, "Unsupported spool source.")
            };
        }
        catch (JsonException)
        {
            return Error(filePath, "The file contains malformed JSON.");
        }
        catch (KeyNotFoundException)
        {
            return Error(filePath, "The file is missing a required field.");
        }
        catch (SpoolFieldException ex)
        {
            return Error(filePath, ex.Message);
        }
        catch (InvalidOperationException)
        {
            return Error(filePath, "A spool field has an invalid JSON type.");
        }
    }

    private static InboxEntry ParseCodex(string filePath, JsonElement root)
    {
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

    private static InboxEntry ParseBroker(string filePath, JsonElement root)
    {
        var allowed = new HashSet<string>(StringComparer.Ordinal)
        {
            "schema_version", "source", "source_event_id", "run_id", "provider_id", "observed_status",
            "occurred_at", "title", "result_locator", "repository"
        };
        var properties = root.EnumerateObject().ToArray();
        if (properties.Length is < 9 or > 10 || properties.Any(property => !allowed.Contains(property.Name)))
        {
            return Error(filePath, "The Broker terminal event has an invalid field set.");
        }
        if (!root.TryGetProperty("schema_version", out var version) || !version.TryGetInt32(out var schemaVersion) || schemaVersion != 1)
        {
            return Error(filePath, "Unsupported Broker terminal event schema version.");
        }
        var runText = RequiredText(root, "run_id");
        if (!Guid.TryParse(runText, out var runId)) return Error(filePath, "The run_id field must be a UUID.");
        var sourceEventId = RequiredText(root, "source_event_id");
        var expectedEventId = $"agent-execution-broker:run:{runId}:terminal";
        if (!string.Equals(sourceEventId, expectedEventId, StringComparison.Ordinal)) return Error(filePath, "The source_event_id field does not match run_id.");
        var locator = RequiredText(root, "result_locator");
        if (!string.Equals(locator, $"broker-run:{runId}", StringComparison.Ordinal)) return Error(filePath, "The result_locator field does not match run_id.");
        var occurredText = RequiredText(root, "occurred_at");
        if (!DateTimeOffset.TryParse(occurredText, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var occurredAt))
        {
            return Error(filePath, "The occurred_at value is not a valid RFC 3339 timestamp.");
        }
        string? repository = null;
        if (root.TryGetProperty("repository", out var repositoryElement))
        {
            if (repositoryElement.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(repositoryElement.GetString()))
            {
                return Error(filePath, "The repository field must be a non-empty JSON string when present.");
            }
            repository = repositoryElement.GetString();
        }
        return new InboxEntry(filePath, null, null)
        {
            BrokerItem = new BrokerTerminalEventV1(schemaVersion, RequiredText(root, "source"), sourceEventId, runId,
                RequiredText(root, "provider_id"), RequiredText(root, "observed_status"), occurredAt.ToUniversalTime(),
                RequiredText(root, "title"), locator, repository)
        };
    }

    private static string RequiredText(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var property))
        {
            throw new SpoolFieldException($"The {name} field is missing.");
        }

        if (property.ValueKind != JsonValueKind.String)
        {
            throw new SpoolFieldException($"The {name} field must be a JSON string.");
        }

        var value = property.GetString();
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new SpoolFieldException($"The {name} field must not be empty.");
        }

        return value;
    }

    private static InboxEntry Error(string filePath, string message) => new(filePath, null, message);

    private sealed class SpoolFieldException(string message) : Exception(message);
}
