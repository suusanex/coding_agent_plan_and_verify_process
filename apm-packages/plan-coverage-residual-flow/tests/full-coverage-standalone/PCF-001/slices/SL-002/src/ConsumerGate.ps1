function Get-ConsumerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StorePath,
        [Parameter(Mandatory)]
        [string]$ExpectedCorrelationId,
        [Parameter(Mandatory)]
        [int]$ExpectedGeneration
    )

    if (-not (Test-Path -LiteralPath $StorePath -PathType Leaf)) {
        throw 'Producer snapshot is not published.'
    }

    $producerSnapshot = Get-Content -LiteralPath $StorePath -Raw | ConvertFrom-Json
    if (-not $producerSnapshot.Published -or
        $producerSnapshot.CorrelationId -cne $ExpectedCorrelationId -or
        [int]$producerSnapshot.Generation -ne $ExpectedGeneration) {
        throw 'Consumer rejected stale or incomplete producer snapshot.'
    }

    [pscustomobject]@{
        State = if ($ProducerSnapshot.SnapshotState -ceq 'Active') { 'Accepting' } else { 'Recovering' }
        CorrelationId = $ProducerSnapshot.CorrelationId
        Generation = [int]$ProducerSnapshot.Generation
    }
}

function Push-ConsumerItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConsumerState,
        [Parameter(Mandatory)]
        [string]$CorrelationId,
        [Parameter(Mandatory)]
        [int]$Generation
    )

    if ($ConsumerState -cne 'Accepting') {
        throw 'Consumer is not accepting items.'
    }

    [pscustomobject]@{
        Postcondition = 'Accepted'
        CorrelationId = $CorrelationId
        Generation = $Generation
    }
}
