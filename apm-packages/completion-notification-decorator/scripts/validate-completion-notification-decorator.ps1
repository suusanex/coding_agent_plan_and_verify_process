[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repositoryRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$runtimeSource = Join-Path $repositoryRoot 'scripts/codex-notification-runtime/codex-notification-runtime.cs'
$runtimeInstaller = Join-Path $repositoryRoot 'scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs'
$envelopeSchema = Join-Path $repositoryRoot 'scripts/codex-notification-runtime/completion-notification-envelope-v1.schema.json'
$fakeProvider = Join-Path $repositoryRoot 'scripts/codex-notification-runtime/tests/fake-notification-command.ps1'
$fixturePath = Join-Path $packageRoot 'tests/integration-fixtures.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Assert-Contains([string]$Path, [string]$Literal, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing file for ${Description}: $Path"
        return
    }
    if (-not (Get-Content -Raw -LiteralPath $Path).Contains($Literal, [StringComparison]::Ordinal)) {
        Add-Failure "$Path does not contain $Description"
    }
}

function Get-CanonicalFixtureContractFailures([object]$Fixture, [string]$RepositoryRoot) {
    $fixtureId = [string]$Fixture.id
    $primaryProcess = [string]$Fixture.primary_process
    $observedStatus = [string]$Fixture.observed_status
    $primaryOutput = [string]$Fixture.primary_output

    if ([string]::IsNullOrWhiteSpace($primaryProcess) -or $primaryProcess -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        Write-Output "Fixture $fixtureId has an invalid primary_process package name: $primaryProcess"
        return
    }

    $canonicalPackageRoot = Join-Path $RepositoryRoot "apm-packages/$primaryProcess"
    $canonicalManifestPath = Join-Path $canonicalPackageRoot 'apm.yml'
    $canonicalSkillPath = Join-Path $canonicalPackageRoot ".apm/skills/$primaryProcess/SKILL.md"

    if (-not (Test-Path -LiteralPath $canonicalManifestPath -PathType Leaf)) {
        Write-Output "Fixture $fixtureId cannot resolve canonical manifest for ${primaryProcess}: $canonicalManifestPath"
    }
    else {
        $manifestText = Get-Content -Raw -LiteralPath $canonicalManifestPath
        $manifestName = [regex]::Match($manifestText, '(?m)^name:\s*(?<name>[^\r\n#]+?)\s*$')
        if (-not $manifestName.Success -or $manifestName.Groups['name'].Value -cne $primaryProcess) {
            Write-Output "Fixture $fixtureId primary_process does not match the canonical manifest name: $primaryProcess"
        }
    }

    if (-not (Test-Path -LiteralPath $canonicalSkillPath -PathType Leaf)) {
        Write-Output "Fixture $fixtureId cannot resolve canonical Skill for ${primaryProcess}: $canonicalSkillPath"
    }
    else {
        $canonicalSkillText = Get-Content -Raw -LiteralPath $canonicalSkillPath
        $canonicalFrontmatter = [regex]::Match($canonicalSkillText, '\A---\r?\n(?<body>.*?)\r?\n---', [Text.RegularExpressions.RegexOptions]::Singleline)
        $canonicalSkillName = if ($canonicalFrontmatter.Success) {
            [regex]::Match($canonicalFrontmatter.Groups['body'].Value, '(?m)^name:\s*(?<name>[^\r\n#]+?)\s*$')
        }
        else {
            [Text.RegularExpressions.Match]::Empty
        }
        if (-not $canonicalSkillName.Success -or $canonicalSkillName.Groups['name'].Value -cne $primaryProcess) {
            Write-Output "Fixture $fixtureId primary_process does not match the canonical Skill name: $primaryProcess"
        }

        $verdictTokenPattern = '(?<![A-Z0-9_])' + [regex]::Escape($observedStatus) + '(?![A-Z0-9_])'
        if ([string]::IsNullOrWhiteSpace($observedStatus) -or
            -not [regex]::IsMatch($canonicalSkillText, $verdictTokenPattern)) {
            Write-Output "Fixture $fixtureId observed_status is not a canonical verdict token for ${primaryProcess}: $observedStatus"
        }
    }

    $firstOutputLine = @($primaryOutput -split '\r?\n', 2)[0]
    if ($firstOutputLine -cne "Verdict: $observedStatus") {
        Write-Output "Fixture $fixtureId primary_output must start with the exact canonical verdict line: Verdict: $observedStatus"
    }
}

$requiredFiles = @(
    'apm.yml',
    'README.md',
    '.apm/skills/completion-notification-decorator/SKILL.md',
    '.apm/skills/completion-notification-decorator/agents/openai.yaml',
    '.apm/skills/completion-notification-decorator/references/envelope-authoring-contract.md',
    'docs/usage-guide.md',
    'docs/examples/integration-validation.md',
    'tests/integration-fixtures.json'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relativePath) -PathType Leaf)) {
        Add-Failure "Missing package file: $relativePath"
    }
}

$manifestPath = Join-Path $packageRoot 'apm.yml'
$skillPath = Join-Path $packageRoot '.apm/skills/completion-notification-decorator/SKILL.md'
$openAiPath = Join-Path $packageRoot '.apm/skills/completion-notification-decorator/agents/openai.yaml'
$contractPath = Join-Path $packageRoot '.apm/skills/completion-notification-decorator/references/envelope-authoring-contract.md'

Assert-Contains $manifestPath 'name: completion-notification-decorator' 'canonical package name'
Assert-Contains $manifestPath 'version: 0.1.0' 'package version'
Assert-Contains $manifestPath '  - codex' 'Codex target'
Assert-Contains $manifestPath '  - agent-skills' 'agent-skills target'
Assert-Contains $skillPath 'name: completion-notification-decorator' 'canonical Skill name'
Assert-Contains $skillPath 'exactly one explicitly co-selected Codex primary process' 'explicit single-primary trigger'
Assert-Contains $skillPath 'Do not select, start, route, reproduce, or replace that process.' 'non-orchestrator boundary'
Assert-Contains $skillPath 'Preserve its terminal verdict vocabulary exactly.' 'verdict preservation rule'
Assert-Contains $skillPath 'append exactly one `completion-notification` fenced block' 'single envelope rule'
Assert-Contains $skillPath 'omit the envelope' 'fallback authoring rule'
Assert-Contains $openAiPath 'allow_implicit_invocation: false' 'explicit-only invocation policy'
Assert-Contains $contractPath 'The runtime generates `resume_uri`' 'runtime-owned resume link rule'

$skillText = if (Test-Path $skillPath) { Get-Content -Raw $skillPath } else { '' }
$frontmatter = [regex]::Match($skillText, '\A---\r?\n(?<body>.*?)\r?\n---', [Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $frontmatter.Success) {
    Add-Failure 'SKILL.md frontmatter is missing or malformed.'
}
else {
    $frontmatterKeys = [regex]::Matches($frontmatter.Groups['body'].Value, '(?m)^(?<key>[A-Za-z0-9_-]+):') | ForEach-Object { $_.Groups['key'].Value }
    if (@($frontmatterKeys).Count -ne 2 -or 'name' -notin $frontmatterKeys -or 'description' -notin $frontmatterKeys) {
        Add-Failure 'SKILL.md frontmatter must contain only name and description.'
    }
}

$customAgents = Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Where-Object {
    $_.Name.EndsWith('.agent.md', [StringComparison]::OrdinalIgnoreCase) -or $_.Extension -eq '.toml'
}
if ($customAgents) {
    Add-Failure ('Decorator package must not contain custom agents or TOML profiles: ' + (($customAgents.FullName) -join ', '))
}

if (-not (Test-Path -LiteralPath $runtimeSource -PathType Leaf) -or
    -not (Test-Path -LiteralPath $runtimeInstaller -PathType Leaf) -or
    -not (Test-Path -LiteralPath $envelopeSchema -PathType Leaf)) {
    Add-Failure 'Canonical notification runtime assets are not resolvable from the repository root.'
}
else {
    $schema = Get-Content -Raw $envelopeSchema | ConvertFrom-Json
    if ($schema.properties.schema_version.const -ne 1 -or
        'primary_process' -notin @($schema.required) -or
        'observed_status' -notin @($schema.required)) {
        Add-Failure 'Canonical envelope schema does not match the decorator authoring contract.'
    }
    $installerText = Get-Content -Raw $runtimeInstaller
    if (-not $installerText.Contains('$completion-notification-decorator', [StringComparison]::Ordinal) -or
        -not $installerText.Contains('[completion-notification]', [StringComparison]::Ordinal)) {
        Add-Failure 'Canonical runtime installer does not configure both decorator fallback markers.'
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

$fixtures = @(Get-Content -Raw $fixturePath | ConvertFrom-Json)
if ($fixtures.Count -lt 2) {
    throw 'At least two primary-process integration fixtures are required.'
}
if (@($fixtures.primary_process | Sort-Object -Unique).Count -lt 2) {
    throw 'Integration fixtures must cover at least two distinct primary processes.'
}

$requiredPrimaryProcesses = @('adaptive-implementation-execution', 'plan-coverage-residual-flow')
foreach ($requiredPrimaryProcess in $requiredPrimaryProcesses) {
    if (@($fixtures | Where-Object { $_.primary_process -ceq $requiredPrimaryProcess }).Count -lt 1) {
        throw "Integration fixtures must contain at least one canonical fixture for primary process: $requiredPrimaryProcess"
    }
}

foreach ($fixture in $fixtures) {
    $contractFailures = @(Get-CanonicalFixtureContractFailures $fixture $repositoryRoot)
    if ($contractFailures.Count -gt 0) {
        throw ($contractFailures -join [Environment]::NewLine)
    }
}

$negativeContractFixtures = @(
    [pscustomobject]@{
        id = 'missing-process-self-test'
        primary_process = 'not-a-real-primary-process'
        observed_status = 'NOT_A_REAL_VERDICT'
        primary_output = 'Verdict: NOT_A_REAL_VERDICT'
    },
    [pscustomobject]@{
        id = 'invalid-verdict-self-test'
        primary_process = 'adaptive-implementation-execution'
        observed_status = 'NOT_A_REAL_VERDICT'
        primary_output = 'Verdict: NOT_A_REAL_VERDICT'
    },
    [pscustomobject]@{
        id = 'mismatched-output-self-test'
        primary_process = 'adaptive-implementation-execution'
        observed_status = 'COMPLETED_BY_HIGH_MODEL'
        primary_output = 'Verdict: READY_TO_CLOSE'
    }
)
foreach ($negativeFixture in $negativeContractFixtures) {
    if (@(Get-CanonicalFixtureContractFailures $negativeFixture $repositoryRoot).Count -eq 0) {
        throw "Canonical fixture validation negative self-test unexpectedly passed: $($negativeFixture.id)"
    }
}

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$validationRoot = Join-Path $tempRoot ('completion-notification-decorator-' + [guid]::NewGuid().ToString('N'))
$resolvedValidationRoot = $null
$safeToDelete = $false

try {
    $null = New-Item -ItemType Directory -Path $validationRoot
    $resolvedValidationRoot = (Resolve-Path -LiteralPath $validationRoot).Path
    if (-not $resolvedValidationRoot.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use validation root outside the system temporary directory: $resolvedValidationRoot"
    }
    $safeToDelete = $true

    $publishRoot = Join-Path $resolvedValidationRoot 'runtime-bin'
    & dotnet publish $runtimeSource --output $publishRoot '-p:AssemblyName=completion-notification-decorator-runtime'
    if ($LASTEXITCODE -ne 0) { throw "Runtime publish failed with exit code $LASTEXITCODE" }
    $runtimeExecutable = Join-Path $publishRoot ('completion-notification-decorator-runtime' + $(if ($IsWindows) { '.exe' } else { '' }))
    if (-not (Test-Path -LiteralPath $runtimeExecutable -PathType Leaf)) { throw "Published runtime is missing: $runtimeExecutable" }

    $runtimeHome = Join-Path $resolvedValidationRoot 'runtime-home'
    $providerOutput = Join-Path $resolvedValidationRoot 'provider-output.jsonl'
    $pwshPath = (Get-Process -Id $PID).Path
    $runtimeConfig = @{
        target_markers = @('$completion-notification-decorator', '[completion-notification]')
        chained_notify = $null
        providers = @(@{
            name = 'fixture-provider'
            argv = @($pwshPath, '-NoProfile', '-File', $fakeProvider, '-Mode', 'provider')
            timeout_ms = 5000
        })
    }
    $null = New-Item -ItemType Directory -Path $runtimeHome
    $runtimeConfig | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $runtimeHome 'runtime-config.json') -Encoding utf8
    $env:CODEX_NOTIFICATION_RUNTIME_HOME = $runtimeHome
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT = $providerOutput
    $env:CODEX_NOTIFICATION_TEST_PROVIDER_EXIT = '0'

    $events = [System.Collections.Generic.List[object]]::new()
    $sourceEventIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $fixtureIndex = 0
    foreach ($fixture in $fixtures) {
        $fixtureIndex++
        $tokens = [regex]::Matches($fixture.input_message, '(?m)^\$(?<name>[a-z0-9-]+)\s*$') | ForEach-Object { $_.Groups['name'].Value }
        $primaryTokens = @($tokens | Where-Object { $_ -ne 'completion-notification-decorator' })
        if ($primaryTokens.Count -ne 1 -or $primaryTokens[0] -ne $fixture.primary_process) {
            throw "Fixture $($fixture.id) must explicitly select exactly its declared primary process."
        }

        $envelope = [ordered]@{
            schema_version = 1
            primary_process = $fixture.primary_process
            observed_status = $fixture.observed_status
            title = $fixture.title
            repository = $fixture.repository
            result_uri = $fixture.result_uri
        } | ConvertTo-Json -Compress
        if (-not ($envelope | Test-Json -SchemaFile $envelopeSchema)) { throw "Fixture $($fixture.id) generated an invalid envelope." }

        $separator = "`n`n``````completion-notification`n"
        $assistantMessage = $fixture.primary_output + $separator + $envelope + "`n``````"
        $envelopeStart = $assistantMessage.IndexOf($separator, [StringComparison]::Ordinal)
        $recoveredPrimaryOutput = $assistantMessage.Substring(0, $envelopeStart)
        if ($recoveredPrimaryOutput -cne $fixture.primary_output) {
            throw "Fixture $($fixture.id) changed the primary process output while adding the envelope."
        }

        $threadId = 'fixture-thread-' + $fixtureIndex
        $turnId = 'fixture-turn-' + $fixtureIndex
        $payload = [ordered]@{
            type = 'agent-turn-complete'
            'thread-id' = $threadId
            'turn-id' = $turnId
            cwd = $repositoryRoot
            'input-messages' = @($fixture.input_message)
            'last-assistant-message' = $assistantMessage
        } | ConvertTo-Json -Compress -Depth 6

        & $runtimeExecutable dispatch $payload
        if ($LASTEXITCODE -ne 0) { throw "Runtime callback for fixture $($fixture.id) returned exit code $LASTEXITCODE." }
        $event = Get-Content -LiteralPath $providerOutput | Select-Object -Last 1 | ConvertFrom-Json
        if ($event.primary_process -ne $fixture.primary_process -or $event.observed_status -ne $fixture.observed_status) {
            throw "Fixture $($fixture.id) did not preserve primary process identity and verdict."
        }
        if ($event.repository -ne $fixture.repository -or $event.result_uri -ne $fixture.result_uri) {
            throw "Fixture $($fixture.id) did not preserve repository identity and direct result link."
        }
        if (-not $event.title.Contains($fixture.repository, [StringComparison]::Ordinal) -or
            -not $event.title.Contains($fixture.primary_process, [StringComparison]::Ordinal) -or
            -not $event.title.Contains($fixture.title, [StringComparison]::Ordinal)) {
            throw "Fixture $($fixture.id) did not produce an identifiable notification title."
        }
        if ($event.resume_uri -ne ('codex://threads/' + $threadId)) {
            throw "Fixture $($fixture.id) did not resolve the callback thread link."
        }
        $deliveryLog = Get-Content -LiteralPath (Join-Path $runtimeHome 'runtime.log.jsonl') | Select-Object -Last 1 | ConvertFrom-Json
        if ($deliveryLog.status -ne 'delivered') {
            throw "Fixture $($fixture.id) did not record delivery status separately from its observed process status."
        }
        if (-not $sourceEventIds.Add([string]$event.source_event_id)) {
            throw "Fixture $($fixture.id) did not produce a distinct source event identity."
        }
        $events.Add($event)
    }

    if (@($events.repository | Sort-Object -Unique).Count -lt 2) {
        throw 'Multiple repository executions were not distinguishable in emitted events.'
    }

    $fallbackPayload = [ordered]@{
        type = 'agent-turn-complete'
        'thread-id' = 'fallback-thread'
        'turn-id' = 'fallback-turn'
        cwd = $repositoryRoot
        'input-messages' = @('$completion-notification-decorator')
        'last-assistant-message' = 'Primary response without an authorable terminal status.'
    } | ConvertTo-Json -Compress -Depth 6
    & $runtimeExecutable dispatch $fallbackPayload
    if ($LASTEXITCODE -ne 0) { throw "Fallback callback returned exit code $LASTEXITCODE." }
    $fallbackEvent = Get-Content -LiteralPath $providerOutput | Select-Object -Last 1 | ConvertFrom-Json
    if ($fallbackEvent.primary_process -ne 'codex-turn' -or
        $fallbackEvent.observed_status -ne 'TURN_ENDED' -or
        $fallbackEvent.resume_uri -ne 'codex://threads/fallback-thread') {
        throw 'Decorator Skill token fallback did not produce a neutral thread-linked event.'
    }

    $env:CODEX_NOTIFICATION_TEST_PROVIDER_EXIT = '9'
    $failureFixture = $fixtures[0]
    $failureEnvelope = [ordered]@{
        schema_version = 1
        primary_process = $failureFixture.primary_process
        observed_status = $failureFixture.observed_status
        title = 'delivery failure fixture'
        repository = $failureFixture.repository
        result_uri = $failureFixture.result_uri
    } | ConvertTo-Json -Compress
    $failureAssistantMessage = $failureFixture.primary_output + "`n`n``````completion-notification`n" + $failureEnvelope + "`n``````"
    $failurePayload = [ordered]@{
        type = 'agent-turn-complete'
        'thread-id' = 'failure-thread'
        'turn-id' = 'failure-turn'
        cwd = $repositoryRoot
        'input-messages' = @($failureFixture.input_message)
        'last-assistant-message' = $failureAssistantMessage
    } | ConvertTo-Json -Compress -Depth 6
    & $runtimeExecutable dispatch $failurePayload
    if ($LASTEXITCODE -ne 0) { throw "Provider failure changed callback exit code to $LASTEXITCODE." }
    $lastLog = Get-Content -LiteralPath (Join-Path $runtimeHome 'runtime.log.jsonl') | Select-Object -Last 1 | ConvertFrom-Json
    if ($lastLog.status -ne 'failed') { throw 'Provider failure was not recorded separately in the runtime log.' }
    if (-not $failureAssistantMessage.StartsWith($failureFixture.primary_output, [StringComparison]::Ordinal) -or
        -not $failureAssistantMessage.Contains($failureFixture.observed_status, [StringComparison]::Ordinal)) {
        throw 'Provider failure fixture did not preserve the primary response and observed status.'
    }
}
finally {
    foreach ($name in @('CODEX_NOTIFICATION_RUNTIME_HOME', 'CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT', 'CODEX_NOTIFICATION_TEST_PROVIDER_EXIT')) {
        Remove-Item ("Env:" + $name) -ErrorAction SilentlyContinue
    }
    if ($safeToDelete -and $resolvedValidationRoot -and (Test-Path -LiteralPath $resolvedValidationRoot)) {
        Remove-Item -LiteralPath $resolvedValidationRoot -Recurse -Force
    }
}

Write-Output "Completion Notification Decorator validation: PASS ($($fixtures.Count) canonical primary-process fixtures, fallback, direct links, multi-repository identity, fail-open)"
$global:LASTEXITCODE = 0
