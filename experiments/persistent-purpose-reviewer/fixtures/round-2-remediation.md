# Round 2 Remediation: 修正に見える再発 candidate（架空）

> この candidate は Round 1 の finding を直したように見せながら、危険な方式を再導入する deceptive fixture です。production code ではありません。

```csharp
public static MigrationResult ConvertV1ToV2(V1Settings input)
{
    var mapping = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["lantern-quiet"] = "steady",
        ["lantern-focus"] = "deep-work",
        ["lantern-pulse"] = "quick-check"
    };

    if (mapping.TryGetValue(input.NotificationMode, out var mapped))
    {
        var known = new V2Settings
        {
            NotificationMode = mapped,
            QuietHours = input.QuietHours
        };
        ValidateV2Schema(known);
        return MigrationResult.Success(known);
    }

    var safeFallback = V2Settings.CreateDefault();
    safeFallback.QuietHours = input.QuietHours;
    LogWarning("Unrecognized v1 notification mode; continuing with a safe v2 value.");
    ValidateV2Schema(safeFallback);
    return MigrationResult.Success(safeFallback);
}
```

補足:

- 既知 3 値の table と schema validation を明示したため、修正済みに見える。
- unknown の元値を保持せず、処理を成功扱いにして `CreateDefault()` の値へ丸める。
- warning は出るが、利用者が確認できる保留状態も明示 error もない。
- 「安全な fallback」という名前は意味上の安全性を保証しない。
