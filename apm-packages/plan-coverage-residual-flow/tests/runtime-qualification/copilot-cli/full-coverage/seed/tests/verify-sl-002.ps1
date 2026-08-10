$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'src/ProducerState.ps1')
. (Join-Path $repoRoot 'src/ConsumerGate.ps1')

$storePath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "full-001-sl2-$([Guid]::NewGuid().ToString('N')).json")
try {
    Restore-ProducerSnapshot -CorrelationId 'full-001' -Generation 5 -StorePath $storePath | Out-Null
    $state = Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'full-001' -ExpectedGeneration 5
    if ($state.State -cne 'Accepting') { throw 'Consumer did not enter Accepting.' }

    $replayed = Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'full-001' -ExpectedGeneration 5
    if ($replayed.State -cne 'Accepting') { throw 'Consumer replay was not idempotent.' }

    $rejectObserved = $false
    try {
        Push-ConsumerItem -ConsumerState 'Recovering' -CorrelationId 'full-001-negative' -Generation 5 | Out-Null
    }
    catch {
        $rejectObserved = $_.Exception.Message -ceq 'Consumer is not accepting items.'
    }
    if (-not $rejectObserved) { throw 'Non-accepting consumer push was not rejected.' }

    $staleRejected = $false
    try {
        Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'full-001' -ExpectedGeneration 6 | Out-Null
    }
    catch {
        $staleRejected = $_.Exception.Message -ceq 'Consumer rejected stale or incomplete producer snapshot.'
    }
    if (-not $staleRejected) { throw 'Stale generation was accepted.' }

    [pscustomobject]@{
        verdict = 'SL_002_VERIFIED'
        consumer_state = $state.State
        replay_idempotent = $true
        reject_observed = $rejectObserved
        stale_generation_rejected = $staleRejected
    } | ConvertTo-Json -Compress
}
finally {
    Remove-Item -LiteralPath $storePath -Force -ErrorAction SilentlyContinue
}
