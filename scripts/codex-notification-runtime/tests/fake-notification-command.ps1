param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('provider', 'chain')]
    [string]$Mode,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

if ($Mode -eq 'provider') {
    $payload = [Console]::In.ReadToEnd()
    [System.IO.File]::AppendAllText($env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT, $payload + [Environment]::NewLine)
    exit ([int]($env:CODEX_NOTIFICATION_TEST_PROVIDER_EXIT ?? '0'))
}

[System.IO.File]::AppendAllText($env:CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT, $RemainingArguments[$RemainingArguments.Count - 1] + [Environment]::NewLine)
