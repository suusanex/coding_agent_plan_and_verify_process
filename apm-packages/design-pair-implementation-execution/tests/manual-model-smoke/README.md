# Design Pair real-model multi-turn smoke

This manual smoke verifies the mandatory human interaction boundary with a disposable repository and a real interactive model. Static validation does not satisfy this procedure.

Formal surfaces:

- **Codex CLI / Codex App** — existing PASS records under `results/`
- **GitHub Copilot CLI** — required for Design Pair package `copilot` target acceptance

VS Code UI is not a formal acceptance surface.

## Fixture intent

The fixture contains a small retry policy, its caller, tests, and an upstream Plan. The Plan includes a pre-map technical proposal so the run can verify that upstream text is not converted into a Design Pair Locked Decision.

Copy `fixture/` to a new temporary directory, initialize a Git repository, and install the current Design Pair and Adaptive packages into that disposable repository. Do not run the smoke in a production repository.

## Preconditions

- Record the process repository revision and Design Pair package version.
- Record the configured model and reasoning effort. If the effective model cannot be independently observed, record it as `Unknown`.
- Record the execution surface (`Codex CLI` or `GitHub Copilot CLI`), CLI version, and any agent flags.
- Open the disposable repository with the current Design Pair Skill installed for the chosen surface.
- Copy `result-template.md` to a run-specific result file outside the fixture or under `results/`.
- Before every initial or resumed turn, verify that the execution process current directory and `git rev-parse --show-toplevel` both resolve to the disposable repository.
  - For `codex exec resume`, invoke the command with the disposable repository as the shell working directory because the resume subcommand has no `-C` option.
  - For GitHub Copilot CLI, keep the disposable repository as the process working directory for every `copilot` invocation. Conversation resume (`--continue` / `--resume=<id>`) is optional convenience only; tracked handoff remains the durable authority.

### Install (GitHub Copilot CLI)

```powershell
apm install <source>/apm-packages/adaptive-implementation-execution#<full-sha> --target copilot,agent-skills --https
apm install <source>/apm-packages/design-pair-implementation-execution#<full-sha> --target copilot,agent-skills --https
copilot --version
copilot skill list
```

Confirm:

- `.agents/skills/design-pair-implementation-execution/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/SKILL.md`
- `.github/agents/decision-surface-implementation-owner.agent.md`
- `.github/agents/bounded-residual-implementation-owner.agent.md`

### Install (Codex)

```powershell
apm install <source>/apm-packages/adaptive-implementation-execution#<full-sha> --target codex,agent-skills
apm install <source>/apm-packages/design-pair-implementation-execution#<full-sha> --target codex,agent-skills
# complete Codex decision-surface-implementation-owner / bounded-residual-implementation-owner models when APM emits model-less TOML stubs
dotnet run --file <moduleRoot>/apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs -- .
dotnet run --file <moduleRoot>/apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs -- . --check
```

## Turn 1: mandatory target-selection stop

Send this prompt without adding a stop instruction:

```text
Use $design-pair-implementation-execution and implement plans/retry-after-plan.md.
```

On GitHub Copilot CLI, invoke from the disposable repository root so the skill is discoverable. Do not pre-select Adaptive agents on turn 1.

Verify and record:

- the response presents the entire bounded Target Map and internal design decision candidates;
- the user-facing response gives every Target's concrete file and symbol, current responsibility and invariant, relation to the change, expected modification or verification, relevant evidence, and open question rather than only Target labels or an artifact link;
- the response uses the required seven-column `Design Pair Target Map`, Coverage evidence, and Selection request structure without compressing the map to a short Target list;
- the response asks for Target IDs and allows optional initial positions, concerns, questions, and delegation of unselected Targets;
- the tracked handoff is `AWAITING_USER_INPUT / target-selection`;
- no Design Pair Locked Decision exists;
- `src/` and `tests/` are unchanged from the baseline commit;
- Adaptive Implementation has not started;
- the Plan's initial parser-placement proposal remains an upstream initial position, not a Locked Decision.

If any item fails, stop the smoke and record `FAIL`.

## Turn 2: discussion and disposition stop

Choose at least one actual Target ID from Turn 1. Do not add an initial position in the mandatory path, so the smoke proves that a Target-only selection starts the concrete discussion:

```text
Discuss <Target ID>.
```

Verify that the model discusses code evidence, alternatives, trade-offs, production wiring or lifecycle effects, and validation expectations. It must not self-confirm a Locked Decision. The handoff must become `AWAITING_USER_INPUT / disposition-confirmation`, and `src/` and `tests/` must remain unchanged.

For every selected Target, verify that the user-facing response itself includes the concrete file and symbol, current responsibility and invariant, caller/wiring/lifecycle/test-seam evidence, the internal design decision, realistic alternatives and trade-offs, a non-binding proposal or an evidence-backed `No proposal` reason, validation expectations, and open questions. An artifact link, Target label, or abstract option list alone is `FAIL` even when the tracked handoff contains more detail.

Verify that the response uses the required `<DP-Txx> Internal design discussion` block and does not collapse its fields into an abstract paragraph or option list.

Forward the human response verbatim to the same task/session. The smoke operator must not ask a separate harness question, append an initial position, or synthesize delegation. A Target-only selection must be accepted without repeating the same selection or requiring an initial position. The process must present the complete selected-Target discussion surface described above, move to `AWAITING_USER_INPUT / disposition-confirmation`, ask for the selected Target's final disposition and any still-missing classification of unselected Targets, keep production/tests unchanged, and synchronize the handoff header and Readiness Check from the same user evidence. An invented stage such as `design-discussion`, a return to `target-selection` for a valid Target ID, contradictory evidence, or a topic-only response is `FAIL`.

Before resuming, recheck the disposable repository root. If the resumed process observes a different worktree, mark the run `FAIL`, verify that neither repository was changed, and start a clean run. Do not move or copy the handoff to repair a harness working-directory error.

## Turn 3: explicit final disposition and Adaptive start

After reviewing the Turn 2 trade-offs, send a final disposition that names the Target ID and exact decision. Verify that:

- the Locked Decision contains a Decision ID, Target ID, actual user turn reference, a short quote or faithful summary, and post-map confirmation `Yes`;
- every `Locked`, `Discussed-Unlocked`, and `Adaptive-Owned` Target has exactly one matching `Target Disposition Evidence` row with its actual post-map user turn, confirmed content, and confirmation `Yes`;
- an explicit multi-Target delegation records one evidence row per delegated Target, even when the rows share the same user turn reference;
- the handoff becomes `complete / READY_FOR_ADAPTIVE_IMPLEMENTATION` only after that response;
- only then does the existing Adaptive Implementation route start;
- the final record distinguishes Design Pair readiness, Adaptive result, validation, and final review status.

On GitHub Copilot CLI, after READY, start Adaptive in a **new CLI process** with explicit `--agent decision-surface-implementation-owner`. Do not treat same-session skill continuation as the canonical Adaptive entry evidence. Do not claim VS Code handoff-button routing. Record requested and observed models when available from CLI output or debug logs.

To exercise the no-discussion shortcut in a separate run, respond after Turn 1 with an explicit all-Target Adaptive delegation. The handoff may become READY without Locked Decisions if every other readiness check passes and every Target has a matching `Adaptive-Owned` disposition evidence row.

## Resume check

Before Turn 2 or Turn 3, a separate run may close and resume while the handoff is waiting.

- Without a new valid user response, resume must remain waiting and must not reconstruct confirmation from the Plan or repository documents.
- On GitHub Copilot CLI, a **new process with no conversation history** must treat the tracked handoff path as authority while still in `target-selection` or `disposition-confirmation`, accept the next human response, and advance only from that evidence. Conversation `--resume` alone is insufficient as the sole durable-resume proof. Missing or contradictory handoff fields fail closed.

## Additional Design Pair Copilot scenarios

Record separate runs or additional turns for:

1. **Explicit all-Adaptive** after Target Map (no Locked Decisions; every Target Adaptive-Owned with disposition evidence).
2. **Design Pair not selected** — ordinary Adaptive / default route; Design Pair must not auto-start.
3. **Locked Decision conflict** — Adaptive decision-surface-implementation-owner with `--agent decision-surface-implementation-owner` stops without silently changing the Locked Decision.
4. **Waiting-state new-session resume** — new process reads `AWAITING_USER_INPUT` handoff and continues after a fresh human response.

bounded-residual-implementation-owner delegation and decision-surface-implementation-owner re-entry after a valid Design Pair READY handoff may cite the Adaptive package Copilot CLI E2E when that package already proves decision-surface-implementation-owner→bounded-residual-implementation-owner→re-entry on the same agents; record the citation and any Design Pair-origin gap as `NOT RUN` only when not re-executed here.

## Plan Coverage boundary (static / ordinary route)

This smoke proves ordinary Plan + explicit Design Pair on the chosen CLI surface. Explicit Plan Coverage parent orchestration with Design Pair waiting-state propagation is covered by package static contracts; full Plan Coverage + Design Pair Copilot CLI E2E is **Issue #86**, not Design Pair package acceptance. Record ordinary Plan route evidence here. Mark Plan Coverage runtime E2E `NOT RUN` / deferred to #86.

## Evidence artifacts

Commit sanitized raw CLI outputs, handoff snapshots, and `git diff` proofs under the run result directory (or record SHA-256 plus retrieval path). The result Markdown must not be the only evidence. Do not store secrets or hidden chain-of-thought.

## Evidence rules

- Keep the exact prompt/response turn references, but do not store secrets or raw hidden reasoning.
- Forward each human response unchanged; record any extra question-and-answer turns instead of completing the input in the harness.
- Record `git diff -- src tests` or an equivalent clean proof after Turns 1 and 2.
- Record the observed repository root for every turn and require it to equal the disposable fixture root.
- Record the tracked handoff path and verdict sequence.
- Record CLI version, unsupported capability notes (for example ignored agent frontmatter fields), and whether Adaptive used `--agent`.
- Mark unexecuted steps `NOT RUN`; never copy a static validator PASS into the runtime result.

Human action required: a human operator must choose the discussion Target, review the model's trade-offs, and provide the final disposition. An initial position is optional.
