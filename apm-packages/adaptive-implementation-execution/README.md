# Adaptive Implementation Execution

通常の Plan Mode output、短い実装計画、または明示選択された Design Pair handoff から、非自明な実装を HIGH_MODEL が開始し、残作業から構造上の意思決定がなくなった場合だけ STANDARD_MODEL へ直列委譲する、Codex / GitHub Copilot Chat in VS Code対応のAPM packageです。

## 解決する問題

外部仕様や課題全体の規模が小さくても、実装開始後には責務配置、signature、dependency、production wiring、error handling、state ownership、test seam などの判断が必要になる場合があります。

この package は、実装前の文書だけで model tier を固定せず、HIGH_MODEL が実コードを編集し、build / focused test の evidence を得た後に残存 decision surface を評価します。

## Plan Coverage Flow との違い

この package は implementation-only flow です。

- 通常 Plan、手書き Plan、Issue 内の実装計画だけで開始できる
- Plan Coverage artifacts を必須にしない
- change-risk-triage、runtime contract、test design、coverage ledger、residual decision を再実装しない
- final code review や総合 architecture review を置き換えない

Plan Coverage Flow が必要な課題は、既存の `plan-coverage-residual-flow` を使用してください。

## Design Pair input

`design-pair-implementation-execution` を利用者が明示選択した場合、この package は tracked Design Pair handoff を追加 input として受け取ります。`READY_FOR_ADAPTIVE_IMPLEMENTATION` だけでなく、`Interaction stage: complete`、Target Map の提示・選択要求、提示後の actual user response、non-empty selection または explicit all-Adaptive delegation、pending Target なしを編集前に検証します。さらに全summary IDのMap実在、5分類集合の相互排他と完全被覆、row Disposition一致、Locked Targetとall-Adaptiveの整合を再検証します。`AWAITING_USER_INPUT`、空の selected set、架空・重複・未分類Target、上流文書から再構成した user evidence は受理せず、`BLOCKED / BlockedByInvalidCompletionHandoff` で停止します。

Selected / Delegated-to-Adaptiveの各Targetには、Target Map rowと一致するfinal disposition、actual post-map user turn、confirmed contentを持つ`Target Disposition Evidence`を一件だけ要求します。AIが未委任Targetを`Adaptive-Owned`へ移したhandoff、最終user responseなしで`Discussed-Unlocked`へ移したhandoff、欠落・重複・架空・pre-map evidenceは編集前に拒否します。

selected Targetがある場合は、user-facing turn reference、具体的code location、current invariant、alternatives / trade-offs、proposalまたはNo proposal理由、validation expectationを含む`Selected Target Discussion Evidence`も要求します。Target名やartifact linkだけの抽象的evidenceでは開始しません。

Target Map presentation evidenceも、全Targetの具体的file / symbol、current invariant、内部設計判断候補、relevant evidenceをuser-facingに提示したturnを参照する必要があります。artifact linkやTarget名だけの初回応答は受理しません。

Design Pair が新たに作る decision のうち binding なのは、handoff の `Locked Decisions` に Decision ID、Target ID、Target Map 提示後の explicit human confirmation がある entry だけです。original Plan、repository policy、`Upstream Binding Constraints` は Design Pair Decision ID を持たない既存の binding input として別に守ります。Target Map、Upstream User Initial Positions、Discussed-Unlocked、Adaptive-Owned、Known Evidence、file / symbol references は HIGH_MODEL の通常 authority または allowed edit surface を拘束しません。Locked Decision conflict は黙って変更せず、Decision ID と actual-code evidence を伴う stop verdict で返します。Design Pair 未使用時の通常 Adaptive route は変わりません。

## Flow

```text
ordinary Plan
  -> high-implementation-starter [HIGH_MODEL]
       -> READY_FOR_STANDARD_COMPLETION
            -> standard-implementation-completer [STANDARD_MODEL]
                 -> COMPLETED
                 -> NEEDS_HIGH_MODEL_REENTRY
                      -> high-implementation-starter [HIGH_MODEL]
       -> COMPLETED_BY_HIGH_MODEL
       -> REPLAN_REQUIRED / HUMAN_DECISION_REQUIRED / BLOCKED
```

HIGH_MODEL と STANDARD_MODEL の write-heavy work は並列化しません。安全な delegation point がない場合、HIGH_MODEL が完了まで実装します。

## Package contents

| Content | Path |
| --- | --- |
| Orchestration skill | `.apm/skills/adaptive-implementation-execution/SKILL.md` |
| Implementation Intent reference | skill の `refs/intent.md` |
| Completion Handoff reference | skill の `refs/handoff.md` |
| Portable HIGH_MODEL agent | repository root `.github/agents/high-implementation-starter.agent.md` |
| Portable STANDARD_MODEL agent | repository root `.github/agents/standard-implementation-completer.agent.md` |
| Codex agent configuration sources | `codex-agents/*.toml` |
| Compatibility installer | `scripts/install-adaptive-implementation-local.cs` |
| Static validator | `scripts/validate-adaptive-implementation-execution.ps1` |
| APM 0.26.0 remote install smoke | `scripts/validate-adaptive-implementation-apm-smoke.ps1` |
| Executable route scenarios A-G | `tests/routing-scenarios.json` + `tests/validate-routing-scenarios.ps1` |
| Pre-Design-Pair resume fixture | `docs/examples/legacy-adaptive-handoff.md` |

root `.github/agents/high-implementation-starter.agent.md` と `standard-implementation-completer.agent.md` がportable agent contractです。APM 0.26.0はこれらの root agent と package Skill を target ごとに導入し、Copilotでは`.agent.md`、Codexではmodel-less TOML stubを扱います。両agentは`disable-model-invocation: true`によりagent pickerからの明示選択を維持しつつ、他agentのmodel判断によるsubagent起動を禁止します。`tools`は省略してCopilotの全toolを許可し、Codex変換時のfrontmatter dropを防ぎます。

local installer は package の `codex-agents/high-implementation-starter.toml` と `standard-implementation-completer.toml` だけを source とし、target の `.codex/agents/*.toml` だけを書き込みます。root `.github/agents/*.agent.md`、Skill、その他の target file をコピーまたは更新しません。APM が Skill と root portable agents を導入し、local installer は Codex の concrete model 設定を補完します。

## Quick start

CodexとGitHub Copilot Chat in VS Codeを同じrepositoryへ導入する場合:

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
```

片方だけ使う場合は、Codexを`codex,agent-skills`、Copilotを`copilot,agent-skills`に絞れます。APM 0.26.0では`vscode`指定も`copilot`へ正規化されますが、manifestと文書ではcanonical target名`copilot`を使用します。`github-copilot`はAPM target名ではありません。

APM install が skill と portable custom agents を導入する本体です。現行 APM が `.codex/agents/*.toml` に concrete model 設定を生成しない場合だけ、互換処理として package 付属の設定を同期し、検証します。

CopilotではVS CodeのChat viewでagent pickerから`high-implementation-starter`を選びます。`standard-implementation-completer`から直接開始しません。model mappingはHIGH / re-entryが`GPT-5.6 Terra (copilot)`、valid `READY_FOR_STANDARD_COMPLETION`後のSTANDARDが`GPT-5.6 Luna (copilot)`です。Terra -> Luna -> Terraの遷移ではtracked handoff pathを渡し、会話履歴だけにstateを置きません。

```powershell
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --dry-run
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target
dotnet run --file .\scripts\install-adaptive-implementation-local.cs -- C:\path\to\target --check
```

installer は File-based app であり、`.csproj` は不要です。APM が生成した model 未設定の同名 custom agent は、既知の APM stub shape と package metadata が一致する場合だけ `--force` なしで補完します。それ以外の異なる同名 TOML は衝突として停止するため、内容を確認して package-owned file と判断できる場合だけ `--force` を指定します。

補助スクリプトがアクセスする導入先ファイルは2つの `.codex/agents/*.toml` だけです。`AGENTS.md` を作成・変更・削除せず、実行しても skill の使用や自動選択を意味しません。`--check` は model / reasoning / workspace-write 設定、role ごとの agent 名、HIGH_MODEL と STANDARD_MODEL の異なる model mapping を検証します。APM が必要な設定を直接生成できるようになれば、この互換処理は不要になる可能性があります。

skill の選択条件と、選択後の実行順序、handoff、re-entry、verification boundary の source of truth は `.apm/skills/adaptive-implementation-execution/SKILL.md` です。この package は repository 内のすべての Plan や実装作業へ skill を強制しません。skill は利用者が `/adaptive-implementation-execution` で slash 起動した場合だけ起動し、通常の「実装して」や自然文での名前言及だけでは自動選択しません。frontmatter は `disable-model-invocation: true` と `user-invocable: true` です。

通常Adaptiveのfresh intakeは`implementation_route: adaptive`、`implementation_route_source: default`、`design_pair_handoff: N/A`を初期化し、3項目をHIGH_MODELへ明示的に渡します。invalid-artifact `BLOCKED`だけは欠落identityを捏造せず、raw observed valueまたは`<missing>`とrepair evidenceを返します。

Copilotのmodel名と利用可否はCopilot plan、VS Code / extension version、organization policyに依存します。requested modelとobserved modelが一致しない、またはTerra / Lunaを選択できない場合は別tierへ黙って開始せず、mappingを明示変更するかpolicy管理者へ確認し、manual smokeへrequested / observed modelを記録します。

Design Pair導入前のtracked Adaptive handoffは、旧必須fieldがすべて揃い、Design Pair evidenceが一切ない場合だけ`Legacy Adaptive handoff normalization`でresumeできます。`route_metadata_normalization: legacy-adaptive-handoff`とdeterministic `LEGACY-HIGH-Dxx` Decision IDsを記録し、新Design Pair fieldsの欠落だけを理由にHIGH_MODELへ戻しません。部分的な新schema、Design Pair evidence、不完全な旧schemaは`BLOCKED` / `BlockedByInvalidCompletionHandoff`としてartifact repairを要求します。

起動例:

```text
/adaptive-implementation-execution この Plan を実装してください。
```

## Documentation

- [Install guide](docs/install-guide.md)
- [Usage guide](docs/usage-guide.md)
- [Validation scenarios](docs/examples/adaptive-routing-validation.md)
- [Manual Copilot smoke](docs/examples/copilot-manual-smoke.md)
