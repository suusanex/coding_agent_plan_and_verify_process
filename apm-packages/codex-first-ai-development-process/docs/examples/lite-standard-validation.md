# Example: Lite / Standard Validation Suite

この suite は、Codex-first と Plan網羅チェック・残件判定フローが `documentation_level: lite / standard` を正しく扱うことを確認するための maintainer 向け validation artifact である。
実リポジトリ、secret、課金、GitHub 設定、外部サービス、本番環境は変更しない。

## Validation scope

この suite は routing contract、artifact shape、stop / ready gate、残件分類を検証する。
実装や修正は行わない。

`documentation_level` は `lite` または `standard` だけを使う。
`strict` は documentation level ではない。
`full-coverage` は `selected_process` または advanced route であり、documentation level ではない。

## Validation rule

各 sample は次を確認する。

- `documentation_level`
- `selected_process`
- required artifact
- required section
- ready / stop gate
- guardrail invariant
- artifact count / sections read

Lite は guardrail を削らない。
Lite は、同じ source of truth、FR / AC coverage、Inline Ready Gate、Implementation Self-Map、Verification Summary、Residual / Close Decision を単一 artifact にまとめて、読ませる artifact と section を減らす。

## VAL-001: Trivial Local Classification

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- docs/examples/simple-local-fix.md の typo を 1 箇所直す。
- 挙動変更、外部 API、secret、本番操作はない。
- 変更後は diff review だけで確認できる。
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `trivial-local` |
| documentation_level | `lite` または Plan artifact 不要の trivial route |
| selected_process | `lower-cost-delegated-scan` or `normal` trivial route |
| required artifact | none, or route-only state note |
| ready / stop gate | exact target and typo must be known before edit |
| guardrail invariant | no fake-only completion claim; no parent Plan pass claim |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Lite / trivial | 0-1 artifact, route-only note or direct diff review |
| Standard baseline | Not required |

## VAL-002: Small Bounded Lite

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- 既存 CLI の help text を 1 オプション分だけ補足する。
- 既存 option parser と test command は明確。
- 外部 API、secret、本番環境、永続 state はない。
- 受け入れ条件は help text と既存 snapshot / text test の更新だけ。
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `small-bounded` |
| documentation_level | `lite` |
| selected_process | `normal` |
| required artifact | `plans/<slug>-plan-coverage-lite.md` or equivalent Lite section |
| required section | Source of truth, FR / AC, Inline behavior sketch, Inline Ready Gate, Implementation Self-Map, Verification Summary, Residual / Close Decision |
| ready / stop gate | Inline Ready Gate must authorize implementation before edit |
| guardrail invariant | Lite keeps Plan source of truth and residual classification |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Lite | 1 integrated artifact, about 7 required sections |
| Previous standard-style baseline | Plan, risk, handoff, verification, residual artifacts; usually 4 or more artifacts |

This sample demonstrates AC-019: Lite reduces artifact count while preserving required coverage.

## VAL-003: Medium Bounded Standard

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- Add a `--json` option to an existing local report command.
- Existing text output must remain unchanged unless `--json` is specified.
- The command already has unit tests.
- No external API, secret, billing, or production environment is involved.
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `medium-bounded` or `small-bounded` with compatibility risk |
| documentation_level | `standard` |
| selected_process | `normal` |
| required artifact | bounded Plan, change-risk-triage, implementation authorization, verification result |
| ready / stop gate | implementation requires separate handoff review or explicitly equivalent gate |
| guardrail invariant | existing output compatibility must map to FR / AC |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Standard | separate Plan / risk / authorization / verification evidence |
| Lite | Not selected because compatibility behavior has multiple acceptance paths |

## VAL-004: High-risk Bounded Standard

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- Change retry behavior for a local job runner.
- Retry count, timeout, and cancellation behavior must remain compatible.
- The implementation surface is one component and one test suite.
- There is no external production environment in this validation.
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `high-risk-bounded` |
| documentation_level | `standard` |
| selected_process | `normal` |
| required artifact | Plan, risk triage, implementation contract when realization risk exists, handoff / readiness evidence, verification |
| ready / stop gate | fail closed on missing retry / cancellation mapping |
| guardrail invariant | high risk does not automatically mean `full-coverage` |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Standard | multiple focused artifacts, canonical ledger if repeated full ledger would be wasteful |
| Advanced full-coverage | Not selected because the pass is bounded |

## VAL-005: Behavior Expansion Standard

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- Add import validation for CSV rows.
- Empty fields, malformed rows, duplicate keys, and rollback behavior have different expected outcomes.
- The source issue does not yet map those cases to acceptance conditions.
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `needs-plan-behavior-expansion` |
| documentation_level | `standard` |
| selected_process | `normal` until Plan readiness is resolved |
| required artifact | Black-box Behavior Spec, then Plan rerun with Case-to-Plan mapping |
| ready / stop gate | stop before risk / implementation while Case-to-Plan mapping is incomplete |
| guardrail invariant | requirement-elaboration gap is not `full-coverage` |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Standard | behavior spec plus Plan mapping |
| Lite | Not selected because behavior cases are not yet mapped |

## VAL-006: Full-coverage Candidate

### Manual prompt

```text
$codex-first-cost-router を使って、この issue を進めてください。

Issue summary:
- Add order creation, inventory reservation, payment request, and compensation handling.
- Retry, timeout, idempotency, and rollback behavior must be correct across components.
- No real payment credential is available in this validation.
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `broad-full-coverage-candidate` |
| documentation_level | `standard` |
| selected_process | `advanced-full-coverage` |
| required artifact | decomposition / slice readiness artifacts before implementation |
| ready / stop gate | stop before implementation until slice decomposition and READY authorization exist |
| guardrail invariant | `full-coverage` is a route, not a documentation level |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Standard documentation level | retained as documentation level for parent planning |
| Advanced full-coverage | selected process for decomposition and cross-slice verification |

## VAL-007: Resume With Core State

### Manual prompt

```text
$codex-first-cost-router を使って、続きやって。

Existing state excerpt:
- task_slug: sample-json-report
- documentation_level: lite
- current_gate: Verification
- next_gate: Close
- selected_process: normal
- audit_artifact: plans/sample-json-report/codex-first-audit.md
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | reuse existing state value |
| documentation_level | reuse `lite` from state unless source of truth changed |
| selected_process | reuse existing process |
| required artifact | `codex-first-state.md`; read audit only when delegation evidence or close permission depends on it |
| ready / stop gate | do not restart Plan unless state is stale or contradictory |
| guardrail invariant | resume does not drop unresolved residuals |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Lite resume | core state first; audit only on evidence-dependent close |
| Standard resume | same state-first behavior, with additional ledger / artifact reads only when required |

## VAL-008: Simple Gap Direct FixNow

### Manual prompt

```text
$codex-first-cost-router を使って、この verification gap を処理してください。

Verification summary:
- One uncovered AC remains.
- Target file and failing assertion are known.
- No behavior ambiguity, human decision, manual verification, or external operation remains.
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `small-bounded` fix pass |
| documentation_level | preserve current Plan level |
| selected_process | `normal` |
| required artifact | Direct FixNow selector with source artifact, source section/table, existing ID, gap type, Plan item, target files/addresses, expected fix, verification command, and reason why direct FixNow is safe |
| ready / stop gate | may skip `coverage-gap-triage` only when direct selector is complete |
| guardrail invariant | FixNow scope cannot expand beyond selected gap |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Direct FixNow | selector plus bounded fix evidence |
| Triage baseline | Not required for 1-2 clear gaps |

## VAL-009: Complex Gap Triage

### Manual prompt

```text
$codex-first-cost-router を使って、この verification gap を処理してください。

Verification summary:
- Several FR / AC rows remain weakly mapped.
- One item may require manual verification.
- One item may be out of scope, but the Plan non-goal is unclear.
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `medium-bounded` or `high-risk-bounded` gap handling |
| documentation_level | preserve current Plan level |
| selected_process | `normal` |
| required artifact | `coverage-gap-triage` before repair, then residual-decision-gate if needed |
| ready / stop gate | block direct FixNow until ambiguity is classified |
| guardrail invariant | unresolved manual / human-decision candidates do not become implementation work |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Standard triage | gap triage, residual decision, explicit FixNow selector only if selected |
| Direct FixNow | Not allowed |

## VAL-010: Unified Implementation Contract

### Manual prompt

```text
$codex-first-cost-router を使って、この implementation-realization risk を確認してください。

Plan excerpt:
- Add durable token refresh through the existing auth abstraction.
- Do not add a second credential store.
- Production wiring must use the existing auth provider.
```

### Expected classification

| Field | Expected value |
| --- | --- |
| task_weight | `medium-bounded` with implementation-realization risk |
| documentation_level | `standard` |
| selected_process | `normal` |
| required artifact | `implementation-contract-kernel` with `Self-check / Readiness verdict` |
| ready / stop gate | review-kernel is explicit review-only fallback, not a normal required next step |
| guardrail invariant | prohibited substitutions and production wiring remain explicit |

### Artifact / section count

| Route | Expected read / write shape |
| --- | --- |
| Unified contract | one implementation contract artifact with self-check verdict |
| Old two-step baseline | implementation-contract plus adjacent review artifact |

## Negative scans

Run these scans after implementing or changing the lite / standard route.
The expected result is either no match or matches that are explicitly documented as unsupported / fallback wording.

```powershell
rg -n "documentation_level.*strict|strict.*documentation_level" .github apm-packages docs README.md
rg -n "Require.*implementation-handoff-review|implementation-handoff-review.*before editing" apm-packages/codex-first-ai-development-process/profiles .github/agents
rg -n "implementation-contract-review-kernel" .github apm-packages docs README.md
rg -n "plan-coverage-shared.instructions.md" .github apm-packages
```

## Validation result template

```md
## Lite / Standard Validation Result

- VAL-001:
- VAL-002:
- VAL-003:
- VAL-004:
- VAL-005:
- VAL-006:
- VAL-007:
- VAL-008:
- VAL-009:
- VAL-010:

### Artifact count / sections read comparison

| Sample | Expected Lite / Standard shape | Observed shape | Pass / fail |
| --- | --- | --- | --- |

### Negative scan result

| Scan | Result | Notes |
| --- | --- | --- |
```

## Operator validation procedure

1. Prepare a disposable validation repository or this repository worktree.
2. Ensure the Codex-first profile or repository-local installer is active.
3. Start a fresh Codex thread for each sample.
4. Paste the sample's Manual prompt exactly.
5. Capture only the first route / validation output before allowing implementation or verification work.
6. Compare the captured output with the Expected classification table.
7. Record artifact count, sections read, stop / ready gate, and residual classification.
8. Run the negative scans after all route changes are present.
9. Record any difference in this file or in the issue report under the relevant sample.

Do not allow implementation, hook blocking, plugin trust changes, secrets, billing settings, GitHub settings, organization repositories, external services, or production environments while running this validation.
