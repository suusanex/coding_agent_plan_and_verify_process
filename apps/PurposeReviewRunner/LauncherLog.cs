using System.Globalization;
using System.Text;

namespace PurposeReviewRunner;

internal sealed class LauncherLogWriter : IDisposable
{
    private readonly StreamWriter writer;

    private LauncherLogWriter(StreamWriter writer) => this.writer = writer;

    public static LauncherLogWriter Open(string runDirectory)
    {
        Directory.CreateDirectory(runDirectory);
        var stream = new FileStream(
            Path.Combine(runDirectory, "launcher.log"),
            FileMode.Append,
            FileAccess.Write,
            FileShare.ReadWrite);
        var writer = new StreamWriter(stream, new UTF8Encoding(false)) { AutoFlush = true };
        return new LauncherLogWriter(writer);
    }

    public void WriteLaunchHeader()
    {
        writer.WriteLine();
        Write("timestamp", DateTimeOffset.UtcNow.ToString("o", CultureInfo.InvariantCulture));
    }

    public void Write(string key, string? value)
    {
        if (string.IsNullOrWhiteSpace(key) || key.Contains('=', StringComparison.Ordinal) || key.Contains('\n', StringComparison.Ordinal))
        {
            throw new ArgumentException("Launcher log key is invalid.", nameof(key));
        }

        var sanitized = (value ?? string.Empty)
            .Replace("\r", " ", StringComparison.Ordinal)
            .Replace("\n", " ", StringComparison.Ordinal);
        writer.WriteLine(key + "=" + sanitized);
    }

    public void Write(string key, bool value) => Write(key, value ? "true" : "false");

    public void Write(string key, int value) => Write(key, value.ToString(CultureInfo.InvariantCulture));

    public void WriteHex(string key, uint value) =>
        Write(key, "0x" + value.ToString("x8", CultureInfo.InvariantCulture));

    public void Dispose() => writer.Dispose();
}
