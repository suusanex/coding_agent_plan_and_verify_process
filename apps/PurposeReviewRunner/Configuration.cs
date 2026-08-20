using System.Text.Json;

namespace PurposeReviewRunner;

public sealed record RunnerPaths(string ConfigPath, string StateRoot)
{
    public static RunnerPaths CreateDefault()
    {
        var configRoot = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var stateRoot = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(configRoot) || string.IsNullOrWhiteSpace(stateRoot))
        {
            throw new RunnerException("USER_PATH_UNAVAILABLE", "User-level configuration or state directory could not be resolved.");
        }
        return new(
            Path.Combine(configRoot, "purpose-review-runner", "config.json"),
            Path.Combine(stateRoot, "purpose-review-runner", "runs"));
    }
}

public static class ConfigLoader
{
    private static readonly HashSet<string> Providers = new(StringComparer.Ordinal)
    {
        "codex", "grok", "copilot"
    };

    private static readonly HashSet<string> ReasoningEfforts = new(StringComparer.Ordinal)
    {
        "none", "minimal", "low", "medium", "high", "xhigh", "max"
    };

    public static RunnerConfig Load(string path)
    {
        if (!File.Exists(path))
        {
            throw new RunnerException("CONFIG_NOT_FOUND", $"Runner config was not found: {path}");
        }

        RunnerConfig config;
        try
        {
            config = JsonSerializer.Deserialize<RunnerConfig>(File.ReadAllText(path), JsonDefaults.Options)
                ?? throw new JsonException("Config JSON was empty.");
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            throw new RunnerException("CONFIG_INVALID", $"Runner config could not be read: {exception.Message}", ExitCodes.ContractError, exception);
        }

        Require(config.SchemaVersion == 1, "schemaVersion must be 1.");
        Require(Providers.Contains(config.Provider), "provider must be codex, grok, or copilot.");
        Require(!string.IsNullOrWhiteSpace(config.Executable), "executable is required.");
        Require(!string.IsNullOrWhiteSpace(config.Model), "model is required.");
        Require(ReasoningEfforts.Contains(config.ReasoningEffort), "reasoningEffort is unsupported.");
        RejectControlCharacters(config.Executable, "executable");
        RejectControlCharacters(config.Model, "model");
        if (config.Profile is not null)
        {
            RejectControlCharacters(config.Profile, "profile");
        }
        return config;
    }

    private static void Require(bool condition, string message)
    {
        if (!condition)
        {
            throw new RunnerException("CONFIG_INVALID", message);
        }
    }

    private static void RejectControlCharacters(string value, string name)
    {
        if (value.Any(char.IsControl))
        {
            throw new RunnerException("CONFIG_INVALID", $"{name} must not contain control characters.");
        }
    }
}

public interface IExecutableResolver
{
    string Resolve(string executable);
}

public sealed class ExecutableResolver : IExecutableResolver
{
    public string Resolve(string executable)
    {
        if (Path.IsPathRooted(executable) || executable.Contains(Path.DirectorySeparatorChar) || executable.Contains(Path.AltDirectorySeparatorChar))
        {
            var fullPath = Path.GetFullPath(executable);
            if (!File.Exists(fullPath))
            {
                throw new RunnerException("EXECUTABLE_NOT_FOUND", $"Configured executable was not found: {fullPath}");
            }
            return fullPath;
        }

        var pathValue = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        var directories = pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var extensions = OperatingSystem.IsWindows()
            ? new[] { ".exe", ".com", ".cmd", ".bat", string.Empty }
            : new[] { string.Empty };
        foreach (var directory in directories)
        {
            foreach (var extension in extensions)
            {
                var candidate = Path.Combine(directory, executable + extension);
                if (File.Exists(candidate))
                {
                    return Path.GetFullPath(candidate);
                }
            }
        }
        throw new RunnerException("EXECUTABLE_NOT_FOUND", $"Configured executable was not found on PATH: {executable}");
    }
}
