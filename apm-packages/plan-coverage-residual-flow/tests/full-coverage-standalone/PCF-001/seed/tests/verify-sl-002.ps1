$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/ConsumerGate.ps1')

$rejectObserved = $false
try {
    Push-ConsumerItem -ConsumerState 'Recovering' -CorrelationId 'pcf-001' -Generation 7 | Out-Null
}
catch {
    $rejectObserved = $_.Exception.Message -ceq 'Consumer is not accepting items.'
}
if (-not $rejectObserved) {
    throw 'SL-002 did not reject a non-accepting consumer state.'
}

$storePath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "pcf-001-sl2-$([Guid]::NewGuid().ToString('N')).json")
[pscustomobject]@{ SnapshotState = 'Active'; CorrelationId = 'pcf-001'; Generation = 7; Published = $true } |
    ConvertTo-Json -Compress | Set-Content -LiteralPath $storePath -Encoding utf8NoBOM
$consumerState = Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'pcf-001' -ExpectedGeneration 7
$accepted = Push-ConsumerItem -ConsumerState $consumerState.State -CorrelationId $consumerState.CorrelationId -Generation $consumerState.Generation
if ($accepted.Postcondition -cne 'Accepted') {
    throw 'SL-002 did not reach the accepted postcondition.'
}

$staleRejected = $false
try {
    Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'pcf-001' -ExpectedGeneration 8 | Out-Null
}
catch {
    $staleRejected = $_.Exception.Message -ceq 'Consumer rejected stale or incomplete producer snapshot.'
}
if (-not $staleRejected) {
    throw 'SL-002 accepted a stale durable generation.'
}

$replayed = Get-ConsumerState -StorePath $storePath -ExpectedCorrelationId 'pcf-001' -ExpectedGeneration 7
if ($replayed.State -cne 'Accepting' -or $replayed.Generation -ne 7) {
    throw 'SL-002 replay was not idempotent.'
}
Remove-Item -LiteralPath $storePath -Force

[pscustomobject]@{
    slice = 'SL-002'
    verdict = 'PARENT_PLAN_VERIFIED'
    consumer_state = $consumerState.State
    postcondition = $accepted.Postcondition
    reject_observed = $rejectObserved
    stale_generation_rejected = $staleRejected
    replay_idempotent = $true
} | ConvertTo-Json -Compress
