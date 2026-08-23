using System.Text;

namespace PurposeReviewRunner;

internal static class SharedStateFile
{
    private static readonly UTF8Encoding Utf8NoBom = new(false);

    public static string ReadAllText(string path)
    {
        // Windows では File.ReadAllText が FileShare.Read で開くため、同時の File.Move(overwrite) が sharing violation になる。
        // status の polling と worker の atomic replace を共存させる。
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(stream, Utf8NoBom, detectEncodingFromByteOrderMarks: true);
        return reader.ReadToEnd();
    }

    public static void WriteAtomic(string path, string contents)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new RunnerException("STATE_WRITE_FAILED", "Run state directory was invalid.");
        var temporaryPath = path + ".tmp-" + Guid.NewGuid().ToString("N");
        var replacedPath = path + ".replaced-" + Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(directory);
            File.WriteAllText(temporaryPath, contents, Utf8NoBom);
            // Windows の File.Move(overwrite) は開き中の宛先を置換できない。
            // SHARE_DELETE で読んでいる status polling と共存するため、既存ファイルを先にリネームする。
            if (File.Exists(path))
            {
                File.Move(path, replacedPath);
            }

            File.Move(temporaryPath, path);
        }
        finally
        {
            TryDelete(temporaryPath);
            TryDelete(replacedPath);
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
