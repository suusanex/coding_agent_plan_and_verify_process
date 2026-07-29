# Plan Kernel

## 目的

通常のCodex作業を依頼するだけで親作業の完了または停止をリンク付き通知から把握し、初回実装後は同じ親スレッド内の短い操作から独立レビュー、修正、目的再レビューを完結できるようにする。固定した二つのトップレベルスレッド間でthread ID、artifact path、result reference、review findingを人間が運ぶ既存運用は、MVPの通常経路から外す。

## 非目標

- 相談、Issue作成、実装、レビュー、修正を人間の開始判断なしにすべて自動進行する巨大なprocessは作らない。
- 通知履歴の永続タイムラインはMVPへ含めない。
- 複数トップレベル実装スレッド、長期中断、任意回数の復旧、複雑なbranch分岐を自動制御しない。
- Adaptive Implementation Executionを同一親スレッドの修正ownerへ差し替える機能は今回実装しない。ただし後続拡張を妨げる結合は避ける。
- GitHub Copilot reviewとCodex code reviewを第2round以降に再実行しない。
- Goal Contextを複数段階の承認workflowまたは利用者向け厳格state machineとして扱わない。
- APMからCodex Pluginへの配布移行は行わない。

## 機能要件

- `FR-001` user-level Codex `notify` callbackを一度導入すると、Decorator Skillや通知専用文言がない通常のCodex親作業でも、完了または停止時に通知対象となる。
- `FR-002` 一般的な通知は発火元Codex threadへのdirect linkを持ち、利用者が通知を選択して元作業へ戻れる。PRや結果URIを安全に特定できる場合は、thread linkを失わず追加導線として提示する。
- `FR-003` callback、provider、既存notify chain、log、重複抑止の失敗は、完了したCodex turnの結果を失敗へ変えない。
- `FR-004` subagent完了がcallback対象になるかを実環境で判定し、親作業以外の不要な通知が大量発生しないことを確認する。公開されているcallback payloadだけで親／subagentを識別できない場合は、未検証のfilterを実装済み扱いせず、MVPの観測結果と制約を明記する。
- `FR-005` 初回実装を行った同じ親スレッドから、一つの短い操作でGoal Context対応review/remediation flowを開始できる。利用者へreview thread ID、implementation thread ID、review-plan path、hash、JSON、result referenceの入力を要求しない。
- `FR-006` round 1は、Ready PRのGitHub Copilot review結果、独立したread-only Codex code reviewer、独立したread-only Goal Context purpose reviewerの結果を収集・保持し、親agentが同じスレッドの実装contextを使ってactionable findingを修正する。
- `FR-007` 修正後のround 2以降は、独立したread-only purpose reviewerだけを新しい実装結果へ再実行し、最大3roundまで同じ親スレッド内で修正と目的再reviewを反復する。
- `FR-008` findingが解消した場合は完了し、最大round到達、Goal Contextから自動決定できないproduct判断、必須入力欠落、外部review取得不能、または安全に修正できない状態では人間判断またはblockedとして停止する。
- `FR-009` terminal状態では再び通知し、同じ親threadと、存在する場合は対象PRまたはreview結果を直接開ける。
- `FR-010` reviewerの独立性は、実装担当とは別のsubagent thread、read-only権限、PR差分とGoal Contextの直接参照、reviewer生出力の保持によって成立させ、親agentの自己評価だけでpurpose completionを判定しない。
- `FR-011` 新しい通常経路と矛盾する既存の固定二task manual handoff、Decorator明示要求、利用者向けcycle管理契約を、現行利用者向けSkill、README、package metadata、validator、fixtureから除去または明確にlegacy扱いする。
- `FR-012` 通知runtimeとreview/remediation flowは既存のAPM配布経路で導入・更新・検証でき、人が実行するinstall、check、開始操作、停止時対応をREADMEまたはpackage docsから確認できる。

## 受け入れ条件

- `AC-001` 通知用Skill markerも`completion-notification` envelopeも含まない通常の`agent-turn-complete` callback fixtureが通知eventを生成し、`codex://threads/<thread-id>`を保持する。
- `AC-002` validな具体的HTTPS result URIがある通知はresultとthreadの両導線を持ち、result URIがない通知もthread導線を持つ。危険または抽象的なURIはresult導線として採用されない。
- `AC-003` 同じcallbackの再送は一意に抑止され、providerまたはchained notifyの失敗時もruntimeはCodex側へ非zeroを返さない。
- `AC-004` cleanな一時Codex homeへのinstall、update、checkで常時通知設定が再現され、既存notifyは自己再帰なしに保持される。
- `AC-005` 実機smokeにより、通常の親作業のterminal通知、thread direct link、result direct link、およびsubagent実行時の通知件数・対象が記録される。subagent判定はstatic fixtureだけで完了扱いしない。
- `AC-006` 利用者向け開始例は同じ親スレッド内の短い一操作であり、別トップレベルreview taskの作成・探索やID/path/hash/JSONの転記を含まない。
- `AC-007` round 1 fixtureまたはreal smokeで、GitHub Copilot review、read-only code reviewer、read-only purpose reviewerが互いに識別できる生出力を返し、親agentがactionable findingを修正・検証する。
- `AC-008` round 2以降のfixtureではcode reviewerとGitHub Copilot waitを再実行せず、purpose reviewerだけを新しいheadへ実行する。
- `AC-009` purpose findingが解消する経路は3round以内にcompleteし、残存finding、human decision、必須入力欠落、review取得不能の各経路は修正継続またはterminal stopへ一意に遷移する。
- `AC-010` 各reviewer subagentはproduction fileへのwriteを行わず、親agentだけが修正write ownerであることをagent contractと検証fixtureが示す。
- `AC-011` terminal出力から通知runtimeが親thread linkと任意のPR/result linkを生成でき、通常作業では通知Decorator指定を要求しない。
- `AC-012` package install smoke、static validator、File-based App publish、deterministic positive/negative fixtureが成功し、fake-only evidenceだけではclose-readyと判定されない。
- `AC-013` root READMEとpackage docsが、install/check、通常通知、同一親スレッドのreview開始、3round上限、人手停止条件、既存固定二task方式からの移行を説明する。

## Black-box behavior coverage

- Expansion required: Yes
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- Plan readiness: ReadyForRiskTriage
- Expansion decision reason: 常時通知のtargeting・dedup・provider failure・subagent挙動と、初回full review／後続purpose-only review／最大round／human decision／blockedという複数の履歴依存ケースがある。negative expectationも目的達成の中心であり、inline sketchではFR / AC traceabilityを安全に保持できない。
- Blocking requirement-elaboration items: なし。`URE-001`は期待behaviorではなく実環境で確認する実装実現性・verification項目として残す。

### Case-to-Plan mapping

| Case ID | Source IDs | FR / AC | Disposition | Notes |
| --- | --- | --- | --- | --- |
| `NTF-001` | `SRC-NOTIFY-001`, `SRC-NOTIFY-002`, `SRC-NOTIFY-005` | `FR-001`, `FR-002` / `AC-001` | MappedToPlan | 通常親作業の常時thread通知。 |
| `NTF-002` | `SRC-NOTIFY-001`, `SRC-NOTIFY-002`, `SRC-REVIEW-007` | `FR-001`, `FR-002` / `AC-001`, `AC-005` | MappedToPlan | stop状態も通知対象。 |
| `NTF-003` | `SRC-NOTIFY-002`, `SRC-NOTIFY-003` | `FR-002` / `AC-002` | MappedToPlan | resultとthreadの両導線。 |
| `NTF-004` | `SRC-NOTIFY-002`, `SRC-NOTIFY-003` | `FR-002` / `AC-002` | MappedToPlan | invalid result時もthread通知を維持。 |
| `NTF-005` | `SRC-NOTIFY-004` | `FR-004` / `AC-005` | MappedToPlan | parent-centric notificationを実機確認する。 |
| `NTF-006` | `SRC-NOTIFY-006` | `FR-003` / `AC-003` | MappedToPlan | callback replayの重複抑止。 |
| `NTF-007` | `SRC-NOTIFY-006` | `FR-003` / `AC-003` | MappedToPlan | provider / chain失敗のfail-open。 |
| `NTF-008` | `SRC-NOTIFY-005`, `SRC-NOTIFY-006` | `FR-001`, `FR-012` / `AC-004`, `AC-013` | MappedToPlan | 一度のAPM導入と既存notify保持。 |
| `REV-001` | `SRC-REVIEW-001`, `SRC-REVIEW-008` | `FR-005` / `AC-006` | MappedToPlan | same-parent one-operation intake。 |
| `REV-002` | `SRC-REVIEW-002`, `SRC-REVIEW-003` | `FR-006`, `FR-010` / `AC-007`, `AC-010` | MappedToPlan | round 1の三系統review。 |
| `REV-003` | `SRC-REVIEW-003`, `SRC-REVIEW-004` | `FR-010` / `AC-010` | MappedToPlan | reviewer read-only、親agent write owner。 |
| `REV-004` | `SRC-REVIEW-002`, `SRC-REVIEW-004`, `SRC-REVIEW-006` | `FR-006`, `FR-007` / `AC-007`, `AC-009` | MappedToPlan | actionable findingの修正と新head再review。 |
| `REV-005` | `SRC-REVIEW-005`, `SRC-REVIEW-006` | `FR-007` / `AC-008` | MappedToPlan | round 2以降purpose-only。 |
| `REV-006` | `SRC-REVIEW-005`, `SRC-REVIEW-006`, `SRC-REVIEW-009` | `FR-007`, `FR-009` / `AC-009`, `AC-011` | MappedToPlan | 3round以内のcloseと通知。 |
| `REV-007` | `SRC-REVIEW-006`, `SRC-REVIEW-007`, `SRC-REVIEW-009` | `FR-008`, `FR-009` / `AC-009`, `AC-011` | MappedToPlan | round 3残存時のhuman stop。 |
| `REV-008` | `SRC-REVIEW-007`, `SRC-SCOPE-003` | `FR-008` / `AC-009` | MappedToPlan | product decisionを推測しない。 |
| `REV-009` | `SRC-REVIEW-001`, `SRC-REVIEW-002`, `SRC-REVIEW-007` | `FR-008` / `AC-009` | MappedToPlan | 必須入力不備のblocked stop。 |
| `REV-010` | `SRC-REVIEW-002`, `SRC-REVIEW-007` | `FR-006`, `FR-008` / `AC-007`, `AC-009` | MappedToPlan | 必須reviewer欠落を完了扱いしない。 |
| `REV-011` | `SRC-REVIEW-004`, `SRC-REVIEW-005`, `SRC-REVIEW-006` | `FR-007`, `FR-008` / `AC-009` | MappedToPlan | findingの解消・残存を区別する。 |
| `REV-012` | `SRC-REVIEW-008`, `SRC-SCOPE-003` | `FR-005`, `FR-011` / `AC-006`, `AC-013` | MappedToPlan | 利用者へ内部state管理を課さない。 |
| `REV-013` | `SRC-REVIEW-009` | `FR-009` / `AC-011` | MappedToPlan | terminal通知のthread / PR導線。 |
| `SCP-001` | `SRC-SCOPE-001` | 非目標 / 今回の対象外 | OutOfScopeWithSource | 複雑・長期・multi-top-level運用はMVP外。 |
| `SCP-002` | `SRC-SCOPE-002` | 非目標 / 今回の対象外 | DeferredWithSource | timelineとAdaptive executor対応は後続課題。 |
| `SCP-003` | `SRC-SCOPE-002` | `FR-012` / `AC-004`, `AC-012` | OutOfScopeWithSource | APMを継続しPlugin移行はしない。 |

## 影響コンポーネント / モジュール

変更候補:

- `scripts/codex-notification-runtime/`: callback分類、event生成、provider invocation、install/check、fixture、実機検証記録。
- `apm-packages/pr-review-remediation/`: 同一親スレッドreview/remediation orchestration、read-only reviewer profile、配布manifest、validator、fixture、利用方法。
- `README.md`: 常時通知と同一親スレッドreview/remediationの標準操作。
- `.github/workflows/`と関連validator entrypoint: package/runtime contractのCI検証。

再利用または参照候補:

- `.github/agents/local-reviewer.agent.md`、`.github/agents/purpose-reviewer.agent.md`: reviewer責務と出力契約。
- `apm-packages/goal-context-authoring/`: Goal Contextの選択・検証契約。ただし利用者向け多段承認を新review flowへ持ち込まない。
- GitHub review context collector: Ready PR、patch、review/comment/check取得。固定Review Thread identity管理は再利用対象にしない。
- `apm-packages/completion-notification-decorator/`: 互換性・移行判断の参照元。通常通知の必須依存にはしない。

## 実装スコープ

- 通常callbackをterminal通知へ変換するuser-level notification runtime契約へ更新する。
- 常時通知runtimeのinstaller、validator、fixtures、manual smoke手順を更新する。
- 同じ親スレッドからreviewer subagentsを起動し、親agentが修正し、purpose-only再reviewするbounded SkillをAPM package内に実装する。
- 既存collectorとreviewerを必要最小限再利用し、固定二task cycle manager中心の利用者契約を新しい通常経路から外す。
- APM manifest、同期helper、README、tests、CI検証を新しい契約に合わせる。

## 既知の high-risk boundaries

| Risk trigger | Present / Absent / Unclear | 概要 |
| --- | --- | --- |
| Cross-process or cross-service sequence | Present | Codex callback、notification runtime、Windows provider、GitHub CLI/API、reviewer subagentsが連携する。 |
| Queue / event / webhook / background worker | Present | `agent-turn-complete` callbackを外部processで受け、通知providerへ配送する。 |
| External API or SDK | Present | Codex callback contract、Windows App SDK、GitHub review取得を使用する。 |
| Authentication or authorization | Present | GitHub review取得とread-only reviewer権限境界がある。 |
| Durable state / retry / replay / idempotency | Present | callback dedupと最大3roundのreview履歴がある。 |
| Startup wiring / DI / configuration | Present | user-level `notify`設定、installer、APM導入後のagent profile同期がある。 |
| Production implementation split from test substitute | Present | fake GitHub fixture、notification fake providerと実runtime/provider/remote reviewが分離する。 |
| Multiple runtime participants coordinating state | Present | 親agent、複数read-only reviewer、GitHub、notification processesが協調する。 |
| Observable behavior spanning more than one component | Present | terminal verdictから通知、deep link、review、修正、再reviewまで複数componentをまたぐ。 |

詳細なcontract selectionとslice routeは`change-risk-triage.agent.md`へ委ねる。

## 今回の対象外

- 通知履歴dashboard、Slack/ntfy等の追加provider、モバイルpush。
- Codex App本体のUI変更または非公開APIへの依存。
- Adaptive Implementation Execution対応の修正executor差し替え。
- 複数トップレベルthread間の自動通信、復旧可能な汎用workflow engine。
- GitHub Copilot review自体の品質改善、Goal Context authoring contractの全面再設計。
- sourceを根拠にしない既存historical `plans/**`の書き換え。

## change-risk-triage への引き継ぎ

- 親Plan source of truthは本artifact、要求sourceは`docs/goal-context-multi-project-ai-development-notification-and-handoff-reduction.md`である。
- notification runtimeの常時targeting、callback payload限界、provider fail-open、dedup、user config導入をruntime / implementation contract候補として確認する。
- same-parent orchestration、read-only reviewer isolation、GitHub review取得、round transition、write ownershipをruntime / implementation contract候補として確認する。
- notification、review orchestration、package/docs/validationが強く相互接続しているため、`full-coverage`の要否を判定する。
- fake-only fixtureをproduction notificationまたは実reviewer orchestrationの完了根拠にしない。

## 実装実現性の残留事項

| Residual ID | 項目 | Status | 次の確認 |
| --- | --- | --- | --- |
| IR-001 | 公開Codex `notify` payloadに親／subagent識別fieldがあるか | Unclear | 現行公式manualでは共通fieldに識別子がなく、実機smokeで発火範囲を確認する。 |
| IR-002 | 同じ親スレッドからGitHub Copilot reviewを起動・待機する既存collector address | Unclear | 既存`collect-pr-review-context.cs`とSkill contractをimplementation-contractで確認する。 |
| IR-003 | reviewer subagentをread-onlyで起動するprofileと親agentへの結果返却contract | Unclear | 既存TOML、agent prompt、Codex subagent capabilityをimplementation-contractで確認する。 |
| IR-004 | 固定二task cycle managerの削除、縮退、legacy維持境界 | Unclear | current package consumerとvalidator surfaceをarchitecture / slice analysisで分類する。 |
| IR-005 | terminal result metadataを通常turnからnotification runtimeへ渡す方法 | Unclear | base notificationとenhanced notificationを分け、外部schema依存をruntime-contractで選択する。 |

## Handoff Packet

- Profile used: plan-kernel
- Plan artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-plan.md`
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- Source artifacts: `docs/goal-context-multi-project-ai-development-notification-and-handoff-reduction.md`、`docs/goal-context-multi-project-ai-development-notification-and-purpose-review.md`、`plans/issue-61-goal-context-multi-round-review-cycle-plan.md`、`plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`、現行Codex ManualのNotifications / Subagents節。
- Selected contracts / IDs: このエージェントでは選択しない。最終選択は change-risk-triage が行う
- Implementation-realization residuals: `IR-001`〜`IR-005`はUnclear。behavior expansion後にtriageで分類する。
- Files inspected: 上記source artifacts、`README.md`のnotification / PR review節、`scripts/codex-notification-runtime/decision-record.md`、notification runtime 3本のsymbol一覧、`apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/SKILL.md`、`apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md`、`manage-review-cycle.cs`のthread / round / verdict surface、`apm-packages/pr-review-remediation/apm.yml`。
- Files intentionally not inspected: notification/reviewに無関係なAPM package、全historical plan、validator全行、fixture本文、CI log、GitHub live PR/Issue。
- Decisions made: `implementation_route: adaptive`、`implementation_route_source: default`、`documentation_level: standard`。separate Black-box Behavior Specが必要。既存固定二task方式は新しい通常経路のauthorityにしない。
- Do not redo unless new evidence appears: Goal Contextが拒否したDecorator必須、固定二task手動handoff、各roundのcode review再実行、Plugin移行を実装案へ戻さない。公開Codex manualのcallback共通fieldには親／subagent識別fieldが記載されていない。
- Remaining work: `Blocking`: なし。`DeferredWithReason`: notification timelineとAdaptive executor対応はGoal Contextの非MVP。`Consumed`: behavior expansion、Case-to-Plan mapping、APM配布、親agent write ownership、code reviewはround 1のみというproduct境界。
- Recommended next step: 本Plan、Black-box Behavior Spec、Goal Contextを入力として`change-risk-triage.agent.md`を実行し、runtime / implementation-realization riskとprocess profileを確定する。
