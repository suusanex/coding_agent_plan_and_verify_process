# Lantern Pulse adapter

```csharp
public static string GetWireMode(string integrationSource)
{
    return integrationSource switch
    {
        "lantern-pulse" => "focus-mode",
        "river-signal" => "steady-check",
        _ => "standard-check"
    };
}
```

```json
{
  "integrationSource": "lantern-pulse",
  "mode": "focus-mode",
  "timeoutSeconds": 15
}
```
