$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/ProducerState.ps1')

$result = Restore-ProducerSnapshot -CorrelationId 'pcf-001'
if ($result.SnapshotState -cne 'Active') {
    throw 'SL-001 did not restore the producer to Active.'
}
if ($result.CorrelationId -cne 'pcf-001') {
    throw 'SL-001 did not preserve correlation_id.'
}

[pscustomobject]@{
    slice = 'SL-001'
    verdict = 'SLICE_VERIFIED'
    snapshot_state = $result.SnapshotState
    correlation_id = $result.CorrelationId
} | ConvertTo-Json -Compress
