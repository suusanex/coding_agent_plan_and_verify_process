# Incomplete seed. Production composition entrypoint must be implemented under Plan Coverage.
function Invoke-StartupFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CorrelationId,
        [Parameter(Mandatory)]
        [int]$Generation,
        [Parameter(Mandatory)]
        [string]$StorePath
    )

    throw 'Invoke-StartupFlow is not implemented.'
}
