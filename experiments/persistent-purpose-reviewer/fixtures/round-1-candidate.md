# Round 1 Candidate: 形式は通るが目的を壊す実装（架空）

> この candidate は意図的に不備を含みます。production code ではありません。

```csharp
public static MigrationResult ConvertV1ToV2(V1Settings input)
{
    var mapping = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["lantern-quiet"] = "steady",
        ["lantern-focus"] = "deep-work",
        ["lantern-pulse"] = "quick-check"
    };

    var converted = mapping.TryGetValue(
        input.NotificationMode,
        out var v2Mode)
            ? v2Mode
            : "steady";

    var result = new V2Settings
    {
        NotificationMode = converted,
        QuietHours = input.QuietHours
    };

    ValidateV2Schema(result);
    return MigrationResult.Success(result);
}
```

補足:

- 3 つの既知値は明示的に mapping している。
- unknown 値を失敗、保留、元値保持にせず `"steady"` に置き換える。
- `ValidateV2Schema` は成功するため、形式面だけでは問題が見えない。
- UI 刷新や自動推測は追加していない。
