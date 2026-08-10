# External oracle for FULL-001 cross-slice behavior. Harness keeps authority over this file.
$ErrorActionPreference = 'Stop'

$repoRoot = if ($env:RQ_WORKTREE) {
    [System.IO.Path]::GetFullPath($env:RQ_WORKTREE)
}
elseif ($PSScriptRoot -and (Split-Path -Leaf $PSScriptRoot) -ceq 'tests') {
    Split-Path -Parent $PSScriptRoot
}
else {
    throw 'FULL-001 verifier requires RQ_WORKTREE or tests/ layout.'
}

. (Join-Path $repoRoot 'src/StartupFlow.ps1')
. (Join-Path $repoRoot 'src/ConsumerGate.ps1')

$storePath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "full-001-cross-$([Guid]::NewGuid().ToString('N')).json")
try {
    $result = Invoke-StartupFlow -CorrelationId 'full-001' -Generation 7 -StorePath $storePath
    if ($result.SnapshotState -cne 'Active' -or $result.ConsumerState -cne 'Accepting' -or $result.Postcondition -cne 'Accepted') {
        throw 'Production entrypoint did not satisfy the accepted postcondition.'
    }
    if ($result.CorrelationId -cne 'full-001') { throw 'correlation_id not preserved.' }
    if ([int]$result.Generation -ne 7) { throw 'generation not preserved.' }

    $replayed = Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'full-001' -ExpectedGeneration 7
    if ($replayed.State -cne 'Accepting') { throw 'Consumer startup replay was not idempotent.' }

    $rejectObserved = $false
    try {
        Push-ConsumerItem -ConsumerState 'Recovering' -CorrelationId 'full-001-negative' -Generation 7 | Out-Null
    }
    catch {
        $rejectObserved = $_.Exception.Message -ceq 'Consumer is not accepting items.'
    }
    if (-not $rejectObserved) { throw 'Non-accepting push was not rejected.' }

    $staleRejected = $false
    try {
        Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'full-001' -ExpectedGeneration 8 | Out-Null
    }
    catch {
        $staleRejected = $_.Exception.Message -ceq 'Consumer rejected stale or incomplete producer snapshot.'
    }
    if (-not $staleRejected) { throw 'Stale generation was accepted.' }

    [pscustomobject]@{
        verdict = 'FULL_001_CROSS_SLICE_VERIFIED'
        production_entrypoint = 'src/StartupFlow.ps1'
        snapshot_state = $result.SnapshotState
        consumer_state = $result.ConsumerState
        postcondition = $result.Postcondition
        correlation_id = $result.CorrelationId
        generation = [int]$result.Generation
        reject_observed = $rejectObserved
        stale_generation_rejected = $staleRejected
        replay_idempotent = $true
    } | ConvertTo-Json -Compress
}
finally {
    Remove-Item -LiteralPath $storePath -Force -ErrorAction SilentlyContinue
}
