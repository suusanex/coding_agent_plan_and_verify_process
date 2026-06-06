# Example: Simple Feature

## Request

```text
設定ファイルから greeting を読み、CLI の挨拶文に反映してください。
Codex-first AI Development Process で進めて。
```

## Expected route

- `codex-plan-coverage`
- `plan-kernel.agent.md`
- `change-risk-triage.agent.md`
- `implementation-execution.agent.md`
- `verification-kernel.agent.md`

## READY example

```text
ReadyForImplementation
- Plan exists.
- Scope is limited to config read and CLI output.
- No secret or external service is involved.
- No full-coverage decomposition is required.
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
