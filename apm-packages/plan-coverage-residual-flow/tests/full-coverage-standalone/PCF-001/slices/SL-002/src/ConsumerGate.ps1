function Get-ConsumerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$ProducerSnapshot
    )

    [pscustomobject]@{
        State = if ($ProducerSnapshot.SnapshotState -ceq 'Active') { 'Accepting' } else { 'Recovering' }
        CorrelationId = $ProducerSnapshot.CorrelationId
    }
}

function Push-ConsumerItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConsumerState,
        [Parameter(Mandatory)]
        [string]$CorrelationId
    )

    if ($ConsumerState -cne 'Accepting') {
        throw 'Consumer is not accepting items.'
    }

    [pscustomobject]@{
        Postcondition = 'Accepted'
        CorrelationId = $CorrelationId
    }
}
