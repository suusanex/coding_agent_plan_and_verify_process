[CmdletBinding()]
param(
    [string]$FixturePath = (Join-Path $PSScriptRoot 'routing-scenarios.json')
)

$ErrorActionPreference = 'Stop'
$script:canonicalRequiredDecisionClosure = @(
    'responsibility_ownership',
    'public_shared_internal_contract',
    'dependency_direction',
    'production_sequence_wiring_architecture',
    'state_error_cancellation_retry_semantics',
    'test_architecture_seam_strategy'
)
$script:canonicalRequiredReentryState = @(
    'original_implementation_intent',
    'implementation_completion_handoff',
    'high_model_reentry_handoff',
    'implementation_route',
    'implementation_route_source',
    'design_pair_handoff',
    'locked_decisions',
    'current_worktree_state',
    'invalidating_evidence',
    'completed_work',
    'files_changed',
    'validation',
    'new_decision',
    'reentry_count',
    'trigger',
    'delegation_surface_reduced'
)
$script:requiredWorkPackageFields = @(
    'work_id',
    'acceptance_items',
    'responsibility',
    'authorized_surface',
    'expected_behavior',
    'locked_boundaries',
    'local_freedom',
    'completion_check'
)
$script:allowedDirectCompletionReasons = @(
    'tiny-local-change',
    'design-implementation-inseparable',
    'standard-model-unavailable',
    'delegation-materially-increases-risk-or-cost',
    'post-reentry-high-ownership'
)
$script:allowedLocalChoices = @('private-helper', 'branch-organization', 'test-data-builder')

function Has-Property([object]$Object, [string]$Name) {
    return $null -ne $Object -and $Name -in $Object.PSObject.Properties.Name
}

function Test-SequenceEqual([object[]]$Actual, [object[]]$Expected) {
    return (@($Actual) -join "`n") -ceq (@($Expected) -join "`n")
}

function Copy-Object([object]$Value) {
    return ($Value | ConvertTo-Json -Depth 40 | ConvertFrom-Json)
}

function Get-Scenario([object]$Document, [string]$Id) {
    return @($Document.scenarios | Where-Object id -CEQ $Id)[0]
}

function Get-ReferenceHandoff([object]$Document) {
    $event = (Get-Scenario $Document 'A').events | Where-Object verdict -CEQ 'READY_FOR_STANDARD_COMPLETION'
    return Copy-Object $event.handoff
}

function Get-ResolvedHandoff([object]$Event, [object]$Document) {
    $handoff = if (Has-Property $Event 'handoff') {
        Copy-Object $Event.handoff
    }
    elseif ($Event.handoff_ref -ceq 'A') {
        Get-ReferenceHandoff $Document
    }
    else {
        $null
    }

    if ($null -ne $handoff -and (Has-Property $Event 'handoff_override')) {
        $concern = [string]$Event.handoff_override.decision_concern
        $handoff.decision_closure.$concern.status = [string]$Event.handoff_override.status
    }
    return $handoff
}

function Get-ResolvedTrackedState([object]$Event, [object]$Document) {
    if (Has-Property $Event 'tracked_state') {
        return $Event.tracked_state
    }
    if ($Event.tracked_state_ref -ceq 'D') {
        $source = (Get-Scenario $Document 'D').events | Where-Object verdict -CEQ 'NEEDS_HIGH_MODEL_REENTRY'
        return Copy-Object $source.tracked_state
    }
    return $null
}

function Test-AuthorizedSurface([string]$Surface, [string[]]$Envelope) {
    foreach ($entry in $Envelope) {
        if ($Surface -ceq $entry -or $Surface.StartsWith($entry + '/', [StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Get-HandoffErrors([object]$Handoff) {
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Handoff -or $Handoff.valid -ne $true) {
        $errors.Add('handoff is absent or not marked valid')
        return $errors
    }
    if ($Handoff.delegation_basis -cne 'non-local-decisions-closed') {
        $errors.Add('delegation basis is not non-local-decisions-closed')
    }
    if (-not (Has-Property $Handoff 'high_model_code_changes') -or $Handoff.high_model_code_changes -isnot [bool]) {
        $errors.Add('HIGH_MODEL code changes is not an explicit boolean')
    }

    foreach ($concern in $script:canonicalRequiredDecisionClosure) {
        if (-not (Has-Property $Handoff.decision_closure $concern)) {
            $errors.Add("decision closure is missing '$concern'")
            continue
        }
        $closure = $Handoff.decision_closure.$concern
        $status = [string]$closure.status
        if ($status -notin @('Locked', 'N/A')) {
            $errors.Add("decision closure '$concern' has invalid status '$status'")
        }
        if ([string]::IsNullOrWhiteSpace([string]$closure.evidence)) {
            $errors.Add("decision closure '$concern' has no evidence or N/A reason")
        }
    }

    $workPackages = @($Handoff.remaining_work)
    if ($workPackages.Count -eq 0) {
        $errors.Add('no Work Package remains')
    }
    $envelope = @($Handoff.allowed_edit_surface)
    if ($envelope.Count -eq 0) {
        $errors.Add('Allowed edit surface envelope is empty')
    }
    foreach ($workPackage in $workPackages) {
        foreach ($field in $script:requiredWorkPackageFields) {
            if (-not (Has-Property $workPackage $field) -or @($workPackage.$field).Count -eq 0) {
                $errors.Add("Work Package is missing '$field'")
            }
        }
        foreach ($surface in @($workPackage.authorized_surface)) {
            if (-not (Test-AuthorizedSurface ([string]$surface) $envelope)) {
                $errors.Add("authorized surface '$surface' is outside the Allowed edit surface envelope")
            }
        }
    }

    $acceptanceRows = @($Handoff.acceptance_status)
    if ($acceptanceRows.Count -eq 0) {
        $errors.Add('Acceptance status is empty')
    }
    $workById = @{}
    foreach ($workPackage in $workPackages) {
        $workById[[string]$workPackage.work_id] = $workPackage
    }
    foreach ($row in $acceptanceRows) {
        if ($row.status -ceq 'Blocked') {
            $errors.Add("acceptance item '$($row.acceptance_item)' is Blocked")
        }
        if ($row.status -ceq 'Complete' -and [string]::IsNullOrWhiteSpace([string]$row.evidence)) {
            $errors.Add("complete acceptance item '$($row.acceptance_item)' has no evidence")
        }
        if ($row.status -ceq 'Incomplete' -and @($row.work_ids).Count -eq 0) {
            $errors.Add("incomplete acceptance item '$($row.acceptance_item)' has no Work ID")
        }
        foreach ($workId in @($row.work_ids)) {
            if (-not $workById.ContainsKey([string]$workId)) {
                $errors.Add("acceptance item '$($row.acceptance_item)' maps to unknown Work ID '$workId'")
            }
        }
    }
    foreach ($workPackage in $workPackages) {
        foreach ($acceptanceItem in @($workPackage.acceptance_items)) {
            $matchingRows = @($acceptanceRows | Where-Object acceptance_item -CEQ $acceptanceItem)
            if ($matchingRows.Count -ne 1 -or $matchingRows[0].status -cne 'Incomplete' -or [string]$workPackage.work_id -cnotin @($matchingRows[0].work_ids)) {
                $errors.Add("Work ID '$($workPackage.work_id)' is not bidirectionally mapped to incomplete acceptance item '$acceptanceItem'")
            }
        }
    }
    return $errors
}

function Get-ScenarioErrors([object]$Scenario, [object]$Document) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $prefix = "Scenario $($Scenario.id)"
    $phase = 'Fresh'
    $standardStarts = 0
    $afterReentry = $false

    $route = $Scenario.route
    $validAdaptiveRoute = $route.implementation_route -ceq 'adaptive' `
        -and $route.implementation_route_source -ceq 'default' `
        -and $route.design_pair_handoff -ceq 'N/A'
    $validDesignPairRoute = $route.implementation_route -ceq 'design-pair' `
        -and $route.implementation_route_source -ceq 'explicit-user-selection' `
        -and -not [string]::IsNullOrWhiteSpace([string]$route.design_pair_handoff) `
        -and $route.design_pair_handoff -cne 'N/A'

    if (-not ($validAdaptiveRoute -or $validDesignPairRoute)) {
        $events = @($Scenario.events)
        if ($events.Count -ne 1 `
            -or $events[0].verdict -cne 'BLOCKED' `
            -or $events[0].stop_reason -cne 'BlockedByInvalidCompletionHandoff' `
            -or $events[0].write_owner -cne 'none' `
            -or $events[0].adaptive_default_inferred -ne $false) {
            $errors.Add("$prefix must fail closed on invalid route identity without inferring Adaptive or assigning a write owner.")
        }
        $phase = 'Blocked'
    }
    else {
        foreach ($event in @($Scenario.events)) {
            if ($phase -in @('Completed', 'Blocked')) {
                $errors.Add("$prefix emitted an event after terminal state $phase.")
                continue
            }
            if ($event.kind -ceq 'start') {
                if ($event.owner -ceq 'high-implementation-starter' -and $phase -in @('Fresh', 'HighReentryReady')) {
                    $phase = 'HighActive'
                }
                elseif ($event.owner -ceq 'standard-implementation-completer' -and $phase -ceq 'StandardReady') {
                    $standardStarts++
                    $phase = 'StandardActive'
                }
                else {
                    $errors.Add("$prefix started '$($event.owner)' from invalid state $phase.")
                }
                continue
            }
            if ($event.kind -cne 'verdict') {
                $errors.Add("$prefix has an unknown event kind '$($event.kind)'.")
                continue
            }

            if ($event.owner -ceq 'high-implementation-starter') {
                if ($phase -cne 'HighActive') {
                    $errors.Add("$prefix emitted a HIGH verdict from invalid state $phase.")
                    continue
                }
                if ($event.verdict -ceq 'COMPLETED_BY_HIGH_MODEL') {
                    $reasonValid = $event.direct_completion_reason -cin $script:allowedDirectCompletionReasons `
                        -and -not [string]::IsNullOrWhiteSpace([string]$event.direct_completion_evidence) `
                        -and ($event.direct_completion_reason -cne 'post-reentry-high-ownership' -or $afterReentry) `
                        -and ($event.direct_completion_reason -cne 'tiny-local-change' -or $event.meaningful_work_package_remaining -eq $false)
                    if (-not $reasonValid) {
                        if ($event.expected_rejected -ne $true) {
                            $errors.Add("$prefix accepted HIGH direct completion without a valid phase-appropriate reason and evidence.")
                        }
                    }
                    else {
                        $phase = 'Completed'
                    }
                }
                elseif ($event.verdict -ceq 'READY_FOR_STANDARD_COMPLETION') {
                    $handoffErrors = @(Get-HandoffErrors (Get-ResolvedHandoff $event $Document))
                    if ($afterReentry -and $event.delegation_surface_reduced -ne $true) {
                        $handoffErrors += 'delegation surface did not strictly shrink after re-entry'
                    }
                    if ($handoffErrors.Count -gt 0) {
                        if ($event.expected_rejected -ne $true) {
                            $errors.Add("$prefix accepted an invalid completion handoff: $($handoffErrors -join '; ').")
                        }
                    }
                    else {
                        if ($validDesignPairRoute -and -not (Test-SequenceEqual @($event.locked_decision_ids) @($route.locked_decision_ids))) {
                            $errors.Add("$prefix changed Design Pair Decision IDs in the completion handoff.")
                        }
                        $phase = 'StandardReady'
                    }
                }
                else {
                    $errors.Add("$prefix has an unsupported HIGH verdict '$($event.verdict)'.")
                }
            }
            elseif ($event.owner -ceq 'standard-implementation-completer') {
                if ($phase -cne 'StandardActive') {
                    $errors.Add("$prefix emitted a STANDARD verdict from invalid state $phase.")
                    continue
                }
                if ($event.verdict -ceq 'COMPLETED') {
                    if (Has-Property $event 'local_choices') {
                        foreach ($choice in @($event.local_choices)) {
                            if ($choice -cnotin $script:allowedLocalChoices) {
                                $errors.Add("$prefix used an unauthorized local choice '$choice'.")
                            }
                        }
                    }
                    if ($event.changed_locked_decision -eq $true) {
                        $errors.Add("$prefix allowed STANDARD to change a locked decision.")
                    }
                    if ($validDesignPairRoute -and -not (Test-SequenceEqual @($event.locked_decision_ids) @($route.locked_decision_ids))) {
                        $errors.Add("$prefix failed to preserve Design Pair Decision IDs through STANDARD completion.")
                    }
                    $phase = 'Completed'
                }
                elseif ($event.verdict -ceq 'NEEDS_HIGH_MODEL_REENTRY') {
                    if ($event.locked_non_local_decision_change_required -ne $true -or $event.edit_type_only -eq $true) {
                        $errors.Add("$prefix used NEEDS_HIGH_MODEL_REENTRY without a locked non-local decision change.")
                    }
                    $trackedState = Get-ResolvedTrackedState $event $Document
                    foreach ($field in $script:canonicalRequiredReentryState) {
                        if (-not (Has-Property $trackedState $field)) {
                            $errors.Add("$prefix re-entry state is missing '$field'.")
                        }
                    }
                    if ($trackedState.implementation_route -cne $route.implementation_route `
                        -or $trackedState.implementation_route_source -cne $route.implementation_route_source `
                        -or $trackedState.design_pair_handoff -cne $route.design_pair_handoff) {
                        $errors.Add("$prefix changed route identity in re-entry state.")
                    }
                    $afterReentry = $true
                    $phase = 'HighReentryReady'
                }
                else {
                    $errors.Add("$prefix has an unsupported STANDARD verdict '$($event.verdict)'.")
                }
            }
            else {
                $errors.Add("$prefix has an invalid verdict owner '$($event.owner)'.")
            }
        }
    }

    if ($phase -cne $Scenario.expected.final_state) {
        $errors.Add("$prefix ended in $phase; expected $($Scenario.expected.final_state).")
    }
    if ($standardStarts -ne [int]$Scenario.expected.standard_starts) {
        $errors.Add("$prefix started STANDARD $standardStarts time(s); expected $($Scenario.expected.standard_starts).")
    }
    if (Has-Property $Scenario.expected 'high_model_code_changes') {
        $readyEvent = @($Scenario.events | Where-Object verdict -CEQ 'READY_FOR_STANDARD_COMPLETION')[0]
        $handoff = Get-ResolvedHandoff $readyEvent $Document
        if ($handoff.high_model_code_changes -ne $Scenario.expected.high_model_code_changes) {
            $errors.Add("$prefix did not preserve the expected HIGH_MODEL code-change state.")
        }
    }
    if (Has-Property $Scenario.expected 'required_local_choices') {
        $completion = @($Scenario.events | Where-Object verdict -CEQ 'COMPLETED')[0]
        foreach ($choice in @($Scenario.expected.required_local_choices)) {
            if ($choice -cnotin @($completion.local_choices)) {
                $errors.Add("$prefix did not exercise required STANDARD local choice '$choice'.")
            }
        }
    }
    if (Has-Property $Scenario.expected 'locked_wiring_implemented') {
        $completion = @($Scenario.events | Where-Object verdict -CEQ 'COMPLETED')[0]
        if ($completion.locked_wiring_implemented -ne $Scenario.expected.locked_wiring_implemented) {
            $errors.Add("$prefix did not exercise locked wiring implementation.")
        }
    }
    return $errors
}

function Assert-RejectedMutation([string]$Name, [object]$Document, [scriptblock]$Mutate) {
    $copy = Copy-Object $Document
    & $Mutate $copy
    $scenario = Get-Scenario $copy $Name.Substring(0, 1)
    if (@(Get-ScenarioErrors $scenario $copy).Count -eq 0) {
        throw "Mutation '$Name' was incorrectly accepted."
    }
}

if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    throw "Routing fixture was not found: $FixturePath"
}

$document = Get-Content -Raw -LiteralPath $FixturePath | ConvertFrom-Json
if ($document.schema_version -ne 3 -or $document.contract -cne 'adaptive-implementation-execution') {
    throw 'Routing fixture identity or schema version is invalid.'
}
if (-not (Test-SequenceEqual @($document.required_decision_closure) $script:canonicalRequiredDecisionClosure)) {
    throw 'Routing fixture must declare the complete decision-closure concern set in contract order.'
}
if (-not (Test-SequenceEqual @($document.required_reentry_state) $script:canonicalRequiredReentryState)) {
    throw 'Routing fixture must declare the complete canonical re-entry state in contract order.'
}
if (-not (Test-SequenceEqual @($document.scenarios.id) @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'))) {
    throw 'Routing scenarios must contain the ordered A-J contract.'
}

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($scenario in @($document.scenarios)) {
    foreach ($errorMessage in @(Get-ScenarioErrors $scenario $document)) {
        $failures.Add($errorMessage)
    }
}
if ($failures.Count -gt 0) {
    throw ("Adaptive routing scenario validation failed:`n- " + ($failures -join "`n- "))
}

Assert-RejectedMutation 'A-missing-high-code-change-state' $document {
    param($copy)
    $handoff = ((Get-Scenario $copy 'A').events | Where-Object verdict -CEQ 'READY_FOR_STANDARD_COMPLETION').handoff
    $handoff.PSObject.Properties.Remove('high_model_code_changes')
}
Assert-RejectedMutation 'A-incomplete-work-package' $document {
    param($copy)
    $workPackage = ((Get-Scenario $copy 'A').events | Where-Object verdict -CEQ 'READY_FOR_STANDARD_COMPLETION').handoff.remaining_work[0]
    $workPackage.PSObject.Properties.Remove('completion_check')
}
Assert-RejectedMutation 'A-broken-acceptance-mapping' $document {
    param($copy)
    $acceptance = ((Get-Scenario $copy 'A').events | Where-Object verdict -CEQ 'READY_FOR_STANDARD_COMPLETION').handoff.acceptance_status[0]
    $acceptance.work_ids = @('RW-missing')
}
Assert-RejectedMutation 'B-change-locked-decision' $document {
    param($copy)
    ((Get-Scenario $copy 'B').events | Where-Object verdict -CEQ 'COMPLETED').changed_locked_decision = $true
}
Assert-RejectedMutation 'C-edit-type-only-reentry' $document {
    param($copy)
    $event = (Get-Scenario $copy 'C').events | Where-Object verdict -CEQ 'COMPLETED'
    $event.verdict = 'NEEDS_HIGH_MODEL_REENTRY'
    $event | Add-Member -NotePropertyName locked_non_local_decision_change_required -NotePropertyValue $false
    $event | Add-Member -NotePropertyName edit_type_only -NotePropertyValue $true
}
Assert-RejectedMutation 'D-missing-reentry-state' $document {
    param($copy)
    $event = (Get-Scenario $copy 'D').events | Where-Object verdict -CEQ 'NEEDS_HIGH_MODEL_REENTRY'
    $event.tracked_state.PSObject.Properties.Remove('validation')
}
Assert-RejectedMutation 'E-accept-reasonless-completion' $document {
    param($copy)
    ((Get-Scenario $copy 'E').events | Where-Object verdict -CEQ 'COMPLETED_BY_HIGH_MODEL').expected_rejected = $false
}
Assert-RejectedMutation 'F-use-post-reentry-reason-initially' $document {
    param($copy)
    ((Get-Scenario $copy 'F').events | Where-Object verdict -CEQ 'COMPLETED_BY_HIGH_MODEL').direct_completion_reason = 'post-reentry-high-ownership'
}
Assert-RejectedMutation 'F-tiny-with-meaningful-work-remaining' $document {
    param($copy)
    ((Get-Scenario $copy 'F').events | Where-Object verdict -CEQ 'COMPLETED_BY_HIGH_MODEL').meaningful_work_package_remaining = $true
}
Assert-RejectedMutation 'G-accept-unresolved-decision' $document {
    param($copy)
    ((Get-Scenario $copy 'G').events | Where-Object verdict -CEQ 'READY_FOR_STANDARD_COMPLETION').expected_rejected = $false
}
Assert-RejectedMutation 'H-redelegate-without-reduction' $document {
    param($copy)
    ((Get-Scenario $copy 'H').events | Where-Object { $_.verdict -ceq 'READY_FOR_STANDARD_COMPLETION' -and $_.expected_rejected -eq $true }).expected_rejected = $false
}
Assert-RejectedMutation 'I-infer-adaptive-default' $document {
    param($copy)
    (Get-Scenario $copy 'I').events[0].adaptive_default_inferred = $true
}
Assert-RejectedMutation 'J-change-locked-decision' $document {
    param($copy)
    ((Get-Scenario $copy 'J').events | Where-Object verdict -CEQ 'COMPLETED').changed_locked_decision = $true
}

Write-Output 'Adaptive routing scenario validation: PASS'
