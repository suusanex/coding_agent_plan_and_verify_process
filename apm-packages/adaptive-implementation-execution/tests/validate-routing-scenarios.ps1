[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$document = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'routing-scenarios.json') | ConvertFrom-Json -Depth 30
$failures = [System.Collections.Generic.List[string]]::new()

function Has-Property([object] $Object, [string] $Name) {
    $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Copy-Object([object] $Value) {
    $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
}

function Test-SequenceEqual([object[]] $Left, [object[]] $Right) {
    if ($Left.Count -ne $Right.Count) { return $false }
    for ($index = 0; $index -lt $Left.Count; $index++) {
        if ([string]$Left[$index] -cne [string]$Right[$index]) { return $false }
    }
    return $true
}

# fixture内の比較例を検査するための表現。runtime handoffのJSON schemaではない。
function Get-ComparisonErrors([object] $Evidence, [string] $Stage) {
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Evidence) { $errors.Add('comparison evidence is missing'); return $errors }
    foreach ($field in @('requirement_delta', 'choice', 'reason', 'semantics')) {
        if ([string]::IsNullOrWhiteSpace([string]$Evidence.$field)) { $errors.Add("comparison is missing '$field'") }
    }
    if ($Evidence.choice -cnotin @('api', 'extension', 'structure', 'alternative', 'new')) { $errors.Add('comparison choice is invalid') }
    if ($Evidence.choice -ceq 'new') {
        if ([string]::IsNullOrWhiteSpace([string]$Evidence.search_scope) -or $Evidence.no_match -ne $true) {
            $errors.Add('no-match comparison lacks bounded search evidence')
        }
    }
    else {
        foreach ($field in @('reference_file', 'reference_symbol', 'call_relationship')) {
            if ([string]::IsNullOrWhiteSpace([string]$Evidence.$field)) { $errors.Add("comparison is missing '$field'") }
        }
    }
    if ($Evidence.choice -ceq 'alternative' -and ([string]::IsNullOrWhiteSpace([string]$Evidence.incompatibility) -or [string]::IsNullOrWhiteSpace([string]$Evidence.exception_scope))) {
        $errors.Add('alternative comparison lacks incompatibility or exception scope')
    }
    if ($Stage -ceq 'inspection-only') {
        if ($Evidence.post_check -cne 'not-performed' -or -not [string]::IsNullOrWhiteSpace([string]$Evidence.actual_diff)) { $errors.Add('inspection-only comparison claims a performed diff check') }
    }
    else {
        if ($Evidence.post_check -cne 'performed') { $errors.Add('implemented comparison lacks post-check') }
        foreach ($field in @('actual_diff', 'state_sequence_bypass_check')) {
            if ([string]::IsNullOrWhiteSpace([string]$Evidence.$field)) { $errors.Add("comparison is missing '$field'") }
        }
    }
    if ($Stage -cne 'complete' -and [string]::IsNullOrWhiteSpace([string]$Evidence.remaining_check)) { $errors.Add('transfer comparison lacks remaining completion check') }
    return $errors
}

function Get-Comparison([object] $Record) {
    if ([string]::IsNullOrWhiteSpace([string]$Record.comparison_ref)) { return $null }
    return $document.comparison_examples.($Record.comparison_ref)
}

function Test-AuthorizedSurface([string] $Surface, [string[]] $Envelope) {
    foreach ($entry in $Envelope) {
        if ($Surface -ceq $entry -or $Surface.StartsWith($entry + '/', [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Get-HandoffErrors([object] $Handoff) {
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Handoff -or $Handoff.valid -ne $true) {
        $errors.Add('handoff is absent or invalid')
        return $errors
    }
    if ($Handoff.ownership_transfer_basis -cne 'human-approved-structure') {
        $errors.Add('ownership transfer basis is invalid')
    }
    if (@($Handoff.implementation_evidence).Count -eq 0) {
        $errors.Add('implementation or inspection evidence is empty')
    }
    foreach ($field in @('reentry_count', 'previous_reentry_trigger', 'reentry_progress_evidence')) {
        if (-not (Has-Property $Handoff $field)) {
            $errors.Add("handoff is missing '$field'")
        }
    }
    foreach ($field in @('trigger', 'resolution', 'verification', 'same_unresolved_cause_rehanded_off')) {
        if (-not (Has-Property $Handoff.reentry_progress_evidence $field)) {
            $errors.Add("re-entry progress evidence is missing '$field'")
        }
    }

    $actualSurfaceNames = @($Handoff.structure_readiness.PSObject.Properties.Name)
    if (-not (Test-SequenceEqual @($document.required_structure_concerns) $actualSurfaceNames)) {
        $errors.Add('decision surface assessment does not exactly match the canonical concern set')
    }
    foreach ($surface in @($document.required_structure_concerns)) {
        if (-not (Has-Property $Handoff.structure_readiness $surface)) {
            $errors.Add("decision surface assessment is missing '$surface'")
            continue
        }
        $assessment = $Handoff.structure_readiness.$surface
        if ([string]$assessment.status -cnotin @('Ready', 'N/A')) {
            $errors.Add("decision surface '$surface' has invalid status '$($assessment.status)'")
        }
        if ([string]::IsNullOrWhiteSpace([string]$assessment.evidence)) {
            $errors.Add("decision surface '$surface' has no evidence or N/A reason")
        }
    }

    $workPackages = @($Handoff.remaining_work)
    $envelope = @($Handoff.allowed_edit_surface)
    if ($workPackages.Count -eq 0) { $errors.Add('no bounded residual Work Package remains') }
    if ($envelope.Count -eq 0) { $errors.Add('Allowed edit surface is empty') }
    $requiredFields = @('work_id', 'acceptance_items', 'responsibility', 'authorized_surface', 'expected_behavior', 'locked_boundaries', 'local_freedom', 'completion_check')
    $workById = @{}
    foreach ($workPackage in $workPackages) {
        foreach ($field in $requiredFields) {
            if (-not (Has-Property $workPackage $field) -or @($workPackage.$field).Count -eq 0) {
                $errors.Add("Work Package is missing '$field'")
            }
        }
        if ($workById.ContainsKey([string]$workPackage.work_id)) {
            $errors.Add("duplicate Work ID '$($workPackage.work_id)'")
        }
        else {
            $workById[[string]$workPackage.work_id] = $workPackage
        }
        foreach ($surface in @($workPackage.authorized_surface)) {
            if (-not (Test-AuthorizedSurface ([string]$surface) $envelope)) {
                $errors.Add("authorized surface '$surface' is outside the envelope")
            }
        }
    }

    $acceptanceRows = @($Handoff.acceptance_status)
    if ($acceptanceRows.Count -eq 0) { $errors.Add('Acceptance status is empty') }
    foreach ($row in $acceptanceRows) {
        if ([string]$row.status -cnotin @('Complete', 'Incomplete')) {
            $errors.Add("unsupported acceptance status '$($row.status)'")
        }
        if ($row.status -ceq 'Complete' -and [string]::IsNullOrWhiteSpace([string]$row.evidence)) {
            $errors.Add("complete acceptance item '$($row.acceptance_item)' has no evidence")
        }
        if ($row.status -ceq 'Incomplete' -and @($row.work_ids).Count -eq 0) {
            $errors.Add("incomplete acceptance item '$($row.acceptance_item)' has no Work ID")
        }
        foreach ($workId in @($row.work_ids)) {
            if (-not $workById.ContainsKey([string]$workId)) {
                $errors.Add("acceptance item maps to unknown Work ID '$workId'")
                continue
            }
            if ([string]$row.acceptance_item -cnotin @($workById[[string]$workId].acceptance_items)) {
                $errors.Add("acceptance mapping for Work ID '$workId' is not bidirectional")
            }
        }
    }
    foreach ($workPackage in $workPackages) {
        foreach ($acceptanceItem in @($workPackage.acceptance_items)) {
            $matching = @($acceptanceRows | Where-Object acceptance_item -CEQ $acceptanceItem)
            if ($matching.Count -ne 1 -or $matching[0].status -cne 'Incomplete' -or [string]$workPackage.work_id -cnotin @($matching[0].work_ids)) {
                $errors.Add("Work ID '$($workPackage.work_id)' is not mapped to incomplete acceptance '$acceptanceItem'")
            }
        }
    }
    return $errors
}

# 以下はfixtureの遷移検査でありruntime enforcementや人間承認の認証ではない。
function Get-ScenarioErrors([object] $Scenario) {
    $errors = [Collections.Generic.List[string]]::new()
    $phase = 'Fresh'; $version = 0; $turn = 0; $snapshot = ''; $count = 0
    $route = $Scenario.route
    $valid = ($route.implementation_route -ceq 'adaptive' -and $route.implementation_route_source -ceq 'default' -and $route.design_pair_handoff -ceq 'N/A') -or
        ($route.implementation_route -ceq 'design-pair' -and $route.implementation_route_source -ceq 'explicit-user-selection' -and $route.design_pair_handoff -like 'plans/*' -and $route.design_pair_valid -eq $true)
    if (-not $valid) { $errors.Add('invalid route identity'); return $errors }
    foreach ($event in @($Scenario.events)) {
        if ($event.turn -lt $turn) { $errors.Add('turn order regressed') }
        switch ($event.kind) {
            'parent' {
                if ($phase -cnotin @('Fresh','Reentry') -or $event.topology -cne 'current-parent' -or $event.model_changed -ne $false) { $errors.Add('parent topology or model changed') }
                $phase = 'Structure'
            }
            'present' {
                if ($phase -cne 'Structure' -or $event.production_build -cne 'PASS' -or $event.details_implemented -ne $false -or $event.version -le $version -or -not $event.snapshot -or $event.end_turn -ne $true) { $errors.Add('invalid structure presentation') }
                $version = $event.version; $snapshot = $event.snapshot; $turn = $event.turn; $phase = 'Waiting'
            }
            'resume' {
                if ($phase -cne 'Waiting' -or $event.edited -ne $false -or $event.child_started -ne $false) { $errors.Add('unapproved resume advanced work') }
            }
            'response' {
                if ($phase -cne 'Waiting' -or $event.turn -le $turn -or $event.author -cne 'user' -or -not $event.quote -or -not $event.reference -or $event.version -ne $version -or $event.snapshot -cne $snapshot) { $errors.Add('response is absent, stale or not post-presentation user evidence') }
                if ($event.decision -ceq 'approve') { $phase = 'Approved' }
                elseif ($event.decision -ceq 'revise') { $phase = 'Structure' }
                else { $errors.Add('unknown response must stay waiting') }
            }
            'transfer' {
                if ($phase -cne 'Approved' -or $event.current_snapshot -cne $snapshot -or $event.schema -cne 'adaptive-structure-0.7') { $errors.Add('transfer without current approval') }
                $handoff = Copy-Object $document.handoff
                if ($event.invalid_readiness -eq $true) { $handoff.structure_readiness.production_sequence.status = 'Open' }
                if ($event.mapping_missing -eq $true) { $handoff.remaining_work = @() }
                foreach ($error in @(Get-HandoffErrors $handoff)) { $errors.Add($error) }
                foreach ($error in @(Get-ComparisonErrors (Get-Comparison $handoff) 'transfer')) { $errors.Add($error) }
                if ($event.reentry_count -ne $count -or ($count -gt 0 -and ($event.trigger -cne $trigger -or -not $event.resolution -or -not $event.verification -or $event.same_unresolved_cause_rehanded_off -ne $false))) { $errors.Add('reentry lineage or resolution missing') }
                if (($event.locked_decision_ids -join ',') -cne ($route.locked_decision_ids -join ',')) { $errors.Add('locked decisions changed') }
                $phase = 'Child'
            }
            'reentry' {
                if ($phase -cne 'Child' -or $event.structural_change -ne $true -or -not $event.trigger -or $event.reentry_count -ne ($count+1)) { $errors.Add('invalid structural reentry') }
                if ($event.implementation_route -cne $route.implementation_route -or $event.implementation_route_source -cne $route.implementation_route_source -or $event.design_pair_handoff -cne $route.design_pair_handoff) { $errors.Add('reentry route changed') }
                $count = $event.reentry_count; $trigger = $event.trigger; $phase = 'Reentry'
            }
            'complete' {
                if ($phase -cne 'Child' -or $event.owner -cne 'child' -or $event.acceptance_complete -ne $true -or -not $event.validation_evidence) { $errors.Add('only validated child may complete') }
                foreach ($error in @(Get-ComparisonErrors (Get-Comparison $event) 'complete')) { $errors.Add($error) }
                $phase = 'Complete'
            }
            default { $errors.Add('unknown event') }
        }
    }
    if ($phase -cne $Scenario.expected_state) { $errors.Add("Unexpected final state: $phase") }
    return $errors
}

if ($document.schema_version -ne 5) { $failures.Add('wrong fixture schema') }
foreach ($scenario in $document.scenarios) {
    $errors = @(Get-ScenarioErrors $scenario)
    if (($errors.Count -eq 0) -ne $scenario.valid) { $failures.Add("Scenario $($scenario.id): $($errors -join '; ')") }
}
foreach ($entry in $document.comparison_examples.PSObject.Properties) {
    foreach ($error in @(Get-ComparisonErrors $entry.Value $entry.Value.stage)) { $failures.Add($error) }
}
foreach ($field in @('reference_file','reference_symbol','call_relationship','requirement_delta','choice','reason','semantics','actual_diff','state_sequence_bypass_check')) {
    $negative = Copy-Object $document.comparison_examples.api; $negative.$field = ''
    if (@(Get-ComparisonErrors $negative 'complete').Count -eq 0) { $failures.Add("Missing comparison $field accepted") }
}
foreach ($case in @(@('alternative','incompatibility'),@('alternative','exception_scope'),@('new','search_scope'),@('inspection','remaining_check'))) {
    $negative = Copy-Object $document.comparison_examples.($case[0]); $negative.($case[1]) = ''
    if (@(Get-ComparisonErrors $negative $negative.stage).Count -eq 0) { $failures.Add("Missing comparison $case accepted") }
}
if ($failures.Count -gt 0) { throw ($failures -join "`n") }
$global:LASTEXITCODE = 0
Write-Output 'Adaptive routing scenario validation: PASS'
