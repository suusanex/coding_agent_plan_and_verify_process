# Issue #21 Codex-first Routing MVP Validation

## Source of truth

- GitHub issue: `https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/21`
- Issue title: `Codex-firstルーティングMVPを手動スキル指定で検証する`
- Issue comments: none at planning time
- PR #20 source artifacts: merge commit `068c37d`
- Scope: sample validation only

## Summary

Issue #21 validates that the Codex-first routing MVP can classify representative work when the user manually invokes `$codex-first-cost-router`.
This is a docs-only validation pass. It does not implement enforcement hardening, Hook audit, plugin packaging, Copilot fallback, or any external / production operation.

This PR validates the routing contract and expected classifications.
It does not yet prove that a fresh Codex session will automatically load and invoke the installed `$codex-first-cost-router` skill.
Operator validation must capture that runtime trigger separately before broader rollout.

## Created artifacts

| Artifact | Purpose |
| --- | --- |
| `apm-packages/codex-first-ai-development-process/docs/examples/routing-mvp-validation.md` | Five-sample validation suite with expected routing and dry-run classification |
| `plans/issue-21-codex-first-routing-mvp-validation.md` | Issue-level validation report, management handoff, and remaining work |

## Changed files

| File | Change |
| --- | --- |
| `apm-packages/codex-first-ai-development-process/docs/examples/routing-mvp-validation.md` | Added manual validation samples for lightweight, normal, full-coverage, resume, and Hook / Plugin cases |
| `apm-packages/codex-first-ai-development-process/docs/user-guide.md` | Split the single MVP sample from the broader validation suite |
| `plans/issue-21-codex-first-routing-mvp-validation.md` | Added this issue report |

## Validation matrix

| Sample | Manual prompt | Task Weight | Selected Process | Model Tier Recommendation | Agent / Subagent Plan | Edit Permission | DelegationRequired | Stop / Ready Gate | Dry-run result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Lightweight local fix | `$codex-first-cost-router` typo fix | `trivial-local` | `lower-cost-delegated-scan` or trivial `normal` | `CHEAP_MODEL` | `cheap-doc-consistency` or parent `TRIVIAL_PARENT_FIX` | No during routing | No unless delegated scan selected | Ready after exact typo target is known | matches |
| Normal bounded implementation | `$codex-first-cost-router` `--json` option | `small-bounded` | `normal` | `STANDARD_MODEL` | `standard-implementer`, then `standard-verifier` | No until READY; then `standard-implementer` | Yes | `ReadyForDelegatedImplementation` / `ReadyForDelegatedVerification` | matches |
| Full-coverage candidate | `$codex-first-cost-router` order / inventory / payment / compensation | `broad-full-coverage-candidate` | `advanced-full-coverage` | `HIGH_MODEL` | decomposition first; slice implementation only after READY | No | Later for READY slices | decomposition next action; no edit | matches |
| Resume from state | `$codex-first-cost-router` `続きやって` | existing state value | existing `normal` | `STANDARD_MODEL` for verifier | `standard-verifier` | verifier-owned checks only | Yes | delegated verification or `DelegationEvidenceMissing` | matches |
| Hook / Plugin change | `$codex-first-cost-router` hook block / plugin rollout | `blocked-human-required` or `high-risk-bounded` | `human-decision-wait` | `HIGH_MODEL` | high plan / risk only | No | No implementation delegation yet | `NeedsHumanDecision` | matches |

## Routing vocabulary coverage

The validation suite explicitly covers:

- Routing Plan
- Task Weight
- Selected Process
- Model Tier Recommendation
- Agent / Subagent Plan
- Edit Permission
- DelegationRequired
- Stop / Ready Gate
- Parent Plan Coverage Ledger
- Residual Decision Ledger
- ManualVerificationRequired

## Parent Plan Coverage Ledger sample

| Issue requirement | Evidence | Status |
| --- | --- | --- |
| Manual skill prompt samples exist | Five samples in `routing-mvp-validation.md` | covered |
| Lightweight fix sample exists | Sample 1 | covered |
| Normal implementation sample exists | Sample 2 | covered |
| Full-coverage branch sample exists | Sample 3 | covered |
| Resume sample exists | Sample 4 | covered |
| Hook / Plugin sample exists | Sample 5 | covered |
| Expected routing results are recorded | Validation matrix and sample tables | covered |
| Coverage ledger sample exists | This section and example docs | covered |
| Residual decision ledger sample exists | Next section and example docs | covered |
| Not READY means no implementation | Samples 1, 3, and 5 | covered |
| ManualVerificationRequired prevents close | Residual Decision Ledger sample | covered |
| Missing work is organized as follow-up candidates | Remaining work section | covered |

## Residual Decision Ledger sample

| Residual | Candidate / decision status | Scope note | Close allowed for Issue #21? | Required owner / next step |
| --- | --- | --- | --- | --- |
| Real organization repository validation | `DeferredWithOwner` | Outside Issue #21 sample validation | Yes | Owner: management repo; choose target repositories later |
| Real model mapping | `DeferredWithOwner` | Later rollout decision, not this docs-only MVP | Yes | Owner: maintainer; decide real model table |
| Plugin trust boundary | `NeedsHumanDecision` | Blocks plugin implementation, not this validation-suite artifact | Yes for this docs-only MVP; No for plugin implementation | Management repo / maintainer decision |
| Hook block scope | `NeedsHumanDecision` | Blocks hook implementation, not this validation-suite artifact | Yes for this docs-only MVP; No for hook implementation | Management repo / maintainer decision |
| Real payment sandbox validation in sample | `ManualVerificationRequired` | Hypothetical full-coverage sample evidence, not Issue #21 required evidence | No for that hypothetical feature; not part of Issue #21 close | Human owner, method, and evidence required |
| Copilot fallback parity | `DeferredWithOwner` | Deferred from this MVP into follow-up work | Yes | Owner: management repo; follow-up: `copilot-fallback-sync` |

`ManualVerificationRequired` remains close-blocking unless an explicit human decision converts it to an accepted residual with owner, method, and required evidence.

## Actual output summary

Codex-produced classification output is captured for all five samples in `routing-mvp-validation.md`.
The captured classification matched the expected output for all five samples.
This validates the routing contract from the local router skill, state template, and cost router goals.

The actual `$codex-first-cost-router` runtime trigger was not independently captured in this session because this Codex thread did not have that local package skill listed as an active callable skill.
The operator validation procedure in `routing-mvp-validation.md` documents how to capture that runtime evidence in a Codex-first profile or installer-prepared repository.

No sample required production code changes, C# script changes, external service calls, GitHub settings changes, secrets, billing operations, or organization repository rollout.

## Commands to run

```powershell
git diff --check
rg -n "Routing Plan|Task Weight|Selected Process|Model Tier Recommendation|Agent / Subagent Plan|Edit Permission|DelegationRequired|Stop / Ready Gate|Parent Plan Coverage Ledger|Residual Decision Ledger|ManualVerificationRequired" plans\issue-21-codex-first-routing-mvp-validation.md apm-packages\codex-first-ai-development-process\docs\examples\routing-mvp-validation.md
```

## Commands not required

`dotnet publish` is not required because this issue changes only Markdown documentation and does not modify `install-codex-first-local.cs` or other C# scripts.

## Unverified items

- `$codex-first-cost-router` runtime trigger evidence from an installed Codex-first profile was not captured in this session.
- No real Codex hook payload was captured.
- No plugin package was built.
- No Copilot fallback workflow was exercised.
- No organization repository was used as a live validation target.
- No effective billing model was independently verified.

## Human / operator execution needed

| Item | Codex can do here? | Human / operator needed? | Reason |
| --- | --- | --- | --- |
| Classify the five samples from the routing contract | Yes | No | The local router skill and docs define the expected route vocabulary |
| Record captured classification output | Yes | No | Captured in `routing-mvp-validation.md` |
| Verify that `$codex-first-cost-router` is loaded as an active runtime skill | No | Yes | Requires a Codex session/profile where the package skill is installed or loaded |
| Capture hook payload evidence | No | Yes | Requires hook configuration and runtime events |
| Validate plugin trust / hook block scope | No | Yes | Requires maintainer decisions before implementation |
| Run against organization repositories | No | Yes | Out of scope and requires repository selection |

## Remaining work

Recommended next ready candidate: `enforcement-hardening`.

Reason: this MVP demonstrates that the routing vocabulary can classify the target cases, but the next practical risk is accidental bypass of READY, edit owner, or delegation rules. Hardening the instructions before Hook audit or plugin packaging reduces the chance that later automation preserves weak policy text.

| Candidate | Suggested status | Reason |
| --- | --- | --- |
| `enforcement-hardening` | ready-next | Strengthens documented routing and delegation rules before automation |
| `hook-audit` | proposed / NeedsHumanDecision | Needs hook block scope and trust decisions |
| `plugin-package` | proposed / NeedsHumanDecision | Needs plugin trust and rollout decisions |
| `copilot-fallback-sync` | proposed | Should follow Codex-first MVP stabilization |

## Management repo handoff

- suggested_management_status: `completed-needs-review`
- remaining_work: `enforcement-hardening` should be readied next
- human_required_items:
  - real model mapping table
  - organization rollout repository selection
  - plugin trust boundary
  - Hook block scope
  - Copilot fallback conditions

## Completion note

This issue can be treated as sample validation complete after docs review and local Markdown diff checks pass.
