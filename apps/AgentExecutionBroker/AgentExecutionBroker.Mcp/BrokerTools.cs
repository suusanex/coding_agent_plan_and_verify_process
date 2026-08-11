using System.Diagnostics;
using System.IO.Pipes;
using System.Text.Json;
using AgentExecutionBroker.Contracts;
using ModelContextProtocol.Server;

namespace AgentExecutionBroker.Mcp;

[McpServerToolType]
public sealed class BrokerTools(BrokerPipeClient client)
{
    [McpServerTool(Name = "start_run")]
    public Task<string> StartRunAsync(string provider_id, string working_directory, string prompt, string execution_profile, string? repository = null, CancellationToken cancellationToken = default) =>
        client.SendAsync("start_run", new StartRunRequest(provider_id, working_directory, prompt, execution_profile, repository), cancellationToken);

    [McpServerTool(Name = "get_run")]
    public Task<string> GetRunAsync(string run_id, CancellationToken cancellationToken = default) =>
        client.SendAsync("get_run", new RunQuery(ParseRunId(run_id)), cancellationToken);

    [McpServerTool(Name = "list_runs")]
    public Task<string> ListRunsAsync(int? limit = null, string? cursor = null, CancellationToken cancellationToken = default) =>
        client.SendAsync("list_runs", new ListRunsRequest(limit, cursor), cancellationToken);

    [McpServerTool(Name = "get_output")]
    public Task<string> GetOutputAsync(string run_id, long? after_sequence = null, int? max_records = null, int? max_bytes = null, CancellationToken cancellationToken = default) =>
        client.SendAsync("get_output", new OutputQuery(ParseRunId(run_id), after_sequence, max_records, max_bytes), cancellationToken);

    [McpServerTool(Name = "cancel_run")]
    public Task<string> CancelRunAsync(string run_id, CancellationToken cancellationToken = default) =>
        client.SendAsync("cancel_run", new RunQuery(ParseRunId(run_id)), cancellationToken);

    private static Guid ParseRunId(string runId) => Guid.TryParse(runId, out var value)
        ? value
        : throw new ArgumentException("run_id must be a UUID.", nameof(runId));
}

public sealed class BrokerPipeClient
{
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web);

    public async Task<string> SendAsync<T>(string operation, T payload, CancellationToken cancellationToken)
    {
        await using var pipe = await ConnectAsync(cancellationToken);
        var request = new BrokerRequest(operation, JsonSerializer.SerializeToElement(payload, _json));
        var bytes = JsonSerializer.SerializeToUtf8Bytes(request, _json);
        await WriteFrameAsync(pipe, bytes, cancellationToken);
        var responseBytes = await ReadFrameAsync(pipe, cancellationToken);
        var response = JsonSerializer.Deserialize<BrokerResponse>(responseBytes, _json)
            ?? throw new InvalidDataException("Broker response was empty.");
        if (!response.Succeeded)
        {
            throw new InvalidOperationException($"{response.ErrorCode}: {response.ErrorMessage}");
        }
        return response.Result?.GetRawText() ?? "null";
    }

    private static async Task<NamedPipeClientStream> ConnectAsync(CancellationToken cancellationToken)
    {
        var pipe = new NamedPipeClientStream(".", BrokerProtocol.PipeName, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        try
        {
            await pipe.ConnectAsync(TimeSpan.FromMilliseconds(500), cancellationToken);
            return pipe;
        }
        catch (TimeoutException)
        {
            pipe.Dispose();
            LaunchHost();
            var launched = new NamedPipeClientStream(".", BrokerProtocol.PipeName, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            try
            {
                await launched.ConnectAsync(TimeSpan.FromSeconds(10), cancellationToken);
                return launched;
            }
            catch
            {
                launched.Dispose();
                throw;
            }
        }
    }

    private static void LaunchHost()
    {
        var configured = Environment.GetEnvironmentVariable("AGENT_EXECUTION_BROKER_HOST_PATH");
        var executable = string.IsNullOrWhiteSpace(configured)
            ? Path.Combine(AppContext.BaseDirectory, "AgentExecutionBroker.Host.exe")
            : configured;
        if (!Path.IsPathFullyQualified(executable) || !File.Exists(executable))
        {
            throw new FileNotFoundException("Agent Execution Broker Host was not found. Set AGENT_EXECUTION_BROKER_HOST_PATH to an absolute Host executable path.", executable);
        }
        var process = Process.Start(new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true });
        if (process is null) throw new InvalidOperationException("Agent Execution Broker Host could not be started.");
    }

    private static async Task WriteFrameAsync(Stream stream, byte[] payload, CancellationToken cancellationToken)
    {
        await stream.WriteAsync(BitConverter.GetBytes(payload.Length), cancellationToken);
        await stream.WriteAsync(payload, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }
    private static async Task<byte[]> ReadFrameAsync(Stream stream, CancellationToken cancellationToken)
    {
        var header = new byte[sizeof(int)];
        await stream.ReadExactlyAsync(header, cancellationToken);
        var length = BitConverter.ToInt32(header, 0);
        if (length <= 0 || length > 4 * 1024 * 1024) throw new InvalidDataException("Broker response frame length is invalid.");
        var payload = new byte[length];
        await stream.ReadExactlyAsync(payload, cancellationToken);
        return payload;
    }
}
