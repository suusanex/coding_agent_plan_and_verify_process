using AgentExecutionBroker.Host;

await using var host = new BrokerHost();
await host.RunAsync();
