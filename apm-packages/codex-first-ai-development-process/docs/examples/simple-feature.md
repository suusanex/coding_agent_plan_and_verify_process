# Example: Simple Feature

## Request

```text
設定ファイルから greeting を読み、CLI の挨拶文に反映して。
```

## Expected route

- cost-router が repo rules と既存 artifact を読む。
- bounded Plan または同等の短い scope を作る。
- config 読み込みと CLI 出力だけが READY なら `STANDARD_MODEL` で実装する。
- 単純な docs / format check は `CHEAP_MODEL` に寄せてもよい。
- production CLI entrypoint を verification で確認する。

## READY example

```text
ReadyForImplementation
- Plan exists.
- Scope is limited to config read and CLI output.
- No secret or external service is involved.
- No advanced route is required.
```

## Close example

```text
SafeToClose
- Acceptance conditions are mapped to verification evidence.
- Production CLI entrypoint uses the config path.
- Remaining work is Deferred and not required for this request.
```

## Not close example

```text
ManualVerificationRequired
- The only evidence is a fake config reader test.
- Production config file path is not wired from the real CLI entrypoint.
```
