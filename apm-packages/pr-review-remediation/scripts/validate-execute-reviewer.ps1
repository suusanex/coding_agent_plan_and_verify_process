[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packageRoot = Join-Path $repoRoot 'apm-packages\pr-review-remediation'
$executor = Join-Path $packageRoot '.apm\skills\goal-context-pr-review\scripts\execute-reviewer.cs'
$skillRoot = Join-Path $packageRoot '.apm\skills\goal-context-pr-review'
$fakeCodexCs = Join-Path $packageRoot 'tests\fixtures\fake-codex.cs'
$fakeCopilotCs = Join-Path $packageRoot 'tests\fixtures\fake-copilot.cs'
$failures = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("execute-reviewer-validate-" + [guid]::NewGuid().ToString('N'))

function Add-Failure([string]$Message) { $failures.Add($Message) }

function Publish-Fake([string]$SourceCs, [string]$OutDir) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    & dotnet publish $SourceCs -o $OutDir --verbosity quiet | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to publish fake CLI to $OutDir" }
    $exe = Get-ChildItem -LiteralPath $OutDir -Filter '*.exe' | Select-Object -First 1
    if ($null -eq $exe) { throw "Published fake CLI executable not found in $OutDir" }
    return $exe.FullName
}

function New-FixtureRepo {
    param([switch]$IncludeCodexProfiles = $true, [switch]$ApmAgentsOnly)
    $root = Join-Path $tempRoot ("repo-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'docs') | Out-Null
    if ($ApmAgentsOnly) {
        $agentDir = Join-Path $root 'apm_modules\owner\repo\.apm\agents'
        New-Item -ItemType Directory -Path $agentDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot '.github\agents\local-reviewer.agent.md') -Destination (Join-Path $agentDir 'local-reviewer.agent.md')
        Copy-Item -LiteralPath (Join-Path $repoRoot '.github\agents\purpose-reviewer.agent.md') -Destination (Join-Path $agentDir 'purpose-reviewer.agent.md')
    }
    else {
        New-Item -ItemType Directory -Path (Join-Path $root '.github\agents') | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot '.github\agents\local-reviewer.agent.md') -Destination (Join-Path $root '.github\agents\local-reviewer.agent.md')
        Copy-Item -LiteralPath (Join-Path $repoRoot '.github\agents\purpose-reviewer.agent.md') -Destination (Join-Path $root '.github\agents\purpose-reviewer.agent.md')
    }
    if ($IncludeCodexProfiles) {
        New-Item -ItemType Directory -Path (Join-Path $root 'apm-packages\pr-review-remediation\codex-agents') | Out-Null
        Copy-Item -LiteralPath (Join-Path $packageRoot 'codex-agents\local-reviewer.toml') -Destination (Join-Path $root 'apm-packages\pr-review-remediation\codex-agents\local-reviewer.toml')
        Copy-Item -LiteralPath (Join-Path $packageRoot 'codex-agents\purpose-reviewer.toml') -Destination (Join-Path $root 'apm-packages\pr-review-remediation\codex-agents\purpose-reviewer.toml')
    }
    Set-Content -LiteralPath (Join-Path $root 'docs\goal-context-fixture.md') -Value "Goal: keep reviewer execution deterministic.`n"
    return $root
}

function New-RunRoot([string]$RepoRoot, [int]$Round = 1, [string]$Mode = 'full') {
    $runRoot = Join-Path $RepoRoot ".review\pr-123\same-thread\20260805T000000Z-deadbeef"
    $roundRoot = Join-Path $runRoot ("round-{0:000}" -f $Round)
    New-Item -ItemType Directory -Path $roundRoot -Force | Out-Null
    $context = @{
        repository = 'fixture/goal-context-review'
        pullRequest = 123
        baseOid = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        headOid = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        isDraft = $false
        copilotObservedState = 'reviewOnly'
        copilotTimedOut = $false
        copilotIsComplete = $true
    } | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Join-Path $roundRoot 'review-context.json') -Value $context -Encoding utf8
    Set-Content -LiteralPath (Join-Path $roundRoot 'pr-diff.patch') -Value "diff --git a/src/A.cs b/src/A.cs`n+// change`n" -Encoding utf8
    $selection = @{
        selectedPath = 'docs/goal-context-fixture.md'
        contentSha256 = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        status = 'SELECTED'
    } | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Join-Path $roundRoot 'goal-context-selection.json') -Value $selection -Encoding utf8
    $state = @{
        schemaVersion = 1
        runId = '20260805T000000Z-deadbeef'
        status = if ($Round -eq 1) { 'Round1Reviewing' } else { 'PurposeReviewing' }
        currentRound = $Round
        maximumRounds = 3
        rounds = @(@{
            number = $Round
            mode = $Mode
            baseOid = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            headOid = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            directory = ("round-{0:000}" -f $Round)
            status = 'AwaitingReviewers'
            mandatorySources = @()
        })
        findings = @()
        reviewerExecutions = @()
    } | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath (Join-Path $runRoot 'run-state.json') -Value $state -Encoding utf8
    return $runRoot
}

function Invoke-Executor {
    param(
        [string[]]$Arguments,
        [hashtable]$Env = @{}
    )
    $old = @{}
    foreach ($key in $Env.Keys) {
        $old[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, [string]$Env[$key])
    }
    try {
        $output = & dotnet run --file $executor -- @Arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
    finally {
        foreach ($key in $Env.Keys) {
            [Environment]::SetEnvironmentVariable($key, $old[$key])
        }
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $fakeBin = Join-Path $tempRoot 'fake-bin'
    $codexPath = Publish-Fake $fakeCodexCs (Join-Path $fakeBin 'codex')
    $copilotPath = Publish-Fake $fakeCopilotCs (Join-Path $fakeBin 'copilot')

    # help
    $help = Invoke-Executor @('--help')
    if ($help.ExitCode -ne 0) { Add-Failure 'help should exit 0' }

    # reject arbitrary command
    $cmd = Invoke-Executor @('--execution-app', 'codex-exec', '--model', 'gpt-5.6-terra', '--reviewer-role', 'local-reviewer', '--run-root', $tempRoot, '--round', '1', '--command', 'echo hi')
    if ($cmd.ExitCode -eq 0 -or $cmd.Output -notmatch 'Arbitrary raw command') { Add-Failure 'arbitrary --command must be rejected' }

    # unsupported app
    $badApp = Invoke-Executor @('--execution-app', 'nope', '--model', 'gpt-5.6-terra', '--reviewer-role', 'local-reviewer', '--run-root', $tempRoot, '--round', '1')
    if ($badApp.ExitCode -eq 0 -or $badApp.Output -notmatch 'Unsupported execution app') { Add-Failure 'unsupported app must fail' }

    # unsupported model
    $badModel = Invoke-Executor @('--execution-app', 'codex-exec', '--model', 'totally-unknown-model', '--reviewer-role', 'local-reviewer', '--run-root', $tempRoot, '--round', '1')
    if ($badModel.ExitCode -eq 0 -or $badModel.Output -notmatch 'Unsupported model') { Add-Failure 'unsupported model must fail' }

    # unsupported role
    $badRole = Invoke-Executor @('--execution-app', 'codex-exec', '--model', 'gpt-5.6-terra', '--reviewer-role', 'review-planner', '--run-root', $tempRoot, '--round', '1')
    if ($badRole.ExitCode -eq 0 -or $badRole.Output -notmatch 'Unsupported reviewer role') { Add-Failure 'unsupported role must fail' }

    # positive codex local-reviewer
    $repo = New-FixtureRepo
    $run = New-RunRoot $repo 1 'full'
    $stateLog = Join-Path $tempRoot 'codex-args.log'
    $ok = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $run,
        '--round', '1',
        '--timeout-seconds', '30',
        '--repository-root', $repo,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'success'; FAKE_CODEX_STATE = $stateLog }
    if ($ok.ExitCode -ne 0) { Add-Failure "codex success path failed: $($ok.Output)" }
    $raw = Join-Path $run 'round-001\local-reviewer.raw.md'
    $meta = Join-Path $run 'round-001\local-reviewer.execution.json'
    if (-not (Test-Path -LiteralPath $raw)) { Add-Failure 'success path did not publish local-reviewer.raw.md' }
    if (-not (Test-Path -LiteralPath $meta)) { Add-Failure 'success path did not publish execution metadata' }
    else {
        $metaObj = Get-Content -Raw -LiteralPath $meta | ConvertFrom-Json
        if ($metaObj.exitStatus -ne 'succeeded') { Add-Failure 'metadata exitStatus should be succeeded' }
        if ($metaObj.executionApp -ne 'codex-exec') { Add-Failure 'metadata executionApp mismatch' }
        if ($metaObj.requestedModel -ne 'gpt-5.6-terra') { Add-Failure 'metadata requestedModel mismatch' }
        if ($metaObj.commandShape -match '(?i)(token|password|secret)=') { Add-Failure 'commandShape leaked secret-like values' }
        if ($metaObj.commandShape -notmatch 'codex') { Add-Failure 'commandShape missing codex' }
    }
    $rawText = Get-Content -Raw -LiteralPath $raw
    if ($rawText -notmatch 'Production code changed:\s*No') { Add-Failure 'raw missing Production code changed marker' }
    if ((Test-Path -LiteralPath $stateLog)) {
        $argLine = Get-Content -Raw -LiteralPath $stateLog
        if ($argLine -notmatch 'exec' -or $argLine -notmatch '-m' -or $argLine -notmatch 'read-only') {
            Add-Failure 'fake-codex did not receive expected argv shape'
        }
        if ($argLine -match '(?i)(api[_-]?key|password|secret)=') { Add-Failure 'argv contained secret-like assignment' }
        if ($argLine -match 'review-context\.json' -or $argLine -match 'pr-diff\.patch') {
            Add-Failure 'codex argv must not contain full reviewer prompt payload'
        }
    }

    # overwrite protection
    $again = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $run,
        '--round', '1',
        '--repository-root', $repo,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'success' }
    if ($again.ExitCode -eq 0) { Add-Failure 'overwrite of existing raw artifact must fail' }

    # empty output must not publish final raw
    $repo2 = New-FixtureRepo
    $run2 = New-RunRoot $repo2 1 'full'
    $empty = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $run2,
        '--round', '1',
        '--repository-root', $repo2,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'empty' }
    if ($empty.ExitCode -eq 0) { Add-Failure 'empty output must fail' }
    if (Test-Path -LiteralPath (Join-Path $run2 'round-001\local-reviewer.raw.md')) {
        Add-Failure 'empty output must not publish final raw artifact'
    }
    if ($empty.Output -match '"exitStatus"\s*:\s*"succeeded"') { Add-Failure 'empty output must not report succeeded' }

    # non-zero exit
    $repo3 = New-FixtureRepo
    $run3 = New-RunRoot $repo3 1 'full'
    $nz = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $run3,
        '--round', '1',
        '--repository-root', $repo3,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'non_zero' }
    if ($nz.ExitCode -eq 0 -or $nz.Output -notmatch 'non_zero_exit|failed') { Add-Failure 'non-zero exit must fail closed' }
    if (Test-Path -LiteralPath (Join-Path $run3 'round-001\local-reviewer.raw.md')) {
        Add-Failure 'non-zero exit must not publish final raw'
    }

    # auth failure classification
    $repoA = New-FixtureRepo
    $runA = New-RunRoot $repoA 1 'full'
    $auth = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runA,
        '--round', '1',
        '--repository-root', $repoA,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'auth_failure' }
    if ($auth.ExitCode -eq 0 -or $auth.Output -notmatch 'auth_failure') { Add-Failure 'auth failure must be classified' }

    # timeout
    $repoT = New-FixtureRepo
    $runT = New-RunRoot $repoT 1 'full'
    $to = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runT,
        '--round', '1',
        '--timeout-seconds', '1',
        '--repository-root', $repoT,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'timeout' }
    if ($to.ExitCode -eq 0 -or $to.Output -notmatch 'timeout') { Add-Failure 'timeout must fail closed' }
    if (Test-Path -LiteralPath (Join-Path $runT 'round-001\local-reviewer.raw.md')) {
        Add-Failure 'timeout must not publish final raw'
    }

    # purpose-only rejects local-reviewer
    $repoP = New-FixtureRepo
    $runP = New-RunRoot $repoP 2 'purpose-only'
    $localOn2 = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runP,
        '--round', '2',
        '--repository-root', $repoP,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'success' }
    if ($localOn2.ExitCode -eq 0) { Add-Failure 'local-reviewer on round 2 must fail' }

    # purpose-reviewer success via codex
    $purposeOk = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'purpose-reviewer',
        '--run-root', $runP,
        '--round', '2',
        '--repository-root', $repoP,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'purpose' }
    if ($purposeOk.ExitCode -ne 0) { Add-Failure "purpose-reviewer success failed: $($purposeOk.Output)" }
    if (-not (Test-Path -LiteralPath (Join-Path $runP 'round-002\purpose-reviewer.raw.md'))) {
        Add-Failure 'purpose-reviewer raw not published'
    }

    # copilot-cli success
    $repoC = New-FixtureRepo
    $runC = New-RunRoot $repoC 1 'full'
    $copilotLog = Join-Path $tempRoot 'copilot-args.log'
    $copilotOk = Invoke-Executor @(
        '--execution-app', 'copilot-cli',
        '--model', 'gpt-5.4',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runC,
        '--round', '1',
        '--repository-root', $repoC,
        '--skill-root', $skillRoot,
        '--copilot-executable', $copilotPath,
        '--format', 'json'
    ) @{ FAKE_COPILOT_SCENARIO = 'success'; FAKE_COPILOT_STATE = $copilotLog }
    if ($copilotOk.ExitCode -ne 0) { Add-Failure "copilot success path failed: $($copilotOk.Output)" }
    if (-not (Test-Path -LiteralPath (Join-Path $runC 'round-001\local-reviewer.raw.md'))) {
        Add-Failure 'copilot success did not publish raw'
    }
    if (Test-Path -LiteralPath $copilotLog) {
        $cArgs = Get-Content -Raw -LiteralPath $copilotLog
        if ($cArgs -notmatch '-p' -or $cArgs -notmatch '--model') { Add-Failure 'copilot argv missing -p/--model' }
        if ($cArgs -notmatch 'available-tools') { Add-Failure 'copilot argv missing available-tools allowlist' }
        if ($cArgs -notmatch 'disable-builtin-mcps') { Add-Failure 'copilot argv missing disable-builtin-mcps' }
        if ($cArgs -notmatch 'deny-tool') { Add-Failure 'copilot argv missing deny-tool write boundary' }
        if ($cArgs -match 'review-context\.json') { Add-Failure 'copilot argv must not embed full reviewer prompt' }
    }

    # copilot empty
    $repoCE = New-FixtureRepo
    $runCE = New-RunRoot $repoCE 1 'full'
    $copilotEmpty = Invoke-Executor @(
        '--execution-app', 'copilot-cli',
        '--model', 'gpt-5.4',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runCE,
        '--round', '1',
        '--repository-root', $repoCE,
        '--skill-root', $skillRoot,
        '--copilot-executable', $copilotPath,
        '--format', 'json'
    ) @{ FAKE_COPILOT_SCENARIO = 'empty' }
    if ($copilotEmpty.ExitCode -eq 0) { Add-Failure 'copilot empty must fail' }
    if (Test-Path -LiteralPath (Join-Path $runCE 'round-001\local-reviewer.raw.md')) {
        Add-Failure 'copilot empty must not publish final raw'
    }

    # copilot without Codex profiles must still run
    $repoNoCodex = New-FixtureRepo -IncludeCodexProfiles:$false
    $runNoCodex = New-RunRoot $repoNoCodex 1 'full'
    $copilotNoCodex = Invoke-Executor @(
        '--execution-app', 'copilot-cli',
        '--model', 'gpt-5.4',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runNoCodex,
        '--round', '1',
        '--repository-root', $repoNoCodex,
        '--skill-root', $skillRoot,
        '--copilot-executable', $copilotPath,
        '--format', 'json'
    ) @{ FAKE_COPILOT_SCENARIO = 'success' }
    if ($copilotNoCodex.ExitCode -ne 0) { Add-Failure "copilot without Codex profile failed: $($copilotNoCodex.Output)" }

    # APM agents path resolution
    $repoApm = New-FixtureRepo -ApmAgentsOnly -IncludeCodexProfiles
    $runApm = New-RunRoot $repoApm 1 'full'
    $apmOk = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runApm,
        '--round', '1',
        '--repository-root', $repoApm,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'success' }
    if ($apmOk.ExitCode -ne 0) { Add-Failure "APM agent path resolution failed: $($apmOk.Output)" }

    # missing marker fails and does not publish raw
    $repoMM = New-FixtureRepo
    $runMM = New-RunRoot $repoMM 1 'full'
    $missingMarker = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runMM,
        '--round', '1',
        '--repository-root', $repoMM,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'missing_marker' }
    if ($missingMarker.ExitCode -eq 0) { Add-Failure 'missing Production code changed marker must fail' }
    if (Test-Path -LiteralPath (Join-Path $runMM 'round-001\local-reviewer.raw.md')) {
        Add-Failure 'missing marker must not publish final raw'
    }

    # write detection
    $repoW = New-FixtureRepo
    $runW = New-RunRoot $repoW 1 'full'
    $write = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runW,
        '--round', '1',
        '--repository-root', $repoW,
        '--skill-root', $skillRoot,
        '--codex-executable', $codexPath,
        '--format', 'json'
    ) @{ FAKE_CODEX_SCENARIO = 'write' }
    if ($write.ExitCode -eq 0 -or $write.Output -notmatch 'write_detected|write detected') {
        Add-Failure "write detection must fail closed: $($write.Output)"
    }
    if (Test-Path -LiteralPath (Join-Path $runW 'round-001\local-reviewer.raw.md')) {
        Add-Failure 'write detection must not publish final raw'
    }

    # missing executable -> process_start_failure
    $repoPS = New-FixtureRepo
    $runPS = New-RunRoot $repoPS 1 'full'
    $missingExe = Join-Path $tempRoot 'does-not-exist-codex.exe'
    $psFail = Invoke-Executor @(
        '--execution-app', 'codex-exec',
        '--model', 'gpt-5.6-terra',
        '--reviewer-role', 'local-reviewer',
        '--run-root', $runPS,
        '--round', '1',
        '--repository-root', $repoPS,
        '--skill-root', $skillRoot,
        '--codex-executable', $missingExe,
        '--format', 'json'
    )
    if ($psFail.ExitCode -eq 0 -or $psFail.Output -notmatch 'process_start_failure') {
        Add-Failure "missing executable must classify process_start_failure: $($psFail.Output)"
    }
}
catch {
    Add-Failure $_.Exception.Message
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'validate-execute-reviewer FAILED'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host 'validate-execute-reviewer PASSED'
exit 0
