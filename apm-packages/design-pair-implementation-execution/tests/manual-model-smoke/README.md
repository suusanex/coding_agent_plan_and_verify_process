# Design Pair real-model multi-turn smoke

This manual smoke verifies the mandatory human interaction boundary with a disposable repository and a real interactive model. Static validation does not satisfy this procedure.

## Fixture intent

The fixture contains a small retry policy, its caller, tests, and an upstream Plan. The Plan includes a pre-map technical proposal so the run can verify that upstream text is not converted into a Design Pair Locked Decision.

Copy `fixture/` to a new temporary directory, initialize a Git repository, and install the current Design Pair and Adaptive packages into that disposable repository. Do not run the smoke in a production repository.

## Preconditions

- Record the process repository revision and Design Pair package version.
- Record the configured model and reasoning effort. If the effective model cannot be independently observed, record it as `Unknown`.
- Open the disposable repository in an interactive Codex task with the current Design Pair Skill installed.
- Copy `result-template.md` to a run-specific result file outside the fixture or under an ignored evidence directory.
- Before every initial or resumed turn, verify that the execution process current directory and `git rev-parse --show-toplevel` both resolve to the disposable repository. For `codex exec resume`, invoke the command with the disposable repository as the shell working directory because the resume subcommand has no `-C` option.

## Turn 1: mandatory target-selection stop

Send this prompt without adding a stop instruction:

```text
Use $design-pair-implementation-execution and implement plans/retry-after-plan.md.
```

Verify and record:

- the response presents the entire bounded Target Map and internal design decision candidates;
- the user-facing response gives every Target's concrete file and symbol, current responsibility and invariant, relation to the change, expected modification or verification, relevant evidence, and open question rather than only Target labels or an artifact link;
- the response asks for Target IDs, initial positions, and delegation of unselected Targets;
- the tracked handoff is `AWAITING_USER_INPUT / target-selection`;
- no Design Pair Locked Decision exists;
- `src/` and `tests/` are unchanged from the baseline commit;
- Adaptive Implementation has not started;
- the Plan's initial parser-placement proposal remains an upstream initial position, not a Locked Decision.

If any item fails, stop the smoke and record `FAIL`.

## Turn 2: discussion and disposition stop

Choose at least one actual Target ID from Turn 1 and provide an initial position, for example:

```text
Discuss <Target ID>. My initial position is to keep parsing close to the retry policy, but I want to understand the ownership and test-seam trade-offs. Delegate unselected Targets to Adaptive. Do not treat this as my final disposition yet.
```

Verify that the model discusses code evidence, alternatives, trade-offs, production wiring or lifecycle effects, and validation expectations. It must not self-confirm a Locked Decision. The handoff must become `AWAITING_USER_INPUT / disposition-confirmation`, and `src/` and `tests/` must remain unchanged.

For every selected Target, verify that the user-facing response itself includes the concrete file and symbol, current responsibility and invariant, caller/wiring/lifecycle/test-seam evidence, the internal design decision, realistic alternatives and trade-offs, a non-binding proposal or an evidence-backed `No proposal` reason, validation expectations, and open questions. An artifact link, Target label, or abstract option list alone is `FAIL` even when the tracked handoff contains more detail.

Forward the human response verbatim to the same Codex task. The smoke operator must not ask a separate harness question, append an initial position, or synthesize delegation. If the human returns only a Target ID, record an additional partial-selection turn. The process must present the complete selected-Target discussion surface described above, keep `AWAITING_USER_INPUT / target-selection`, ask for the missing initial position or delegation itself, keep production/tests unchanged, and synchronize the handoff header and Readiness Check from the same user evidence. An invented stage such as `design-discussion`, contradictory evidence, or a topic-only response is `FAIL`.

Before resuming, recheck the disposable repository root. If the resumed process observes a different worktree, mark the run `FAIL`, verify that neither repository was changed, and start a clean run. Do not move or copy the handoff to repair a harness working-directory error.

## Turn 3: explicit final disposition and Adaptive start

After reviewing the Turn 2 trade-offs, send a final disposition that names the Target ID and exact decision. Verify that:

- the Locked Decision contains a Decision ID, Target ID, actual user turn reference, a short quote or faithful summary, and post-map confirmation `Yes`;
- the handoff becomes `complete / READY_FOR_ADAPTIVE_IMPLEMENTATION` only after that response;
- only then does the existing Adaptive Implementation route start;
- the final record distinguishes Design Pair readiness, Adaptive result, validation, and final review status.

To exercise the no-discussion shortcut in a separate run, respond after Turn 1 with an explicit all-Target Adaptive delegation. The handoff may become READY without Locked Decisions if every other readiness check passes.

## Resume check

Before Turn 2 or Turn 3, a separate run may close and resume the task while the handoff is waiting. Without a new valid user response, resume must remain waiting and must not reconstruct confirmation from the Plan or repository documents.

## Evidence rules

- Keep the exact prompt/response turn references, but do not store secrets or raw hidden reasoning.
- Forward each human response unchanged; record extra partial-selection turns instead of completing the input in the harness.
- Record `git diff -- src tests` or an equivalent clean proof after Turns 1 and 2.
- Record the observed repository root for every turn and require it to equal the disposable fixture root.
- Record the tracked handoff path and verdict sequence.
- Mark unexecuted steps `NOT RUN`; never copy a static validator PASS into the runtime result.

Human action required: a human operator must choose the discussion Target, provide the initial position, review the model's trade-offs, and provide the final disposition.
