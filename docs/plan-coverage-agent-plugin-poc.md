# Plan Coverage Agent Plugins PoC (Issue #107)

## Goal

Demonstrate that the **same** package-owned canonical source established in #105 can produce an Agent Plugins v1.0.0–aware plugin-format bundle via APM packaging, and measure how far that bundle can be **directly** consumed by GitHub Copilot CLI compared with the #106 APM → Copilot qualification baseline.

This is a **PoC**, not a production distribution cutover.

## Non-goals

- Changing Plan Coverage process semantics
- Bumping `plan-coverage-residual-flow` past `0.13.0`
- Replacing or rewriting #106 QUALIFIED evidence
- Creating a second process implementation (duplicate Skill/agents trees)
- Hand-materializing shared instructions into plugin fixtures to force PASS
- Inventing Codex direct-load support without client evidence

## Agent Plugins spec version

- Spec: **Agent Plugins 1.0.0**
- Manifest schema: `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`
- Offline fixture: `apm-packages/plan-coverage-residual-flow/tests/agent-plugin-poc/fixtures/plugin.schema.1.0.0.json` (provenance file alongside)

`plugin.json` is treated as a **closed** manifest (`additionalProperties: false`). Copilot-native top-level fields such as `agents` / `skills` / `mcpServers` are **not** placed in `plugin.json`.

## Canonical source

```text
apm-packages/plan-coverage-residual-flow/.apm/
apm-packages/plan-coverage-residual-flow/apm.yml
```

Canonical semantics remain `.apm/**` only.

**`plugin.json` is not checked into the package root.** APM treats a directory with `plugin.json` as a plugin bundle install path; keeping it out of the source package preserves `apm install <package-path>` as a true local-source install (Issue #107 must not break APM distribution). The build script synthesizes Agent Plugins v1 `plugin.json` only inside the temporary pack stage from `apm.yml` (name/version/description + `$schema` + repository).

## Generated bundle structure

Produced by:

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/build-plan-coverage-agent-plugin.ps1
```

Flow:

1. Temporary stage (does not dirty the source package tree; no checked-in `plugin.json`)
2. **Adaptive attestation install**: source-layout Plan Coverage + path dep on Adaptive (**no** `plugin.json`) → consumer `apm.lock.yaml` must list Adaptive Skill + HIGH + STANDARD under `deployed_files` / `deployed_file_hashes`
3. Prove `apm pack` **refuses** local path dependencies (cannot pack Adaptive via path dep)
4. Separate pack-lock seed (package-owned only) so pack can embed `apm.lock.yaml`
5. Synthesize `plugin.json` in pack stage; `apm pack --format plugin` (**target-neutral**) with original `git:parent` `apm.yml`
6. Assert Adaptive is **not** inlined into the Plan Coverage plugin bundle; optionally pack Adaptive standalone as its own plugin bundle
7. Cleanup unless `-KeepStage`

This separates “Adaptive is attested in APM install lock” from “APM pack of Plan Coverage inlines Adaptive” — the HOLD gap is a packaging/materialization boundary, not a missing attestation.

Typical bundle layout:

```text
plan-coverage-residual-flow-0.13.0/
  plugin.json                          # Agent Plugins v1 closed manifest
  apm.lock.yaml                        # APM pack provenance / bundle_files
  skills/plan-coverage-residual-flow/  # portable Skill + references
  agents/*.agent.md                    # Copilot plugin extension surface (not AP v1 portable core)
  instructions/plan-coverage-shared.instructions.md  # present in bundle; runtime path ≠ APM materialization
```

Under APM CLI 0.26.0, **Adaptive Implementation is not inlined** into this pack output. Adaptive remains a separate package boundary / APM projection concern.

## Portable / non-portable boundary

| Surface | Classification |
| --- | --- |
| `plugin.json` + Skill tree | `agent-plugins-portable` |
| Adaptive Skill (if ever packed transitively) | `transitive-portable-dependency` |
| `agents/*.agent.md` | `copilot-plugin-extension` (not AP v1 portable component) |
| Shared instruction path contract (`.github/instructions/...`) | `apm-projection-materialization` |
| Codex TOML / concrete models | `codex-runtime-adapter` |
| Embedded `apm.lock.yaml` | `apm-distribution-provenance` |

Full inventory is recorded in each PoC result JSON `boundary_inventory`.

## APM baseline (#106)

| Field | Value |
| --- | --- |
| Result | `tests/runtime-qualification/results/2026-08-10-copilot-cli.json` |
| overall_status | QUALIFIED |
| package | 0.13.0 |
| fingerprint | `98a49a9a3efa807363d3f4411f01f15992642fd1f4224fa8d8a57de2aa0e4ffb` |
| Path | APM install → projections → Copilot CLI |

PoC comparison **fail-closes** semantic parity claims when fingerprints differ. This Issue does not modify `.apm/**` so the baseline fingerprint remains comparable.

Doc: [plan-coverage-runtime-qualification.md](./plan-coverage-runtime-qualification.md).

## Copilot direct-load evidence

Harness:

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-plugin-poc.ps1 `
  -ConfirmExternalModelPayload
```

Constraints:

- Fixture repos **must not** `apm install` Plan Coverage
- No project-level shadow Skill/agents/instructions for the same names
- Authorization A–H and STD/FULL fixtures reused from #106 authorities (no forked catalogs)
- Shared instruction is **not** hand-copied into fixtures; gaps are recorded as adapter/materialization needs
- External model requires explicit `-ConfirmExternalModelPayload`

Install/discovery probes use:

- `copilot --plugin-dir <bundle> plugin list`
- `copilot plugin install <bundle>`

Results: `apm-packages/plan-coverage-residual-flow/tests/agent-plugin-poc/results/`.

## Codex support evidence

Observed on `codex-cli` at implementation time:

- `codex plugin` exists
- `codex plugin add` installs from **configured marketplace snapshots** (`PLUGIN@MARKETPLACE`)
- No documented local bundle path / `--plugin-dir` equivalent for arbitrary Agent Plugins directories

Therefore Codex direct-load is recorded as `UNSUPPORTED_CURRENT_CLIENT` or `UNCONFIRMED` from actual client help — **not** by unpacking the bundle into `.codex/**` by hand.

APM Codex projection remains a separate distribution path.

## Observed gaps (expected HOLD drivers)

1. **Shared instruction materialization** — agents reference `.github/instructions/plan-coverage-shared.instructions.md`; APM install materializes it, direct plugin does not place that path into the work repo.
2. **Adaptive transitive dependency** — not present in `apm pack` plugin output for this package under APM 0.26.0; full route parity needs APM install or a separate Adaptive plugin/adapter.
3. **Custom agents** — loaded only if the client treats bundle `agents/` as an additive extension (Copilot), not as Agent Plugins v1 portable core.
4. **Codex** — no direct local bundle consume path on current client.

None of these authorize rewriting `.apm/**` inside this PoC.

## GO / HOLD / NO_GO

| Verdict | When |
| --- | --- |
| **GO** | Conforming bundle from canonical source; Copilot direct install/discovery; A–H + representative routes with fingerprint-matched semantic parity; remaining gaps are clean adapters |
| **HOLD** | Bundle/portable Skill OK but shared instruction / agents / Adaptive / client limits block full parity — **PoC success if gaps are evidenced** |
| **NO_GO** | Requires duplicate semantic source, canonical rewrite, broken explicit-invocation safety, or a custom packager instead of `apm pack` |

### Current decision (2026-08-11 clean-commit evidence)

**HOLD**

Evidence: `apm-packages/plan-coverage-residual-flow/tests/agent-plugin-poc/results/2026-08-11-copilot-plugin-poc.json`  
`candidate_commit`: `e3928cd95aa7afc3830fc75d37715f61d1e69722` (clean 40-char SHA)

| Gate | Result |
| --- | --- |
| Bundle / AP v1 conformance | PASS (`apm pack`, pack-stage synthesized closed `plugin.json`, Skill/agent equivalence, lock inventory) |
| Package-root `plugin.json` | **Absent** (APM local-source install semantics preserved) |
| Adaptive install-lock attestation | PASS (Skill + HIGH + STANDARD in `deployed_files` / hashes) |
| `apm pack` + local path dep | **Refused** (expected) |
| Adaptive in Plan Coverage plugin bundle | **Absent** |
| Adaptive standalone plugin pack | PASS |
| Duplicate process source | None |
| Canonical fingerprint vs #106 | Match (`98a49a9a…`) |
| Copilot plugin install/discovery | PASS (`plugin install` + `--plugin-dir`) |
| Authorization A–H | PASS |
| STD-001 | FAIL on residual-decision-gate (oracle `STD_001_VERIFIED`; plan/risk/verify stages observed) |
| FULL-001 | NOT_RUN |
| Adaptive connection (strict #106 rules) | FAIL (not in PC bundle) |
| Codex local direct-load | `UNCONFIRMED_NO_LOCAL_DIRECT_LOAD_OBSERVED` |
| Semantic parity claimed | **false** |

This HOLD is a successful PoC outcome: portable packaging works; Adaptive gap is an evidenced APM materialization / separate-plugin boundary, not a missing attestation.

## Recommended next steps

1. Keep APM as **projection + dependency materialization + multi-target distribution**.
2. Treat Agent Plugins as the **portable Skill packaging contract** (+ optional client extension directories).
3. If adopting plugins more broadly: design a thin **Copilot plugin adapter** for instruction path + Adaptive composition without forking process semantics.
4. Revisit Codex when the client documents local Agent Plugins bundle load.
5. Version bump only after production adoption decision (not in #107).

## Reproduce (deterministic CI)

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-agent-plugin.ps1
```

## Related

- Package README: `apm-packages/plan-coverage-residual-flow/README.md`
- Runtime qualification matrix: [plan-coverage-runtime-qualification.md](./plan-coverage-runtime-qualification.md)
- PoC harness/tests: `apm-packages/plan-coverage-residual-flow/tests/agent-plugin-poc/`
