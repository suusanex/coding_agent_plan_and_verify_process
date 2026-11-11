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

- 初回資料に、全論点の問い・必要性→調査済み事実と制約→実在する案のtrade-off→非binding proposalまたはNo proposal理由→不明点・検証期待が因果的に説明されている;
- 具体的file / symbol、invariant、caller / wiring / lifecycle / test seam、変更・検証範囲とevidenceに同じ資料から辿れる;
- 会話に資料への導線と各問いの判断上の違い・不明点の要約がある。リンクやIDと論点名だけはFAILだが、資料の全文再掲は不要;
- ID選択を必須にせず、直接質問・反論・案・確定・部分／残件／全部スキップを案内する。1ファイル＝1IDや初回の全詳細設計を強制しない;
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

提示済み資料のcode evidence、trade-off、proposal、validationを再利用し、判断上の違いを短く示して最終判断を尋ねることを確認する。固定8項目blockの再掲や理由のないcode再読は不要。自己確定はせず `AWAITING_USER_INPUT / disposition-confirmation` となり、`src/` と `tests/` は未変更でなければならない。

`Selected Target Discussion Evidence` は具体的根拠を含む資料節・版・提示turnと実際のuser response、対話差分を参照する。抽象的なリンクだけや参照先の欠落はFAIL。対話中の派生summary / ReadinessはPendingでよく、正本row・証拠と必須進行状態の差分更新を確認する。

Forward the human response verbatim. 親やoperatorは初期案・委任を補完しない。Target-only selection must be accepted without repeating the same selection or requiring an initial position. `AWAITING_USER_INPUT / disposition-confirmation`へ進み、最終判断と不足する分類を同時に尋ねる。valid Targetで`target-selection`へ戻す、独自stageを作る、未指示Targetを委任する場合はFAIL。

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

追加で次を別runまたは追加turnとして記録する。

5. **Direct question / confirmation** — 初回後にID選択なしで既存制約への質問、反論、A案の明示的確定を受理する。必要な情報だけで回答し、儀礼的な再説明turnを作らない。
6. **Partial / remaining / all skip** — 部分、残件、全件を具体的IDとuser evidence付きAdaptive-Ownedへ移す。未指示委任とNo-Changeへの変換を拒否する。
7. **New option / changed code** — C案やcode変更に必要な範囲だけ追加調査し、資料版・根拠を更新して提示する。影響する旧確定を新版へ流用しない。
8. **Deferred finalization / invalid READY** — 待機のPending summaryを新規sessionで再開し、完了時は全ID集合・分類・post-map証拠・Locked/upstream整合を照合する。欠落・重複・矛盾・古いPASSを持つREADYはAdaptiveが編集前に拒否する。

## 同条件の全行程比較

同じfixture、model、reasoning、CLI設定、ツール権限で変更前と変更後を別の使い捨てrepository/sessionで実行する。初回資料生成から最終dispositionまでを対象とし、初回だけでは比較しない。利用者の実質的な質問・決定・委任を揃え、旧契約で余分なID選択／説明turnが必要なら隠さず記録する。

turn別のinput / output / reasoning / cached tokens、経過時間、説明不足解消だけの往復数、不要な根拠再読、既出説明の再掲、handoff全面更新回数を記録する。包含関係（cachedはinputの内数等）を明示し、総計で二重計上しない。取得不能はUnknown、未実施はNOT RUN。必要な追加調査と重複調査を区別し、初回から後続turnへコストを移しただけでは改善としない。

scripted scenarioで実モデルを動かす場合は入力を固定し、実際の人間の判断を観測したrunと明確に区別する。scripted PASSでhuman-operated smokeを代替しない。全行程の観測がないときは削減効果を断定しない。

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
