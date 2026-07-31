[CmdletBinding()]
param(
    [string]$FixturePath = (Join-Path $PSScriptRoot 'routing-scenarios.json')
)

$ErrorActionPreference = 'Stop'
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

function Has-Property([object]$Object, [string]$Name) {
    return $null -ne $Object -and $Name -in $Object.PSObject.Properties.Name
}

function Test-SequenceEqual([object[]]$Actual, [object[]]$Expected) {
    return (@($Actual) -join "`n") -ceq (@($Expected) -join "`n")
}

function Get-ScenarioErrors([object]$Scenario, [string[]]$RequiredReentryState) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $prefix = "Scenario $($Scenario.id)"
    $phase = 'Fresh'
    $standardStarts = 0
    $afterReentry = $false
    $delegationSurfaceReduced = $true

    $route = $Scenario.route
    $validAdaptiveRoute = $route.implementation_route -ceq 'adaptive' `
        -and $route.implementation_route_source -ceq 'default' `
        -and $route.design_pair_handoff -ceq 'N/A'
    $validDesignPairRoute = $route.implementation_route -ceq 'design-pair' `
        -and $route.implementation_route_source -ceq 'explicit-user-selection' `
        -and -not [string]::IsNullOrWhiteSpace([string]$route.design_pair_handoff) `
        -and $route.design_pair_handoff -cne 'N/A'
    $validRoute = $validAdaptiveRoute -or $validDesignPairRoute

    if (-not $validRoute) {
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
                if ($event.owner -ceq 'high-implementation-starter') {
                    if ($phase -notin @('Fresh', 'HighReentryReady')) {
                        $errors.Add("$prefix started HIGH from invalid state $phase.")
                    }
                    else {
                        $phase = 'HighActive'
                    }
                }
                elseif ($event.owner -ceq 'standard-implementation-completer') {
                    if ($phase -cne 'StandardReady') {
                        $errors.Add("$prefix started STANDARD without a valid READY_FOR_STANDARD_COMPLETION handoff.")
                    }
                    else {
                        $standardStarts++
                        $phase = 'StandardActive'
                    }
                }
                else {
                    $errors.Add("$prefix has an unknown start owner '$($event.owner)'.")
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
                    $phase = 'Completed'
                }
                elseif ($event.verdict -ceq 'READY_FOR_STANDARD_COMPLETION') {
                    $handoffValid = (Has-Property $event 'handoff') `
                        -and $event.handoff.valid -eq $true `
                        -and @($event.handoff.remaining_work).Count -gt 0 `
                        -and @($event.handoff.allowed_edit_surface).Count -gt 0
                    if (-not $handoffValid) {
                        if ($event.expected_rejected -ne $true) {
                            $errors.Add("$prefix attempted STANDARD delegation with an incomplete handoff.")
                        }
                    }
                    elseif ($afterReentry -and -not $delegationSurfaceReduced) {
                        $errors.Add("$prefix re-delegated after re-entry without a strictly reduced completion surface.")
                    }
                    else {
                        if ($validDesignPairRoute -and -not (Test-SequenceEqual @($event.handoff.locked_decision_ids) @($route.locked_decision_ids))) {
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
                    if ($validDesignPairRoute) {
                        if ($event.changed_locked_decision -ne $false) {
                            $errors.Add("$prefix allowed STANDARD to change a locked Design Pair decision.")
                        }
                        if (-not (Test-SequenceEqual @($event.locked_decision_ids) @($route.locked_decision_ids))) {
                            $errors.Add("$prefix failed to preserve Design Pair Decision IDs through STANDARD completion.")
                        }
                    }
                    $phase = 'Completed'
                }
                elseif ($event.verdict -ceq 'NEEDS_HIGH_MODEL_REENTRY') {
                    if ($event.structural_trigger -ne $true) {
                        $errors.Add("$prefix used NEEDS_HIGH_MODEL_REENTRY without a structural trigger.")
                    }
                    foreach ($field in $RequiredReentryState) {
                        if (-not (Has-Property $event.tracked_state $field)) {
                            $errors.Add("$prefix re-entry state is missing '$field'.")
                        }
                    }
                    if ($event.tracked_state.implementation_route -cne $route.implementation_route `
                        -or $event.tracked_state.implementation_route_source -cne $route.implementation_route_source `
                        -or $event.tracked_state.design_pair_handoff -cne $route.design_pair_handoff) {
                        $errors.Add("$prefix changed route identity in re-entry state.")
                    }
                    $delegationSurfaceReduced = $event.tracked_state.delegation_surface_reduced -eq $true
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

    return $errors
}

function Copy-Document([object]$Document) {
    return ($Document | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function Get-Scenario([object]$Document, [string]$Id) {
    return @($Document.scenarios | Where-Object id -CEQ $Id)[0]
}

function Assert-RejectedMutation([string]$Name, [object]$Document, [scriptblock]$Mutate) {
    $copy = Copy-Document $Document
    & $Mutate $copy
    $scenario = Get-Scenario $copy $Name.Substring(0, 1)
    $errors = @(Get-ScenarioErrors $scenario $script:canonicalRequiredReentryState)
    if ($errors.Count -eq 0) {
        throw "Mutation '$Name' was incorrectly accepted."
    }
}

if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    throw "Routing fixture was not found: $FixturePath"
}

$document = Get-Content -Raw -LiteralPath $FixturePath | ConvertFrom-Json
if ($document.schema_version -ne 2 -or $document.contract -cne 'adaptive-implementation-execution') {
    throw 'Routing fixture identity or schema version is invalid.'
}
if (-not (Test-SequenceEqual @($document.required_reentry_state) $script:canonicalRequiredReentryState)) {
    throw 'Routing fixture must declare the complete canonical re-entry state in contract order.'
}

$ids = @($document.scenarios.id)
if (-not (Test-SequenceEqual $ids @('A', 'B', 'C', 'D', 'E', 'F', 'G'))) {
    throw "Routing scenarios must contain the ordered A-G contract. Observed: $($ids -join ', ')"
}

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($scenario in @($document.scenarios)) {
    foreach ($errorMessage in @(Get-ScenarioErrors $scenario $script:canonicalRequiredReentryState)) {
        $failures.Add($errorMessage)
    }
}
if ($failures.Count -gt 0) {
    throw ("Adaptive routing scenario validation failed:`n- " + ($failures -join "`n- "))
}

Assert-RejectedMutation 'B-standard-direct-start' $document {
    param($copy)
    (Get-Scenario $copy 'B').events[0].owner = 'standard-implementation-completer'
}
Assert-RejectedMutation 'C-invalid-handoff-accepted' $document {
    param($copy)
    $scenario = Get-Scenario $copy 'C'
    $scenario.events += [pscustomobject]@{ kind = 'start'; owner = 'standard-implementation-completer' }
}
Assert-RejectedMutation 'D-missing-reentry-state' $document {
    param($copy)
    $event = (Get-Scenario $copy 'D').events | Where-Object verdict -CEQ 'NEEDS_HIGH_MODEL_REENTRY'
    $event.tracked_state.PSObject.Properties.Remove('validation')
}
Assert-RejectedMutation 'E-redelegate-without-reduction' $document {
    param($copy)
    $event = (Get-Scenario $copy 'E').events[-1]
    $event.verdict = 'READY_FOR_STANDARD_COMPLETION'
    $event | Add-Member -NotePropertyName handoff -NotePropertyValue ([pscustomobject]@{ valid = $true; remaining_work = @('W-2'); allowed_edit_surface = @('src/Bounded.cs') })
}
Assert-RejectedMutation 'F-infer-adaptive-default' $document {
    param($copy)
    (Get-Scenario $copy 'F').events[0].adaptive_default_inferred = $true
}
Assert-RejectedMutation 'G-change-locked-decision' $document {
    param($copy)
    $event = (Get-Scenario $copy 'G').events | Where-Object verdict -CEQ 'COMPLETED'
    $event.changed_locked_decision = $true
}

Write-Output 'Adaptive routing scenario validation: PASS'
