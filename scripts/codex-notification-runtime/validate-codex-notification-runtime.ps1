$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $PSScriptRoot 'codex-notification-runtime.cs'
$provider = Join-Path $PSScriptRoot 'windows-app-notification-provider.cs'
$installer = Join-Path $PSScriptRoot 'install-codex-notification-runtime-local.cs'
$fakeProvider = Join-Path $PSScriptRoot 'tests/fake-notification-command.ps1'
foreach ($path in @($runtime, $provider, $installer, (Join-Path $PSScriptRoot 'completion-notification-envelope-v1.schema.json'), (Join-Path $PSScriptRoot 'completion-notification-event-v1.schema.json'))) {
    if (-not (Test-Path $path)) { throw "Missing required runtime asset: $path" }
}
dotnet run --file $runtime -- --self-test
if (-not (Test-Path $fakeProvider)) { throw "Missing fake provider: $fakeProvider" }
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-notification-runtime-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempHome | Out-Null
try {
    $env:CODEX_NOTIFICATION_RUNTIME_HOME = $tempHome
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT = Join-Path $tempHome 'provider.jsonl'
    $env:CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT = Join-Path $tempHome 'chain.jsonl'
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    @{
        target_markers = @('[completion-notification]')
        chained_notify = @{ argv = @($pwsh, '-NoProfile', '-File', $fakeProvider, 'chain') }
        providers = @(@{ name = 'fake'; argv = @($pwsh, '-NoProfile', '-File', $fakeProvider, 'provider'); timeout_ms = 5000 })
    } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $tempHome 'runtime-config.json') -Encoding utf8
    $assistantMessage = @'
```completion-notification
{"schema_version":1,"primary_process":"fixture","observed_status":"BLOCKED","result_uri":"https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/52"}
```
'@
    $payload = @{ type = 'agent-turn-complete'; 'thread-id' = 'fixture-thread'; 'turn-id' = 'fixture-turn'; cwd = $root; 'input-messages' = @('[completion-notification]'); 'last-assistant-message' = $assistantMessage } | ConvertTo-Json -Compress
    dotnet run --file $runtime -- dispatch $payload
    dotnet run --file $runtime -- dispatch $payload
    for ($i = 0; $i -lt 20 -and -not (Test-Path $env:CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT); $i++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT)) { throw ("Provider did not write output. Runtime log: " + (Get-Content (Join-Path $tempHome 'runtime.log.jsonl') -Raw -ErrorAction SilentlyContinue)) }
    if ((Get-Content $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT).Count -ne 1) { throw 'Dedup did not suppress the second provider delivery.' }
    if ((Get-Content $env:CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT).Count -ne 2) { throw 'Existing notify was not forwarded for both callbacks.' }
    $event = Get-Content $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT -Raw | ConvertFrom-Json
    if ($event.observed_status -ne 'BLOCKED' -or $event.result_uri -notlike 'https://github.com/*' -or $event.resume_uri -ne 'codex://threads/fixture-thread') { throw 'Provider received an invalid completion event.' }
}
finally {
    Remove-Item Env:CODEX_NOTIFICATION_RUNTIME_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT -ErrorAction SilentlyContinue
    if (Test-Path $tempHome) { Remove-Item -LiteralPath $tempHome -Recurse -Force }
}
dotnet publish $runtime --disable-build-servers
dotnet publish $provider --disable-build-servers
dotnet publish $installer --disable-build-servers
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-home-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryCodexHome | Out-Null
try {
    'notify = [ "C:\\existing-notifier.exe", "turn-ended" ]' | Set-Content (Join-Path $temporaryCodexHome 'config.toml') -Encoding utf8
    dotnet run --file $installer -- --dry-run --codex-home $temporaryCodexHome
}
finally {
    if (Test-Path $temporaryCodexHome) { Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force }
}
Write-Host 'PASS codex notification runtime validation'
