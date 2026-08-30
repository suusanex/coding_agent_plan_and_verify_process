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

function Test-StrictSetSuperset([object[]] $Current, [object[]] $Previous) {
    $currentSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $previousSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Current) { [void]$currentSet.Add([string]$entry) }
    foreach ($entry in $Previous) { [void]$previousSet.Add([string]$entry) }
    if ($currentSet.Count -le $previousSet.Count) { return $false }
    foreach ($entry in $previousSet) {
        if (-not $currentSet.Contains($entry)) { return $false }
    }
    return $true
}

function Get-Scenario([string] $Id) {
    @($document.scenarios | Where-Object id -CEQ $Id)[0]
}

function Get-Handoff([object] $Event) {
    $handoff = if (Has-Property $Event 'handoff') {
        Copy-Object $Event.handoff
    }
    elseif ($Event.handoff_ref -ceq 'A') {
        $source = @((Get-Scenario 'A').events | Where-Object verdict -CEQ 'READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION')[0]
        Copy-Object $source.handoff
    }
    else {
        return $null
    }

    if (Has-Property $Event 'handoff_override') {
        $surface = [string]$Event.handoff_override.decision_surface
        $handoff.decision_surface_assessment.$surface.status = [string]$Event.handoff_override.status
    }
    if (Has-Property $Event 'reentry_count') {
        $handoff.reentry_count = [int]$Event.reentry_count
    }
    if (Has-Property $Event 'previous_reentry_trigger') {
        $handoff.previous_reentry_trigger = [string]$Event.previous_reentry_trigger
    }
    if (Has-Property $Event 'reentry_progress_evidence') {
        $handoff.reentry_progress_evidence = Copy-Object $Event.reentry_progress_evidence
    }
    if (Has-Property $Event 'additional_acceptance_status') {
        $handoff.acceptance_status = @($handoff.acceptance_status) + @(Copy-Object $Event.additional_acceptance_status)
    }
    if (Has-Property $Event 'additional_remaining_work') {
        $handoff.remaining_work = @($handoff.remaining_work) + @(Copy-Object $Event.additional_remaining_work)
    }
    if (Has-Property $Event 'additional_allowed_edit_surface') {
        $handoff.allowed_edit_surface = @($handoff.allowed_edit_surface) + @($Event.additional_allowed_edit_surface)
    }
    return $handoff
}

function Get-TrackedState([object] $Event) {
    $trackedState = if (Has-Property $Event 'tracked_state') {
        Copy-Object $Event.tracked_state
    }
    elseif ($Event.tracked_state_ref -ceq 'D') {
        $source = @((Get-Scenario 'D').events | Where-Object verdict -CEQ 'NEEDS_DECISION_SURFACE_REENTRY')[0]
        Copy-Object $source.tracked_state
    }
    else {
        return $null
    }
    if (Has-Property $Event 'tracked_state_trigger') {
        $trackedState.trigger = [string]$Event.tracked_state_trigger
    }
    if (Has-Property $Event 'tracked_state_reentry_count') {
        $trackedState.reentry_count = [int]$Event.tracked_state_reentry_count
    }
    return $trackedState
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
    if ($Handoff.ownership_transfer_basis -cne 'bounded-residual-work-only') {
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

    $actualSurfaceNames = @($Handoff.decision_surface_assessment.PSObject.Properties.Name)
    if (-not (Test-SequenceEqual @($document.required_decision_surfaces) $actualSurfaceNames)) {
        $errors.Add('decision surface assessment does not exactly match the canonical concern set')
    }
    foreach ($surface in @($document.required_decision_surfaces)) {
        if (-not (Has-Property $Handoff.decision_surface_assessment $surface)) {
            $errors.Add("decision surface assessment is missing '$surface'")
            continue
        }
        $assessment = $Handoff.decision_surface_assessment.$surface
        if ([string]$assessment.status -cnotin @('Resolved', 'N/A')) {
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

function Get-ScenarioErrors([object] $Scenario) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $phase = 'Fresh'
    $boundedStarts = 0
    $afterReentry = $false
    $previousAcceptedHandoff = $null
    $pendingReentryTrigger = $null
    $pendingReentryCount = $null
    $route = $Scenario.route
    $validAdaptive = $route.implementation_route -ceq 'adaptive' -and $route.implementation_route_source -ceq 'default' -and $route.design_pair_handoff -ceq 'N/A'
    $validDesignPair = $route.implementation_route -ceq 'design-pair' -and $route.implementation_route_source -ceq 'explicit-user-selection' -and -not [string]::IsNullOrWhiteSpace([string]$route.design_pair_handoff) -and $route.design_pair_handoff -cne 'N/A'

    if (-not ($validAdaptive -or $validDesignPair)) {
        $events = @($Scenario.events)
        if ($events.Count -ne 1 -or $events[0].verdict -cne 'BLOCKED' -or $events[0].stop_reason -cne 'BlockedByInvalidCompletionHandoff' -or $events[0].write_owner -cne 'none' -or $events[0].adaptive_default_inferred -ne $false) {
            $errors.Add('invalid route did not fail closed without a write owner')
        }
        $phase = 'Blocked'
    }
    else {
        foreach ($event in @($Scenario.events)) {
            if ($phase -in @('Completed', 'Blocked')) {
                $errors.Add("event emitted after terminal state '$phase'")
                continue
            }
            if ($event.kind -ceq 'start') {
                if ($event.owner -ceq 'decision-surface-implementation-owner' -and $phase -in @('Fresh', 'DecisionSurfaceReentryReady')) {
                    $phase = 'DecisionSurfaceActive'
                }
                elseif ($event.owner -ceq 'bounded-residual-implementation-owner' -and $phase -ceq 'BoundedResidualReady') {
                    $boundedStarts++
                    $phase = 'BoundedResidualActive'
                }
                else {
                    $errors.Add("owner '$($event.owner)' started from invalid state '$phase'")
                }
                continue
            }

            if ($event.owner -ceq 'decision-surface-implementation-owner') {
                if ($phase -cne 'DecisionSurfaceActive') {
                    $errors.Add("decision-surface verdict emitted from '$phase'")
                    continue
                }
                switch ($event.verdict) {
                    'READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION' {
                        $handoff = Get-Handoff $event
                        $handoffErrors = @(Get-HandoffErrors $handoff)
                        if ($afterReentry) {
                            $progress = $handoff.reentry_progress_evidence
                            if ([int]$handoff.reentry_count -ne [int]$pendingReentryCount -or
                                [string]$handoff.previous_reentry_trigger -cne [string]$pendingReentryTrigger -or
                                [string]$progress.trigger -cne [string]$pendingReentryTrigger -or
                                [string]::IsNullOrWhiteSpace([string]$progress.resolution) -or
                                [string]$progress.resolution -ceq 'N/A' -or
                                [string]::IsNullOrWhiteSpace([string]$progress.verification) -or
                                [string]$progress.verification -ceq 'N/A' -or
                                $progress.same_unresolved_cause_rehanded_off -ne $false) {
                                $handoffErrors += 're-entry trigger resolution evidence is missing'
                            }
                            if ($event.expected_surface_expansion -eq $true) {
                                $currentWorkIds = @($handoff.remaining_work | ForEach-Object { [string]$_.work_id })
                                $previousWorkIds = @($previousAcceptedHandoff.remaining_work | ForEach-Object { [string]$_.work_id })
                                if (-not (Test-StrictSetSuperset $currentWorkIds $previousWorkIds) -or
                                    -not (Test-StrictSetSuperset @($handoff.allowed_edit_surface) @($previousAcceptedHandoff.allowed_edit_surface))) {
                                    $handoffErrors += 'expected expanded remaining work and allowed edit surface were not present'
                                }
                            }
                        }
                        elseif ([int]$handoff.reentry_count -ne 0 -or
                            [string]$handoff.previous_reentry_trigger -cne 'N/A' -or
                            [string]$handoff.reentry_progress_evidence.trigger -cne 'N/A' -or
                            [string]$handoff.reentry_progress_evidence.resolution -cne 'N/A' -or
                            [string]$handoff.reentry_progress_evidence.verification -cne 'N/A' -or
                            [string]$handoff.reentry_progress_evidence.same_unresolved_cause_rehanded_off -cne 'N/A') {
                            $handoffErrors += 'initial re-entry history must start at zero with N/A evidence'
                        }
                        if ($handoffErrors.Count -gt 0) {
                            if ($event.expected_rejected -ne $true) {
                                $errors.Add('invalid transfer was accepted: ' + ($handoffErrors -join '; '))
                            }
                        }
                        else {
                            if ($validDesignPair -and -not (Test-SequenceEqual @($event.locked_decision_ids) @($route.locked_decision_ids))) {
                                $errors.Add('Design Pair Decision IDs changed during transfer')
                            }
                            $previousAcceptedHandoff = Copy-Object $handoff
                            $pendingReentryTrigger = $null
                            $pendingReentryCount = $null
                            $afterReentry = $false
                            $phase = 'BoundedResidualReady'
                        }
                    }
                    'IMPLEMENTATION_COMPLETED' {
                        if ($event.acceptance_complete -ne $true -or @($event.implementation_evidence).Count -eq 0 -or @($event.validation_evidence).Count -eq 0) {
                            $errors.Add('implementation completion lacks acceptance or evidence')
                        }
                        else {
                            $phase = 'Completed'
                        }
                    }
                    'BLOCKED' {
                        if ($event.stop_reason -cne 'BlockedByInvalidCompletionHandoff' -or
                            $event.old_schema_detected -ne $true -or
                            $event.compatibility_normalization_applied -ne $false) {
                            $errors.Add('old-schema BLOCKED result is incomplete or normalized')
                        }
                        else {
                            $phase = 'Blocked'
                        }
                    }
                    default { $errors.Add("unsupported decision-surface verdict '$($event.verdict)'") }
                }
            }
            elseif ($event.owner -ceq 'bounded-residual-implementation-owner') {
                if ($phase -cne 'BoundedResidualActive') {
                    $errors.Add("bounded-residual verdict emitted from '$phase'")
                    continue
                }
                switch ($event.verdict) {
                    'IMPLEMENTATION_COMPLETED' {
                        if ($event.changed_locked_decision -eq $true) {
                            $errors.Add('bounded residual owner changed a locked decision')
                        }
                        elseif ($validDesignPair -and -not (Test-SequenceEqual @($event.locked_decision_ids) @($route.locked_decision_ids))) {
                            $errors.Add('Design Pair Decision IDs changed during completion')
                        }
                        else {
                            $phase = 'Completed'
                        }
                    }
                    'NEEDS_DECISION_SURFACE_REENTRY' {
                        $trackedState = Get-TrackedState $event
                        $reentryErrors = [System.Collections.Generic.List[string]]::new()
                        if ($event.new_decision_surface_required -ne $true -or $event.edit_type_only -eq $true) {
                            $reentryErrors.Add('re-entry lacks a new decision surface')
                        }
                        foreach ($field in @($document.required_reentry_state)) {
                            if (-not (Has-Property $trackedState $field)) {
                                $reentryErrors.Add("re-entry state is missing '$field'")
                            }
                        }
                        if ([string]::IsNullOrWhiteSpace([string]$trackedState.trigger) -or [string]$trackedState.trigger -ceq 'N/A') {
                            $reentryErrors.Add('re-entry trigger is empty or N/A')
                        }
                        if ($null -eq $previousAcceptedHandoff -or
                            [int]$trackedState.reentry_count -ne ([int]$previousAcceptedHandoff.reentry_count + 1)) {
                            $reentryErrors.Add('re-entry count does not increment the accepted handoff')
                        }
                        if ($trackedState.implementation_route -cne $route.implementation_route -or $trackedState.implementation_route_source -cne $route.implementation_route_source -or $trackedState.design_pair_handoff -cne $route.design_pair_handoff) {
                            $reentryErrors.Add('re-entry route identity changed')
                        }
                        if ($reentryErrors.Count -gt 0) {
                            if ($event.expected_rejected -ne $true) {
                                $errors.Add('invalid re-entry was accepted: ' + ($reentryErrors -join '; '))
                            }
                        }
                        else {
                            $afterReentry = $true
                            $pendingReentryTrigger = [string]$trackedState.trigger
                            $pendingReentryCount = [int]$trackedState.reentry_count
                            $phase = 'DecisionSurfaceReentryReady'
                        }
                    }
                    default { $errors.Add("unsupported bounded-residual verdict '$($event.verdict)'") }
                }
            }
            else {
                $errors.Add("invalid verdict owner '$($event.owner)'")
            }
        }
    }

    if ($phase -cne $Scenario.expected.final_state) {
        $errors.Add("ended in '$phase'; expected '$($Scenario.expected.final_state)'")
    }
    if ($boundedStarts -ne [int]$Scenario.expected.bounded_residual_starts) {
        $errors.Add("bounded residual owner started $boundedStarts time(s); expected $($Scenario.expected.bounded_residual_starts)")
    }
    return $errors
}

if ($document.schema_version -ne 4 -or $document.contract -cne 'adaptive-implementation-execution') {
    $failures.Add('routing fixture schema or contract is invalid')
}
if (@($document.scenarios).Count -lt 15) {
    $failures.Add('routing fixture does not cover the required scenario breadth')
}
if ((Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'routing-scenarios.json')) -match 'high-implementation-starter|standard-implementation-completer|READY_FOR_STANDARD_COMPLETION|COMPLETED_BY_HIGH_MODEL|HIGH_MODEL code changes|Direct completion reason|transfer_surface_reduced') {
    $failures.Add('routing fixture contains removed 0.5 ownership vocabulary')
}

foreach ($scenario in @($document.scenarios)) {
    foreach ($error in @(Get-ScenarioErrors $scenario)) {
        $failures.Add("Scenario $($scenario.id): $error")
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Adaptive routing scenario validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

$global:LASTEXITCODE = 0
Write-Output 'Adaptive routing scenario validation: PASS'
