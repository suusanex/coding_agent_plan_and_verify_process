$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/ProducerState.ps1')

$storePath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "pcf-001-sl1-$([Guid]::NewGuid().ToString('N')).json")
$result = Restore-ProducerSnapshot -CorrelationId 'pcf-001' -Generation 7 -StorePath $storePath
if ($result.SnapshotState -cne 'Active') {
    throw 'SL-001 did not restore the producer to Active.'
}
if ($result.CorrelationId -cne 'pcf-001') {
    throw 'SL-001 did not preserve correlation_id.'
}
if ($result.Generation -ne 7 -or -not $result.Published -or -not (Test-Path -LiteralPath $storePath -PathType Leaf)) {
    throw 'SL-001 did not atomically publish the expected durable identity.'
}
Remove-Item -LiteralPath $storePath -Force

[pscustomobject]@{
    slice = 'SL-001'
    verdict = 'PARENT_PLAN_VERIFIED'
    snapshot_state = $result.SnapshotState
    correlation_id = $result.CorrelationId
    generation = $result.Generation
    atomic_publish = $true
} | ConvertTo-Json -Compress
