# Issue #38 Lite / Standard 実装計画

## ソースコンテキスト

- Issue: https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/38
- Issue title: Plan Coverage Flow の Lite/Standard 化と軽量化
- 計画作成時点の Issue 状態: Open、issue comment なし
- この成果物は分析専用であり、Issue #38 の実装は行わない。
- レビュー反映方針: Codex-first profile agent、implementation execution、coverage gap repair、shared instruction 配布経路、Copilot fallback の対象範囲、旧前提の negative scan を Plan に追加する。

## 計画上の制約

- この計画タスクの対象外: コード、agent、skill、README、template の実装
- 実装計画では、既存の guardrail invariant を維持する必要がある:
  - `Plan is source of truth`
  - `No fake-only completion`
  - `Residual requires explicit decision`
- `strict` をサポート対象の `documentation_level` にしてはいけない。
- `full-coverage` は `documentation_level` ではなく、route / selected process のままとする。
- Codex-first の router / template だけでなく、実行入口である profile agent TOML と profile `AGENTS.md` も lite / standard 互換の対象に含める。
- `copilot-fallback-ai-development-process` はこの Issue #38 の対象外とする。必要な場合は後続 issue で lite / standard 語彙と state / stop-report 互換を移植する。
- `.github/instructions/plan-coverage-shared.instructions.md` は `.github/agents/*.agent.md` と APM package 側の shared instruction として扱う。Codex-first local profile TOML はこの shared file を直接参照せず、必要な互換条件を profile 側に明示する。
- 以下の各 implementation slice は 1 つの主責務だけを持つ。実装中に、その slice が列挙された target files の外まで広い書き換えを必要とすることが分かった場合は、編集前にその slice をさらに分割する。

## 既存ファイルマップ

| Area | Existing path | 現時点で確認した役割 |
| --- | --- | --- |
| Plan Coverage skill | `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` | Plan Coverage Check and Residual Decision Flow の直接 entrypoint |
| Plan Coverage package manifest | `apm-packages/token-aware-guardrail-kernel-flow/apm.yml` | root の `.github/agents/*.agent.md` dependency を APM target に配布する |
| Codex-first router skill | `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md` | task weight、selected process、state、delegation、READY / close rule を持つ |
| Codex-first instructions | `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md` | Codex-first の runtime instruction set |
| Codex-first profile | `apm-packages/codex-first-ai-development-process/profiles/codex-first/AGENTS.md`, `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/*.toml` | local / profile agent の実行入口と stop condition |
| Codex-first state template | `apm-packages/codex-first-ai-development-process/templates/codex-first-state.md` | 現在は core の resume state と audit ledger が同居している |
| Codex-first installer | `apm-packages/codex-first-ai-development-process/scripts/install-codex-first-local.cs` | Codex-first の skill、agent、config、template をコピーする。現状は `.github/instructions` をコピーしない |
| Agent manifests | `.github/agents/*.agent.md` | agent 固有ルール、output section、verdict の source of truth |
| Main docs | `README.md`, `docs/token-aware-guardrail-kernel-process-and-agents.md` | process 概要、routing 例、artifact 命名、guardrail の意味を説明する |
| Codex-first docs | `apm-packages/codex-first-ai-development-process/docs/*.md` | user / maintainer / process docs と validation sample |
| Validation examples | `apm-packages/codex-first-ai-development-process/docs/examples/routing-mvp-validation.md` | router 挙動に対する既存 sample suite |

## 実装順序

| Order | Slice | 主責務 | Depends on |
| --- | --- | --- | --- |
| 1 | SL-001 | shared instruction の stable invariants を定義する | none |
| 2 | SL-002 | shared instruction の APM 配布方針を固定する | SL-001 |
| 3 | SL-003 | direct Plan Coverage に `documentation_level` の routing vocabulary を追加する | SL-002 |
| 4 | SL-004 | Codex-first router に `documentation_level` 選択を追加する | SL-003 |
| 5 | SL-005 | Plan Coverage Lite artifact template を定義する | SL-003 |
| 6 | SL-006 | Inline Ready Gate を handoff 相当 gate として定義する | SL-005 |
| 7 | SL-007 | Codex profile agents の lite / standard compatibility を追加する | SL-004, SL-006 |
| 8 | SL-008 | inline behavior sketch と Behavior Spec への escalation を定義する | SL-005 |
| 9 | SL-009 | canonical coverage ledger と delta update を定義する | SL-006 |
| 10 | SL-010 | coverage-gap-triage を条件付きにし、direct FixNow selector を追加する | SL-009 |
| 11 | SL-011 | implementation-contract-kernel に self-check / readiness verdict を追加する | SL-001 |
| 12 | SL-012 | implementation-contract-review-kernel を compatibility shim / review-only mode へ変換し、参照を更新する | SL-011 |
| 13 | SL-013 | pre-implementation agent を shared instruction 参照へ移行する | SL-001, SL-011, SL-012 |
| 14 | SL-014 | post-implementation agent を shared instruction 参照へ移行する | SL-001, SL-009, SL-010, SL-012 |
| 15 | SL-015 | Codex-first state を core template と audit template に分割する | SL-004 |
| 16 | SL-016 | VAL-001 から VAL-010 までの validation sample と negative scan を追加する | SL-005 through SL-015 |
| 17 | SL-017 | README と user / maintainer docs の最終整合を取る | all prior slices |

## Slice 詳細

### SL-001: Shared Instruction Stable Invariants

| Field | Plan |
| --- | --- |
| Target files | New `.github/instructions/plan-coverage-shared.instructions.md` |
| Implementation content | 共通 failure mode、guardrail intent、Plan source-of-truth rule、no fake-only completion、residual decision の基礎、共有 Handoff Packet field、共有 status vocabulary、portability rule、"do not over-read" rule だけを持つ shared instruction file を追加する。lite / standard routing policy の詳細は、routing vocabulary が確定する後続 slice で扱う。agent 固有の output path、allowed verdict vocabulary、stop condition は shared file へ移してはいけない。 |
| Verification method | `rg -n "Plan is source of truth|No fake-only completion|Residual requires explicit decision|Handoff Packet|do not over-read" .github/instructions/plan-coverage-shared.instructions.md`; `rg -n "Allowed verdict|output path|Stop condition" .github/instructions/plan-coverage-shared.instructions.md` で agent 固有語彙が混入していないことを確認する。 |
| Dependencies | None |
| Completion criteria | common instruction が存在し、stable invariants のみを含み、verdict vocabulary / output path / stop condition は agent 側に残ることが明示されている。 |
| Rollback | 新しい instruction file を削除する。この時点では agent 側がまだ利用していないため、振る舞い変更は残らない。 |

### SL-002: Shared Instruction APM Distribution Policy

| Field | Plan |
| --- | --- |
| Target files | `apm-packages/token-aware-guardrail-kernel-flow/apm.yml`; `apm-packages/codex-first-ai-development-process/apm.yml`; `apm-packages/codex-first-ai-development-process/docs/maintainer-guide.md` |
| Implementation content | `.github/instructions/plan-coverage-shared.instructions.md` を APM 配布対象として manifest dependency に追加する。Codex-first local installer は現状 `.github/instructions` をコピーしないため、profile TOML は shared instruction を直接参照しない方針を maintainer doc に明記する。local profile に必要な互換条件は SL-007 で profile TOML / profile `AGENTS.md` へ直接書く。 |
| Verification method | `rg -n "plan-coverage-shared.instructions.md" apm-packages/token-aware-guardrail-kernel-flow/apm.yml apm-packages/codex-first-ai-development-process/apm.yml apm-packages/codex-first-ai-development-process/docs/maintainer-guide.md`; `rg -n "plan-coverage-shared.instructions.md" apm-packages/codex-first-ai-development-process/profiles/codex-first` が empty であることを確認する。 |
| Dependencies | SL-001 |
| Completion criteria | shared instruction は `.github/agents` / APM 配布経路で利用され、Codex-first local profile TOML が存在しない shared file を参照しないことが明確である。 |
| Rollback | manifest dependency と maintainer doc の配布方針を revert する。SL-001 の shared file は未使用のまま残ってもよい。 |

### SL-003: Direct Plan Coverage Documentation Level Routing

| Field | Plan |
| --- | --- |
| Target files | `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md`; `.github/agents/change-risk-triage.agent.md`; `.github/agents/plan-kernel.agent.md` |
| Implementation content | direct Plan Coverage flow に `documentation_level: lite / standard` を導入する。`lite` と `standard` を定義し、`strict` を禁止し、`full-coverage` は `ReadyForRiskTriage` 後の route / process profile であることを明記する。skill flow では lite が単一 artifact を使え、standard は圧縮版 guardrail を使う形へ更新する。triage / plan の handoff vocabulary も更新し、広い ready work は `documentation_level: standard` と selected route `full-coverage` を記録し、full coverage を level として扱わないようにする。 |
| Verification method | `rg -n "documentation_level|lite|standard|strict|full-coverage" apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md .github/agents/change-risk-triage.agent.md .github/agents/plan-kernel.agent.md`; `strict` が明示的な非対応としてのみ現れることを目視確認する。 |
| Dependencies | SL-002 |
| Completion criteria | direct flow が、ユーザーに選ばせずに lite / standard を分類でき、full-coverage は advanced route のままである。 |
| Rollback | 3 つの対象ファイルを revert する。`documentation_level` に依存する後続 slice は先に戻す必要がある。 |

### SL-004: Codex-first Documentation Level Selection

| Field | Plan |
| --- | --- |
| Target files | `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md`; `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md`; `apm-packages/codex-first-ai-development-process/templates/codex-first-state.md`; `apm-packages/codex-first-ai-development-process/templates/stop-report.md` |
| Implementation content | task weight と risk から導出される router-owned field として `documentation_level` を追加する。`trivial-local`、`small-bounded`、`medium-bounded`、`high-risk-bounded`、`needs-plan-behavior-expansion`、`broad-full-coverage-candidate`、`blocked-human-required` それぞれの rule を定義する。ユーザー選択は引き続き無効のままとする。`selected_process` は変えず、state / stop-report に `documentation_level` field を追加する。 |
| Verification method | `rg -n "documentation_level|lite|standard|selected_process|advanced-full-coverage|strict" apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md apm-packages/codex-first-ai-development-process/templates`; `strict` が enum value に入っていないことを目視確認する。 |
| Dependencies | SL-003 |
| Completion criteria | Codex-first が `documentation_level` を自動記録し、`full-coverage` は selected process / route の意味のまま維持される。 |
| Rollback | router skill、instruction、template の変更を revert する。 |

### SL-005: Plan Coverage Lite Artifact Template

| Field | Plan |
| --- | --- |
| Target files | New `apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md`; `.github/agents/plan-kernel.agent.md`; `.github/agents/implementation-execution.agent.md` |
| Implementation content | Plan Coverage Lite の標準構造を定義する: Source of truth、Plan summary、FR / AC、Inline behavior sketch、Risk checklist、Inline Ready Gate、Implementation Self-Map、Verification Summary、Residual / Close Decision。lite でも FR / AC coverage と residual / human-decision classification を必須にする。`implementation-execution.agent.md` には、Lite artifact 内の `Implementation Self-Map` を正式な更新対象として扱えることを追加する。lite は artifact を統合するのであって、guardrail を削るものではないことも明確にする。 |
| Verification method | `rg -n "Plan Coverage Lite|Source of truth|FR / AC|Inline behavior sketch|Inline Ready Gate|Implementation Self-Map|Residual / Close Decision" apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md .github/agents/implementation-execution.agent.md`; skill / plan-kernel 側の参照も確認する。 |
| Dependencies | SL-003 |
| Completion criteria | Lite artifact が documented / templated され、Issue #38 の必須 section をすべて含み、implementation-execution が Lite artifact を正式入力 / 更新対象として扱える。 |
| Rollback | template を削除し、skill / plan-kernel / implementation-execution の参照を revert する。 |

### SL-006: Inline Ready Gate Equivalence

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/implementation-handoff-review.agent.md`; `.github/agents/implementation-execution.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md`; `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md` |
| Implementation content | `Inline Ready Gate` がどの条件で `implementation-handoff-review` と明示的に等価になるかを定義する。Plan readiness、expansion required、Case-to-Plan mapping、risk checklist、parent coverage、implementation allowed の全項目が complete であることを要求する。`implementation-execution.agent.md` には、Lite artifact の `Inline Ready Gate` を implementation authorization source として読めることと、separate `implementation-handoff-review.md` がないことだけで停止しないことを追加する。lite では通常 `plans/<slug>-implementation-handoff-review.md` を作らず、standard では risk に応じて inline または separate gate を選べることも明記する。 |
| Verification method | `rg -n "Inline Ready Gate|implementation-handoff-review 相当|Implementation allowed|Parent Plan coverage|Expansion required|implementation authorization source" .github/agents/implementation-handoff-review.agent.md .github/agents/implementation-execution.agent.md apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md` |
| Dependencies | SL-005 |
| Completion criteria | implementation permission に使えるだけの厳密さで inline gate の等価条件が定義され、不完全な場合は fail-closed になる。 |
| Rollback | 4 つの対象ファイルを revert する。lite template は残っても、implementation を inline で許可しなくなる。 |

### SL-007: Codex Profile Agents Lite / Standard Compatibility

| Field | Plan |
| --- | --- |
| Target files | `apm-packages/codex-first-ai-development-process/profiles/codex-first/AGENTS.md`; `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/standard-implementer.toml`; `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/standard-verifier.toml`; 必要に応じて `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/high-risk-triage.toml`; `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/high-implementation-contract.toml`; `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/implementation-handoff-review.toml`; `apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/cheap-artifact-format-checker.toml` |
| Implementation content | profile agent が旧 standard 前提だけで停止しないよう、lite / standard compatibility を追加する。`standard-implementer.toml` は separate handoff review または Inline Ready Gate equivalent を implementation authorization source として扱う。`standard-verifier.toml` は canonical ledger + delta、Lite artifact、Behavior Case Evidence Ledger の読み方を更新する。profile `AGENTS.md` には shared instruction を直接参照しない local profile 方針と、profile 側で満たすべき互換条件を明記する。高リスク / contract / handoff / cheap checker agent に旧 prerequisite が残る場合は、同じ slice 内で profile-level wording だけを更新する。 |
| Verification method | `rg -n "documentation_level|lite|standard|Inline Ready Gate|implementation authorization|coverage-ledger|Coverage Ledger Delta|Behavior Case Evidence Ledger" apm-packages/codex-first-ai-development-process/profiles/codex-first`; `rg -n "Require the change-risk-triage artifact and implementation-handoff-review parent authorization artifact before editing" apm-packages/codex-first-ai-development-process/profiles/codex-first` が旧必須条件だけを残していないことを確認する。 |
| Dependencies | SL-004, SL-006 |
| Completion criteria | router は lite を選べるが profile agent が旧 standard prerequisite で停止する、という断絶がなくなる。 |
| Rollback | profile `AGENTS.md` と対象 TOML を revert する。router / template の lite vocabulary は残るが、profile 実行入口は旧 standard 前提へ戻る。 |

### SL-008: Inline Behavior Sketch and Escalation

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/plan-kernel.agent.md`; `.github/agents/black-box-behavior-spec-kernel.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` |
| Implementation content | 2 段階の Behavior Spec rule を追加する。lite / standard ではまず inline behavior sketch を記録し、case 数、negative expectation、recovery / rollback / retry / replay / cleanup、durable state、idempotency、mapping risk、human decision、standard / full-coverage への escalation などが必要な場合にだけ `plans/<slug>-black-box-behavior-spec.md` へ進める。既存の Plan readiness failure の扱いは維持する。 |
| Verification method | `rg -n "Inline behavior sketch|Black-box Behavior Spec|escalation|negative expectation|rollback|retry|idempotency|NeedsPlanBehaviorExpansion" .github/agents/plan-kernel.agent.md .github/agents/black-box-behavior-spec-kernel.agent.md apm-packages/token-aware-guardrail-kernel-flow/.apm` |
| Dependencies | SL-005 |
| Completion criteria | 単純なケースでは inline sketch で足り、separate Behavior Spec へ上げる条件も明確になっている。 |
| Rollback | 対象ファイルを revert する。既存の behavior spec kernel 自体はそのまま利用できる。 |

### SL-009: Canonical Coverage Ledger and Delta Updates

| Field | Plan |
| --- | --- |
| Target files | New `apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/coverage-ledger.md`; `.github/agents/implementation-handoff-review.agent.md`; `.github/agents/implementation-execution.agent.md`; `.github/agents/verification-kernel.agent.md`; `.github/agents/residual-decision-gate.agent.md`; `.github/agents/coverage-gap-resolution-slice.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` |
| Implementation content | `plans/<slug>-coverage-ledger.md` を canonical ledger、`Coverage Ledger Delta` を中間 gate 用の update format として定義する。すべての FR / AC row は分類されたままであること、close / residual decision 時には full completion view を作ってよいことを維持する。handoff / execution / verification / residual / gap-resolution agent は canonical ledger と relevant delta を読む形へ更新する。 |
| Verification method | `rg -n "coverage-ledger|Coverage Ledger Delta|canonical ledger|full completion view|Parent Plan Coverage Ledger" apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/coverage-ledger.md .github/agents/implementation-handoff-review.agent.md .github/agents/implementation-execution.agent.md .github/agents/verification-kernel.agent.md .github/agents/residual-decision-gate.agent.md .github/agents/coverage-gap-resolution-slice.agent.md` |
| Dependencies | SL-006 |
| Completion criteria | standard route が、未分類の FR / AC row を隠さずに full ledger の再掲を減らせる。implementation-execution と gap-resolution も旧 ledger 前提だけで動かない。 |
| Rollback | ledger template を削除し、agent / skill の参照を revert する。既存の full ledger 挙動へ戻る。 |

### SL-010: Conditional Coverage Gap Triage and Direct FixNow

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/verification-kernel.agent.md`; `.github/agents/coverage-gap-triage.agent.md`; `.github/agents/residual-decision-gate.agent.md`; `.github/agents/coverage-gap-resolution-slice.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` |
| Implementation content | gap が 1〜2 件で、gap type と target file / address が明確で、human decision / manual verification / Plan ambiguity / Behavior Case residual がなく、bounded fix pass で安全に扱える場合は `coverage-gap-triage` を省略できる条件を追加する。verification / residual gate から simple gap 向けの direct FixNow selector を出せるようにし、complex / ambiguous gap は引き続き `coverage-gap-triage` へ送る。`coverage-gap-resolution-slice.agent.md` は explicit FixNow selector を受けた repair-only agent のまま維持する。 |
| Verification method | `rg -n "direct FixNow|coverage-gap-triage|simple gap|PlanAmbiguity|UnmappedParentAcceptance|BehaviorCaseWithoutEvidence|ManualVerificationRequired|FixNow selector" .github/agents/verification-kernel.agent.md .github/agents/coverage-gap-triage.agent.md .github/agents/residual-decision-gate.agent.md .github/agents/coverage-gap-resolution-slice.agent.md apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` |
| Dependencies | SL-009 |
| Completion criteria | simple gap は直接 FixNow へ進み、complex gap は引き続き triage を通る。gap-resolution は residual decision を飛ばす入口にならない。 |
| Rollback | 対象ファイルを revert する。未解決項目は再びすべて coverage-gap-triage 経由になる。 |

### SL-011: Unified Implementation Contract Self-check

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/implementation-contract-kernel.agent.md` |
| Implementation content | required output structure に `Self-check / Readiness verdict` を追加する。Issue #38 の verdict vocabulary、つまり `READY_FOR_RUNTIME_CONTRACT`、`READY_FOR_IMPLEMENTATION`、`BLOCKED_BY_DEPENDENCY_MISSING`、`BLOCKED_BY_API_SURFACE_UNKNOWN`、`BLOCKED_BY_UNJUSTIFIED_SUBSTITUTION`、`BLOCKED_BY_SOURCE_OF_TRUTH_DRIFT`、`NEEDS_HUMAN_DECISION` を使う。no-code / no-test policy は維持する。 |
| Verification method | `rg -n "Self-check / Readiness verdict|READY_FOR_RUNTIME_CONTRACT|READY_FOR_IMPLEMENTATION|BLOCKED_BY_DEPENDENCY_MISSING|BLOCKED_BY_API_SURFACE_UNKNOWN|BLOCKED_BY_UNJUSTIFIED_SUBSTITUTION|BLOCKED_BY_SOURCE_OF_TRUTH_DRIFT|NEEDS_HUMAN_DECISION" .github/agents/implementation-contract-kernel.agent.md` |
| Dependencies | SL-001 |
| Completion criteria | implementation-contract が 1 つの artifact で contract と readiness verdict を出せる。 |
| Rollback | `implementation-contract-kernel.agent.md` を revert する。separate review kernel はそのまま残る。 |

### SL-012: Review Kernel Compatibility Shim and Reference Update

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/implementation-contract-review-kernel.agent.md`; `.github/agents/coverage-gap-resolution-slice.agent.md`; `.github/agents/coverage-gap-triage.agent.md`; `.github/agents/implementation-execution.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md`; `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md`; `README.md`; `docs/token-aware-guardrail-kernel-process-and-agents.md` |
| Implementation content | old review kernel の compatibility 挙動を決めて文書化する。推奨方針は、この file を deprecated な compatibility shim / explicit review-only mode として残し、必要なときだけ unified implementation-contract self-check を検証できるようにすること。新しい通常フローは unified contract artifact を使うよう参照を更新しつつ、既存参照は壊さない。`coverage-gap-resolution-slice.agent.md` と `coverage-gap-triage.agent.md` は、旧 review-kernel を通常推奨の次工程として案内し続けないよう更新する。 |
| Verification method | `rg -n "implementation-contract-review-kernel|deprecated|compatibility|review-only mode|implementation-contract-kernel" .github/agents/implementation-contract-review-kernel.agent.md .github/agents/coverage-gap-resolution-slice.agent.md .github/agents/coverage-gap-triage.agent.md .github/agents/implementation-execution.agent.md apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md README.md docs/token-aware-guardrail-kernel-process-and-agents.md`; 旧 kernel 参照が通常推奨か explicit fallback かを手動確認する。 |
| Dependencies | SL-011 |
| Completion criteria | 既存参照は有効なままで、通常パスでは 2 つの薄い隣接 artifact を要求しなくなる。gap-resolution / gap-triage も旧 review-kernel を通常ルートとして案内しない。 |
| Rollback | 対象ファイルをすべて revert する。old 2-step contract review flow に戻る。 |

### SL-013: Shared Instruction Migration for Pre-implementation Agents

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/plan-kernel.agent.md`; `.github/agents/black-box-behavior-spec-kernel.agent.md`; `.github/agents/change-risk-triage.agent.md`; `.github/agents/implementation-contract-kernel.agent.md`; `.github/agents/runtime-contract-kernel.agent.md`; `.github/agents/test-design-kernel.agent.md`; `.github/agents/implementation-handoff-review.agent.md` |
| Implementation content | pre-implementation agent に重複している embedded policy / status vocabulary / 共通 Handoff Packet boilerplate を、`.github/instructions/plan-coverage-shared.instructions.md` 参照へ置き換える。agent 固有の責務、required input、output path、required output section、allowed verdict vocabulary、stop condition、agent 固有の must-not-do section は各 agent 内に残す。 |
| Verification method | `rg -n "plan-coverage-shared.instructions.md|Allowed verdict|output path|Stop condition|Must not do" .github/agents/plan-kernel.agent.md .github/agents/black-box-behavior-spec-kernel.agent.md .github/agents/change-risk-triage.agent.md .github/agents/implementation-contract-kernel.agent.md .github/agents/runtime-contract-kernel.agent.md .github/agents/test-design-kernel.agent.md .github/agents/implementation-handoff-review.agent.md`; verdict が落ちていないかは手動確認する。 |
| Dependencies | SL-001, SL-011, SL-012 |
| Completion criteria | boilerplate が減りつつ、各 agent の local verdict と stop rule は失われていない。 |
| Rollback | 列挙した agent file を revert する。shared instruction file は未使用のまま残ってもよい。 |

### SL-014: Shared Instruction Migration for Post-implementation Agents

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/verification-kernel.agent.md`; `.github/agents/coverage-gap-triage.agent.md`; `.github/agents/residual-decision-gate.agent.md`; `.github/agents/cross-slice-verification-kernel.agent.md`; `.github/agents/coverage-gap-resolution-slice.agent.md` |
| Implementation content | post-implementation / close agent にある共通 status vocabulary と Handoff Packet boilerplate を shared instruction 参照へ移す。production-binding verification rule、gap type precedence、residual verdict vocabulary、output path、close-blocking logic、explicit FixNow selector requirement は各 agent 側に残す。 |
| Verification method | `rg -n "plan-coverage-shared.instructions.md|PARENT_PLAN_VERIFIED|READY_TO_CLOSE|Gap type|FixNow|Residual Decision|Stop condition" .github/agents/verification-kernel.agent.md .github/agents/coverage-gap-triage.agent.md .github/agents/residual-decision-gate.agent.md .github/agents/cross-slice-verification-kernel.agent.md .github/agents/coverage-gap-resolution-slice.agent.md`; production-binding / residual rule が落ちていないか手動確認する。 |
| Dependencies | SL-001, SL-009, SL-010, SL-012 |
| Completion criteria | common policy の重複は減るが、post-implementation の fail-closed semantics は各 agent 内に明示的に残る。 |
| Rollback | 列挙した agent file を revert する。 |

### SL-015: Codex-first Core / Audit State Split

| Field | Plan |
| --- | --- |
| Target files | `apm-packages/codex-first-ai-development-process/templates/codex-first-state.md`; new `apm-packages/codex-first-ai-development-process/templates/codex-first-audit.md`; `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md`; `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md`; `apm-packages/codex-first-ai-development-process/templates/stop-report.md`; `apm-packages/codex-first-ai-development-process/docs/codex-first-ai-development-process.md`; `apm-packages/codex-first-ai-development-process/docs/user-guide.md`; `apm-packages/codex-first-ai-development-process/docs/maintainer-guide.md` |
| Implementation content | `plans/<slug>/codex-first-state.md` は resume core として維持し、task slug、source of truth、documentation level、selected process、current/next gate、plan readiness、risk artifact status、edit permission、stop reason、human-required items、unresolved residuals、next action、last updated summary を持たせる。完全な Agent Usage Ledger、observed runs、configured / hook / reported / effective model detail、delegation compliance detail、historical routing detail は `plans/<slug>/codex-first-audit.md` へ移す。router は必要な場合だけ audit を読むよう更新する。既存 installer は Markdown template をすべてコピーするため、実装で非 `.md` asset を追加しない限り installer logic の変更は不要。 |
| Verification method | `rg -n "codex-first-audit|documentation_level|Agent Usage Ledger|Observed runs|configured_model|hook_model|reported_model|effective_model" apm-packages/codex-first-ai-development-process/templates apm-packages/codex-first-ai-development-process/.apm apm-packages/codex-first-ai-development-process/docs`; 環境に互換 .NET SDK がある場合は `dotnet run --file apm-packages/codex-first-ai-development-process/scripts/install-codex-first-local.cs -- . --dry-run` も実行する。 |
| Dependencies | SL-004 |
| Completion criteria | core の resume state が小さくなり、audit は引き続き利用可能で、どちらをいつ読むかが docs / template で説明されている。 |
| Rollback | `codex-first-audit.md` template を削除し、router / docs / state template を combined state に戻す。 |

### SL-016: Validation Samples and Negative Scans

| Field | Plan |
| --- | --- |
| Target files | New `apm-packages/codex-first-ai-development-process/docs/examples/lite-standard-validation.md`; 必要なら `apm-packages/codex-first-ai-development-process/docs/examples/routing-mvp-validation.md` に pointer を追加 |
| Implementation content | VAL-001 から VAL-010 までの validation sample を追加する: trivial-local、small-bounded-lite、medium-standard、high-risk-standard、behavior-expansion-standard、full-coverage-candidate、resume-with-core-state、simple-gap-direct-fixnow、complex-gap-triage、unified-implementation-contract。lite route の軽量化が観測できるよう、想定 artifact count / sections read 比較も含める。加えて、`strict` enum 残存、Inline Ready Gate 導入後の separate handoff-only prerequisite、旧 review-kernel の通常推奨、shared instruction 参照と配布経路の矛盾を検出する negative scan を validation sample または最終検証手順へ追加する。 |
| Verification method | `rg -n "VAL-001|VAL-002|VAL-003|VAL-004|VAL-005|VAL-006|VAL-007|VAL-008|VAL-009|VAL-010|artifact count|sections read|negative scan" apm-packages/codex-first-ai-development-process/docs/examples/lite-standard-validation.md`; 最終検証の negative scan 4 本も実行する。 |
| Dependencies | SL-005 through SL-015 |
| Completion criteria | 10 個すべての validation sample が存在し、軽量化効果と guardrail 維持の両方をカバーしている。旧前提が残るリスクを検出する negative scan が定義されている。 |
| Rollback | 新しい validation file と pointer を削除する。最終検証手順に追加した negative scan も revert する。 |

### SL-017: Final Documentation Consistency

| Field | Plan |
| --- | --- |
| Target files | `README.md`; `docs/token-aware-guardrail-kernel-process-and-agents.md`; `apm-packages/codex-first-ai-development-process/docs/user-guide.md`; `apm-packages/codex-first-ai-development-process/docs/maintainer-guide.md`; `apm-packages/codex-first-ai-development-process/docs/codex-first-ai-development-process.md`; state/template install の挙動が変わる場合は `apm-packages/codex-first-ai-development-process/docs/bootstrap-and-merge-policy.md` |
| Implementation content | すべての挙動変更を実装し終えたあとに、user-facing / maintainer doc を更新する。lite / standard、strict なし、full-coverage は route、Lite artifact、Inline Ready Gate、Behavior Spec escalation、ledger delta、conditional gap triage、unified implementation contract、common instruction ownership、profile agent compatibility、core/audit state、validation sample を説明する。`copilot-fallback-ai-development-process` は Issue #38 の対象外であることを明記する。初心者向け doc では、user が process / agent / model / documentation level を選ばないことも明確に維持する。 |
| Verification method | `rg -n "documentation_level|lite|standard|strict|full-coverage|Inline Ready Gate|Coverage Ledger Delta|codex-first-audit|standard-implementer.toml|copilot-fallback-ai-development-process|VAL-010" README.md docs/token-aware-guardrail-kernel-process-and-agents.md apm-packages/codex-first-ai-development-process/docs`; `strict` が非対応としてのみ記載されていること、Copilot fallback が対象外としてのみ記載されていることを目視確認する。 |
| Dependencies | All prior slices |
| Completion criteria | 公開 docs と package docs が、実装済み挙動を一貫して説明している。Copilot fallback の対象外境界も明確である。 |
| Rollback | docs だけを revert する。core implementation は残るが、公向け説明は以前の wording に戻る。 |

## FR Traceability Matrix

| FR | 要件要約 | 対応する slice |
| --- | --- | --- |
| FR-001 | `documentation_level: lite / standard` を router / skill / docs に導入する | SL-003, SL-004, SL-007, SL-017 |
| FR-002 | `strict` を選択肢として追加しない | SL-003, SL-004, SL-016, SL-017 |
| FR-003 | `full-coverage` を route として維持し、documentation level にしない | SL-003, SL-004, SL-017 |
| FR-004 | Plan Coverage Lite artifact format を定義する | SL-005 |
| FR-005 | lite でも source of truth、FR / AC coverage、residual classification を要求する | SL-005, SL-006, SL-007 |
| FR-006 | Inline Ready Gate を implementation-handoff-review 代替として定義する | SL-006, SL-007 |
| FR-007 | Behavior Spec を inline sketch から separate artifact へ escalate する | SL-008 |
| FR-008 | canonical coverage ledger と delta update を導入する | SL-009 |
| FR-009 | coverage-gap-triage の発火条件を定義する | SL-010 |
| FR-010 | simple gap に対する direct FixNow selector を許可する | SL-010 |
| FR-011 | implementation-contract-kernel と review-kernel の責務を統合する | SL-011, SL-012 |
| FR-012 | unified implementation-contract に self-check verdict を追加する | SL-011 |
| FR-013 | old review kernel の compatibility 挙動を決める | SL-012 |
| FR-014 | common instruction file を agent と一緒に配布する | SL-001, SL-002 |
| FR-015 | agent の重複 boilerplate を common instruction 参照へ移す | SL-013, SL-014 |
| FR-016 | agent 固有の verdict vocabulary / stop condition を agent file に残す | SL-001, SL-013, SL-014 |
| FR-017 | codex-first-state を core と audit に分割する | SL-015 |
| FR-018 | validation sample を追加する | SL-016 |

## AC Coverage Matrix

| AC | Acceptance criteria 要約 | 対応する slice | Validation evidence |
| --- | --- | --- | --- |
| AC-001 | `documentation_level` は `lite` / `standard` のみで、`strict` は存在しない | SL-003, SL-004, SL-016, SL-017 | `rg` による enum / wording scan と negative scan |
| AC-002 | router / skill が task weight と risk から lite / standard を自動選択する | SL-003, SL-004, SL-016 | Router sample VAL-001 から VAL-006 |
| AC-003 | `full-coverage` が selected_process / route であり documentation level ではない | SL-003, SL-004, SL-017 | `rg` と docs review |
| AC-004 | Lite route の標準構造が documented / templated されている | SL-005 | Lite template section scan |
| AC-005 | Lite でも Plan source of truth、FR / AC coverage、residual / human decision classification を維持する | SL-005, SL-006, SL-007, SL-016 | Lite template、profile agent wording、VAL-002 |
| AC-006 | Inline Ready Gate の等価条件が documented されている | SL-006, SL-007 | Inline gate table scan と profile agent scan |
| AC-007 | Inline behavior sketch と separate Behavior Spec への escalation 条件が documented されている | SL-008 | Behavior escalation scan |
| AC-008 | canonical coverage ledger、delta format、読み方、close 時の扱いが documented されている | SL-009 | Ledger template、implementation-execution、gap-resolution、verification / residual agent 参照 |
| AC-009 | coverage-gap-triage の実行条件 / 省略条件が documented されている | SL-010 | Gap triage condition scan |
| AC-010 | simple gap で direct FixNow selector を出せる | SL-010 | VAL-008 と agent wording |
| AC-011 | `implementation-contract-kernel.agent.md` が contract と self-check verdict を 1 つの artifact として出せる | SL-011 | Required output structure scan |
| AC-012 | unified implementation-contract の verdict vocabulary が定義されている | SL-011 | Verdict vocabulary scan |
| AC-013 | review-kernel の扱いが deprecated alias / shim / removed のいずれかで明記され、参照を壊さない | SL-012, SL-016 | Review-kernel と参照の scan、通常推奨が残らない negative scan |
| AC-014 | common instruction file が docs runtime dependency を作らずに agent と同梱される | SL-001, SL-002, SL-017 | Manifest dependency scan、profile TOML が存在しない shared file を参照しないことの scan |
| AC-015 | Embedded policy / status vocabulary / Handoff Packet boilerplate の重複が減っている | SL-013, SL-014 | Agent diff review と shared reference scan |
| AC-016 | agent 固有の verdict vocabulary / output path / stop condition が agent 側に残る | SL-013, SL-014 | Agent-specific section の手動確認 |
| AC-017 | codex-first-state の core / audit 分割が template / docs / skill に反映されている | SL-015 | Template と docs の scan |
| AC-018 | VAL-001 から VAL-010 が validation suite に追加または反映されている | SL-016 | Validation ID scan |
| AC-019 | lite が現行 standard より読む / 作る artifact または section を減らせることが validation で示される | SL-016 | VAL-002 の artifact count / section count |
| AC-020 | source-of-truth、no fake-only completion、residual explicit decision の invariant が維持されている | SL-001, SL-005, SL-009, SL-014, SL-017 | Shared instruction と docs scan |

## User Requirement Traceability

| UR | 要件要約 | 対応する slice |
| --- | --- | --- |
| UR-001 | 実装漏れや要素同士の断絶を防ぐ | SL-005, SL-006, SL-007, SL-009, SL-012, SL-014 |
| UR-002 | 自走しすぎによる token 消費を防ぐ | SL-003, SL-004, SL-005, SL-010, SL-015 |
| UR-003 | 別 AI / 別 thread でも docs を根拠に継続できる | SL-001, SL-002, SL-005, SL-009, SL-015, SL-017 |
| UR-004 | Plan を最後まで source of truth として保つ | SL-001, SL-005, SL-009, SL-014, SL-017 |
| UR-005 | stub test だけでなく production implementation まで確認する | SL-001, SL-011, SL-014 |
| UR-006 | residual を個別に判断可能にする | SL-005, SL-009, SL-010, SL-014 |
| UR-007 | 別 AI / lower-cost model への分担を支える | SL-004, SL-007, SL-015, SL-016 |
| UR-008 | 過剰な artifact / token 消費を減らす | SL-005, SL-009, SL-010, SL-015, SL-016 |
| UR-009 | 段階を lite / standard の 2 段階にする | SL-003, SL-004, SL-007, SL-017 |
| UR-010 | strict を作らない | SL-003, SL-004, SL-016, SL-017 |
| UR-011 | full-coverage と level 分類の衝突を避ける | SL-003, SL-004, SL-017 |
| UR-012 | 薄い隣接 kernel を統合する | SL-011, SL-012 |
| UR-013 | 共有 boilerplate を bundled common instruction へ移す | SL-001, SL-002, SL-013, SL-014 |

## NFR Traceability

| NFR | 要件要約 | 対応する slice |
| --- | --- | --- |
| NFR-001 | Token-aware: 軽い作業で読む / 生成する artifact を減らす | SL-005, SL-009, SL-010, SL-015, SL-016 |
| NFR-002 | Traceable: FR / AC / Behavior Case / residual を追跡可能に保つ | SL-005, SL-008, SL-009, SL-014 |
| NFR-003 | Portable: consuming repo に `docs/` runtime dependency を持ち込まない | SL-001, SL-002, SL-013, SL-014 |
| NFR-004 | readiness / human decision / residual issue で fail-closed する | SL-006, SL-007, SL-008, SL-010, SL-014, SL-015 |
| NFR-005 | backward-compatible に移行する | SL-007, SL-012, SL-015, SL-017 |
| NFR-006 | policy / vocabulary の重複を減らして保守しやすくする | SL-001, SL-002, SL-013, SL-014 |
| NFR-007 | full-coverage / standard / lite の責務を混同しない | SL-003, SL-004, SL-017 |

## Decision Traceability

| Decision | 要約 | 対応する slice |
| --- | --- | --- |
| DEC-001 | documentation level は lite / standard のみ | SL-003, SL-004, SL-017 |
| DEC-002 | full-coverage は documentation level ではなく route | SL-003, SL-004, SL-017 |
| DEC-003 | lite route を追加する | SL-005, SL-006, SL-007, SL-008 |
| DEC-004 | standard route を guardrail を保ったまま圧縮する | SL-009, SL-010, SL-011, SL-012, SL-013, SL-014 |
| DEC-005 | Inline Ready Gate で独立 handoff review を置き換え可能にする | SL-006, SL-007 |
| DEC-006 | Behavior Spec を inline sketch から separate artifact へ上げる | SL-008 |
| DEC-007 | canonical coverage ledger と delta を導入する | SL-009 |
| DEC-008 | coverage-gap-triage を条件付きにする | SL-010 |
| DEC-009 | implementation contract と review kernel を統合する | SL-011, SL-012 |
| DEC-010 | 共通 boilerplate を bundled instruction へ抽出する | SL-001, SL-002, SL-013, SL-014 |
| DEC-011 | state を core と audit に分割する | SL-015 |
| DEC-012 | validation sample を追加する | SL-016 |
| DEC-013 | Codex-first profile agents も lite / standard 互換対象にする | SL-007 |
| DEC-014 | Copilot fallback は Issue #38 の対象外とする | SL-017 |

## Review Comment Traceability

| Review item | 対応方針 | 対応する slice |
| --- | --- | --- |
| Codex profile agent TOML が target files から漏れている | profile `AGENTS.md` / `standard-implementer.toml` / `standard-verifier.toml` を対象化し、必要な TOML も追従する | SL-007 |
| Lite artifact を実装 / 検証 agent が消費する導線が薄い | `implementation-execution.agent.md` を Lite artifact / Inline Ready Gate / canonical ledger の対象に入れる | SL-005, SL-006, SL-009 |
| canonical coverage ledger の影響範囲が不足している | `coverage-gap-resolution-slice.agent.md` を canonical ledger / delta の対象に入れる | SL-009 |
| implementation-contract-review-kernel 統合後の参照更新が不足しそう | gap-resolution / gap-triage / execution の旧 review-kernel 参照を explicit fallback に限定する | SL-012, SL-016 |
| shared instruction の配布経路が APM と local installer で割れそう | shared instruction は APM / `.github/agents` 用とし、profile TOML は直接参照しない方針を固定する | SL-002, SL-007 |
| Copilot fallback を対象外か追従対象か明記する | Issue #38 では対象外とし、必要なら後続 issue で移植する | SL-017 |
| 旧前提が残っていないことの検証が必要 | final verification に negative scan を追加する | SL-016 |

## Rollback Policy

1. 各 slice は別 commit、または独立レビュー可能な PR section として実装する。
2. Rollback は dependency の逆順で行う。たとえば agent が shared instruction を参照し始めた後なら、SL-001 より先に SL-014 と SL-013 を revert する。
3. すべての参照が更新される前に compatibility shim を外さない。SL-012 は、もし削除方針を取るなら最後に old review-kernel behavior を外す箇所とする。
4. documentation-only slice の rollback は file-level の revert とする。
5. template / installer slice では rollback 後に dry-run / check-only validation を実行し、target repo bootstrap の整合を確認する。
6. 後半の slice が前半の slice の設計問題を露出させた場合でも、無関係な責務をその場で混ぜて直さず、corrective slice を新しく作る。
7. このレビュー反映作業自体の rollback は、`plans/issue-38-lite-standard-implementation-plan.md` の変更だけを revert する。

## 最終検証計画

最後の implementation slice の後に、次の check を実行する:

```powershell
git diff --check
rg -n "FR-00[1-9]|FR-01[0-8]|AC-00[1-9]|AC-01[0-9]|AC-020" plans/issue-38-lite-standard-implementation-plan.md
rg -n "documentation_level|lite|standard|strict|full-coverage" README.md docs apm-packages .github
rg -n "VAL-001|VAL-002|VAL-003|VAL-004|VAL-005|VAL-006|VAL-007|VAL-008|VAL-009|VAL-010" apm-packages/codex-first-ai-development-process/docs/examples
rg -n "standard-implementer.toml|standard-verifier.toml|implementation-execution.agent.md|coverage-gap-resolution-slice.agent.md|copilot-fallback-ai-development-process|plan-coverage-shared.instructions.md" plans/issue-38-lite-standard-implementation-plan.md
dotnet run --file apm-packages/codex-first-ai-development-process/scripts/install-codex-first-local.cs -- . --dry-run
dotnet run --file scripts/setup-work-repo-agents.cs -- . --dry-run
```

旧前提が残っていないことを確認するため、次の negative scan も実行する:

```powershell
rg -n "documentation_level.*strict|strict.*documentation_level" .github apm-packages docs README.md
rg -n "Require.*implementation-handoff-review|implementation-handoff-review.*before editing" apm-packages/codex-first-ai-development-process/profiles .github/agents
rg -n "implementation-contract-review-kernel" .github apm-packages docs README.md
rg -n "plan-coverage-shared.instructions.md" .github apm-packages
```

ローカル環境に互換 .NET SDK がない場合は、その exact error を添えて未検証として記録し、`rg` と `git diff --check` の evidence は維持する。
