using System.Diagnostics;
using System.Text;

namespace PurposeReviewRunner;

public sealed class TranscriptStore
{
    private readonly string transcriptDirectory;

    public TranscriptStore(string runDirectory)
    {
        transcriptDirectory = Path.Combine(Path.GetFullPath(runDirectory), "transcript");
    }

    public void SavePrompt(int round, string payload) => Save(round, "prompt", payload);

    public void SaveResponse(int round, string response) => Save(round, "response", response);

    private void Save(int round, string kind, string content)
    {
        try
        {
            Directory.CreateDirectory(transcriptDirectory);
            var path = Path.Combine(transcriptDirectory, $"round-{round:D2}-{kind}.md");
            File.WriteAllText(path, content, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("TRANSCRIPT_WRITE_FAILED", "Review transcript could not be saved.", ExitCodes.ContractError, exception);
        }
    }
}
