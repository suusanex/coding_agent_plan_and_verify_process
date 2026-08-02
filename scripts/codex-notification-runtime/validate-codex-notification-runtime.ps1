$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtimeSource = Join-Path $PSScriptRoot 'codex-notification-runtime.cs'
$providerSource = Join-Path $PSScriptRoot 'local-spool-provider.cs'
$installerSource = Join-Path $PSScriptRoot 'install-codex-notification-runtime-local.cs'
$spoolSchema = Join-Path $PSScriptRoot 'spool-item-v1.schema.json'
$eventSchema = Join-Path $PSScriptRoot 'completion-notification-event-v1.schema.json'
$fakeProvider = Join-Path $PSScriptRoot 'tests/fake-notification-command.ps1'
foreach ($path in @($runtimeSource, $providerSource, $installerSource, $spoolSchema, $eventSchema, $fakeProvider)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing Local Spool asset: $path" }
}

function Invoke-Checked([scriptblock]$Action, [string]$Description) {
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE" }
}
function New-Payload([string]$TurnId, [string]$ResultUri = '') {
    $message = if ($ResultUri) {
        $envelope = @{ schema_version = 1; primary_process = 'validator'; observed_status = 'COMPLETED'; title = 'validated'; repository = 'owner/repository'; result_uri = $ResultUri } | ConvertTo-Json -Compress
        [string]::Join("`n", @('```completion-notification', $envelope, '```'))
    } else { $null }
    return @{ type = 'agent-turn-complete'; 'thread-id' = 'fixture-thread'; 'turn-id' = $TurnId; cwd = $root; 'last-assistant-message' = $message } | ConvertTo-Json -Compress
}
function New-Event([string]$Id, [AllowNull()][object]$ResultUri = $null) {
    return [ordered]@{
        schema_version = 1; source = 'codex.agent-turn-complete'; source_event_id = $Id; primary_process = 'validator'
        observed_status = 'COMPLETED'; occurred_at = '2026-08-01T00:00:00.0000000Z'; title = 'fixture title'
        repository = 'owner/repository'; resume_uri = 'codex://threads/fixture-thread'; result_uri = $ResultUri; notification_status = 'PENDING'
    }
}
function New-SpoolItem([string]$Id) {
    return [ordered]@{
        schema_version = 1; source = 'codex.agent-turn-complete'; source_event_id = $Id; primary_process = 'validator'
        observed_status = 'COMPLETED'; occurred_at = '2026-08-01T00:00:00.0000000+00:00'; title = 'collision fixture'
        repository = 'owner/repository'; resume_uri = 'codex://threads/collision'; result_uri = $null
    }
}
function Get-SourceHash([string]$Value) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}
function ConvertTo-Projection([string]$Value, [int]$Maximum) {
    $normalized = $Value.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant()
    $normalized = ([regex]::Replace($normalized, '[^a-z0-9]+', '-')).Trim('-')
    if (-not $normalized) { $normalized = 'unknown' }
    return $normalized.Substring(0, [Math]::Min($Maximum, $normalized.Length))
}
function Get-CandidateName([Collections.IDictionary]$Event, [int]$HashLength) {
    $timestamp = ([DateTimeOffset]::Parse($Event.occurred_at)).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss.fffffff'Z'")
    $hash = Get-SourceHash $Event.source_event_id
    return "${timestamp}__$(ConvertTo-Projection $Event.observed_status 24)__$(ConvertTo-Projection $Event.repository 48)__$($hash.Substring(0, $HashLength)).json"
}
function Invoke-ProviderJson([string]$Json, [string]$SpoolRoot) {
    $errorPath = Join-Path $validationRoot ('provider-error-' + [guid]::NewGuid().ToString('N') + '.txt')
    $Json | & $provider --spool-root $SpoolRoot 2>$errorPath
    $exitCode = $LASTEXITCODE
    $diagnostic = if (Test-Path -LiteralPath $errorPath) { Get-Content -LiteralPath $errorPath -Raw } else { '' }
    Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ ExitCode = $exitCode; Diagnostic = $diagnostic }
}
function Start-ProviderJson([string]$Json, [string]$SpoolRoot) {
    $info = [Diagnostics.ProcessStartInfo]::new($provider)
    $info.UseShellExecute = $false; $info.RedirectStandardInput = $true; $info.RedirectStandardError = $true
    $info.ArgumentList.Add('--spool-root'); $info.ArgumentList.Add($SpoolRoot)
    $process = [Diagnostics.Process]::Start($info)
    $stderr = $process.StandardError.ReadToEndAsync()
    $activeProviderProcesses.Add($process)
    $process.StandardInput.Write($Json); $process.StandardInput.Close()
    return [pscustomobject]@{ Process = $process; Stderr = $stderr }
}
function Wait-ProviderGroup([array]$Started) {
    $results = @()
    foreach ($entry in $Started) {
        try {
            $entry.Process.WaitForExit()
            $results += [pscustomobject]@{ ExitCode = $entry.Process.ExitCode; Diagnostic = $entry.Stderr.GetAwaiter().GetResult() }
        }
        finally {
            $null = $activeProviderProcesses.Remove($entry.Process)
            $entry.Process.Dispose()
        }
    }
    return $results
}
function Start-Runtime([string]$Executable, [string]$Payload) {
    $info = [Diagnostics.ProcessStartInfo]::new($Executable); $info.UseShellExecute = $false
    $info.ArgumentList.Add('dispatch'); $info.ArgumentList.Add($Payload)
    return [Diagnostics.Process]::Start($info)
}
function Set-RuntimeConfig([string]$RuntimeConfigRoot, [array]$Providers) {
    @{ target_markers = @(); chained_notify = @{ argv = @('ignored.exe') }; providers = $Providers } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RuntimeConfigRoot 'runtime-config.json') -Encoding utf8
}
function Assert-Item([string]$Path, [string]$ExpectedId, [string]$ExpectedResumeUri, [AllowNull()][object]$ExpectedResultUri) {
    $raw = Get-Content -LiteralPath $Path -Raw
    $item = $raw | ConvertFrom-Json
    $names = @($item.PSObject.Properties.Name)
    if ($names.Count -ne 10 -or $names -contains 'notification_status') { throw 'Spool item is not the stable 10-field contract.' }
    if ($item.source_event_id -ne $ExpectedId) { throw "Unexpected source_event_id in $Path" }
    if ($item.resume_uri -ne $ExpectedResumeUri) { throw "Unexpected resume_uri in $Path" }
    if ($null -eq $ExpectedResultUri) {
        if ($null -ne $item.result_uri -or $raw -notmatch '"result_uri"\s*:\s*null') { throw "result_uri was not exact JSON null in $Path" }
    } elseif ($item.result_uri -ne $ExpectedResultUri) { throw "Unexpected result_uri in $Path" }
    if (-not ($raw | Test-Json -SchemaFile $spoolSchema)) { throw 'Spool item did not validate against spool-item-v1.' }
}
function Assert-NoPublish([string]$SpoolRoot) {
    if (Test-Path -LiteralPath $SpoolRoot) {
        if (@(Get-ChildItem -LiteralPath $SpoolRoot -Force -File -ErrorAction SilentlyContinue).Count -ne 0) { throw "Invalid input left output in $SpoolRoot" }
    }
}
function Get-TreeDigest([string]$Path) {
    return (@(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName.Substring($Path.Length)):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) -join "`n")
}

$validationRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-notification-local-spool-' + [guid]::NewGuid().ToString('N'))
$activeProviderProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()
try {
    $build = Join-Path $validationRoot 'build'
    New-Item -ItemType Directory -Path $build | Out-Null
    Invoke-Checked { dotnet publish $runtimeSource --output (Join-Path $build 'runtime') --disable-build-servers } 'runtime publish'
    Invoke-Checked { dotnet publish $providerSource --output (Join-Path $build 'provider') --disable-build-servers } 'Local Spool provider publish'
    Invoke-Checked { dotnet publish $installerSource --output (Join-Path $build 'installer') --disable-build-servers } 'installer publish'
    $runtime = Join-Path $build 'runtime/codex-notification-runtime.exe'
    $provider = Join-Path $build 'provider/local-spool-provider.exe'
    $installer = Join-Path $build 'installer/install-codex-notification-runtime-local.exe'
    Invoke-Checked { & $runtime --self-test } 'runtime self-test'
    Invoke-Checked { & $provider --self-test } 'provider self-test'
    Invoke-Checked { & $installer --self-test } 'installer self-test'

    # VK-76-001 / TP-002: the provider consumes the exact 11-field event contract and fails closed before creating output.
    $invalidRoot = Join-Path $validationRoot 'invalid-input'
    $invalidCases = [Collections.Generic.List[string]]::new()
    $invalidCases.Add('{')
    $missingStatus = New-Event 'codex:invalid:missing-status'; $missingStatus.Remove('notification_status'); $invalidCases.Add(($missingStatus | ConvertTo-Json -Compress))
    $extra = New-Event 'codex:invalid:extra'; $extra.extra = 'not-allowed'; $invalidCases.Add(($extra | ConvertTo-Json -Compress))
    foreach ($mutation in @(
        @{ Name = 'schema_version'; Value = 2 }, @{ Name = 'source'; Value = 'other' }, @{ Name = 'source_event_id'; Value = 'codex:' },
        @{ Name = 'primary_process'; Value = ' ' }, @{ Name = 'observed_status'; Value = '' }, @{ Name = 'occurred_at'; Value = 'not-a-date' },
        @{ Name = 'title'; Value = '' }, @{ Name = 'repository'; Value = ' ' }, @{ Name = 'resume_uri'; Value = 'https://example.test/thread' },
        @{ Name = 'result_uri'; Value = 'https://github.com/owner/repository' }, @{ Name = 'notification_status'; Value = 'UNKNOWN' }
    )) {
        $event = New-Event "codex:invalid:$($mutation.Name)"; $event[$mutation.Name] = $mutation.Value; $invalidCases.Add(($event | ConvertTo-Json -Compress))
    }
    foreach ($json in $invalidCases) {
        $result = Invoke-ProviderJson $json $invalidRoot
        if ($result.ExitCode -ne 2 -or $result.Diagnostic -notmatch 'invalid-stdin') { throw 'Invalid provider stdin was not rejected with exit 2.' }
        Assert-NoPublish $invalidRoot
    }
    $validSchemaEvent = New-Event 'codex:schema:valid' 'https://github.com/openai/codex/issues/76'
    if (-not (($validSchemaEvent | ConvertTo-Json -Compress) | Test-Json -SchemaFile $eventSchema)) { throw 'Valid 11-field provider event did not match its schema.' }

    # VK-76-002 / TP-001: exact URI value and JSON-null projection.
    $projectionRoot = Join-Path $validationRoot 'projection'
    $valueEvent = New-Event 'codex:projection:value' 'https://github.com/openai/codex/issues/76'
    $nullEvent = New-Event 'codex:projection:null' $null
    foreach ($event in @($valueEvent, $nullEvent)) { $result = Invoke-ProviderJson ($event | ConvertTo-Json -Compress) $projectionRoot; if ($result.ExitCode -ne 0) { throw 'Valid projection failed.' } }
    $projectionItems = @(Get-ChildItem -LiteralPath $projectionRoot -Filter '*.json')
    Assert-Item ($projectionItems | Where-Object { (Get-Content $_ -Raw | ConvertFrom-Json).source_event_id -eq $valueEvent.source_event_id }).FullName $valueEvent.source_event_id $valueEvent.resume_uri $valueEvent.result_uri
    Assert-Item ($projectionItems | Where-Object { (Get-Content $_ -Raw | ConvertFrom-Json).source_event_id -eq $nullEvent.source_event_id }).FullName $nullEvent.source_event_id $nullEvent.resume_uri $null

    # VK-76-003 / TP-004, TP-005: distinct parallel, direct same-ID race, and immutable existing final.
    $distinctRoot = Join-Path $validationRoot 'distinct-parallel'
    $distinctEvents = 1..4 | ForEach-Object { New-Event "codex:distinct:$_" }
    $processes = @($distinctEvents | ForEach-Object { Start-ProviderJson ($_ | ConvertTo-Json -Compress) $distinctRoot })
    $distinctResults = @(Wait-ProviderGroup $processes)
    if (@($distinctResults | Where-Object { $_.ExitCode -ne 0 }).Count -ne 0) { throw 'Distinct-ID parallel provider failed.' }
    $distinctItems = @(Get-ChildItem -LiteralPath $distinctRoot -Filter '*.json')
    if ($distinctItems.Count -ne 4 -or @($distinctItems | ForEach-Object { (Get-Content $_ -Raw | ConvertFrom-Json).source_event_id } | Sort-Object -Unique).Count -ne 4) { throw 'Distinct-ID parallel events were not independently retained.' }
    $raceRoot = Join-Path $validationRoot 'same-id-race'; $raceEvent = New-Event 'codex:race:same'
    $processes = @(1..4 | ForEach-Object { Start-ProviderJson ($raceEvent | ConvertTo-Json -Compress) $raceRoot })
    $raceResults = @(Wait-ProviderGroup $processes)
    $raceFailures = @($raceResults | Where-Object { $_.ExitCode -ne 0 })
    if ($raceFailures.Count -ne 0) { throw "Same-ID provider race failed after all processes exited: $($raceFailures | ConvertTo-Json -Compress)" }
    $raceItems = @(Get-ChildItem -LiteralPath $raceRoot -Filter '*.json'); if ($raceItems.Count -ne 1) { throw 'Same-ID provider race did not converge to one final.' }
    $beforeReplay = (Get-FileHash -LiteralPath $raceItems[0].FullName -Algorithm SHA256).Hash
    $changedReplay = New-Event 'codex:race:same'; $changedReplay.title = 'must not replace existing final'
    $result = Invoke-ProviderJson ($changedReplay | ConvertTo-Json -Compress) $raceRoot
    if ($result.ExitCode -ne 0 -or (Get-FileHash -LiteralPath $raceItems[0].FullName -Algorithm SHA256).Hash -ne $beforeReplay) { throw 'Same-ID replay changed the existing final.' }

    # VK-76-004 / TP-006: 16/24/32/64 suffix expansion and terminal collision.
    $collisionEvent = New-Event 'codex:collision:target'; $collisionHash = Get-SourceHash $collisionEvent.source_event_id
    foreach ($expectedLength in @(24, 32, 64)) {
        $collisionRoot = Join-Path $validationRoot "collision-$expectedLength"; New-Item -ItemType Directory -Path $collisionRoot | Out-Null
        foreach ($length in @(16, 24, 32, 64) | Where-Object { $_ -lt $expectedLength }) {
            $occupied = New-SpoolItem "codex:occupied:${expectedLength}:$length"
            ($occupied | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $collisionRoot (Get-CandidateName $collisionEvent $length)) -Encoding utf8
        }
        $result = Invoke-ProviderJson ($collisionEvent | ConvertTo-Json -Compress) $collisionRoot
        if ($result.ExitCode -ne 0 -or $result.Diagnostic -notmatch 'filename-collision-disambiguated' -or -not (Test-Path -LiteralPath (Join-Path $collisionRoot (Get-CandidateName $collisionEvent $expectedLength)))) { throw "Hash suffix did not expand to $expectedLength." }
    }
    $terminalRoot = Join-Path $validationRoot 'collision-terminal'; New-Item -ItemType Directory -Path $terminalRoot | Out-Null
    foreach ($length in @(16, 24, 32, 64)) {
        $occupied = New-SpoolItem "codex:occupied:terminal:$length"
        ($occupied | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $terminalRoot (Get-CandidateName $collisionEvent $length)) -Encoding utf8
    }
    $terminalBefore = Get-TreeDigest $terminalRoot; $result = Invoke-ProviderJson ($collisionEvent | ConvertTo-Json -Compress) $terminalRoot
    if ($result.ExitCode -ne 3 -or $result.Diagnostic -notmatch 'identity-collision' -or (Get-TreeDigest $terminalRoot) -ne $terminalBefore) { throw 'Terminal hash collision did not preserve existing finals and exit 3.' }

    # VK-76-005 / TP-007: individual write, flush, and move failures.
    foreach ($stage in @('write', 'flush', 'move')) {
        $failureRoot = Join-Path $validationRoot "failure-$stage"; New-Item -ItemType Directory -Path $failureRoot | Out-Null
        $sentinel = New-SpoolItem "codex:sentinel:$stage"; ($sentinel | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $failureRoot 'sentinel.json') -Encoding utf8
        $sentinelHash = (Get-FileHash -LiteralPath (Join-Path $failureRoot 'sentinel.json') -Algorithm SHA256).Hash
        $env:CODEX_NOTIFICATION_TEST_PROVIDER_FAILURE = $stage
        $result = Invoke-ProviderJson ((New-Event "codex:failure:$stage") | ConvertTo-Json -Compress) $failureRoot
        Remove-Item Env:CODEX_NOTIFICATION_TEST_PROVIDER_FAILURE -ErrorAction SilentlyContinue
        if ($result.ExitCode -ne 3 -or $result.Diagnostic -notmatch 'publish-failed') { throw "$stage failure did not surface as exit 3." }
        if (@(Get-ChildItem -LiteralPath $failureRoot -Filter '*.json').Count -ne 1 -or @(Get-ChildItem -LiteralPath $failureRoot -Force -Filter '*.tmp').Count -ne 0 -or (Get-FileHash -LiteralPath (Join-Path $failureRoot 'sentinel.json') -Algorithm SHA256).Hash -ne $sentinelHash) { throw "$stage failure left output or changed the existing final." }
    }

    # VK-76-006 / TP-008: production nonzero and fake timeout both fail open, release claims, kill the tree, and retry through the real provider.
    $nonzeroHome = Join-Path $validationRoot 'runtime-nonzero'; New-Item -ItemType Directory -Path $nonzeroHome | Out-Null
    Set-RuntimeConfig $nonzeroHome @(@{ name = 'local-spool'; argv = @($provider); timeout_ms = 5000 })
    $env:CODEX_NOTIFICATION_RUNTIME_HOME = $nonzeroHome; $env:CODEX_NOTIFICATION_TEST_PROVIDER_FAILURE = 'move'
    $retryPayload = New-Payload 'retry-after-nonzero'; & $runtime dispatch $retryPayload
    if ($LASTEXITCODE -ne 0 -or @(Get-ChildItem (Join-Path $nonzeroHome 'state') -Filter '*.claim').Count -ne 0 -or (Get-Content (Join-Path $nonzeroHome 'runtime.log.jsonl') -Raw) -notmatch 'provider-exit') { throw 'Production provider nonzero did not fail open and release its claim.' }
    Remove-Item Env:CODEX_NOTIFICATION_TEST_PROVIDER_FAILURE -ErrorAction SilentlyContinue
    Invoke-Checked { & $runtime dispatch $retryPayload } 'real provider retry after nonzero'
    if (@(Get-ChildItem (Join-Path $nonzeroHome 'spool') -Filter '*.json').Count -ne 1) { throw 'Retry after production nonzero did not create exactly one final.' }

    $timeoutHome = Join-Path $validationRoot 'runtime-timeout'; New-Item -ItemType Directory -Path $timeoutHome | Out-Null
    Set-RuntimeConfig $timeoutHome @(@{ name = 'local-spool'; argv = @((Get-Command pwsh).Source, '-NoProfile', '-File', $fakeProvider, 'provider'); timeout_ms = 1000 })
    $fakeOutput = Join-Path $timeoutHome 'fake-output.jsonl'; $childOutput = Join-Path $timeoutHome 'child-output.txt'
    $env:CODEX_NOTIFICATION_RUNTIME_HOME = $timeoutHome; $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT = $fakeOutput; $env:CODEX_NOTIFICATION_TEST_PROVIDER_DELAY_MS = '10000'; $env:CODEX_NOTIFICATION_TEST_PROVIDER_CHILD_OUTPUT = $childOutput
    $timeoutPayload = New-Payload 'retry-after-timeout'; & $runtime dispatch $timeoutPayload
    if ($LASTEXITCODE -ne 0 -or @(Get-ChildItem (Join-Path $timeoutHome 'state') -Filter '*.claim').Count -ne 0 -or (Get-Content (Join-Path $timeoutHome 'runtime.log.jsonl') -Raw) -notmatch 'provider-timeout') { throw 'Provider timeout did not fail open and release its claim.' }
    Start-Sleep -Milliseconds 3000
    if (Test-Path -LiteralPath $childOutput) { throw 'Timed-out provider child process survived the process-tree kill.' }
    Remove-Item Env:CODEX_NOTIFICATION_TEST_PROVIDER_DELAY_MS, Env:CODEX_NOTIFICATION_TEST_PROVIDER_CHILD_OUTPUT -ErrorAction SilentlyContinue
    Set-RuntimeConfig $timeoutHome @(@{ name = 'local-spool'; argv = @($provider); timeout_ms = 5000 })
    Invoke-Checked { & $runtime dispatch $timeoutPayload } 'real provider retry after timeout'
    if (@(Get-ChildItem (Join-Path $timeoutHome 'spool') -Filter '*.json').Count -ne 1) { throw 'Retry after timeout did not create exactly one final.' }

    # VK-76-007 / TP-009: zero and multiple provider configurations never start a provider.
    $gateHome = Join-Path $validationRoot 'provider-gate'; New-Item -ItemType Directory -Path $gateHome | Out-Null
    $env:CODEX_NOTIFICATION_RUNTIME_HOME = $gateHome; $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT = Join-Path $gateHome 'must-not-start.jsonl'; $env:CODEX_NOTIFICATION_TEST_PROVIDER_DELAY_MS = '0'
    $fakeSpec = @{ name = 'local-spool'; argv = @((Get-Command pwsh).Source, '-NoProfile', '-File', $fakeProvider, 'provider'); timeout_ms = 5000 }
    Set-RuntimeConfig $gateHome @(); Invoke-Checked { & $runtime dispatch (New-Payload 'zero-provider') } 'zero provider fail-open'
    Set-RuntimeConfig $gateHome @($fakeSpec, $fakeSpec); Invoke-Checked { & $runtime dispatch (New-Payload 'multiple-provider') } 'multiple provider fail-open'
    if ((Test-Path -LiteralPath $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT) -or @((Get-Content (Join-Path $gateHome 'runtime.log.jsonl')) | Where-Object { $_ -match 'invalid-provider-count' }).Count -lt 2) { throw 'Zero/multiple provider gate started a provider or omitted diagnostics.' }

    # VK-76-007 / TP-010, TP-011, TP-013: fresh/reinstall/legacy update, rollback matrix, and installed production path.
    $codexHome = Join-Path $validationRoot 'codex-home'; $installRoot = Join-Path $validationRoot 'install-root'; New-Item -ItemType Directory -Path $codexHome | Out-Null
    Set-Content -LiteralPath (Join-Path $codexHome 'config.toml') 'model_provider = "openai"' -NoNewline
    Invoke-Checked { & $installer install --codex-home $codexHome --install-root $installRoot } 'Local Spool fresh install'
    Invoke-Checked { & $installer --check --codex-home $codexHome --install-root $installRoot } 'Local Spool fresh install check'
    $backup = Join-Path $codexHome 'config.toml.codex-notification-runtime.bak'; $backupHash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
    Invoke-Checked { & $installer install --codex-home $codexHome --install-root $installRoot } 'Local Spool reinstall'
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $backupHash) { throw 'Reinstall overwrote the protected original backup.' }
    $installed = Get-Content -LiteralPath (Join-Path $installRoot 'runtime-config.json') -Raw | ConvertFrom-Json
    if (@($installed.providers).Count -ne 1 -or $installed.providers[0].name -ne 'local-spool' -or $installed.providers[0].timeout_ms -ne 5000 -or (Test-Path (Join-Path $installRoot 'bin/windows-app-notification-provider.exe'))) { throw 'Installer did not bind exactly one Local Spool provider.' }
    $installedRuntime = Join-Path $installRoot 'bin/codex-notification-runtime.exe'; $env:CODEX_NOTIFICATION_RUNTIME_HOME = $installRoot
    Invoke-Checked { & $installedRuntime dispatch (New-Payload 'installed-production' 'https://github.com/openai/codex/issues/76') } 'installed runtime to provider callback'
    $installedItems = @(Get-ChildItem -LiteralPath (Join-Path $installRoot 'spool') -Filter '*.json'); if ($installedItems.Count -ne 1) { throw 'Installed production entrypoint did not create exactly one real filesystem final.' }
    Assert-Item $installedItems[0].FullName 'codex:fixture-thread:installed-production' 'codex://threads/fixture-thread' 'https://github.com/openai/codex/issues/76'

    $legacyCodex = Join-Path $validationRoot 'legacy-codex'; $legacyInstall = Join-Path $validationRoot 'legacy-install'; New-Item -ItemType Directory -Path $legacyCodex, (Join-Path $legacyInstall 'bin') | Out-Null
    $legacyNotify = Join-Path $legacyInstall 'bin/windows-app-notification-provider.exe'; Set-Content -LiteralPath $legacyNotify 'legacy'
    Set-Content -LiteralPath (Join-Path $legacyCodex 'config.toml') "notify = [ `"$($legacyNotify.Replace('\','\\'))`" ]" -NoNewline
    @{ providers = @(@{ name = 'windows-app'; argv = @($legacyNotify); timeout_ms = 5000 }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $legacyInstall 'runtime-config.json') -Encoding utf8
    Invoke-Checked { & $installer install --codex-home $legacyCodex --install-root $legacyInstall } 'legacy Windows provider update'
    $legacyUpdated = Get-Content -LiteralPath (Join-Path $legacyInstall 'runtime-config.json') -Raw | ConvertFrom-Json
    if (@($legacyUpdated.providers).Count -ne 1 -or $legacyUpdated.providers[0].name -ne 'local-spool' -or (Test-Path (Join-Path $legacyInstall 'bin/windows-app-notification-provider.exe'))) { throw 'Legacy update did not replace the production provider with Local Spool.' }

    foreach ($failureStage in @('stage', 'self-test', 'bin-swap', 'config-swap')) {
        $beforeBin = Get-TreeDigest (Join-Path $installRoot 'bin'); $beforeConfig = (Get-FileHash -LiteralPath (Join-Path $installRoot 'runtime-config.json') -Algorithm SHA256).Hash; $beforeUser = (Get-FileHash -LiteralPath (Join-Path $codexHome 'config.toml') -Algorithm SHA256).Hash
        $env:CODEX_NOTIFICATION_TEST_INSTALL_FAILURE = $failureStage
        & $installer install --codex-home $codexHome --install-root $installRoot 2>$null
        if ($LASTEXITCODE -eq 0) { throw "Injected installer $failureStage failure unexpectedly succeeded." }
        Remove-Item Env:CODEX_NOTIFICATION_TEST_INSTALL_FAILURE -ErrorAction SilentlyContinue
        if ((Get-TreeDigest (Join-Path $installRoot 'bin')) -ne $beforeBin -or (Get-FileHash -LiteralPath (Join-Path $installRoot 'runtime-config.json') -Algorithm SHA256).Hash -ne $beforeConfig -or (Get-FileHash -LiteralPath (Join-Path $codexHome 'config.toml') -Algorithm SHA256).Hash -ne $beforeUser) { throw "Installer $failureStage failure did not restore bin/config/user state." }
    }

    Write-Host 'PASS codex notification Local Spool validation (VK-76-001..007, VK-76-009 automated scope)'
}
finally {
    Remove-Item Env:CODEX_NOTIFICATION_RUNTIME_HOME, Env:CODEX_NOTIFICATION_SPOOL_HOME, Env:CODEX_NOTIFICATION_TEST_PROVIDER_FAILURE, Env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT, Env:CODEX_NOTIFICATION_TEST_PROVIDER_DELAY_MS, Env:CODEX_NOTIFICATION_TEST_PROVIDER_CHILD_OUTPUT, Env:CODEX_NOTIFICATION_TEST_INSTALL_FAILURE, Env:CODEX_NOTIFICATION_TEST_FAIL_AFTER_BIN_SWAP -ErrorAction SilentlyContinue
    foreach ($process in @($activeProviderProcesses)) {
        try {
            if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
            $process.Dispose()
        } catch { }
    }
    if (Test-Path -LiteralPath $validationRoot) { Remove-Item -LiteralPath $validationRoot -Recurse -Force }
}
