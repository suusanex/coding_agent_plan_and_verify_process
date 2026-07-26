$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtimeSource = Join-Path $PSScriptRoot 'codex-notification-runtime.cs'
$providerSource = Join-Path $PSScriptRoot 'windows-app-notification-provider.cs'
$installerSource = Join-Path $PSScriptRoot 'install-codex-notification-runtime-local.cs'
$fakeCommand = Join-Path $PSScriptRoot 'tests/fake-notification-command.ps1'
$envelopeSchema = Join-Path $PSScriptRoot 'completion-notification-envelope-v1.schema.json'
$eventSchema = Join-Path $PSScriptRoot 'completion-notification-event-v1.schema.json'
$artifactRoot = Join-Path $PSScriptRoot 'artifacts'
$workflow = Join-Path $root '.github/workflows/validate-codex-notification-runtime.yml'

foreach ($path in @($runtimeSource, $providerSource, $installerSource, $fakeCommand, $envelopeSchema, $eventSchema, $workflow)) {
    if (-not (Test-Path $path)) { throw "Missing required runtime asset: $path" }
}
if ((Test-Path $artifactRoot) -and @(Get-ChildItem -LiteralPath $artifactRoot -Recurse -File).Count -gt 0) { throw 'Generated notification artifacts must not be tracked or distributed.' }
if (-not (Get-Content (Join-Path $root '.gitignore') -Raw).Contains('scripts/codex-notification-runtime/artifacts/', [StringComparison]::Ordinal)) { throw 'Notification artifact ignore rule is missing.' }
if (-not (Get-Content $workflow -Raw).Contains('timeout-minutes: 15', [StringComparison]::Ordinal)) { throw 'Notification workflow timeout is missing.' }

function Invoke-Checked([scriptblock]$Action, [string]$Description) {
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE" }
}

function Write-RuntimeConfig([string]$RuntimeDirectory, [string]$PowerShellPath, [int]$TimeoutMs = 5000) {
    @{
        target_markers = @('[completion-notification]')
        chained_notify = @{ argv = @($PowerShellPath, '-NoProfile', '-File', $fakeCommand, 'chain') }
        providers = @(@{ name = 'fake'; argv = @($PowerShellPath, '-NoProfile', '-File', $fakeCommand, 'provider'); timeout_ms = $TimeoutMs })
    } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $RuntimeDirectory 'runtime-config.json') -Encoding utf8
}

function New-Payload([string]$TurnId, [AllowNull()][string]$AssistantMessage, [object]$InputMessages = @('[completion-notification]')) {
    return @{ type = 'agent-turn-complete'; 'thread-id' = 'fixture-thread'; 'turn-id' = $TurnId; cwd = $root; 'input-messages' = $InputMessages; 'last-assistant-message' = $AssistantMessage } | ConvertTo-Json -Compress
}

function New-Envelope([string]$Status, [string]$ResultUri = 'https://github.com/suusanex/coding_agent_plan_and_verify_process/pull/57') {
    $json = @{ schema_version = 1; primary_process = 'fixture'; observed_status = $Status; result_uri = $ResultUri } | ConvertTo-Json -Compress
    return '```completion-notification' + "`n" + $json + "`n" + '```'
}

function Invoke-Runtime([string]$Executable, [string]$Payload) {
    & $Executable dispatch $Payload
    if ($LASTEXITCODE -ne 0) { throw "Runtime callback must fail open, exit=$LASTEXITCODE" }
}

function Start-Runtime([string]$Executable, [string]$Payload) {
    $info = [System.Diagnostics.ProcessStartInfo]::new($Executable)
    $info.UseShellExecute = $false
    $info.ArgumentList.Add('dispatch')
    $info.ArgumentList.Add($Payload)
    return [System.Diagnostics.Process]::Start($info)
}

$validationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-notification-validation-' + [guid]::NewGuid().ToString('N'))
$buildRoot = Join-Path $validationRoot 'build'
$runtimeHome = Join-Path $validationRoot 'runtime-home'
$codexHome = Join-Path $validationRoot 'codex-home'
$installRoot = Join-Path $validationRoot 'install-root'
New-Item -ItemType Directory -Path $buildRoot, $runtimeHome, $codexHome | Out-Null

try {
    Invoke-Checked { dotnet publish $runtimeSource --output (Join-Path $buildRoot 'runtime') --disable-build-servers } 'runtime publish'
    Invoke-Checked { dotnet publish $providerSource --output (Join-Path $buildRoot 'provider') --disable-build-servers } 'provider publish'
    Invoke-Checked { dotnet publish $installerSource --output (Join-Path $buildRoot 'installer') --disable-build-servers } 'installer publish'

    $runtime = Join-Path $buildRoot 'runtime/codex-notification-runtime.exe'
    $provider = Join-Path $buildRoot 'provider/windows-app-notification-provider.exe'
    $installer = Join-Path $buildRoot 'installer/install-codex-notification-runtime-local.exe'
    Invoke-Checked { & $runtime --self-test } 'runtime self-test'
    Invoke-Checked { & $provider --self-test } 'provider self-test'
    Invoke-Checked { & $installer --self-test } 'installer self-test'

    $env:CODEX_NOTIFICATION_RUNTIME_HOME = $runtimeHome
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT = Join-Path $runtimeHome 'provider.jsonl'
    $env:CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT = Join-Path $runtimeHome 'chain.jsonl'
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    Write-RuntimeConfig $runtimeHome $pwsh

    $blockedPayload = New-Payload 'blocked-duplicate' (New-Envelope 'BLOCKED')
    Invoke-Runtime $runtime $blockedPayload
    Invoke-Runtime $runtime $blockedPayload
    if (@(Get-Content $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT).Count -ne 1) { throw 'Dedup did not suppress the second provider delivery.' }
    if (@(Get-Content $env:CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT).Count -ne 2) { throw 'Existing notify was not forwarded for duplicate callbacks.' }

    $parallelPayload = New-Payload 'parallel-duplicate' (New-Envelope 'COMPLETED')
    $parallel = @(
        Start-Runtime $runtime $parallelPayload
        Start-Runtime $runtime $parallelPayload
    )
    $parallel | ForEach-Object { $_.WaitForExit(); if ($_.ExitCode -ne 0) { throw 'Parallel callback did not fail open.' }; $_.Dispose() }
    if (@(Get-Content $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT | Where-Object { $_ -like '*codex:fixture-thread:parallel-duplicate*' }).Count -ne 1) { throw 'Parallel dedup delivered more than once.' }

    foreach ($status in @('COMPLETED', 'FAILED', 'HUMAN_DECISION_REQUIRED', 'TIMED_OUT')) {
        Invoke-Runtime $runtime (New-Payload ('status-' + $status) (New-Envelope $status))
    }
    Invoke-Runtime $runtime (New-Payload 'fallback-missing' $null)
    Invoke-Runtime $runtime (New-Payload 'fallback-invalid' ('```completion-notification' + "`n" + '{invalid}' + "`n" + '```'))
    Invoke-Runtime $runtime (New-Payload 'null-input' (New-Envelope 'FAILED') $null)
    Invoke-Runtime $runtime (New-Payload 'coarse-uri' (New-Envelope 'COMPLETED' 'https://github.com/suusanex/coding_agent_plan_and_verify_process'))
    Invoke-Runtime $runtime (New-Payload 'mixed-valid-uri' (New-Envelope 'COMPLETED' 'HTTPS://Example.com/result/1'))
    Invoke-Runtime $runtime (New-Payload 'mixed-coarse-uri' (New-Envelope 'COMPLETED' 'https://GitHub.com/suusanex/coding_agent_plan_and_verify_process'))
    Invoke-Runtime $runtime (New-Payload 'not-targeted' $null @('ordinary turn'))

    $events = @(Get-Content $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT | ForEach-Object { $_ | ConvertFrom-Json })
    foreach ($status in @('BLOCKED', 'COMPLETED', 'FAILED', 'HUMAN_DECISION_REQUIRED', 'TIMED_OUT')) {
        if (-not ($events.observed_status -contains $status)) { throw "Status was not preserved: $status" }
    }
    $fallbacks = @($events | Where-Object source_event_id -in @('codex:fixture-thread:fallback-missing', 'codex:fixture-thread:fallback-invalid'))
    if ($fallbacks.Count -ne 2 -or @($fallbacks | Where-Object observed_status -ne 'TURN_ENDED').Count -ne 0) { throw 'Fallback status contract failed.' }
    $coarse = $events | Where-Object source_event_id -eq 'codex:fixture-thread:coarse-uri'
    if ($null -ne $coarse.result_uri -or $coarse.resume_uri -ne 'codex://threads/fixture-thread') { throw 'Coarse URI did not fall back to resume_uri.' }
    $mixedValid = $events | Where-Object source_event_id -eq 'codex:fixture-thread:mixed-valid-uri'
    $mixedCoarse = $events | Where-Object source_event_id -eq 'codex:fixture-thread:mixed-coarse-uri'
    if ($mixedValid.result_uri -ne 'HTTPS://Example.com/result/1' -or $null -ne $mixedCoarse.result_uri) { throw 'Mixed-case runtime URI contract failed.' }
    if ($events.source_event_id -contains 'codex:fixture-thread:not-targeted') { throw 'Untargeted callback was delivered.' }

    $env:CODEX_NOTIFICATION_TEST_PROVIDER_EXIT = '2'
    $failurePayload = New-Payload 'provider-retry' (New-Envelope 'FAILED')
    Invoke-Runtime $runtime $failurePayload
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_EXIT = '0'
    Invoke-Runtime $runtime $failurePayload
    if (@(Get-Content $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT | Where-Object { $_ -like '*codex:fixture-thread:provider-retry*' }).Count -ne 2) { throw 'Provider failure was not retryable.' }

    Write-RuntimeConfig $runtimeHome $pwsh 1000
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_DELAY_MS = '1500'
    $timeoutPayload = New-Payload 'provider-timeout' (New-Envelope 'TIMED_OUT')
    Invoke-Runtime $runtime $timeoutPayload
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_DELAY_MS = '0'
    Invoke-Runtime $runtime $timeoutPayload
    if (@(Get-Content $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT | Where-Object { $_ -like '*codex:fixture-thread:provider-timeout*' }).Count -ne 1) { throw 'Provider timeout was not terminated and retried cleanly.' }

    @{ target_markers = $null; providers = $null; chained_notify = @{ argv = $null } } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $runtimeHome 'runtime-config.json') -Encoding utf8
    Invoke-Runtime $runtime (New-Payload 'null-config' (New-Envelope 'FAILED'))

    foreach ($line in Get-Content $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT) {
        if (-not ($line | Test-Json -SchemaFile $eventSchema -ErrorAction Stop)) { throw 'Provider event does not match event schema.' }
    }
    $validEnvelope = '{"schema_version":1,"primary_process":"fixture","observed_status":"COMPLETED","result_uri":"https://github.com/suusanex/coding_agent_plan_and_verify_process/pull/57"}'
    $coarseEnvelope = '{"schema_version":1,"primary_process":"fixture","observed_status":"COMPLETED","result_uri":"https://github.com/suusanex/coding_agent_plan_and_verify_process"}'
    $userinfoEnvelope = '{"schema_version":1,"primary_process":"fixture","observed_status":"COMPLETED","result_uri":"https://user@example.com/result/1"}'
    $mixedValidEnvelope = '{"schema_version":1,"primary_process":"fixture","observed_status":"COMPLETED","result_uri":"HTTPS://Example.com/result/1"}'
    $mixedCoarseEnvelope = '{"schema_version":1,"primary_process":"fixture","observed_status":"COMPLETED","result_uri":"https://GitHub.com/suusanex/coding_agent_plan_and_verify_process"}'
    if (-not ($validEnvelope | Test-Json -SchemaFile $envelopeSchema) -or -not ($mixedValidEnvelope | Test-Json -SchemaFile $envelopeSchema) -or ($coarseEnvelope | Test-Json -SchemaFile $envelopeSchema -ErrorAction SilentlyContinue) -or ($mixedCoarseEnvelope | Test-Json -SchemaFile $envelopeSchema -ErrorAction SilentlyContinue) -or ($userinfoEnvelope | Test-Json -SchemaFile $envelopeSchema -ErrorAction SilentlyContinue)) { throw 'Envelope URI schema contract failed.' }
    $log = Get-Content (Join-Path $runtimeHome 'runtime.log.jsonl') -Raw
    if ($log.Contains('github.com', [StringComparison]::OrdinalIgnoreCase) -or $log.Contains('completion-notification', [StringComparison]::Ordinal)) { throw 'Runtime log contains prohibited message or URI content.' }

    $originalConfig = (@('model_provider = "openai"', 'notify = [ "C:\\existing-notifier.exe", "turn-ended" ]', '', '[features]', 'web_search = true') -join "`r`n") + "`r`n"
    Set-Content (Join-Path $codexHome 'config.toml') -Value $originalConfig -NoNewline -Encoding utf8
    Invoke-Checked { & $installer install --codex-home $codexHome --install-root $installRoot } 'isolated install'
    $installedConfig = Get-Content (Join-Path $codexHome 'config.toml') -Raw
    if ($installedConfig.IndexOf('notify =', [StringComparison]::Ordinal) -gt $installedConfig.IndexOf('[features]', [StringComparison]::Ordinal)) { throw 'Installer placed notify inside a TOML table.' }
    $installedRuntimeConfig = Get-Content (Join-Path $installRoot 'runtime-config.json') -Raw | ConvertFrom-Json
    if (@($installedRuntimeConfig.target_markers).Count -ne 2 -or
        '[completion-notification]' -notin @($installedRuntimeConfig.target_markers) -or
        '$completion-notification-decorator' -notin @($installedRuntimeConfig.target_markers)) {
        throw 'Installer did not configure both default completion notification target markers.'
    }
    $backup = Join-Path $codexHome 'config.toml.codex-notification-runtime.bak'
    $backupHash = (Get-FileHash $backup -Algorithm SHA256).Hash
    $checkOutput = & $installer --check --codex-home $codexHome --install-root $installRoot
    $checkExit = $LASTEXITCODE
    $checkOutput | ForEach-Object { Write-Host $_ }
    if ($checkExit -notin @(0, 3) -or ($checkExit -eq 3 -and ($checkOutput -join "`n") -notmatch 'DEGRADED installer check')) { throw "Isolated installer check returned unexpected exit code $checkExit." }
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_UNSUPPORTED = '1'
    $degradedOutput = & $installer --check --codex-home $codexHome --install-root $installRoot
    $degradedExit = $LASTEXITCODE
    Remove-Item Env:CODEX_NOTIFICATION_TEST_PROVIDER_UNSUPPORTED -ErrorAction SilentlyContinue
    $degradedOutput | ForEach-Object { Write-Host $_ }
    $degradedText = $degradedOutput -join "`n"
    if ($degradedExit -ne 3 -or $degradedText -notmatch 'provider_support: unsupported' -or $degradedText -notmatch 'DEGRADED installer check') { throw 'Unsupported provider was not reported as degraded.' }
    $hangPidPath = Join-Path $validationRoot 'hanging-provider.pid'
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_HANG = '1'
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_HANG_PID_FILE = $hangPidPath
    $hangStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $hangOutput = & $installer --check --codex-home $codexHome --install-root $installRoot
    $hangExit = $LASTEXITCODE
    $hangStopwatch.Stop()
    Remove-Item Env:CODEX_NOTIFICATION_TEST_PROVIDER_HANG -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_NOTIFICATION_TEST_PROVIDER_HANG_PID_FILE -ErrorAction SilentlyContinue
    $hangOutput | ForEach-Object { Write-Host $_ }
    $hangText = $hangOutput -join "`n"
    if ($hangExit -ne 3 -or $hangText -notmatch 'provider_support: check-failed' -or $hangText -notmatch 'DEGRADED installer check') { throw 'Hanging provider was not reported as degraded.' }
    if ($hangStopwatch.Elapsed -gt [TimeSpan]::FromSeconds(10)) { throw "Hanging provider check exceeded time bound: $($hangStopwatch.Elapsed)." }
    if (-not (Test-Path $hangPidPath)) { throw 'Hanging provider did not record its process ID.' }
    $hangPid = [int](Get-Content $hangPidPath -Raw)
    if (Get-Process -Id $hangPid -ErrorAction SilentlyContinue) { throw "Hanging provider process was not terminated: $hangPid" }
    Write-Host "PASS hanging provider timeout ($([int]$hangStopwatch.Elapsed.TotalMilliseconds) ms, pid $hangPid terminated)"
    Invoke-Checked { & $installer install --codex-home $codexHome --install-root $installRoot } 'isolated reinstall'
    if ((Get-FileHash $backup -Algorithm SHA256).Hash -ne $backupHash) { throw 'Reinstall overwrote the original configuration backup.' }

    $runtimeHash = (Get-FileHash (Join-Path $installRoot 'bin/codex-notification-runtime.exe') -Algorithm SHA256).Hash
    $env:CODEX_NOTIFICATION_TEST_FAIL_AFTER_BIN_SWAP = '1'
    & $installer install --codex-home $codexHome --install-root $installRoot 2>$null
    if ($LASTEXITCODE -eq 0) { throw 'Injected installer failure unexpectedly succeeded.' }
    Remove-Item Env:CODEX_NOTIFICATION_TEST_FAIL_AFTER_BIN_SWAP -ErrorAction SilentlyContinue
    if ((Get-FileHash (Join-Path $installRoot 'bin/codex-notification-runtime.exe') -Algorithm SHA256).Hash -ne $runtimeHash) { throw 'Installer did not restore the previous binary after failure.' }
    if ((Get-FileHash $backup -Algorithm SHA256).Hash -ne $backupHash) { throw 'Failure path changed the original backup.' }
    $runtimeConfigPath = Join-Path $installRoot 'runtime-config.json'
    $savedRuntimeConfig = Get-Content $runtimeConfigPath -Raw
    $selfConfig = $savedRuntimeConfig | ConvertFrom-Json
    $selfConfig.chained_notify = @{ argv = @((Join-Path $installRoot 'bin/codex-notification-runtime.exe'), 'dispatch') }
    $selfConfig | ConvertTo-Json -Depth 6 | Set-Content $runtimeConfigPath -Encoding utf8
    & $installer --dry-run --codex-home $codexHome --install-root $installRoot 2>$null
    if ($LASTEXITCODE -eq 0) { throw 'Runtime self-wrap was not rejected.' }
    Set-Content $runtimeConfigPath -Value $savedRuntimeConfig -NoNewline -Encoding utf8
    Copy-Item $backup (Join-Path $codexHome 'config.toml') -Force
    if ((Get-Content (Join-Path $codexHome 'config.toml') -Raw) -ne $originalConfig) { throw 'Documented backup rollback did not restore the original config.' }

    $profileHome = Join-Path $validationRoot 'profile-home'
    New-Item -ItemType Directory -Path $profileHome | Out-Null
    Set-Content (Join-Path $profileHome 'team.config.toml') -Value '# profile'
    & $installer --dry-run --codex-home $profileHome --install-root (Join-Path $validationRoot 'profile-install') 2>$null
    if ($LASTEXITCODE -eq 0) { throw 'Profile conflict was not rejected.' }
    $multilineHome = Join-Path $validationRoot 'multiline-home'
    New-Item -ItemType Directory -Path $multilineHome | Out-Null
    Set-Content (Join-Path $multilineHome 'config.toml') -Value (@('notify = [', '  "tool.exe"', ']') -join "`n")
    & $installer --dry-run --codex-home $multilineHome --install-root (Join-Path $validationRoot 'multiline-install') 2>$null
    if ($LASTEXITCODE -eq 0) { throw 'Multiline notify conflict was not rejected.' }

    $installerText = Get-Content $installerSource -Raw
    if (-not $installerText.Contains('StandardOutput.ReadToEndAsync()', [StringComparison]::Ordinal) -or -not $installerText.Contains('StandardError.ReadToEndAsync()', [StringComparison]::Ordinal)) { throw 'Publish output streams are not drained concurrently.' }
}
finally {
    foreach ($name in @('CODEX_NOTIFICATION_RUNTIME_HOME', 'CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT', 'CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT', 'CODEX_NOTIFICATION_TEST_PROVIDER_EXIT', 'CODEX_NOTIFICATION_TEST_PROVIDER_DELAY_MS', 'CODEX_NOTIFICATION_TEST_FAIL_AFTER_BIN_SWAP', 'CODEX_NOTIFICATION_TEST_PROVIDER_UNSUPPORTED', 'CODEX_NOTIFICATION_TEST_PROVIDER_HANG', 'CODEX_NOTIFICATION_TEST_PROVIDER_HANG_PID_FILE')) {
        Remove-Item ("Env:" + $name) -ErrorAction SilentlyContinue
    }
    if (Test-Path $validationRoot) { Remove-Item -LiteralPath $validationRoot -Recurse -Force }
}

Write-Host 'PASS codex notification runtime validation'
$global:LASTEXITCODE = 0
