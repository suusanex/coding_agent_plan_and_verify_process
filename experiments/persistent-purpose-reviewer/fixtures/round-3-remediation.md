# Round 3 Remediation: 目的を満たす解決版（架空）

> この candidate は検証契約を満たす解決版です。production code ではありません。

```csharp
public static MigrationResult ConvertV1ToV2(V1Settings input)
{
    var mapping = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["lantern-quiet"] = "steady",
        ["lantern-focus"] = "deep-work",
        ["lantern-pulse"] = "quick-check"
    };

    if (!mapping.TryGetValue(input.NotificationMode, out var mapped))
    {
        return MigrationResult.Pending(
            code: "PURPOSE_REVIEW_UNKNOWN_LEGACY_VALUE",
            originalV1Value: input.NotificationMode,
            message: "The legacy value needs explicit user confirmation.");
    }

    var converted = new V2Settings
    {
        NotificationMode = mapped,
        QuietHours = input.QuietHours
    };

    ValidateV2Schema(converted);
    return MigrationResult.Success(converted);
}
```

補足:

- 対象 3 既知値だけを明示 mapping する。
- unknown は元の値を保持した `Pending` とし、明示的な code と利用者向け message を返す。
- unknown を通常値へ置換せず、失敗を成功に見せない。
- UI 刷新、自動推測、類似値検索は追加していない。
