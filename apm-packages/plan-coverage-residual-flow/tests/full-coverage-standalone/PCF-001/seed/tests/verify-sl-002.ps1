$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../src/ConsumerGate.ps1')

$rejectObserved = $false
try {
    Push-ConsumerItem -ConsumerState 'Recovering' -CorrelationId 'pcf-001' | Out-Null
}
catch {
    $rejectObserved = $_.Exception.Message -ceq 'Consumer is not accepting items.'
}
if (-not $rejectObserved) {
    throw 'SL-002 did not reject a non-accepting consumer state.'
}

$consumerState = Get-ConsumerState -ProducerSnapshot ([pscustomobject]@{
    SnapshotState = 'Active'
    CorrelationId = 'pcf-001'
})
$accepted = Push-ConsumerItem -ConsumerState $consumerState.State -CorrelationId $consumerState.CorrelationId
if ($accepted.Postcondition -cne 'Accepted') {
    throw 'SL-002 did not reach the accepted postcondition.'
}

[pscustomobject]@{
    slice = 'SL-002'
    verdict = 'PARENT_PLAN_VERIFIED'
    consumer_state = $consumerState.State
    postcondition = $accepted.Postcondition
    reject_observed = $rejectObserved
} | ConvertTo-Json -Compress
