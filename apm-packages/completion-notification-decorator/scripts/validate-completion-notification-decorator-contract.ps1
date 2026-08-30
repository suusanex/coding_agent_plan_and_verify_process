[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repositoryRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$assetRoot = Join-Path $packageRoot '.apm/skills/completion-notification-decorator/assets/codex-notification-runtime'
$runtimeSource = Join-Path $assetRoot 'codex-notification-runtime.cs'
$providerSource = Join-Path $assetRoot 'local-spool-provider.cs'
$envelopeSchema = Join-Path $assetRoot 'completion-notification-envelope-v1.schema.json'
$fixturePath = Join-Path $packageRoot 'tests/integration-fixtures.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Contains([string]$Path, [string]$Literal, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $failures.Add("Missing file for ${Description}: $Path"); return }
    if (-not (Get-Content -Raw -LiteralPath $Path).Contains($Literal, [StringComparison]::Ordinal)) { $failures.Add("$Path does not contain $Description") }
}

function Assert-NotContains([string]$Path, [string]$Literal, [string]$Description) {
    if ((Test-Path -LiteralPath $Path -PathType Leaf) -and (Get-Content -Raw -LiteralPath $Path).Contains($Literal, [StringComparison]::Ordinal)) { $failures.Add("$Path still contains $Description") }
}

function Get-ContractFailures([object]$Fixture) {
    $primaryProcess = [string]$Fixture.primary_process
    $status = [string]$Fixture.observed_status
    $package = Join-Path $repositoryRoot "apm-packages/$primaryProcess"
    $manifest = Join-Path $package 'apm.yml'
    $skill = Join-Path $package ".apm/skills/$primaryProcess/SKILL.md"
    $result = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { $result.Add("missing manifest") }
    if (-not (Test-Path -LiteralPath $skill -PathType Leaf)) { $result.Add("missing skill") }
    if ((Test-Path -LiteralPath $manifest) -and -not (Get-Content -Raw $manifest).Contains("name: $primaryProcess", [StringComparison]::Ordinal)) { $result.Add('manifest name mismatch') }
    if ((Test-Path -LiteralPath $skill) -and -not (Get-Content -Raw $skill).Contains("name: $primaryProcess", [StringComparison]::Ordinal)) { $result.Add('skill name mismatch') }
    if ([string]::IsNullOrWhiteSpace($status) -or (Test-Path -LiteralPath $skill) -and -not ([regex]::IsMatch((Get-Content -Raw $skill), '(?<![A-Z0-9_])' + [regex]::Escape($status) + '(?![A-Z0-9_])'))) { $result.Add('status is not a canonical verdict token') }
    if (@($Fixture.primary_output -split '\r?\n', 2)[0] -cne "Verdict: $status") { $result.Add('primary output changed verdict prefix') }
    return $result
}

$requiredFiles = @(
    'apm.yml', 'README.md', '.apm/skills/completion-notification-decorator/SKILL.md',
    '.apm/skills/completion-notification-decorator/agents/openai.yaml',
    '.apm/skills/completion-notification-decorator/references/envelope-authoring-contract.md',
    'docs/usage-guide.md', 'docs/examples/integration-validation.md', 'tests/integration-fixtures.json',
    '.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/README.md',
    '.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/codex-notification-runtime.cs',
    '.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/local-spool-provider.cs',
    '.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/completion-notification-envelope-v1.schema.json',
    '.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/completion-notification-event-v1.schema.json',
    '.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/spool-item-v1.schema.json'
)
foreach ($relativePath in $requiredFiles) { if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relativePath) -PathType Leaf)) { $failures.Add("Missing package file: $relativePath") } }

$manifestPath = Join-Path $packageRoot 'apm.yml'
$skillPath = Join-Path $packageRoot '.apm/skills/completion-notification-decorator/SKILL.md'
$openAiPath = Join-Path $packageRoot '.apm/skills/completion-notification-decorator/agents/openai.yaml'
$contractPath = Join-Path $packageRoot '.apm/skills/completion-notification-decorator/references/envelope-authoring-contract.md'
Assert-Contains $manifestPath 'name: completion-notification-decorator' 'canonical package name'
Assert-Contains $manifestPath 'version: 0.2.1' 'package version'
Assert-Contains $skillPath 'exactly one explicitly co-selected Codex primary process' 'explicit single-primary trigger'
Assert-Contains $skillPath 'Do not select, start, route, reproduce, or replace that process.' 'non-orchestrator boundary'
Assert-Contains $skillPath 'Preserve its terminal verdict vocabulary exactly.' 'verdict preservation rule'
Assert-Contains $skillPath 'append exactly one `completion-notification` fenced block' 'single envelope rule'
Assert-Contains $skillPath 'ordinary notifications do not require this Skill' 'optional enrichment boundary'
Assert-Contains $skillPath 'omit the envelope' 'fallback authoring rule'
Assert-Contains $openAiPath 'allow_implicit_invocation: false' 'explicit-only invocation policy'
Assert-Contains $contractPath 'The runtime generates `resume_uri`' 'runtime-owned resume link rule'
Assert-Contains $contractPath 'Local Spool' 'Local Spool persistence boundary'
Assert-NotContains $contractPath 'both a result action and a current-task action' 'obsolete dual-button contract'
Assert-NotContains (Join-Path $packageRoot 'docs/usage-guide.md') 'two actions' 'obsolete dual-action wording'

$customAgents = Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Where-Object { $_.Name.EndsWith('.agent.md', [StringComparison]::OrdinalIgnoreCase) -or $_.Extension -eq '.toml' }
if ($customAgents) { $failures.Add('Decorator package must not contain custom agents or TOML profiles.') }

$fixtures = @(Get-Content -Raw $fixturePath | ConvertFrom-Json)
if ($fixtures.Count -lt 2 -or @($fixtures.primary_process | Sort-Object -Unique).Count -lt 2) { $failures.Add('Integration fixtures must cover at least two primary processes.') }
foreach ($requiredProcess in @('adaptive-implementation-execution', 'plan-coverage-residual-flow')) { if (@($fixtures | Where-Object { $_.primary_process -ceq $requiredProcess }).Count -lt 1) { $failures.Add("Missing integration fixture for $requiredProcess") } }
foreach ($fixture in $fixtures) { $fixtureFailures = @(Get-ContractFailures $fixture); if ($fixtureFailures.Count -gt 0) { $failures.Add("Fixture $($fixture.id): $($fixtureFailures -join ', ')") } }

$negative = @(
    [pscustomobject]@{ id = 'missing-process'; primary_process = 'not-a-real-primary-process'; observed_status = 'NOT_A_REAL_VERDICT'; primary_output = 'Verdict: NOT_A_REAL_VERDICT' },
    [pscustomobject]@{ id = 'invalid-verdict'; primary_process = 'adaptive-implementation-execution'; observed_status = 'NOT_A_REAL_VERDICT'; primary_output = 'Verdict: NOT_A_REAL_VERDICT' },
    [pscustomobject]@{ id = 'mismatched-output'; primary_process = 'adaptive-implementation-execution'; observed_status = 'IMPLEMENTATION_COMPLETED'; primary_output = 'Verdict: READY_TO_CLOSE' }
)
foreach ($fixture in $negative) { if (@(Get-ContractFailures $fixture).Count -eq 0) { $failures.Add("Negative fixture unexpectedly passed: $($fixture.id)") } }

if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Error $_ }; exit 1 }

$validationRoot = Join-Path ([IO.Path]::GetTempPath()) ('completion-notification-contract-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $validationRoot | Out-Null
    $runtimeBin = Join-Path $validationRoot 'runtime'; $providerBin = Join-Path $validationRoot 'provider'; New-Item -ItemType Directory -Path $runtimeBin, $providerBin | Out-Null
    dotnet publish $runtimeSource --output $runtimeBin --disable-build-servers; if ($LASTEXITCODE -ne 0) { throw 'Runtime publish failed.' }; $global:LASTEXITCODE = 0
    dotnet publish $providerSource --output $providerBin --disable-build-servers; if ($LASTEXITCODE -ne 0) { throw 'Provider publish failed.' }; $global:LASTEXITCODE = 0
    $runtimeExe = Join-Path $runtimeBin 'codex-notification-runtime.exe'; $providerExe = Join-Path $providerBin 'local-spool-provider.exe'
    & $runtimeExe --self-test; if ($LASTEXITCODE -ne 0) { throw 'Runtime self-test failed.' }; $global:LASTEXITCODE = 0
    $runtimeHome = Join-Path $validationRoot 'runtime-home'; $spool = Join-Path $runtimeHome 'spool'; New-Item -ItemType Directory -Path $runtimeHome | Out-Null
    @{ target_markers = @(); chained_notify = $null; providers = @(@{ name = 'local-spool'; argv = @($providerExe); timeout_ms = 5000 }) } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $runtimeHome 'runtime-config.json') -Encoding utf8
    $env:CODEX_NOTIFICATION_RUNTIME_HOME = $runtimeHome
    $events = @()
    $index = 0
    foreach ($fixture in $fixtures) {
        $index++
        $tokens = [regex]::Matches($fixture.input_message, '(?m)^\$(?<name>[a-z0-9-]+)\s*$') | ForEach-Object { $_.Groups['name'].Value }
        $primaryTokens = @($tokens | Where-Object { $_ -ne 'completion-notification-decorator' })
        if ($primaryTokens.Count -ne 1 -or $primaryTokens[0] -cne $fixture.primary_process) { throw "Fixture $($fixture.id) must explicitly select exactly its declared primary process." }
        $envelope = [ordered]@{ schema_version = 1; primary_process = $fixture.primary_process; observed_status = $fixture.observed_status; title = $fixture.title; repository = $fixture.repository; result_uri = $fixture.result_uri } | ConvertTo-Json -Compress
        if (-not ($envelope | Test-Json -SchemaFile $envelopeSchema)) { throw "Fixture $($fixture.id) envelope schema validation failed." }
        $assistant = "$($fixture.primary_output)`n`n``````completion-notification`n$envelope`n``````"
        if (-not $assistant.StartsWith($fixture.primary_output, [StringComparison]::Ordinal)) { throw "Fixture $($fixture.id) changed primary output." }
        $payload = @{ type = 'agent-turn-complete'; 'thread-id' = "fixture-thread-$index"; 'turn-id' = "fixture-turn-$index"; cwd = $repositoryRoot; 'input-messages' = @($fixture.input_message); 'last-assistant-message' = $assistant } | ConvertTo-Json -Compress -Depth 6
        & $runtimeExe dispatch $payload; if ($LASTEXITCODE -ne 0) { throw "Fixture $($fixture.id) callback failed." }; $global:LASTEXITCODE = 0
        $itemFile = Get-ChildItem -LiteralPath $spool -Filter '*.json' | Sort-Object LastWriteTime | Select-Object -Last 1; $item = Get-Content -Raw $itemFile.FullName | ConvertFrom-Json
        if ($item.primary_process -ne $fixture.primary_process -or $item.observed_status -ne $fixture.observed_status -or $item.repository -ne $fixture.repository -or $item.result_uri -ne $fixture.result_uri) { throw "Fixture $($fixture.id) did not preserve decorator metadata." }
        $events += $item
    }
    if (@($events.repository | Sort-Object -Unique).Count -lt 2) { throw 'Multiple repository identity was not preserved.' }
    $genericPayload = @{ type = 'agent-turn-complete'; 'thread-id' = 'generic-thread'; 'turn-id' = 'generic-turn'; cwd = $repositoryRoot; 'input-messages' = @('ordinary task'); 'last-assistant-message' = 'plain response' } | ConvertTo-Json -Compress -Depth 6
    & $runtimeExe dispatch $genericPayload; if ($LASTEXITCODE -ne 0) { throw 'Generic callback failed.' }; $global:LASTEXITCODE = 0
    $generic = Get-ChildItem -LiteralPath $spool -Filter '*.json' | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Raw | ConvertFrom-Json
    if ($generic.primary_process -ne 'codex' -or $generic.observed_status -ne 'TURN_ENDED') { throw 'Generic callback contract failed.' }
    $invalidPayload = @{ type = 'agent-turn-complete'; 'thread-id' = 'invalid-envelope-thread'; 'turn-id' = 'invalid-envelope-turn'; cwd = $repositoryRoot; 'input-messages' = @('ordinary task'); 'last-assistant-message' = "``````completion-notification`n{invalid}`n``````" } | ConvertTo-Json -Compress -Depth 6
    & $runtimeExe dispatch $invalidPayload; if ($LASTEXITCODE -ne 0) { throw 'Invalid envelope changed callback exit code.' }; $global:LASTEXITCODE = 0
    $fallback = Get-ChildItem -LiteralPath $spool -Filter '*.json' | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Raw | ConvertFrom-Json
    if ($fallback.primary_process -ne 'codex' -or $fallback.observed_status -ne 'TURN_ENDED' -or $null -ne $fallback.result_uri) { throw 'Invalid envelope fallback contract failed.' }
    $failurePayload = @{ type = 'agent-turn-complete'; 'thread-id' = 'failure-thread'; 'turn-id' = 'failure-turn'; cwd = $repositoryRoot; 'input-messages' = @('ordinary task'); 'last-assistant-message' = 'provider failure probe' } | ConvertTo-Json -Compress -Depth 6
    $fakeOutput = Join-Path $validationRoot 'fake-provider-output.jsonl'
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_EXIT = '9'; $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT = $fakeOutput
    @{ target_markers = @(); chained_notify = $null; providers = @(@{ name = 'local-spool'; argv = @((Get-Process -Id $PID).Path, '-NoProfile', '-File', (Join-Path $repositoryRoot 'scripts/codex-notification-runtime/tests/fake-notification-command.ps1'), '-Mode', 'provider'); timeout_ms = 5000 }) } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $runtimeHome 'runtime-config.json') -Encoding utf8
    & $runtimeExe dispatch $failurePayload; if ($LASTEXITCODE -ne 0) { throw 'Provider failure changed primary callback exit code.' }; $global:LASTEXITCODE = 0
    $lastLog = Get-Content -LiteralPath (Join-Path $runtimeHome 'runtime.log.jsonl') | Select-Object -Last 1 | ConvertFrom-Json
    if ($lastLog.status -ne 'failed') { throw 'Provider failure was not recorded separately from the primary callback result.' }
    Write-Output "Completion Notification Decorator contract validation: PASS ($($fixtures.Count) fixtures, primary/verdict preservation, generic fallback, invalid envelope fallback, multi-repository identity, provider fail-open)"
}
finally {
    Remove-Item Env:CODEX_NOTIFICATION_RUNTIME_HOME, Env:CODEX_NOTIFICATION_TEST_PROVIDER_EXIT, Env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $validationRoot) { Remove-Item -LiteralPath $validationRoot -Recurse -Force }
    $global:LASTEXITCODE = 0
}
