# Example: Simple Feature

## Request

```text
設定ファイルから greeting を読み、CLI の挨拶文に反映してください。
```

## Expected route

- cost-router が repo rules と既存 artifact を読む。
- bounded Plan または同等の短い scope を作る。
- config 読み込みと CLI 出力だけが READY でも、非自明な実装は handoff review で parent authorization artifact を作ってから `high-implementation-starter` で開始する。既存 pattern が明確で decision-free remainder になった場合だけ `standard-implementation-completer` へ serial delegation する。
- 単純な docs / format check は Routing Plan に応じて `CHEAP_MODEL` worker へ委譲する。
- production CLI entrypoint を verification で確認する。

## READY example

```text
ReadyForHighImplementationStart
- Plan exists.
- Scope is limited to config read and CLI output.
- implementation-handoff-review artifact exists.
- EditOwner is high-implementation-starter.
- ShapeHandoffStatus is NotStarted.
- No secret or external service is involved.
- No advanced route is required.
```

## Close example

```text
SafeToClose
- Acceptance conditions are mapped to verification evidence.
- Production CLI entrypoint uses the config path.
- Audit DelegationCompliance is PASS.
- HIGH start, optional valid STANDARD completion, and any HIGH re-entry are recorded without overlapping write ownership.
- Remaining work is Deferred and not required for this request.
```

## Not close example

```text
ManualVerificationRequired
- The only evidence is a fake config reader test.
- Production config file path is not wired from the real CLI entrypoint.
```
