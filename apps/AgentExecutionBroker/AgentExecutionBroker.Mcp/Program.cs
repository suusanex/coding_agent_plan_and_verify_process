using AgentExecutionBroker.Mcp;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddSingleton<BrokerPipeClient>();
builder.Services.AddMcpServer()
    .WithStdioServerTransport()
    .WithTools<BrokerTools>();
await builder.Build().RunAsync();
