$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/StartupFlow.ps1')

$result = Invoke-StartupFlow -CorrelationId 'pcf-001'
if ($result.SnapshotState -cne 'Active' -or $result.ConsumerState -cne 'Accepting' -or $result.Postcondition -cne 'Accepted') {
    throw 'The production entrypoint did not satisfy the accepted postcondition.'
}
if ($result.CorrelationId -cne 'pcf-001') {
    throw 'The production entrypoint did not preserve correlation_id.'
}

$rejectObserved = $false
try {
    Push-ConsumerItem -ConsumerState 'Recovering' -CorrelationId 'pcf-001-negative' | Out-Null
}
catch {
    $rejectObserved = $_.Exception.Message -ceq 'Consumer is not accepting items.'
}
if (-not $rejectObserved) {
    throw 'The production binding did not reject a non-accepting state.'
}

[pscustomobject]@{
    verdict = 'CROSS_SLICE_VERIFIED'
    production_entrypoint = 'src/StartupFlow.ps1'
    snapshot_state = $result.SnapshotState
    consumer_state = $result.ConsumerState
    postcondition = $result.Postcondition
    correlation_id = $result.CorrelationId
    reject_observed = $rejectObserved
} | ConvertTo-Json -Compress
