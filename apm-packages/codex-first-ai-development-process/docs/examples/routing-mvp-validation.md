# Example: Routing MVP Validation Suite

この suite は、`codex-first-cost-router` を手動スキル指定で呼び出した場合の MVP 検証用サンプルである。
実リポジトリ、secret、課金、GitHub 設定、外部サービス、本番環境は変更しない。

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

`actual dry-run classification` は、PR #20 で整備された router skill、state template、cost router goals に照らして分類した手動検証結果である。

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
| Model Tier Recommendation | `STANDARD_MODEL` for implementation and verification |
| Agent / Subagent Plan | `standard-implementer` for READY implementation, `standard-verifier` for verification |
| Edit Permission | `allowed_to_edit: No` before Plan / risk; `edit_owner: standard-implementer` after READY |
| DelegationRequired | `Yes` for implementation and verification |
| Stop / Ready Gate | `ReadyForDelegatedImplementation` after bounded Plan, risk check, allowed paths, and compatibility rule exist |

### Expected Routing Plan excerpt

```text
Routing Plan:
- Plan: STANDARD_MODEL or HIGH_MODEL if ambiguity appears.
- Risk: STANDARD_MODEL.
- Implementation: STANDARD_MODEL, DelegationRequired = Yes, edit_owner = standard-implementer.
- Verification: STANDARD_MODEL, DelegationRequired = Yes, edit_owner = standard-verifier.

Stop / Ready Gate:
- Stop with ReadyForDelegatedImplementation until observed standard-implementer run exists.
- Stop with ReadyForDelegatedVerification until observed standard-verifier run exists.
```

### Actual dry-run classification

Matches expected. The compatibility condition makes the task non-trivial, but the scope is bounded to one local command and test path.

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
- Verification remains STANDARD_MODEL and delegated.
- Close is blocked until verification evidence and DelegationCompliance pass.

Edit Permission:
- edit_owner: standard-verifier.
- parent_direct_edit_allowed: No.
```

### Actual dry-run classification

Matches expected. The router should continue from state and avoid asking the user to choose a model, process, or agent.

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

### Gap / follow-up

`hook-audit` and `plugin-package` remain separate work items. This MVP only validates that the router stops safely.

## Parent Plan Coverage Ledger sample

| Parent item | Sample coverage | Status | Evidence |
| --- | --- | --- | --- |
| Manual skill prompt exists | Samples 1-5 include `$codex-first-cost-router` prompts | implemented | This validation suite |
| Lightweight fix classification | Sample 1 records expected and dry-run routing | verified | `trivial-local`, `CHEAP_MODEL` |
| Normal implementation classification | Sample 2 records READY delegation gates | verified | `standard-implementer`, `standard-verifier` |
| Full-coverage candidate classification | Sample 3 stops before implementation | verified | `advanced-full-coverage` |
| Resume classification | Sample 4 reads existing state first | verified | state excerpt |
| Hook / Plugin classification | Sample 5 stops with human decision | verified | `NeedsHumanDecision` |
| Real organization rollout | Out of scope | ResidualDecisionCandidate | Requires repository selection |

## Residual Decision Ledger sample

| Residual | Candidate status | Close allowed? | Required explicit decision |
| --- | --- | --- | --- |
| Real payment sandbox validation | `ManualVerificationRequired` | No | Owner, sandbox, credential source, required evidence |
| Plugin trust boundary | `NeedsHumanDecision` | No | Trusted plugin source and rollout scope |
| Hook block scope | `NeedsHumanDecision` | No | Event list, block behavior, bypass policy |
| Copilot fallback parity | Deferred candidate | Yes for this MVP only | Separate `copilot-fallback-sync` work item |
| Enforcement hardening | Deferred candidate | Yes for this MVP only | Separate `enforcement-hardening` work item |

`ManualVerificationRequired` is not an accepted residual. It becomes close-compatible only after an explicit human decision records owner, method, and required evidence.

## Validation result

- The five MVP samples cover the expected routing vocabulary.
- READY implementation is not started in non-READY examples.
- `DelegationRequired = Yes` gates require observed agent evidence before success.
- Close is blocked while `ManualVerificationRequired`, `NeedsHumanDecision`, or missing delegation evidence remains.
- The next ready follow-up should be `enforcement-hardening`, because it turns these documented stop rules into harder-to-bypass guidance before Hook audit or plugin packaging.
