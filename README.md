# coding_agent_plan_and_verify_process

GitHub Copilot / Codex で Plan-first 開発をするための agent（`.github/agents/`）、APM package、運用ドキュメントを管理する repository です。

## Codex completion notification runtime

WindowsでCodex親turnの終了を通知する共通runtimeは、[scripts/codex-notification-runtime](scripts/codex-notification-runtime) にあります。これは既存のuser-level `notify` commandを捨てずに転送し、`completion-notification` fenced blockからeventを作るFile-based apps群です。導入前には必ずdry-runを実行してください。

```powershell
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --dry-run
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- install
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --check
```

一時環境でinstall/update/checkを検証するときは、`--codex-home <path> --install-root <path>`を併用します。`--install-root`を省略した通常導入では`%LOCALAPPDATA%\CodexNotificationRuntime`を使用します。

`--check`のWindows provider support probeは5秒で打ち切り、process treeを終了して`DEGRADED`を返します。repositoryの専用GitHub Actions jobにも15分の上限を設けています。

配布・導入のsource of truthは3本の`.cs` File-based appsです。installerが導入時にsourceから一時領域へpublishするため、`scripts/codex-notification-runtime/artifacts/`の生成物は追跡・配布しません。

最終回答へ付けるenvelopeは次の形式です。`result_uri`が有効なHTTPS URLなら、Windows通知は「結果を開く」と「このタスクを開く」の両ボタンを表示します。`result_uri`がなければ現在のCodex taskへ戻るボタンだけを表示します。runtimeは通知失敗をCodex turnの失敗へ変更しません。

````markdown
```completion-notification
{"schema_version":1,"primary_process":"adaptive-implementation-execution","observed_status":"COMPLETED","title":"implementation completed","repository":"owner/repository","result_uri":"https://github.com/owner/repository/pull/123"}
```
````

`result_uri`は具体的な結果を指すuserinfoなしのHTTPS URLだけを受理します。hostのroot URL、およびGitHubのトップ・ownerトップ・repositoryトップは粗いリンクとして破棄します。`resume_uri`はcallbackのtask IDから常に導出し、有効な`result_uri`があっても保持します。

`$completion-notification-decorator`または`[completion-notification]`を入力に含めても、有効なterminal envelopeがないcallbackは通知されません。marker-onlyは`awaiting-terminal-envelope`、不正envelopeは`invalid-envelope`として診断logへ残し、terminal envelope後にだけproviderへ配送します。詳細とrollbackは [decision-record.md](scripts/codex-notification-runtime/decision-record.md)、実機確認状況は [manual-verification.md](scripts/codex-notification-runtime/manual-verification.md) を参照してください。

## Completion Notification Decorator

`completion-notification-decorator`は、任意の既存Codexプロセスと同じ親turnへ明示追加する観測用Skillです。主プロセスの選択・起動・routing・verdict再判定は行わず、最終回答の末尾へversion 1 envelopeだけを追加します。

```text
$completion-notification-decorator
$adaptive-implementation-execution

このPlanを実装してください。
```

SkillはAPM packageからrepository-localに導入し、上記のcanonical runtime installerをuser-level設定へ適用します。runtime sourceをpackageへ複製しません。

```powershell
apm install .\apm-packages\completion-notification-decorator --target codex,agent-skills
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- install
```

使い方、terminal-envelope gating、2系統のintegration fixtureは [package README](apm-packages/completion-notification-decorator/README.md) を参照してください。

単純な Plan モードでは不十分と感じた点を、自分の用途向けに改善したものです。

この repository には、大きく分けて 4 系統のプロセスがあります。

1. Full autonomous Plan-first flow
   runtime evidence・integration test の設計・検証・ギャップ解消を広く使い、ゴールまで自走しやすい従来型のフロー。

2. Plan網羅チェック・残件判定フロー
   English helper name: Plan Coverage Check and Residual Decision Flow

   source requirement を必要に応じて black-box behavior cases へ展開し、bounded Plan を source of truth として維持しながら、通常可能な実装・検証は parent Plan に沿って進めるフロー。深い runtime / production-binding 確認は Guardrail Focus に絞れるが、それは implementation scope ではありません。高コスト、manual-only、blocked、ambiguous、human decision が必要な項目は residual candidate として記録し、Residual Decision Gate で明示判断します。

Current naming: `plan-coverage-residual-flow` is the standard entrypoint for the Plan Coverage Check and Residual Decision Flow. Use this name in prompts and package references.

3. Adaptive Implementation Execution
   通常 Plan Mode 後の非自明な実装を HIGH_MODEL で開始し、実コードと focused verification の evidence に基づいて、安全な残作業だけを STANDARD_MODEL へ直列委譲する implementation-only flow。Plan Coverage artifacts は必須にしません。

4. Codex-first AI Development Process
   Codex を第一優先にし、初心者でも短い依頼から cost-aware routing に入れる応用運用。中核はモデル tier の自動分担であり、full-coverage 3層運用は標準ルートではなく advanced route として分離します。

---

## 基本的な考え方

このプロセスが防ぎたい主な失敗は 4 つです。

1. sequence contract の不一致
   プロセス間・コンポーネント間の処理で、各コンポーネント内では unit test が通るが、実際につなげると runtime contract・メッセージ・状態遷移・wiring が対応していない。

2. stub は完成しているが production 実装が存在しない
   stub / fake / mock / in-memory 実装を使った自動テストは通るが、対応する production 実装または production wiring が存在しない。

3. parent Plan の縮小を完了と誤認する
   深く確認した Guardrail Focus だけを見て、parent Plan の FR / AC 全体が完了したように扱ってしまう。

4. Requirement-elaboration gap
   Plan 以降の runtime contract、test design、implementation、verification は整合しているが、Plan 自体が元要求のケース別期待結果、negative expectation、recovery / rollback / retry / replay / cleanup などを十分に展開していないため、要求を満たさない実装が完成扱いになる。

Plan網羅チェック・残件判定フローでは、次の guardrail chain を維持します。

```text
Source requirement
  -> Black-box behavior cases
  -> Plan FR / AC
  -> Guardrail Focus runtime contract
  -> Guardrail Focus test point
  -> stub/fake の使用
  -> production 実装
  -> production wiring / entrypoint
  -> Parent Plan Coverage Ledger
  -> Residual Decision Ledger
```

軽量化する場合も、削る対象は parent Plan の責務ではありません。Guardrail Focus は deep-check subset であり、implementation scope ではありません。

---

## APM package の選び方

この repository では、応用運用を使う方法と、既存 package を直接使う方法の両方を残します。

| package | Use when |
| --- | --- |
| `apm-packages/completion-notification-decorator` | 任意の既存Codex主プロセスを変更せず、同じ親turnの終了時にverdictと復帰リンクを通知したい |
| `apm-packages/pr-review-remediation` | 基礎版またはGoal Context対応版でReady PRをreviewし、local / purpose / GitHub Copilot findingsを統合して、別親ターンの既存Adaptive Implementationへ渡したい |
| `apm-packages/adaptive-implementation-execution` | 通常 Plan Mode 後の非自明な実装を HIGH_MODEL で開始し、実コード上の decision surface が解消した場合だけ STANDARD_MODEL へ直列委譲したい |
| `apm-packages/design-pair-implementation-execution` | 利用者が明示選択した場合だけ、実装前に code の予定変更面を対話し、explicit Locked Decisions を通常の Adaptive Implementation へ渡したい |
| `apm-packages/goal-context-authoring` | ChatGPT 等で完了した初期検討を、元会話なしで目的達成レビューに使える human-reviewed `goal-context-*.md` へ変換したい |
| `apm-packages/codex-first-ai-development-process` | Codex を第一優先にし、短い依頼から cost-aware routing、モデル tier 分担、READY / close gate、stateful resume に入りたい |
| `apm-packages/copilot-fallback-ai-development-process` | Codex 枠が尽きた場合などに、GitHub Copilot Chat in VS Code へ同じ思想の cost-aware process を repo-local 導入したい |
| `apm-packages/plan-coverage-residual-flow` | operator が Plan網羅チェック・残件判定フローを直接選べる。通常利用では `plan-coverage-residual-flow` skill を入口にして既存 agent 群を進行管理したい |
| `apm-packages/token-aware-full-coverage-3layer` | PR #10 由来の Codex 向け full-coverage 3層応用運用だけを直接使いたい |
| `apm-packages/full-autonomous-plan-first-flow` | broad autonomous flow を明示的に選び、runtime evidence / integration test design を広く使いたい |

`codex-first-ai-development-process` は既存 package の source を複製しません。同じ `.github/agents/*.agent.md` を参照しつつ、Codex-first の入口、instructions、Skill、停止語彙、tier 別 agent / profile テンプレート、state / stop templates、examples、user / maintainer guide を追加します。

通常の Plan網羅チェック・残件判定フローを直接使う場合は、`apm-packages/plan-coverage-residual-flow` に含まれる同名の skill を入口にします。Codex / Copilot には「この issue を `plan-coverage-residual-flow` で進めて」のように依頼できます。full-coverage 3層運用 skill は、`change-risk-triage.agent.md` が `full-coverage` を返し、Architecture Slice Readiness Gate が decomposition を許可した後に使う advanced route です。

### 導入スクリプトの使い分け

この repository には、対象リポジトリへ Codex 向け agent / skill を配置するスクリプトが複数あります。
目的が異なるため、先に次の表で選んでください。

| Script | Use when | Installs / fixes |
| --- | --- | --- |
| `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs` | Completion Notification Decoratorのcallback runtimeをuser-level Codex設定へ安全に導入・更新・検証したい | canonical runtimeとWindows providerをsourceからpublishし、既存`notify`をchainして、decorator Skill tokenとcompatibility markerをtarget宣言として設定 |
| `apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs` | PR Review Remediation導入後にread-only review agentの具体的Codex profileを同期し、依存するAdaptive assets/profileの存在も確認したい | `.codex/agents/local-reviewer.toml`、`.codex/agents/purpose-reviewer.toml`、`.codex/agents/review-planner.toml`。Adaptive profileは既存Adaptive helperを使用し、`AGENTS.md`と`.codex/config.toml`は操作しない |
| `apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs` | APM 導入後に Adaptive Implementation の必須 concrete Codex profile を repository-local に同期・検証したい | `.codex/agents/high-implementation-starter.toml`、`.codex/agents/standard-implementation-completer.toml`。`AGENTS.md` は操作しない |
| `apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs` | Codex-first を repository-local に導入したい | `AGENTS.md` の Codex-first managed section、`.codex/config.toml`、`.codex/agents/*.toml`、Codex-first / Adaptive / Design Pair skills、canonical implementation agent contracts、`templates/*.md` |
| `scripts/provision-work-repo-agents.cs` | 既存の token-aware / full-coverage package を APM 経由で導入し、agent TOML と template 配置を補正したい | `apm install` の実行、canonical Adaptive agents と legacy `.codex/agents/slice-prep.toml` / `slice-impl.toml` の top-level 設定補正、`plans/_templates/full-coverage-parent-orchestration-state.md` の配置 |
| `apm-packages/goal-context-authoring/.apm/skills/goal-context-authoring/scripts/validate-goal-context.cs` | 導入先を含む任意のGoal Context文書をcanonical contractで検証したい | 必須章、entry単位のprovenance、table、命名、human-review state、高確度のcredential pattern、正規化SHA-256を検証。semantic / privacy review は人間が行う |
| `apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1` | Goal Context packageとfixtureを共通validator込みで検証したい | package構成とnegative mutationを検証し、文書検証は配布版canonical validatorへ委譲 |
| `apm-packages/goal-context-authoring/scripts/test-apm-package-install.ps1` | Goal Context package の標準APM導入経路を検証したい | temporary root へ package root を導入し、Skill、4 references、canonical validatorの配置・SHA-256一致・起動を検証 |
| `scripts/validate-architecture-slice-readiness.ps1` | Architecture Slice Readinessのagent、manifest、template、routing、validation resultを静的検証したい | dependency path、frontmatter、必須contract、旧direct routeの残存を検証 |

Codex-first を使いたい場合の入口は `apply-codex-first-local.cs` です。
`provision-work-repo-agents.cs` は legacy / existing package 向けの APM 補助であり、Codex-first local bootstrap には使いません。

Adaptive Implementation package を変更した場合は、次を実行してください。

```powershell
./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs
git diff --check
```

Design Pair implementation route を変更した場合は、次も実行してください。

```powershell
./apm-packages/design-pair-implementation-execution/scripts/validate.ps1
dotnet publish ./apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs
git diff --check
```

PR Review Remediation packageを変更した場合は、次を実行してください。

```powershell
./apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs
dotnet publish ./apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/select-goal-context.cs
dotnet publish ./apm-packages/goal-context-authoring/.apm/skills/goal-context-authoring/scripts/validate-goal-context.cs
dotnet publish ./apm-packages/pr-review-remediation/scripts/validate-prr-002-contract.cs
dotnet publish ./apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs
git diff --check
```

Architecture Slice Readiness contractを変更した場合は、repository rootで次を実行してください。このcheckはGitHub Actionsでも実行されます。

ASR-001〜006の監査可能なinput、actual output、expected/actual JSON、run metadataは`tests/architecture-slice-readiness/`に保存されています。

```powershell
./scripts/validate-architecture-slice-readiness.ps1
git diff --check
```

Goal Context Authoring package またはその文書契約を変更した場合は、次を実行してください。この check も GitHub Actions で実行されます。

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1
./apm-packages/goal-context-authoring/scripts/test-apm-package-install.ps1
git diff --check
```

### 既存APM向け補助スクリプト provision-work-repo-agents

この章は、`plan-coverage-residual-flow` や `token-aware-full-coverage-3layer` を APM 経由で対象リポジトリへ導入する場合だけ参照します。
Codex-first の導入手順ではありません。

apm を使用して agent.md 形式から Codex 向けの toml 形式を作成すると、一部の top-level TOML field が欠落する動作が確認されています。(2026/6/8)
`provision-work-repo-agents.cs` は、その欠落を補うために次を行います。

- 対象リポジトリで `apm install --update --target copilot,codex,agent-skills ...` を実行する。
- canonical Adaptive route 用に生成された `.codex/agents/high-implementation-starter.toml` と `.codex/agents/standard-implementation-completer.toml`、および互換用の `.codex/agents/slice-prep.toml` と legacy `.codex/agents/slice-impl.toml` を検査する。
- 必要に応じて top-level `model` / `model_reasoning_effort` / `sandbox_mode` を追加・移動・補正する。
- canonical Adaptive agents は package の model mapping と一致することを要求する。不一致がある場合は失敗し、`--force` 指定時だけ package mapping へ補正する。
- `plans/_templates/full-coverage-parent-orchestration-state.md` に親 orchestration 再開 state template を配置し、後続 parent agent が consuming repo 内で template を読めるようにする。

次のように、セットアップ対象のリポジトリのルートパスを渡して実行する。

```powershell
dotnet run --file scripts/provision-work-repo-agents.cs -- "C:\\path\\to\\work-repo" --dry-run
dotnet run --file scripts/provision-work-repo-agents.cs -- "C:\\path\\to\\work-repo"
dotnet run --file scripts/provision-work-repo-agents.cs -- "C:\\path\\to\\work-repo" --check
dotnet run --file scripts/provision-work-repo-agents.cs -- "C:\\path\\to\\work-repo" --force
```

`--dry-run` と `--check` では `apm` 実行やファイル書き込みは行いません。
既存値を上書きして補正したい場合だけ `--force` を使います。特に canonical Adaptive agents の model mapping 不一致は、HIGH / STANDARD の役割分離を保つため、`--force` なしでは検証失敗になります。

---

## Goal Context Authoring

ChatGPT 等で完了した初期検討を、元会話へアクセスできない後続 AI が目的達成レビューに使える自己完結した Markdown へ変換します。

```text
design conversation finalized
  -> goal-context-authoring
  -> goal-context-<topic-summary>.md (draft)
  -> human review
  -> goal-context-<topic-summary>.md (human-reviewed)
```

生成物は Issue 本文の長文化や会話の時系列要約ではありません。Original problem、Desired outcome、具体的な利用状況、MVP / Non-goals / Future work、採用・棄却判断と理由、constraints / invariants、success scenarios、acceptance evidence、形式上成立しても目的上失敗する条件、review questions、open questions、訂正・優先順位変更を保持します。material statement は `[Explicit]`、`[Inferred]`、`[Unknown]` で区別します。

APM で導入する場合:

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target codex,agent-skills
```

生成プロンプト、文書契約、template、human review checklist は Skill の `references/` に同梱されます。追加 installer は不要です。

draft と human-reviewed artifact の検証例:

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1 -GoalContextPath ./docs/goal-context-<topic-summary>.md
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1 -GoalContextPath ./docs/goal-context-<topic-summary>.md -RequireHumanReview
```

validator は必須章、frontmatter、provenance vocabulary、命名、人間確認 state、高確度の secret pattern を検査しますが、元会話への semantic fidelity または privacy safety を証明しません。Desired outcome、棄却案、否定条件、MVP 境界、訂正・優先順位変更、機密情報の除外は人間が checklist で確認します。

詳細:

- `apm-packages/goal-context-authoring/README.md`
- `apm-packages/goal-context-authoring/docs/usage-and-install-guide.md`
- `apm-packages/goal-context-authoring/docs/examples/source-conversation-fixture.md`
- `apm-packages/goal-context-authoring/docs/examples/goal-context-resumable-local-batch-export.md`

---

## Adaptive Implementation Execution

通常 Plan Mode output、手書き Plan、repository-tracked Plan、Issue 内の実装計画、または明示選択された Design Pair handoff を入力にする、独立した implementation-only flow です。

すべての非自明な implementation は `high-implementation-starter` が開始し、production code / tests を実際に編集して focused verification を行います。残作業に新しい構造上の意思決定が不要になった場合だけ、`Implementation Completion Handoff` を介して `standard-implementation-completer` へ直列委譲します。

```text
ordinary Plan
  -> high-implementation-starter [HIGH_MODEL]
       -> READY_FOR_STANDARD_COMPLETION
            -> standard-implementation-completer [STANDARD_MODEL]
                 -> COMPLETED
                 -> NEEDS_HIGH_MODEL_REENTRY
                      -> high-implementation-starter [HIGH_MODEL]
       -> COMPLETED_BY_HIGH_MODEL
```

課題全体が small-bounded、low risk、少数ファイルであることだけを STANDARD_MODEL 直行の理由にしません。安全な delegation point がなければ HIGH_MODEL が完了まで担当します。HIGH_MODEL と STANDARD_MODEL の write-heavy work は並列化しません。

この package は Plan Coverage Lite / Standard / Full Coverage の縮小版ではありません。Plan Coverage artifacts、change-risk-triage、runtime contract、test design、coverage ledger、residual decision を必須にせず、final code review または総合 architecture review も置き換えません。

APM で導入する場合:

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
```

APM install が skill と portable custom agents を導入する本体です。現行 APM が model 未設定の custom agent TOML を生成する場合だけ、package 付属の補助スクリプトを `--dry-run`、install、`--check` の順で実行して具体的なmodel設定を補完します。補助スクリプトは `AGENTS.md` を変更せず、実行してもskillの使用を強制しません。詳細は install guide を参照してください。

起動例:

```text
$adaptive-implementation-execution を使って、直前の Plan を実装してください。
```

詳細:

- `apm-packages/adaptive-implementation-execution/README.md`
- `apm-packages/adaptive-implementation-execution/docs/install-guide.md`
- `apm-packages/adaptive-implementation-execution/docs/usage-guide.md`
- `apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md`

---

## PR Review Remediation

`pr-review-remediation` packageはレビュー計画だけを目的としません。PRを成立させ、review findingsを統合し、その指摘を既存Adaptive Implementationで実装・検証するレビュー反映processです。入口は、目的reviewを行わない基礎版`$pr-review-remediation`と、Goal Contextを必須にする`$goal-context-pr-review`に分かれます。

processはreviewとimplementationの二つの独立したrole taskに分かれます。同じPRでは各taskを維持し、工程ごとにそのtaskの新しい明示親ターンを開始します。

```text
Implementation Thread: initial implementation -> branch/commit/push/ready PR

Review Thread Phase 1:
  -> review context + remote patch collection
  -> local-reviewer [+ purpose-reviewer in Goal Context mode]
  -> review-planner
  -> review-plan.md / READY_FOR_ADAPTIVE_IMPLEMENTATION
  -> parent turn stops

Implementation Thread Phase 2: resume the same task for an explicit new parent turn
  -> adaptive-implementation-execution
  -> implementation and validation
```

Phase 1の停止はprocess全体の完了ではありません。旧独自implementation routeは持たず、Adaptive Skillとcanonical HIGH / STANDARD agentsをAPM依存として再利用します。Draft PRは作成せず、既存Draftは人手でReady for reviewへ変更するまで停止します。

導入:

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills
dotnet run --file apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs -- . --dry-run
dotnet run --file apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs -- .
dotnet run --file apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs -- .
dotnet run --file apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs -- . --check
```

Phase 1起動例:

```text
$pr-review-remediation を使って、このbranchのPRをレビュー反映プロセスで処理してください。
review-plan.mdを作成したところで親ターンを停止してください。
```

明示multi-roundではround 1だけが上記full reviewです。round 2以降は同じReview Threadを再開し、collectorを`--no-wait-for-copilot`で使ってidentityとpatchを更新し、`purpose-reviewer`と`review-planner`だけを実行します。修正は同じImplementation Threadを再開します。remote review/comment/checkは監査用`noAction`として保持し、local-reviewerとCopilotレビュー待機は繰り返しません。review／implementation間の自動起動は行いません。

Goal Context対応版を通知付きで起動する例:

```text
$completion-notification-decorator
$goal-context-pr-review

このbranchのPRを docs/goal-context-example.md で目的達成レビューしてください。
local-reviewerとpurpose-reviewerを独立に実行し、統合review-plan.mdを作成したところで停止してください。
```

Goal Contextが欠落・不正・複数候補で曖昧な場合、Issue本文だけで目的review済みとは扱いません。Goal Contextを修正・選択するか、利用者が基礎版を明示選択します。軽量開発、Plan Coverage、Design PairのいずれでPRを作った場合も、同じ通知付きGoal Context Review Threadと、別roleのImplementation Thread内の明示Adaptive turnへ進みます。

Phase 2起動例:

```text
$completion-notification-decorator
$adaptive-implementation-execution

<cycle-root>/round-NNN/review-plan.md を実装してください。
```

詳細は`apm-packages/pr-review-remediation/README.md`を参照してください。

実agent chainの固定証跡と再現:

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -DescribePayload

pwsh -File apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -ConfirmExternalModelPayload

pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation.ps1
```

`-DescribePayload`は外部modelへ送信せず対象一覧だけを表示します。内容を確認して送信を明示承認した場合だけ、`-ConfirmExternalModelPayload`で実model smokeを実行します。

Goal Context対応版を本物のmodelで確認する場合は、検証対象のprocess PR自身ではなくdisposable target repositoryの小さなPRを使います。Codex Appがtarget選定とpackage準備を行った後、固定Implementation Thread自身がsynthetic fixtureの初回実装、commit、push、Ready PR作成を担当します。人はGitHub変更、model送信、通知runtime、Review／Implementation role taskの明示ターンを承認します。round 1 full review、初回実装と同じImplementation ThreadでのAdaptive、同じReview Threadでのround 2以降のpurpose-only review、terminal時だけのdirect-link通知までの手順と証拠様式は`tests/pr-review-remediation/manual-model-smoke/README.md`を参照してください。

固定実行証跡は`tests/pr-review-remediation/PRR-001/`、外部modelを呼ばないGoal Context contract replayは`PRR-002/`、multi-round state replayは`PRR-003/`に保存します。remote APM導入はAPM 0.26.0で次のように再現でき、CIではpull requestのfull head SHAまたはpushの`github.sha`を指定して検証対象を固定します。

```powershell
pwsh -File apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1 `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <git-ref>
```

---

## Design Pair Implementation Execution

通常の implementation route は Adaptive Implementation です。

```yaml
implementation_route: adaptive
implementation_route_source: default
```

利用者が開始時に Design Pair を明示選択した場合だけ、次の metadata を durable artifact / resume state に保存し、Adaptive Implementation の前段を追加します。

```yaml
implementation_route: design-pair
implementation_route_source: explicit-user-selection
```

```text
ordinary Plan / Implementation Intent
  -> design-pair-implementation-execution
  -> plans/<slug>-design-pair-implementation-handoff.md
  -> adaptive-implementation-execution
```

Design Pair は予定変更面全体を bounded に調査し、具体的な file / symbol、current responsibility、requested change との関係、evidence を Target Map に記録します。人間が選んだ論点だけを対話し、explicit confirmation のある `Locked Decisions` だけを binding とします。`Discussed-Unlocked`、`Adaptive-Owned`、Target Map、Known Evidence は HIGH_MODEL の通常 authority または allowed edit surface を拘束しません。

Design Pair phase の完了前に production code / tests を編集しません。tracked handoff が `READY_FOR_ADAPTIVE_IMPLEMENTATION` になった後、既存の HIGH -> optional STANDARD -> HIGH re-entry route を開始します。Locked Decision conflict は黙って変更せず、Decision ID と actual-code evidence を伴う stop verdict で返します。automatic Design Pair re-entry は行いません。

Plan Coverage Flow では handoff review または equivalent Inline Ready Gate 後に Design Pair を起動し、後段の verification / residual decision を省略しません。package の正式 target は `codex` と `agent-skills` です。GitHub Copilot の Design Pair -> Adaptive end-to-end route は未検証であり、対応済みとは宣言しません。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target codex,agent-skills
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- . --dry-run
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- .
dotnet run --file C:\path\to\coding_agent_plan_and_verify_process\apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs -- . --check
```

fresh Codex targetではAdaptiveとのco-installとconcrete HIGH / STANDARD profileの`--check`までを一組とします。Design Pair package単体の導入だけでは、後段のmodel mappingが完成したとは扱いません。

詳細:

- `apm-packages/design-pair-implementation-execution/README.md`
- `apm-packages/design-pair-implementation-execution/docs/usage-guide.md`
- `apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md`

---

## Codex-first AI Development Process

Codex を第一優先にしたチーム導入向けの応用運用です。
これは full-coverage 3層運用を標準化する package ではありません。
中核は cost-aware routing であり、難しい判断を `HIGH_MODEL`、通常実装を `STANDARD_MODEL`、軽い探索・整合確認を `CHEAP_MODEL` へ分担するための入口です。
full-coverage 3層運用は advanced route として分離されています。
この分担は単なる候補ではなく、Routing Plan と Agent Usage Ledger によって期待委譲と実績を記録します。

### 想定用途

次のような場合に使います。

- 利用者が VS Code の Codex 拡張 / Codex App や agent の選び方に慣れていない
- 「この issue を進めて」のような短い依頼からでも Plan-first に入りたい
- 実装前 READY 判定と実装後 close 判定を明示したい
- Codex の利用枠を優先し、必要な場合だけ GitHub Copilot fallback を検討したい
- read-heavy scan や docs consistency を低コスト側へ寄せたい
- advanced route が必要な大規模変更を、標準ルートから分離したい

### 利用者の入口

利用者は次のように短く依頼します。

```text
この issue を進めてください。
このバグを修正してください。
続きやって。
```

`codex-first-cost-router` が内部で source of truth、repo rules、state artifact、次 gate、model tier、agent / subagent 候補を決めます。
利用者に process 名、skill 名、agent 名、full-coverage 分岐を選ばせません。
内部では `documentation_level: lite / standard` も決めます。`strict` は documentation level ではなく、full-coverage は advanced route です。

### 内部 routing

1. `codex-first-cost-router` が依頼と既存 state を読む
2. Intake / Plan / Risk / Scan / Contract / Implementation handoff review / Implementation / Verification / Close のうち次 gate を選ぶ
3. gate ごとに `HIGH_MODEL` / `STANDARD_MODEL` / `CHEAP_MODEL` と agent / subagent を割り当て、state artifact には Routing Plan / Edit Permission / audit artifact path / DelegationCompliance summary / next action を記録し、audit artifact には Agent Usage Ledger / DelegationCompliance detail / model observability / route history / close audit を記録する
4. READY でない場合は実装せず、state artifact と stop reason を更新する
5. 実装前に `implementation-handoff-review` または明示的に同等の gate で parent authorization artifact を作る
6. READY 後の非自明な実装は `high-implementation-starter` で開始し、complete な handoff 後だけ `standard-implementation-completer` へ直列委譲する。構造判断が再発したら HIGH_MODEL に戻す
7. 通常 verification は `standard-verifier` へ serial delegation する
8. close 可否、residual、DelegationCompliance を state artifact に戻す

Codex-first routing は「軽い処理」と「Plan網羅チェック・残件判定フロー」の二択ではありません。
実際には `task_weight` / `selected_process` / `execution_mode` の 3 軸で分岐します。
たとえば `high-risk-bounded` でも、作業範囲が明確に bounded であれば `selected_process: normal` のまま、Plan / risk / implementation contract / close gate だけを厚くして進めます。
詳しい分岐構造は [docs/codex-first-routing-branching.md](docs/codex-first-routing-branching.md) を参照してください。

full-coverage 3層運用は、標準 cost-router で安全に bounded 化できない場合、または熟練 operator が明示的に選んだ場合だけ advanced route として扱います。
write-heavy parallel editing を標準化しないことは、親エージェントが直接実装してよいことを意味しません。委譲必須 gate は observed run または explicit human approval 付き `ParentDirectExecutionException` がない限り成功扱いしません。

### モデル階層

| Label | Intended use |
| --- | --- |
| `HIGH_MODEL` | 曖昧な要求整理、bounded Plan、難しい risk triage、非自明な実装開始・再入場、implementation contract、危険な close gate |
| `STANDARD_MODEL` | valid handoff 後の bounded completion を担当する `standard-implementation-completer`、通常 verification を担当する `standard-verifier`、test update |
| `CHEAP_MODEL` | read-heavy scan、docs consistency、artifact format check、単純局所修正 |

実名モデルは固定しません。組織の契約、利用枠、品質要求に合わせて mapping してください。
この package には、そのまま使える profile / agent file テンプレート例として `profiles/codex-first/` を含めます。
現行 default では、抽象 tier と実モデルは一対一対応ではなく、agent ごとの責務に応じて model / reasoning effort を設定します。

- `high-implementation-starter`: Terra / high
- `standard-implementation-completer`: Luna / high
- `standard-implementer`: Luna / high（legacy compatibility only）
- `standard-verifier`: Terra / medium
- `HIGH_MODEL` agents: 原則 Terra。reasoning effort は agent ごとに medium または high

### 導入方法

Codex-first は、VS Code の Codex 拡張や Codex App で対象 repository を開いて使うことを主経路にします。
repo 固有の build / test / security ルールは、対象 repository 側の `AGENTS.md` が引き続き優先されます。

#### 手動で使う場合

単発で使う場合は、Codex に skill を明示して依頼します。

```text
$codex-first-cost-router を使って、この issue を進めてください。
$codex-first-cost-router を使って、このバグを修正してください。
$codex-first-cost-router を使って、続きやって。
```

この場合も、利用者は model tier、agent、full-coverage 分岐を選びません。`codex-first-cost-router` が repo rules、既存 artifact、state artifact、必要な audit artifact を見て次 gate を決めます。

#### 自動で呼ばせたい場合

通常の依頼を自動で Codex-first に入れたい場合は、対象 repository の `AGENTS.md` に次のような記載を入れます。
既存の `AGENTS.md` を置き換えず、repo 固有ルールの後に追記するのが基本です。

```md
## Codex-first

普通の開発依頼は Codex-first cost-aware routing として扱う。

- 利用者に process 名、skill 名、agent 名、model tier、full-coverage 分岐を選ばせない。
- `codex-first-cost-router` skill の振る舞いで、source of truth、repo rules、既存 artifact、state artifact を確認する。
- 非自明な作業では `plans/<slug>/codex-first-state.md` を作成または更新する。
- state artifact には Routing Plan、Edit Permission、audit artifact path、DelegationCompliance summary、next action を記録する。
- audit artifact には Agent Usage Ledger、DelegationCompliance detail、model observability、route history、close audit を記録する。
- 実装前に `implementation-handoff-review` または明示的に同等の gate で parent authorization artifact を作成し、`Expansion required: Yes` の場合は Behavior Case Coverage Ledger が complete になるまで `high-implementation-starter` へ渡さない。
- READY 後の非自明な実装は `high-implementation-starter` から始め、valid handoff 後だけ `standard-implementation-completer`、re-entry は HIGH_MODEL、通常 verification は `standard-verifier` へ serial delegation する。
- `DelegationRequired = Yes` の gate は observed run または explicit human approval 付き `ParentDirectExecutionException` がない限り成功扱いしない。
- write-heavy parallel editing を標準化しないことは、親が直接実装してよいことを意味しない。
- repo-local の build / test / security ルールと explicit user instructions を常に優先する。
```

この記載に加えて、対象 repository で `codex-first-cost-router` skill と標準 agent / template を参照できるようにします。手作業で配置する場合の最小構成は次です。

- `.agents/skills/codex-first-cost-router/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/SKILL.md` と `refs/handoff.md`
- `.agents/skills/design-pair-implementation-execution/SKILL.md` と `map.md` / `handoff.md`
- `.github/agents/high-implementation-starter.agent.md`
- `.github/agents/standard-implementation-completer.agent.md`
- `.codex/agents/*.toml`（`high-implementation-starter`、`standard-implementation-completer`、`standard-verifier`、必要な high / cheap agents。`standard-implementer` は互換用）
- `templates/codex-first-state.md`
- `templates/codex-first-audit.md`

Codex-first をこの repository の package からローカル導入する場合は、次のインストーラで標準 bootstrap を追加できます。
この経路では別途 APM を実行しなくても、標準ルートに必要な skill / agent / template を対象 repository に配置します。
既存APM向けの `scripts/provision-work-repo-agents.cs` は使いません。

```powershell
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- . --dry-run
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- .
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- . --check
```

これで対象リポジトリに次を追加します。

- `AGENTS.md` の codex-first セクション
- `.codex/config.toml`
- `.codex/agents/*.toml`
- `.agents/skills/codex-first-cost-router/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/SKILL.md` と `refs/*.md`
- `.agents/skills/design-pair-implementation-execution/SKILL.md` と `map.md` / `handoff.md`
- `.github/agents/high-implementation-starter.agent.md`
- `.github/agents/standard-implementation-completer.agent.md`
- `templates/*.md`

`--dry-run` と `--check` はファイルやディレクトリを作成しません。`--check-only` は互換 alias です。`--check` は canonical agent contracts と complete な `refs/handoff.md` schema が対象 repository に実在し、package source と一致することも検証します。
VS Code の Codex 拡張や Codex App では、インストール済みリポジトリを開くと、ローカル `AGENTS.md` / `.agents/skills` / `.codex` を見て既定のルーティングに入ります。

### 詳細ドキュメント

- `apm-packages/codex-first-ai-development-process/AGENTS.md`
- `apm-packages/codex-first-ai-development-process/docs/codex-first-ai-development-process.md`
- `apm-packages/codex-first-ai-development-process/docs/user-guide.md`
- `apm-packages/codex-first-ai-development-process/docs/maintainer-guide.md`
- `apm-packages/codex-first-ai-development-process/docs/examples/lite-standard-validation.md`

---

## GitHub Copilot fallback AI Development Process

Codex 枠が尽きた場合や利用者環境の都合で Codex を使えない場合に、GitHub Copilot Chat in VS Code へ fallback するための repo-local package です。
Codex-first と state artifact、stop vocabulary、gate 設計、READY / close policy は共有します。ただし導入面は Codex 用 `.codex/agents/*.toml` や `.codex/config.toml` ではなく、VS Code Copilot が読む `.github/` 配下の custom instructions / custom agents / prompt files へ置きます。
Issue #38 の lite / standard 実装、Codex-first core / audit state 分離、profile TOML 互換更新は Codex-first 経路を対象にしており、Copilot fallback への移植は必要に応じて後続 issue で扱います。

標準入口は `copilot-cost-router` です。full-coverage 3層運用は standard route ではなく advanced route であり、初心者向け導入では判断させません。

### 導入方法

既存 `.github` や `AGENTS.md` を壊さないように、まず dry-run で確認します。

```powershell
dotnet run --file .\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs -- <target-repo-path> --dry-run
```

衝突がなければ `--dry-run` を外して適用します。

```powershell
dotnet run --file .\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs -- <target-repo-path>
```

同名 template を上書きする必要がある場合だけ `--force` を使います。既存 `.github/copilot-instructions.md` は marker 管理された `copilot-fallback` block だけを差し替え、marker がない既存 file は manual merge blocker として停止します。

導入後は主に次が配置されます。

- `.github/copilot-instructions.md`
- `.github/instructions/cost-aware-routing.instructions.md`
- `.github/instructions/state-and-close-rules.instructions.md`
- `.github/agents/copilot-cost-router.agent.md`
- `.github/agents/copilot-high-planner.agent.md`
- `.github/agents/copilot-risk-triage.agent.md`
- `.github/agents/high-implementation-starter.agent.md`
- `.github/agents/standard-implementation-completer.agent.md`
- `.github/agents/copilot-standard-implementer.agent.md`
- `.github/agents/copilot-standard-verifier.agent.md`
- `.github/agents/copilot-cheap-repo-scanner.agent.md`
- `.github/agents/copilot-close-reviewer.agent.md`
- `.github/prompts/cost-route.prompt.md`
- `.github/prompts/resume-state.prompt.md`
- `.github/prompts/verify-and-close.prompt.md`
- `.github/prompts/fix-selected-residual.prompt.md`
- `templates/codex-first-state.md`

### 使い方

利用者は普通に依頼します。

```text
この issue を進めてください。
このバグを修正してください。
この機能を実装してください。
この PR の残件を片付けて。
続きやって。
```

明示入口が必要な場合は VS Code Chat の prompt file を使います。

```text
/cost-route この issue を進めて
/resume-state
/verify-and-close
/fix-selected-residual RES-001
```

`copilot-cost-router` は repo-local instructions と既存 artifact を読み、必要なら `plans/<slug>/codex-first-state.md` を作成または更新します。ユーザーに process 名、agent 名、model tier、full-coverage 判断を要求せず、Intake / Plan / Risk / Scan / Contract / Implementation handoff review / Implementation / Verification / Close の次 gate を選びます。

### モデル tier

Copilot fallback の抽象 tier は Codex-first と別管理です。

| Label | Intended use |
| --- | --- |
| `COPILOT_HIGH_MODEL` | 曖昧な要求整理、bounded Plan、high-risk triage、auth / security / production close 判断 |
| `COPILOT_STANDARD_MODEL` | READY 後の通常実装、通常 verification |
| `COPILOT_CHEAP_MODEL` | read-heavy scan、docs consistency、trivial local fix |

実名モデルは VS Code / GitHub Copilot の可用性、組織 policy、premium request、品質要求に合わせて `apm-packages/copilot-fallback-ai-development-process/docs/model-tier-mapping.md` と agent / prompt frontmatter で調整します。

### 安全ルール

- READY 前に実装しない
- close 不可状態のまま完了扱いしない
- `ManualVerificationRequired`、`NeedsHumanDecision`、`NeedsHigherModelReview` が残る場合は close しない
- fake / stub / mock-only success を production success と扱わない
- secret / production / billing / external operation を explicit approval なしに実行しない
- repo 固有の build / test / security rules を常に優先する

### 詳細ドキュメント

- `apm-packages/copilot-fallback-ai-development-process/docs/copilot-fallback-guide.md`
- `apm-packages/copilot-fallback-ai-development-process/docs/user-guide.md`
- `apm-packages/copilot-fallback-ai-development-process/docs/install-guide.md`
- `apm-packages/copilot-fallback-ai-development-process/docs/model-tier-mapping.md`
- `apm-packages/copilot-fallback-ai-development-process/docs/limitations.md`

---

## Full autonomous Plan-first flow

従来の、広く自走させる用途向けのフローです。

### 想定用途

- 機能全体のスコープがまだ広い、または曖昧
- 複数の runtime sequence が絡む
- recovery・retry・rollback・データ整合性が重要
- full runtime evidence や integration test の設計を人間がレビューしたい
- トークンコストより網羅性を優先する
- 一度 agent に大きく自走させ、残ったギャップを後続で処理したい

### 典型的な手順

1. `plan-generation.agent.md`
2. `plan-review.agent.md`
3. 通常エージェントで実装
4. `integration-test-verification-implementation.agent.md`
5. `coverage-gap-resolution.agent.md`

### オプション: implementation contract フェーズ

新しい実現方式の採用や、標準 API・既存 OSS・既存コードの比較検討が重要なケースでは、実装前に次のオプションフェーズを追加できます。

1. `implementation-contract-generation.agent.md`
2. `implementation-contract-review.agent.md`

---

## Plan網羅チェック・残件判定フロー

bounded Plan を作成し、その parent Plan を実装・検証の source of truth として維持します。

### 想定用途

- full flow は重すぎるが、Plan-first の効果は保ちたい
- runtime contract の guardrail は外したくない
- 複数のプロセス・サービス・コンポーネントが絡むが、深く確認すべき runtime / production-binding surface は限定できる
- stub / fake を使ったテストがあり、production 実装 / wiring の欠落を防ぎたい
- 1 回の bounded pass で全項目を無理に終わらせず、残件を明示判断したい

### 不変条件

- parent Plan は `plan-kernel.agent.md` が作成した bounded Plan であり、実装・検証の source of truth です。
- Plan readiness は risk triage より前に確認します。behavior expansion が必要なのに artifact や Case-to-Plan mapping が不足している場合は `NeedsPlanBehaviorExpansion` として Plan フェーズへ差し戻します。
- `change-risk-triage`、`runtime-contract-kernel`、`test-design-kernel`、`implementation-handoff-review` は parent Plan を縮小しません。
- Guardrail Focus は deep runtime / production-binding verification の重点対象です。implementation scope ではありません。
- Guardrail Focus 外の parent Plan item も Parent Plan Coverage Ledger で必ず分類します。
- standard route で ledger の再掲が膨らむ場合は、`plans/<ticket-or-slug>-coverage-ledger.md` を canonical ledger とし、中間 artifact は `Coverage Ledger Delta` だけを出します。canonical ledger がある場合、handoff / verification artifact は full ledger を再掲せず、その section から canonical ledger を参照します。
- residual は記録しただけでは accepted ではありません。`ManualVerificationRequired` は close 不可の candidate status です。explicit human decision により owner / method / required evidence が明示された場合だけ、`AcceptedResidual`、`ManualVerificationDelegated`、`DeferredWithOwner`、`AbortedWithReason` などの close 可能な decision status にできます。
- final done は Parent Plan Coverage Ledger と Residual Decision Ledger で判定します。
- full-coverage decomposition 後の cross-slice verification は、production interface / implementation / wiring の存在確認だけでは完了しません。producer から production wiring を通した後、consumer 側の runtime gate / durable state / async worker / recovery semantics が parent acceptance condition の runtime postcondition を満たすことを確認します。
- source-structure test と CI green は、それだけでは runtime postcondition の証明ではありません。test body または test-design mapping が required postcondition / forbidden state を assertion している場合だけ close evidence として扱います。
- rerun で previous gap / residual を close する場合、前回と同等または弱い evidence では close できません。previous `RES-*` や `NeedsHumanDecision` を skip するには explicit human decision、parent Plan の既決基準に合う code/test 修正、または previous residual の前提誤りを示す新 evidence が必要です。

### 典型的な手順

1. `plan-kernel.agent.md`
2. `black-box-behavior-spec-kernel.agent.md`（behavior expansion が必要だが artifact が不足する場合）
3. `plan-kernel.agent.md` 再実行（behavior spec の Case IDs を Plan FR / AC / explicit disposition へ mapping する場合）
4. `change-risk-triage.agent.md`（`ReadyForRiskTriage` の場合だけ）
5. `full-coverage` の場合は `architecture-slice-readiness.agent.md`。`NeedsArchitectureElaboration` なら `architecture-elaboration.agent.md` 後に再判定する
6. `ReadyForSliceDecomposition` または `ArchitectureNotRequired` の場合だけ `plan-slice-decomposition.agent.md`
7. 通常passまたは各sliceで必要なimplementation contract / runtime contract / test design / handoff reviewを実行
8. 非自明な実装を `high-implementation-starter.agent.md` で開始し、valid handoff 後だけ `standard-implementation-completer.agent.md` を実行。re-entry は HIGH_MODEL へ戻す
9. 必要に応じて `code-review-focus-kernel.agent.md` と human code review
10. `verification-kernel.agent.md`
11. full-coverage slice完了後は`cross-slice-verification-kernel.agent.md`
12. 未解決がありcomplete `Direct FixNow selectors` tableがない場合は`coverage-gap-triage.agent.md`
13. `residual-decision-gate.agent.md`
14. explicit FixNow selectorがある場合だけ`coverage-gap-resolution-slice.agent.md`を実行し、verificationとresidual decisionへ戻る

各 agent は 1 回の bounded な実行を行い、未解決項目は成果物に残して停止します。「直るまで修正し続ける」ことは目的ではありません。

### full-coverage handling

`change-risk-triage.agent.md` が `full-coverage` と診断した場合でも、parent Plan coverage は縮小しません。`full-coverage` は `ReadyForRiskTriage` の Plan が広い、強く相互接続している、複数 runtime sequence にまたがる、または decomposition が必要という診断です。要求展開不足は `full-coverage` ではなく `NeedsPlanBehaviorExpansion` または `NeedsHumanDecision` として Plan フェーズへ戻します。

```text
full-coverage
  -> architecture-slice-readiness.agent.md
     -> ReadyForSliceDecomposition / ArchitectureNotRequired
        -> plan-slice-decomposition.agent.md
     -> NeedsArchitectureElaboration
        -> architecture-elaboration.agent.md
        -> architecture-slice-readiness.agent.md (rerun)
     -> NeedsHumanDecision (stop)
  -> per-slice bounded parent Plan pass
  -> cross-slice-verification-kernel.agent.md
  -> residual-decision-gate.agent.md
```

slice decomposition は scope shrink ではありません。各 slice は parent Plan item mapping を持ち、最後に cross-slice verification と residual decision を通します。

cross-slice verification では、runtime postcondition oracle と forbidden-state oracle を作ります。stateful cross-slice contract では、producer state と consumer gate の両方が整合し、禁止状態が起きない evidence がない限り `CROSS_SLICE_VERIFIED` にできません。

### Adaptive Implementation route に渡すもの

`high-implementation-starter.agent.md` は parent Plan に対する非自明な実装を HIGH_MODEL で開始します。`standard-implementation-completer.agent.md` は complete な `READY_FOR_STANDARD_COMPLETION` handoff 後だけ bounded remainder を実装します。`runtime-contract-kernel` だけを渡してはいけません。`implementation-execution.agent.md` は既存 invocation の互換入口としてのみ残ります。

少なくとも次を渡してください。

- `plans/<ticket-or-slug>.md`
- `plans/<ticket-or-slug>-black-box-behavior-spec.md`（Behavior spec artifact required: Yes の場合）
- parent Plan / slice artifact 内の Inline behavior sketch と Case mapping（inline behavior sketch sufficient の場合）
- `plans/<ticket-or-slug>-change-risk-triage.md`
- `plans/<ticket-or-slug>-architecture-slice-readiness.md`（full-coverageの場合）
- `plans/<ticket-or-slug>-slice-architecture.md`（`ReadyForSliceDecomposition`の場合）
- `plans/<ticket-or-slug>-implementation-contract-kernel.md`（implementation-realization risk が Present / Unclear の場合）
- `plans/<ticket-or-slug>-coverage-ledger.md`（存在する場合）
- `plans/<ticket-or-slug>-implementation-contract-review-kernel.md`（explicit review-only fallback が存在する場合）
- `plans/<ticket-or-slug>-runtime-contract-kernel.md`
- `plans/<ticket-or-slug>-test-design-kernel.md`
- `plans/<ticket-or-slug>-implementation-handoff-review.md`
- `plans/<ticket-or-slug>-slice-decomposition.md`（full-coverage decomposition 由来の slice を扱う場合）
- parent Plan の Non-goals / constraints / residual policy

実装者は通常可能な FR / AC を parent Plan に沿って進め、詰まった項目は `Blocked`、`NeedsHumanDecision`、`ManualVerificationRequired`、`TooCostlyForBoundedPass`、`ImplementationEvidenceMissing` などで記録します。

---

## Agent 群

### `plan-kernel.agent.md`

bounded Plan を作成し、Goal / Non-goals / Functional requirements / Acceptance conditions / Black-box behavior coverage / Affected components / Residual policy / Guardrail Focus candidates を記録します。final runtime contracts は選びません。`Plan readiness` が `ReadyForRiskTriage` でない場合は risk triage へ進めず、behavior expansion または human decision へ差し戻します。

### `black-box-behavior-spec-kernel.agent.md`

source requirements を external black-box behavior cases へ展開し、stable な Case ID、negative expectation、derived invariant、excluded combinations、unresolved requirement-elaboration items を記録します。Plan FR / AC は変更せず、Case-to-Plan mapping は `plan-kernel.agent.md` が Plan 内で行います。

### `change-risk-triage.agent.md`

Plan readiness check を行い、`ReadyForRiskTriage` の場合だけ parent Plan 全体の risk inventory、implementation-realization risk、Guardrail Focus recommendation、Residual risk candidates、Recommended process path を出します。実装 scope は縮小しません。

### `architecture-slice-readiness.agent.md`

Requirement readinessとは別に、state owner、source precedence、identity、temporal sequence、retry / release、capacity、schema、invariants、production wiringがslice可能な精度か判定します。`ReadyForSliceDecomposition`、`NeedsArchitectureElaboration`、`ArchitectureNotRequired`、`NeedsHumanDecision`のいずれかを返します。

`ArchitectureNotRequired`ではreadiness artifact自身が軽量baseline authorityとなり、後続は新しいshared semanticsを導入していないことを`Match`として確認します。freshnessはHEAD一致ではなく、tracked sourceのcontent hash / explicit revision比較とsource commit以降のwatch path diffで判定します。artifact追加commitだけではself-invalidationせず、baseline sourceへ影響する変更だけを`stale`として再判定します。

Elaboration前のreadiness R1はSlice Architectureの`elaboration_trigger`へ監査snapshotとして残しますが、freshness dependencyにはしません。Elaboration後に同じreadiness pathをR2へ更新してもSlice Architectureはcurrentのままで、R2がSlice Architectureの外部hashを保持します。

### `architecture-elaboration.agent.md`

requirement baselineを変更せず、`plans/<ticket-or-slug>-slice-architecture.md`へshared architecture semanticsを確定します。完了後はreadiness checkへ戻り、直接decompositionへ進みません。

既存systemでは、関連production entrypoint、DI / startup、schema、DTO / message、state owner、retry / cleanup pathをboundedに確認し、production evidence addressとinspection範囲をartifactへ残します。

### `plan-slice-decomposition.agent.md`

Architecture Slice Readiness Gateが許可したfull-coverage Planについて、確定済みarchitectureをbounded execution sliceへ射影します。各sliceはparent Plan item mapping、architecture traceability、cross-slice verification requirementsを持ち、shared semanticsを新しく発明しません。

### `implementation-contract-kernel.agent.md`

dependency / API / provider / substitution risk を確認し、unresolved implementation-realization items を guessed address に変換せず residual candidate として保持します。`Self-check / Readiness verdict` も同じ artifact に記録します。

### `implementation-contract-review-kernel.agent.md`

`implementation-contract-kernel.agent.md` の `Self-check / Readiness verdict` を explicit review-only fallback として確認する compatibility shim です。通常ルートでは自動的に挟みません。

### `runtime-contract-kernel.agent.md`

Guardrail Focus runtime contract だけを深く固定します。focus 外の parent Plan item を out-of-scope 扱いにせず、Parent Plan Coverage Ledger へ残す前提で downstream に渡します。

### `test-design-kernel.agent.md`

Guardrail Focus RC を Guardrail Focus TP に落とし、stub / fake / mock / in-memory を使う場合は production binding check を必須にします。behavior spec がある場合は selected scope の Case IDs を test points または明示的 coverage disposition に接続します。focus 外 parent Plan item の verification responsibility は消えません。

### `implementation-handoff-review.agent.md`

実装前 gate です。Plan → Guardrail Focus RC → TP → production binding requirement の接続、Parent Plan Coverage Ledger、必要な場合は Behavior Case Coverage Ledger を確認し、`READY_FOR_BOUNDED_PARENT_PLAN_PASS` 系または `BLOCKED_*` verdict を出します。

### `high-implementation-starter.agent.md` / `standard-implementation-completer.agent.md`

非自明な実装は HIGH_MODEL から開始し、実コード上の decision surface が解消するまで `high-implementation-starter` が所有します。complete な handoff が作られた場合だけ `standard-implementation-completer` が残作業を担当し、構造判断が再発したら `NEEDS_HIGH_MODEL_REENTRY` で HIGH_MODEL に戻します。各 phase の owner、verdict、Implementation Self-Map、checks、acceptance evidence、Remaining Work は `plans/<ticket-or-slug>-implementation-execution.md` に集約します。

### `code-review-focus-kernel.agent.md`

human review 用の重点 surface を整理します。parent Plan item に影響する changed files と Guardrail Focus surface を分けて出します。

### `verification-kernel.agent.md`

Parent Plan Coverage Ledger と Behavior Case Evidence Ledger を更新し、Guardrail Focus RC/TP については production binding / wiring / contract representation を深く確認します。final verdict は parent Plan verdict です。
canonical coverage ledger が存在する場合は、変更行を `Coverage Ledger Delta` として出します。1〜2 件の simple gap で source artifact、source section/table、existing ID、gap type、Plan item / Case ID、target files / addresses、direct FixNow が安全な理由を明確にできる場合だけ `Direct FixNow selectors` table を出せます。

### `coverage-gap-triage.agent.md`

Parent Plan Coverage Ledger から unresolved items を抽出し、FixNow items、manual decision candidates、Residual decision candidates を分けます。defer / abort / manual delegation を承認しません。
verification または residual gate が complete `Direct FixNow selectors` table を出した simple gap では省略できます。

### `residual-decision-gate.agent.md`

coverage-gap-triage、verification-kernel、または cross-slice-verification-kernel 後の docs-only gate です。explicit human decision がある項目だけ accepted residual として扱い、Residual Decision Ledger と final next-step verdict を出します。previous `RES-*` や `NeedsHumanDecision` がある rerun では、closure / skip 理由を明示します。

### `coverage-gap-resolution-slice.agent.md`

post-verification repair subflow です。verification-kernel、coverage-gap-triage、または residual-decision-gate が出した explicit FixNow selector だけを修正し、修正後は verification-kernel と residual-decision-gate に戻します。

### `cross-slice-verification-kernel.agent.md`

slice ごとの pass を parent Plan completion と扱わず、parent acceptance conditions、cross-slice contracts、runtime postcondition oracle、forbidden-state oracle、residual decisions を統合して residual-decision-gate へ渡します。production interface / implementation / wiring の存在、source-structure test、CI green だけでは `Bound` や `CROSS_SLICE_VERIFIED` にできません。

---

## 応用運用: PR #10 で追加した Codex 向け full-coverage 3層運用

これは基本プロセスそのものではなく、`change-risk-triage.agent.md` が `full-coverage` を返し、Architecture Slice Readiness Gateを通過して`plan-slice-decomposition.agent.md`で複数sliceに分けたあとに使うCodex向けの応用運用です。

PR #10（`Codex向け full-coverage 3層運用を追加`）では、その局面で slice を安全に扱うための補助一式を追加しました。現在の `main` では、その内容は主に `apm-packages/token-aware-full-coverage-3layer/` を source of truth として管理しています。

| 役割 | 現在の主な配置 |
| --- | --- |
| Codex へのプロジェクト指示 | `apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md` |
| 親エージェントが呼ぶ skill | `apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md` |
| slice 準備 subagent | `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-prep.agent.md` |
| slice 実装 route | root `high-implementation-starter.agent.md` → valid handoff 後の `standard-implementation-completer.agent.md` → re-entry 時は HIGH_MODEL |
| legacy slice 実装入口 | `apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md` |
| 親 orchestration 再開 state template | `token-aware-full-coverage-3layer` Skill の `references/full-coverage-parent-orchestration-state.md` |
| Slice Architecture template | `plan-coverage-residual-flow` Skill の `references/slice-architecture.md` |
| Codex project config | `.codex/config.toml` |

### 何をする応用か

この 3 層運用は、`plan-slice-decomposition.agent.md` の出力をそのまま実装開始条件にしないためのものです。

開始前にArchitecture Slice Readiness verdictと、`ReadyForSliceDecomposition`の場合のslice architecture artifactがcurrentであることも必須です。slice-prepまたはAdaptive Implementationがshared semanticsを変更する場合、parent reviewは実装をBLOCKし、Architecture Slice Readiness Gateへ戻します。

1. 親エージェントが slice 実行表と parent review gate を管理する
2. `slice-prep` が slice ごとの kernel artifact を下書きする
3. `DELEGATED_IMPLEMENTATION` mode では、親レビューで READY になった非自明な slice を必ず `high-implementation-starter` から開始し、valid handoff 後だけ STANDARD completion を行って slice-local verification まで進める
4. 最後に親エージェントが cross-slice verification と residual decision をまとめる

つまり、「full-coverage decomposition を Codex でそのまま分解実装させる」のではなく、「親が整合を握ったまま、準備と実装だけを bounded に委譲する」ための運用補助です。
ユーザーが実施・進行・実装を依頼し、準備やレビューまでで止める明示指示がない場合、既定の `ExecutionMode` は `DELEGATED_IMPLEMENTATION` です。`PREP_ONLY` は「実装はまだ行わない」「準備まで」「レビューまでで停止」と明示された場合だけ使います。
Parent review gate は人間レビュー待ちではなく、親エージェントが READY slice の実装可否を判定する gate です。`Can implement now? = Yes` の slice がある場合、親はそこで成功終了せず Adaptive Implementation route へ委譲します。
親エージェントは `DELEGATED_IMPLEMENTATION` で production code / tests を直接編集しません。非自明な READY slice に HIGH_MODEL start がない場合は `BlockedByMissingAdaptiveImplementationDelegation` として停止します。各 slice 内の HIGH → STANDARD → HIGH ownership は直列にし、slice 間の既存非重複条件だけを並列性の根拠にします。

親エージェントは `plans/<ticket-or-slug>-parent-orchestration-state.md` を軽量な再開入口として作成・更新します。この artifact は Codex / GitHub Copilot / 別セッション間で親 orchestration を移管するための tool-neutral な Markdown で、Current phase、Next required action、Artifact index、Slice queue、Parent decisions made、Cross-slice blockers、Pending parent decisions、Emergency checkpoint を path / status / next action 中心に記録します。full transcript、source artifact 本文、subagent output 全文、長い reasoning trace、source excerpt は保存しません。必要な場合は短い pointer に抑え、file が大きくなりすぎた場合は完了済み slice 行を短い summary に圧縮します。

再開する親エージェントは prior conversation context に依存せず、現在の ticket / slug / branch / work item / PR と一致する `plans/<ticket-or-slug>-parent-orchestration-state.md` を選びます。複数候補を一意に絞れない場合は fail closed し、対象 state の確認を求めます。その後、state に列挙された source artifact と Agent Usage Ledger を照合し、完了済み slice を不用意に再実行せず、blocking decision や cross-slice 未検証項目を確認してから続行します。

この応用運用では、Codex App / Desktop thread path を primary path、CLI non-interactive / `codex exec` path を separate compatibility path として扱います。CLI 側で deterministic に同じ custom agent type を起動できると確認できるまでは、App / Desktop と同等扱いしません。

### APM で取得できるもの / できないもの

この応用運用では、APM package に入っているものと、workspace 側に残すものを分けています。

- APM で取得できるもの
  - project guidance 相当の instructions
  - reusable skill
  - custom agent として使う `slice-prep` と canonical Adaptive Implementation agents（`slice-impl` は legacy compatibility only）
  - `full-coverage-parent-orchestration-state.md` template
- APM で取得できないもの
  - workspace そのものの Codex 実行設定（例: `.codex/config.toml`）
  - repository 固有のローカル配置や、利用者の作業環境に依存する設定値（`provision-work-repo-agents.cs` を使う場合は `plans/_templates/full-coverage-parent-orchestration-state.md` へ template を配置する）

関係としては、APM で取得できるものが「何を守ってどう進めるか」を定義し、APM で取得できないものが「その workspace でどう実行するか」を補います。前者だけでは運用方針は入るけれど、並列度や再帰深さのようなローカル実行境界までは固定しません。

### APM で取得できないものの使い方

`.codex/config.toml` は package の代用品ではなく、APM で入った instructions / skill / agents をこの repository で安全に動かすための補助設定として使います。

この repository では、少なくとも次の意図で使っています。

- 親エージェント既定値を重めにし、広い設計整合を見落としにくくする
- `max_threads = 3` で slice の無制限並列化を防ぐ
- `max_depth = 1` で subagent からさらに subagent を増殖させない

つまり、APM で取得した skill / agents が作業手順のガードレール、`.codex/config.toml` がそのガードレールを壊しにくい実行境界、という分担です。どちらか片方だけだと運用が痩せます。

### 実績ログと未解決事項

3層運用の実績ログでは、`model` を1語で混ぜず、少なくとも `configured_model`、`hook_model`、`effective_model` を分けて扱います。`configured_model` は custom agent file の frontmatter、`hook_model` は hook payload の観測値、`effective_model` は別経路で独立確認できた場合だけ使います。

logger 側は、dated な JSONL ファイル名、`agent_transcript_path`、短い `last_assistant_message_preview` の保存を推奨します。ただし transcript 全文 scraping を前提にせず、repository-tracked な Agent Usage Ledger を主証跡、hook log を補助証跡として扱ってください。

歴史記録（model-routing-history allowlist）として、`gpt-5.4` から `gpt-5.5` への migration notice の実影響と、CLI 経路で `agent_type = default` になり得る問題は、今回の本番修正とは切り分けた未解決事項です。詳細な修正要求は [docs/codex-full-coverage-3layer-fixes.md](docs/codex-full-coverage-3layer-fixes.md) に置いています。

---

## Verdict 語彙

### implementation-handoff-review

- `READY_FOR_BOUNDED_PARENT_PLAN_PASS`
- `READY_FOR_BOUNDED_PARENT_PLAN_PASS_WITH_DECLARED_RESIDUAL_RISKS`
- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
- `BLOCKED_BY_ARTIFACT_MISMATCH`
- `BLOCKED_BY_HUMAN_DECISION`
- `BLOCKED`

### verification-kernel

- `PARENT_PLAN_VERIFIED`
- `PARENT_PLAN_VERIFIED_WITH_ACCEPTED_RESIDUALS`
- `PARENT_PLAN_PARTIAL_WITH_FIX_CANDIDATES`
- `PARENT_PLAN_NEEDS_RESIDUAL_DECISION`
- `BLOCKED_BY_PRODUCTION_BINDING_GAP`
- `BLOCKED_BY_CONTRACT_MISMATCH`
- `BLOCKED_BY_UNMAPPED_PARENT_ACCEPTANCE`
- `BLOCKED_BY_HUMAN_DECISION`

### residual-decision-gate

- `READY_TO_CLOSE_WITH_NO_RESIDUALS`
- `READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS`
- `READY_FOR_NEXT_BOUNDED_FIX_PASS`
- `READY_FOR_MANUAL_VERIFICATION_HANDOFF`
- `NEEDS_HUMAN_RESIDUAL_DECISION`
- `REPLAN_REQUIRED`
- `ABORT_RECOMMENDED`

`READY_TO_CLOSE_WITH_ACCEPTED_RESIDUALS` は、input artifact、issue comment、PR comment、user prompt などに explicit human decision がある場合だけ出せます。`ManualVerificationRequired` のままでは close 不可で、owner / method / required evidence が明示された `ManualVerificationDelegated` に変換されている必要があります。

---

## フローの選び方

### Full autonomous Plan-first flow を使う場合

- 要求が広い、または曖昧
- 複数のシナリオをまとめて設計したい
- runtime evidence と integration test の設計を詳細に作りたい
- トークンコストより網羅性を優先する
- agent にある程度ゴールまで自走させたい

### Plan網羅チェック・残件判定フローを使う場合

- Plan-first は維持したいが、full flow は重すぎる
- bounded parent Plan pass で進めたい
- Guardrail Focus を深く確認しつつ parent Plan coverage を落としたくない
- implementation-realization risk がある場合だけ implementation-contract branch を差し込みたい
- residual を explicit decision なしに accepted 扱いしたくない
- トークンコストと bounded な進捗を重視する

---

## よく使うプロンプトパターン

### Plan から始める

```text
この変更について、Plan網羅チェック・残件判定フローで進めます。
まず plan-kernel.agent.md を使って bounded Plan を作成してください。
実装・テスト作成・full runtime evidence・full integration test design は行わず、Goal、Non-goals、Functional requirements、Acceptance conditions、Black-box behavior coverage、Affected components、Residual policy、Guardrail Focus candidates、Plan readiness、次 gate への handoff を出してください。
Expansion required: Yes の場合でも、inline behavior sketch sufficient なら separate behavior spec artifact を作らず、Plan 内の Inline behavior sketch と Case mapping を source of truth として扱ってください。Behavior spec artifact required: Yes なのに artifact がない場合は NeedsPlanBehaviorExpansion で停止し、black-box-behavior-spec-kernel.agent.md を recommended next step にしてください。
```

### behavior expansion を作る

```text
plans/<ticket-or-slug>.md の Plan readiness が NeedsPlanBehaviorExpansion なので、black-box-behavior-spec-kernel.agent.md を実行してください。
source requirements を stable Case IDs、negative expectation、derived invariant、excluded combinations、unresolved requirement-elaboration items へ展開してください。
Plan FR / AC、runtime contract、test design、implementation は変更せず、plans/<ticket-or-slug>-black-box-behavior-spec.md を作成してください。
```

### Plan をもとにトリアージする

```text
plans/<ticket-or-slug>.md を入力として、change-risk-triage.agent.md を実行してください。
まず Plan readiness check を行い、ReadyForRiskTriage の場合だけ parent Plan 全体の risk inventory、Guardrail Focus recommendation、Residual risk candidates、Implementation-realization risk、Recommended process path を出してください。実装 scope は縮小しないでください。
NeedsPlanBehaviorExpansion または NeedsHumanDecision の場合は runtime risk / process profile を選ばず Plan フェーズへ差し戻してください。
```

### 実装前に handoff review を行う

```text
実装に入る前に、implementation-handoff-review.agent.md を必須 gate として使ってください。
source code は読まず、artifacts も修正しないでください。
Parent Plan Coverage Ledger を作成し、Plan → Guardrail Focus RC → TP → production binding requirement の接続を確認してください。
Behavior spec artifact required: Yes の場合、または Inline behavior sketch が Case IDs を持つ場合は、Behavior Case Coverage Ledger または Inline Ready Gate equivalent の coverage disposition で relevant Case IDs をすべて分類してください。
Guardrail Focus ready と Parent Plan coverage ledger complete を分け、READY_FOR_BOUNDED_PARENT_PLAN_PASS 系または BLOCKED_* verdict を出してください。
```

### Adaptive Implementation route で実装する

```text
high-implementation-starter.agent.md を使って、parent Plan に対する非自明な実装を HIGH_MODEL から開始してください。READY_FOR_STANDARD_COMPLETION の complete handoff がある場合だけ standard-implementation-completer.agent.md へ残作業を直列委譲し、NEEDS_HIGH_MODEL_REENTRY は high-implementation-starter.agent.md に戻してください。

次の成果物を必ず読んでください。

- plans/<ticket-or-slug>.md
- plans/<ticket-or-slug>-black-box-behavior-spec.md（Behavior spec artifact required: Yes の場合）
- parent Plan / slice artifact 内の Inline behavior sketch と Case mapping（inline behavior sketch sufficient の場合）
- plans/<ticket-or-slug>-change-risk-triage.md
- plans/<ticket-or-slug>-implementation-contract-kernel.md（implementation-realization risk が Present / Unclear の場合）
- plans/<ticket-or-slug>-coverage-ledger.md（存在する場合）
- plans/<ticket-or-slug>-implementation-contract-review-kernel.md（explicit review-only fallback が存在する場合）
- plans/<ticket-or-slug>-runtime-contract-kernel.md
- plans/<ticket-or-slug>-test-design-kernel.md
- plans/<ticket-or-slug>-implementation-handoff-review.md

実装の source of truth は bounded Plan です。Guardrail Focus artifacts は deep-check guardrail として使い、implementation scope として扱わないでください。
通常可能な Functional requirements と Acceptance conditions を満たし、Non-goals / constraints / parent Plan 外の作業は行わないでください。
完了できない項目は NeedsHumanDecision / ManualVerificationRequired / TooCostlyForBoundedPass / ImplementationEvidenceMissing などで Implementation Self-Map と Remaining Work に記録してください。
```

### 実装後に review focus を作る

```text
人手レビュー用の読み順を整理したいので、code-review-focus-kernel.agent.md を実行してください。
bounded Plan、kernel artifacts、plans/<ticket-or-slug>-implementation-execution.md、working tree diff または PR diff を入力にしてください。
parent Plan item に影響する changed files と Guardrail Focus surface を分け、P0 / P1 / P2 review target と Suggested human review order を出してください。
```

### 実装後に検証する

```text
実装後の状態について、verification-kernel.agent.md を実行してください。
Parent Plan Coverage Ledger を更新し、Guardrail Focus RC/TP は production implementation、wiring/entrypoint、contract representation を深く確認してください。
behavior spec がある場合は current pass の Case IDs を Behavior Case Evidence Ledger に記録し、test / manual / production evidence へ接続してください。
focus 外の parent Plan item も implemented / verified / ManualVerificationRequired / ResidualDecisionCandidate / unmapped のいずれかに分類してください。
修正は行わず、parent Plan verdict と未解決項目を出してください。
```

### residual decision を行う

```text
verification-kernel と coverage-gap-triage の出力を入力として、residual-decision-gate.agent.md を実行してください。
Residual Decision Ledger を作成し、`ManualVerificationRequired` は close 不可の candidate action、`ManualVerificationDelegated` は owner / method / required evidence が明示された explicit decision 後の decision status として扱ってください。
explicit human decision がある項目だけ AcceptedResidual / ManualVerificationDelegated / DeferredWithOwner / AbortedWithReason として扱ってください。
human decision がない residual は NEEDS_HUMAN_RESIDUAL_DECISION として停止してください。
previous RES-* または NeedsHumanDecision がある rerun では、Previous residual closure / skip table を作り、human decision が不要になった理由を記録してください。
```

### 選択した FixNow だけを修正する

```text
verification-kernel、coverage-gap-triage、または residual-decision-gate の FixNow selector だけを対象に、coverage-gap-resolution-slice.agent.md を実行してください。
FixNow selector 外へ広げず、parent Plan との整合を崩さないでください。
修正後、verification-kernel.agent.md と residual-decision-gate.agent.md の再実行を次のステップとして記録してください。
```

---

## 成果物の命名規則

Plan網羅チェック・残件判定フローでは、通常は次の成果物を作成します。

| 成果物 | 目的 |
| --- | --- |
| `plans/<ticket-or-slug>.md` | bounded Plan。実装の source of truth |
| `plans/<ticket-or-slug>-black-box-behavior-spec.md` | source requirements から Case IDs、negative expectation、derived invariant への展開 |
| `plans/<ticket-or-slug>-change-risk-triage.md` | risk inventory、Guardrail Focus recommendation、Residual risk candidates |
| `plans/<ticket-or-slug>-implementation-contract-kernel.md` | dependency/API/provider path の確認結果、required code changes、prohibited substitutions、self-check readiness verdict |
| `plans/<ticket-or-slug>-implementation-contract-review-kernel.md` | explicit review-only fallback としての implementation-contract self-check review |
| `plans/<ticket-or-slug>-coverage-ledger.md` | canonical Parent Plan Coverage Ledger、Behavior Case coverage、Residual Decision Ledger、Coverage Ledger Delta |
| `plans/<ticket-or-slug>-runtime-contract-kernel.md` | Guardrail Focus runtime contract・producer / consumer・メッセージ・フィールド・production 実装の所在 |
| `plans/<ticket-or-slug>-test-design-kernel.md` | Guardrail Focus TP・stub/fake の使用有無・production binding 確認要件 |
| `plans/<ticket-or-slug>-implementation-handoff-review.md` | 実装直前の lightweight review verdict と Parent Plan Coverage Ledger |
| `plans/<ticket-or-slug>-implementation-execution.md` | 実装結果、Implementation Self-Map、Test / Check Summary、Remaining Work |
| `plans/<ticket-or-slug>-code-review-focus-kernel.md` | 人手コードレビュー向けの重点確認箇所・読む順番・不確実性の整理 |
| `plans/<ticket-or-slug>-verification-kernel.md` | Parent Plan Coverage Ledger / Coverage Ledger Delta 更新、production binding / wiring / contract の検証結果 |
| `plans/<ticket-or-slug>-parent-orchestration-state.md` | full-coverage 3層運用の親 orchestration 再開入口。現在 phase、次 action、artifact index、slice queue、Parent decisions made、blocking decision |
| `plans/<ticket-or-slug>-cross-slice-verification-kernel.md` | full-coverage decomposition 後の runtime postcondition oracle、forbidden-state oracle、previous gap closure delta、cross-slice verdict |
| `plans/<ticket-or-slug>-coverage-gap-triage.md` | 未解決ギャップの分類、FixNow items、Residual decision candidates |
| `plans/<ticket-or-slug>-residual-decision-gate.md` | Residual Decision Ledger と next-step verdict |
| `plans/<ticket-or-slug>-coverage-gap-resolution-slice.md` | FixNow selector の修正結果と残作業 |

---

## 運用原則

- Plan網羅チェック・残件判定フローでも Plan 作成を省略しない
- source requirement の期待動作が複数条件・状態・履歴・negative expectation に依存する場合は、black-box behavior expansion を Plan readiness gate として扱う
- 要求展開不足を full-coverage や slice decomposition で覆い隠さない
- 実装の source of truth は bounded Plan とする
- Guardrail Focus は implementation scope ではない
- kernel artifacts は deep-check guardrail として扱い、Plan の代替にしない
- parent Plan を agent が勝手に縮小しない
- Parent Plan Coverage Ledger を実装前と検証後に維持する
- Residual Decision Ledger なしに residual を accepted 扱いしない
- `AcceptedResidual` は explicit human decision がある場合だけ使う
- `ManualVerificationRequired` は「確認済み」ではなく、decision gate へ渡す close 不可の candidate status として扱う
- `ManualVerificationDelegated` は owner / method / required evidence が明示された explicit human decision 後の close 可能な decision status として扱う
- cross-slice verification では source-structure test と CI green だけで runtime postcondition を close しない
- stateful cross-slice contract は producer state と consumer gate の両方を確認する
- previous gap / residual は同等または弱い evidence で close しない
- 不明な項目を推測で埋めない
- テストが通ることを production binding の証拠にしない
- fake / stub だけを production の完成と扱わない
- 1 回の bounded な実行で停止し、残件は成果物に残す
- final done は parent Plan coverage と residual decision の両方で判定する
