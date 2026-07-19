# Example: Routing MVP Validation Suite

この suite は、`codex-first-cost-router` を手動スキル指定で呼び出した場合の MVP 検証用サンプルである。
実リポジトリ、secret、課金、GitHub 設定、外部サービス、本番環境は変更しない。

## Validation limitation

This suite validates the routing contract and expected classifications.
It does not yet prove that a fresh Codex session will automatically load and invoke the installed `$codex-first-cost-router` skill.
Operator validation must capture that runtime trigger separately before broader rollout.

For Issue #38 lite / standard validation, use `docs/examples/lite-standard-validation.md`.
That suite checks `documentation_level`, Lite artifact shape, canonical ledger / delta behavior, direct FixNow conditions, unified implementation contract behavior, artifact count, and negative scans.

## Validation rule

各サンプルは次の項目を確認する。

- Routing Plan
- Task Weight
- Selected Process
- Model Tier Recommendation
- Agent / Subagent Plan
- Edit Permission
- DelegationRequired
- Stop / Ready Gate

`Captured Codex classification output` は、この repository に含まれる router skill、state template、cost router goals に照らして Codex が分類した出力である。
このセッションでは対象 profile に install 済みの `$codex-first-cost-router` skill としての runtime trigger 証跡は取得していない。
runtime trigger まで確認する場合は、末尾の operator validation procedure に従って、Codex-first profile または installer 適用済み repository で同じ prompt を実行する。

## Sample 1: lightweight local fix

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- docs/examples/simple-local-fix.md の typo を 1 箇所直す。
- 挙動変更、外部 API、secret、本番操作はない。
- 変更後は diff review だけで確認できる。
```

### Expected routing

| Field | Expected value |
| --- | --- |
| Task Weight | `trivial-local` |
| Selected Process | `lower-cost-delegated-scan` or `normal` trivial route |
| Model Tier Recommendation | `CHEAP_MODEL` for scan / format check |
| Agent / Subagent Plan | `cheap-doc-consistency` when delegated scan is useful; otherwise parent `TRIVIAL_PARENT_FIX` |
| Edit Permission | `allowed_to_edit: No` during route-only classification; trivial edit may require `TRIVIAL_PARENT_FIX` reason |
| DelegationRequired | `No` unless Routing Plan chooses cheap delegated check |
| Stop / Ready Gate | Ready only after target file and typo are identified |

### Expected Routing Plan excerpt

```text
Routing Plan:
- Intake: CHEAP_MODEL or STANDARD_MODEL, parent may classify.
- Scan: CHEAP_MODEL, cheap-doc-consistency if delegated.
- Implementation: CHEAP_MODEL or TRIVIAL_PARENT_FIX only after target is explicit.

Edit Permission:
- allowed_to_edit: No during Intake / Scan.
- parent_direct_edit_allowed: Yes only for documented TRIVIAL_PARENT_FIX.
```

### Actual dry-run classification

Matches expected. The task is local, explicit, and low risk. The router must still avoid claiming cost-saving delegation unless a cheap delegated run is recorded.

### Captured Codex classification output

```text
task_weight: trivial-local
selected_process: lower-cost-delegated-scan or normal
current_gate: Intake
next_gate: Scan
recommended_model_tier: CHEAP_MODEL
model_tier_recommendation: CHEAP_MODEL for target confirmation and format / docs consistency check
execution_mode: ROUTE_ONLY
selected_agent_name: cheap-doc-consistency if delegated; none if handled as TRIVIAL_PARENT_FIX
delegation_required: No unless the Routing Plan explicitly delegates the scan
allowed_to_edit: No
edit_owner: none
parent_direct_edit_allowed: No during route-only classification
stop_ready_gate: Ready only after the exact file and typo are identified
stop_reason: None
delegation_violation: No
cost_saving_delegation_countable: No without observed cheap delegated run evidence
```

### Gap / follow-up

No MVP blocker. Enforcement hardening can later make the parent-direct trivial exception harder to misuse.

## Sample 2: normal bounded implementation

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- Add a `--json` option to an existing local report command.
- Existing text output must remain unchanged unless `--json` is specified.
- The command already has unit tests.
- No external API, secret, billing, or production environment is involved.
```

### Expected routing

| Field | Expected value |
| --- | --- |
| Task Weight | `small-bounded` |
| Selected Process | `normal` |
| Model Tier Recommendation | `HIGH_MODEL` for implementation start, conditional `STANDARD_MODEL` completion, `STANDARD_MODEL` for verification |
| Agent / Subagent Plan | `implementation-handoff-review` before READY implementation, `high-implementation-starter` first, `standard-implementation-completer` only after valid handoff, `standard-verifier` for verification |
| Edit Permission | `allowed_to_edit: No` before Plan / risk / handoff review; `edit_owner: high-implementation-starter` after parent authorization artifact exists |
| DelegationRequired | `Yes` for implementation and verification |
| Stop / Ready Gate | `ReadyForImplementationHandoffReview` after bounded Plan, `plans/<slug>-change-risk-triage.md`, allowed paths, and compatibility rule exist; `ReadyForHighImplementationStart` after parent authorization artifact exists |

### Expected Routing Plan excerpt

```text
Routing Plan:
- Plan: STANDARD_MODEL or HIGH_MODEL if ambiguity appears.
- Risk: STANDARD_MODEL.
- Implementation handoff review: HIGH_MODEL or STANDARD_MODEL, edit_owner = implementation-handoff-review.
- Implementation start: HIGH_MODEL, DelegationRequired = Yes, edit_owner = high-implementation-starter.
- Bounded completion: STANDARD_MODEL only after valid handoff, DelegationRequired = Yes, edit_owner = standard-implementation-completer.
- Verification: STANDARD_MODEL, DelegationRequired = Yes, edit_owner = standard-verifier.

Stop / Ready Gate:
- Stop with ReadyForImplementationHandoffReview until parent authorization artifact exists.
- Stop with ReadyForHighImplementationStart until observed high-implementation-starter run exists.
- Stop with ReadyForStandardCompletion only after a valid handoff exists.
- Stop with ReadyForDelegatedVerification until observed standard-verifier run exists.
```

### Actual dry-run classification

Matches expected. The compatibility condition makes the task non-trivial, but the scope is bounded to one local command and test path.

### Captured Codex classification output

```text
task_weight: small-bounded
selected_process: normal
current_gate: Plan
next_gate: Risk
recommended_model_tier: STANDARD_MODEL
model_tier_recommendation: HIGH_MODEL for implementation start; STANDARD_MODEL for valid bounded completion and verification
execution_mode: ROUTE_ONLY before READY and handoff review, then DELEGATED_WORK
selected_agent_name: implementation-handoff-review before implementation; high-implementation-starter for READY implementation start; standard-implementation-completer only after valid handoff; standard-verifier for verification
delegation_required: Yes for Implementation and Verification
allowed_to_edit: No before READY
edit_owner: high-implementation-starter after READY implementation is authorized; standard-implementation-completer only while consuming a valid handoff
parent_direct_edit_allowed: No
shape_handoff_status: NotStarted before HIGH start; Ready only after a complete handoff; Consumed while STANDARD owns the bounded remainder
remaining_design_uncertainty: Unknown before HIGH start; None before STANDARD completion
completion_scope: N/A before handoff; Work IDs and allowed edit surface after handoff
shape_reentry_reason: N/A unless STANDARD returns NEEDS_HIGH_MODEL_REENTRY
stop_ready_gate: ReadyForImplementationHandoffReview after bounded Plan, plans/<slug>-change-risk-triage.md, allowed paths, and compatibility rule exist; ReadyForHighImplementationStart after parent authorization artifact exists
stop_reason: ReadyForHighImplementationStart until an observed high-implementation-starter run exists
delegation_violation: No while no parent-direct edit occurs
cost_saving_delegation_countable: No until observed delegated run evidence exists
```

### Gap / follow-up

No MVP blocker. Later enforcement should detect parent-direct implementation when `DelegationRequired = Yes`.

## Sample 3: full-coverage candidate

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- Add order creation, inventory reservation, payment request, and compensation handling.
- Retry, timeout, and idempotency behavior must be correct across components.
- Parallelization may be useful.
- No real payment credential is available in this validation.
```

### Expected routing

| Field | Expected value |
| --- | --- |
| Task Weight | `broad-full-coverage-candidate` |
| Selected Process | `advanced-full-coverage` |
| Model Tier Recommendation | `HIGH_MODEL` for Plan / decomposition / cross-slice close judgment |
| Agent / Subagent Plan | `plan-slice-decomposition`, then slice prep / slice implementation only after slice READY |
| Edit Permission | `allowed_to_edit: No` during route and decomposition |
| DelegationRequired | `Yes` later for READY slice implementation; no implementation in this validation |
| Stop / Ready Gate | Stop before implementation with decomposition next action |

### Expected Routing Plan excerpt

```text
Routing Plan:
- Plan: HIGH_MODEL.
- Risk: HIGH_MODEL.
- Decomposition: HIGH_MODEL / advanced full-coverage route.
- Implementation: not READY.

Stop / Ready Gate:
- No edit until slice decomposition, parent review, and READY slice authorization exist.
```

### Actual dry-run classification

Matches expected. Cross-component runtime contracts, retries, compensation, and external payment validation risk exceed a single bounded implementation pass.

### Captured Codex classification output

```text
task_weight: broad-full-coverage-candidate
selected_process: advanced-full-coverage
current_gate: Risk
next_gate: Decomposition
recommended_model_tier: HIGH_MODEL
model_tier_recommendation: HIGH_MODEL for parent Plan, risk triage, decomposition, and cross-slice close judgment
execution_mode: ROUTE_ONLY
selected_agent_name: plan-slice-decomposition after advanced-route confirmation
delegation_required: No for route-only decomposition; Yes later for READY slice implementation
allowed_to_edit: No
edit_owner: none
parent_direct_edit_allowed: No
stop_ready_gate: Stop before implementation until slice decomposition, parent review, and READY slice authorization exist
stop_reason: NeedsHigherModelReview or advanced-route decomposition next action
delegation_violation: No
cost_saving_delegation_countable: No
```

### Gap / follow-up

Real payment sandbox validation remains `ManualVerificationRequired` and cannot be accepted without explicit owner, method, and evidence.

## Sample 4: resume from state

### Manual prompt

```text
$codex-first-cost-router を使って、続きやって。

Existing state excerpt:
- task_slug: sample-json-report
- current_gate: Verification
- next_gate: Close
- selected_process: normal
- allowed_to_edit: Yes
- edit_owner: standard-verifier
- delegation_required: Yes
- stop_reason: ReadyForDelegatedVerification
```

### Expected routing

| Field | Expected value |
| --- | --- |
| Task Weight | reuse existing state value |
| Selected Process | reuse existing `normal` process |
| Model Tier Recommendation | `STANDARD_MODEL` for verifier |
| Agent / Subagent Plan | `standard-verifier` only; do not restart Plan unless state is stale or contradictory |
| Edit Permission | verifier owns verification artifacts / checks only |
| DelegationRequired | `Yes` |
| Stop / Ready Gate | execute only delegated verification or stop with `DelegationEvidenceMissing` |

### Expected Routing Plan excerpt

```text
Routing Plan:
- Resume reads newest matching codex-first-state.md first.
- Resume reads matching codex-first-audit.md when delegation evidence or close permission is needed.
- Verification remains STANDARD_MODEL and delegated.
- Close is blocked until verification evidence and audit DelegationCompliance pass.

Edit Permission:
- edit_owner: standard-verifier.
- parent_direct_edit_allowed: No.
```

### Actual dry-run classification

Matches expected. The router should continue from state and avoid asking the user to choose a model, process, or agent.

### Captured Codex classification output

```text
task_weight: reuse existing state value
selected_process: normal
current_gate: Verification
next_gate: Close
recommended_model_tier: STANDARD_MODEL
model_tier_recommendation: STANDARD_MODEL for delegated verification; HIGH_MODEL only if close risk becomes ambiguous
execution_mode: DELEGATED_WORK
selected_agent_name: standard-verifier
delegation_required: Yes
allowed_to_edit: Yes for verification-owned artifacts and local checks only
edit_owner: standard-verifier
parent_direct_edit_allowed: No
stop_ready_gate: ReadyForDelegatedVerification
stop_reason: DelegationEvidenceMissing if no observed standard-verifier run is recorded
delegation_violation: No unless parent performs verifier-owned work directly
cost_saving_delegation_countable: No until observed standard-verifier evidence exists
```

### Gap / follow-up

If state discovery finds multiple candidates, later enforcement can require a deterministic selection or a minimal human question.

## Sample 5: Hook / Plugin change

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- Add a hook that blocks writes before READY.
- Package it as a plugin for team rollout.
- Define which repos should trust the plugin and which hook events should block.
- Do not change production repositories yet.
```

### Expected routing

| Field | Expected value |
| --- | --- |
| Task Weight | `blocked-human-required` or `high-risk-bounded` |
| Selected Process | `human-decision-wait` until plugin trust and hook block scope are decided |
| Model Tier Recommendation | `HIGH_MODEL` for risk / contract judgment |
| Agent / Subagent Plan | high planner / high risk triage only; no implementation owner yet |
| Edit Permission | `allowed_to_edit: No` |
| DelegationRequired | `No` for implementation because the scope is not READY |
| Stop / Ready Gate | `NeedsHumanDecision` |

### Expected Routing Plan excerpt

```text
Routing Plan:
- Plan: HIGH_MODEL.
- Risk: HIGH_MODEL.
- Implementation: not READY.

human_required_items:
- Decide plugin trust boundary.
- Decide hook block scope.
- Decide rollout targets.
```

### Actual dry-run classification

Matches expected. Hook blocking and plugin trust affect developer workflow and require explicit human decisions before implementation.

### Captured Codex classification output

```text
task_weight: blocked-human-required or high-risk-bounded
selected_process: human-decision-wait
current_gate: Plan
next_gate: HumanDecision
recommended_model_tier: HIGH_MODEL
model_tier_recommendation: HIGH_MODEL for hook / plugin risk and trust boundary analysis
execution_mode: ROUTE_ONLY
selected_agent_name: high-planner or high-risk-triage only
delegation_required: No for implementation because the scope is not READY
allowed_to_edit: No
edit_owner: none
parent_direct_edit_allowed: No
stop_ready_gate: NeedsHumanDecision
stop_reason: NeedsHumanDecision
human_required_items: plugin trust boundary; hook block scope; rollout targets; bypass policy
delegation_violation: No
cost_saving_delegation_countable: No
```

### Gap / follow-up

`hook-audit` and `plugin-package` remain separate work items. This MVP only validates that the router stops safely.

## Parent Plan Coverage Ledger sample

| Parent item | Sample coverage | Status | Evidence |
| --- | --- | --- | --- |
| Manual skill prompt exists | Samples 1-5 include `$codex-first-cost-router` prompts | implemented | This validation suite |
| Lightweight fix classification | Sample 1 records expected and dry-run routing | verified | `trivial-local`, `CHEAP_MODEL` |
| Normal implementation classification | Sample 2 records HIGH start, conditional STANDARD completion, re-entry, and verification gates | verified | `high-implementation-starter`, `standard-implementation-completer`, `standard-verifier` |
| Full-coverage candidate classification | Sample 3 stops before implementation | verified | `advanced-full-coverage` |
| Resume classification | Sample 4 reads existing state first | verified | state excerpt |
| Hook / Plugin classification | Sample 5 stops with human decision | verified | `NeedsHumanDecision` |
| Real organization rollout | Out of scope | ResidualDecisionCandidate | Requires repository selection |

## Residual Decision Ledger sample

| Residual | Candidate / decision status | Scope note | Close allowed? | Required explicit decision or owner |
| --- | --- | --- | --- | --- |
| Real payment sandbox validation | `ManualVerificationRequired` | Hypothetical full-coverage sample evidence | No | Owner, sandbox, credential source, required evidence |
| Plugin trust boundary | `NeedsHumanDecision` | Required before plugin implementation | No | Trusted plugin source and rollout scope |
| Hook block scope | `NeedsHumanDecision` | Required before hook implementation | No | Event list, block behavior, bypass policy |
| Copilot fallback parity | `DeferredWithOwner` | Deferred from this MVP into follow-up work | Yes for this MVP only | Owner: management repo; follow-up: `copilot-fallback-sync` |
| Enforcement hardening | `DeferredWithOwner` | Deferred from this MVP into follow-up work | Yes for this MVP only | Owner: management repo; follow-up: `enforcement-hardening` |

`ManualVerificationRequired` is not an accepted residual. It becomes close-compatible only after an explicit human decision records owner, method, and required evidence.

## Validation result

- The five MVP samples cover the expected routing vocabulary.
- READY implementation is not started in non-READY examples.
- `DelegationRequired = Yes` gates require observed agent evidence before success.
- Close is blocked while `ManualVerificationRequired`, `NeedsHumanDecision`, or missing delegation evidence remains.
- The next ready follow-up should be `enforcement-hardening`, because it turns these documented stop rules into harder-to-bypass guidance before Hook audit or plugin packaging.

## Operator validation procedure

The captured outputs above are Codex-produced classifications from the local routing contract.
To verify the actual `$codex-first-cost-router` runtime trigger, an operator should run the same samples in a Codex environment where the Codex-first package has been installed or loaded as the active profile.

1. Prepare a disposable validation repository or this repository worktree.
2. Ensure one of the following is true:
   - the Codex-first profile is active, including `profiles/codex-first/AGENTS.md`
   - the target repository has been prepared with `apply-codex-first-local.cs`
   - the local skill path `.agents/skills/codex-first-cost-router/SKILL.md` is available to the Codex session
3. Start a fresh Codex thread for each sample.
4. Paste the sample's Manual prompt exactly.
5. Capture only the first router output before allowing implementation or verification work.
6. Compare the captured output with the sample's Expected routing and Captured Codex classification output.
7. Record any difference in this file or in the issue report under the relevant sample.

Run this first trial as route-only.
Do not allow implementation, hook blocking, plugin trust changes, secrets, billing settings, GitHub settings, organization repositories, external services, or production environments.
For the Hook / Plugin sample, the expected result is a stop with `NeedsHumanDecision`, not implementation.
