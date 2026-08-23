using System.Text;

namespace PurposeReviewRunner;

internal static class SharedStateFile
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);

    public static string ReadAllText(string path)
    {
        // Windows では File.ReadAllText が FileShare.Read で開くため、同時の置換が sharing violation になる。
        // File.Replace 中の短い排他も、status polling が旧版または新版を読めるよう再試行する。
        Exception? lastException = null;
        for (var attempt = 1; attempt <= 20; attempt++)
        {
            try
            {
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                using var reader = new StreamReader(stream, Utf8NoBom, detectEncodingFromByteOrderMarks: true);
                return reader.ReadToEnd();
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                lastException = exception;
                Thread.Sleep(attempt <= 5 ? 1 : 5);
            }
        }

        throw lastException!;
    }

    public static void WriteAtomic(string path, string contents)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new RunnerException("STATE_WRITE_FAILED", "Run state directory was invalid.");
        var temporaryPath = path + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(directory);
            File.WriteAllText(temporaryPath, contents, Utf8NoBom);
            if (File.Exists(path))
            {
                // Windows の File.Move(overwrite) は SHARE_DELETE で開かれた宛先でも失敗する。
                // File.Replace は正式 path が常に旧版か新版として残る単一置換。
                File.Replace(temporaryPath, path, destinationBackupFileName: null);
            }
            else
            {
                File.Move(temporaryPath, path);
            }
        }
        finally
        {
            TryDelete(temporaryPath);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (Exception exception)
        {
            System.Diagnostics.Trace.TraceError(exception.ToString());
        }
    }
}
