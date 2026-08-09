$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/StartupFlow.ps1')

$storePath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "pcf-001-cross-$([Guid]::NewGuid().ToString('N')).json")
$result = Invoke-StartupFlow -CorrelationId 'pcf-001' -Generation 7 -StorePath $storePath
if ($result.SnapshotState -cne 'Active' -or $result.ConsumerState -cne 'Accepting' -or $result.Postcondition -cne 'Accepted') {
    throw 'The production entrypoint did not satisfy the accepted postcondition.'
}
if ($result.CorrelationId -cne 'pcf-001') {
    throw 'The production entrypoint did not preserve correlation_id.'
}
if ($result.Generation -ne 7) {
    throw 'The production entrypoint did not preserve generation.'
}

$replayed = Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'pcf-001' -ExpectedGeneration 7
if ($replayed.State -cne 'Accepting') {
    throw 'Consumer startup replay was not idempotent.'
}

$rejectObserved = $false
try {
    Push-ConsumerItem -ConsumerState 'Recovering' -CorrelationId 'pcf-001-negative' -Generation 7 | Out-Null
}
catch {
    $rejectObserved = $_.Exception.Message -ceq 'Consumer is not accepting items.'
}
if (-not $rejectObserved) {
    throw 'The production binding did not reject a non-accepting state.'
}

$staleRejected = $false
try {
    Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'pcf-001' -ExpectedGeneration 8 | Out-Null
}
catch {
    $staleRejected = $_.Exception.Message -ceq 'Consumer rejected stale or incomplete producer snapshot.'
}
if (-not $staleRejected) {
    throw 'The production binding accepted a stale generation.'
}
Remove-Item -LiteralPath $storePath -Force

[pscustomobject]@{
    verdict = 'CROSS_SLICE_VERIFIED'
    production_entrypoint = 'src/StartupFlow.ps1'
    snapshot_state = $result.SnapshotState
    consumer_state = $result.ConsumerState
    postcondition = $result.Postcondition
    correlation_id = $result.CorrelationId
    generation = $result.Generation
    reject_observed = $rejectObserved
    stale_generation_rejected = $staleRejected
    replay_idempotent = $true
} | ConvertTo-Json -Compress
