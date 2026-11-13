# Design Pair Implementation Execution

利用者が明示的に選択した場合だけ、実装前に既存codeに基づく判断資料を提示し、人間が明示的に確定した `Locked Decisions` を Adaptive Implementation へ渡す APM package です。論点は独立して判断・委任できる問いを単位とし、1ファイル＝1IDにはしません。

通常経路は `adaptive-implementation-execution` です。この package は課題の難易度、risk、規模から Design Pair を自動選択、推奨、提案しません。

## Flow

```text
ordinary Plan / Implementation Intent
  -> design-pair-implementation-execution [explicit selection only]
  -> bounded Target Map presentation
  -> AWAITING_USER_INPUT / target-selection [mandatory turn stop]
  -> direct questions / decisions / explicit skips
  -> AWAITING_USER_INPUT / disposition-confirmation [when needed]
  -> tracked Design Pair handoff / READY_FOR_ADAPTIVE_IMPLEMENTATION
  -> adaptive-implementation-execution
       -> decision-surface-implementation-owner
       -> human structure review stop -> approved bounded-residual-implementation-owner
       -> decision-surface-implementation-owner on re-entry
```

Plan Coverage Flow では `implementation-handoff-review` または同等の Inline Ready Gate が implementation を許可した後に Design Pair を開始します。parent state は interaction stage と tracked handoff path を保持し、waiting 中に Adaptive / verification へ進みません。Design Pair は upstream guardrails、Adaptive orchestration、verification、residual decision を置き換えません。

## Package contents

| Content | Path |
| --- | --- |
| Design Pair orchestration skill | `.apm/skills/design-pair-implementation-execution/SKILL.md` |
| Target Map reference | skill の `map.md` |
| Tracked handoff reference | skill の `handoff.md` |
| Usage guide | `docs/usage-guide.md` |
| Validation scenarios | `docs/examples/design-pair-validation.md` |
| Real-model multi-turn smoke fixture | `tests/manual-model-smoke/` |
| Static validator | `scripts/validate.ps1` |

Adaptive Implementation の decision-surface-implementation-owner / bounded-residual-implementation-owner orchestration と portable agent 定義は、この package へ複製しません。manifest dependency で既存 `adaptive-implementation-execution` skill と canonical agents を導入します。

## Fresh install

Design Pair は Adaptive Implementation の前段です。正式 target は `copilot`、`codex`、`agent-skills` です。Design Pair package単体のinstallだけでは、後段の子bounded-residual-implementation-ownerのconcrete model mappingが完成した証拠になりません。

### GitHub Copilot CLI

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,agent-skills
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target copilot,agent-skills
```

配置後の確認:

- `.agents/skills/design-pair-implementation-execution/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/SKILL.md`
- `.github/agents/decision-surface-implementation-owner.agent.md`
- `.github/agents/bounded-residual-implementation-owner.agent.md`

GitHub Copilot CLI ではDesign Pair READY後も現在の親sessionがAdaptive Skillとcanonical親契約を読み、選択済みmodelで構造を作ります。別の上位agentを起動しません。tracked handoffをdurable authorityとしてrouteとLocked Decisionsを保持し、構造コードの提示後AWAITING_STRUCTURE_REVIEWでそのturnを終了します。Design Pair応答を構造承認には流用しません。正式 acceptance は GitHub Copilot CLIであり、実model証拠はtests/manual-model-smokeを参照します。

**Issue #69 / #86 境界:** ordinary Plan + explicit Design Pair + Adaptive handoff は本 package の Copilot formal support です。Plan Coverage parent からの Design Pair runtime E2E は #86 の資格認定範囲です。

### Codex

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target codex,agent-skills
```

APM が管理対象agentの旧本文を残す、または concrete model / reasoning / sandbox を持たない custom agent TOML を生成する環境では、導入済みmoduleの共通 finalizer で `decision-surface-implementation-owner` と `bounded-residual-implementation-owner` をcanonical定義へ同期します。子だけがCodex profileを持ちます。同名TOMLの独自編集は上書きされます。

```powershell
dotnet run --file .\apm_modules\suusanex\coding_agent_plan_and_verify_process\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs -- .
```

Copilot-only導入ではCodex profileが不要なため、finalizerの実行も不要です。`--dry-run`、`--check`、`--force`の保守手順は Adaptive package の `docs/install-guide.md` を参照してください。

通常 Plan Mode 後の起動例:

```text
$design-pair-implementation-execution を明示的に選びます。
直前の Plan の予定変更面を調査し、問い・判断材料・選択肢の違い・不明点を資料にしてください。
資料を読んで質問・確定・スキップを回答します。
対話で disposition が確定した後に Adaptive Implementation へ進んでください。
```

利用者が毎回「停止してください」と補足する必要はありません。最初の依頼が単に「実装してください」であっても、Skill は Target Map を提示し、`AWAITING_USER_INPUT / target-selection` を保存してその turn を終了します。Target Map 提示前の Plan / Issue / gold document や利用者の技術案は upstream constraint / initial position であり、Design Pair Locked Decision ではありません。

初回資料は原則としてtracked handoff内に保存します。各論点は問い・必要性→調査済み事実と制約→実在する選択肢の違い→根拠付きの非binding proposalまたはNo proposal理由→不明点・検証期待を説明し、具体的file / symbolや関連構造へ辿れる形にします。初回から全詳細設計を行う要求ではありません。会話は資料への導線と判断入口の要約を示し、資料の全文再掲は要求しません。リンクやIDと論点名だけでは提示になりません。

初回後は「A案ではこの既存制約を満たせないのでは？」「DP-T01はA案で確定」「DP-T02は議論をスキップ」「残りはスキップ」「全部スキップ」と直接応答できます。スキップは判断をAdaptiveへ委ねる `Adaptive-Owned` であり、実装省略や `No-Change` ではありません。対象とpost-map user evidenceを記録し、未指示Targetはpendingのままです。既存Locked等も含む全件スキップでは、その撤回まで意図するか不明なら確認します。

利用者の応答は親フローや検証harnessで補完しません。Target IDのみでも受理し、初期案や同じ選択を再要求せず、資料の判断上の違いを短く示して `AWAITING_USER_INPUT / disposition-confirmation` で最終判断を待ちます。直接質問は必要な根拠と差分だけで回答します。初回資料を踏まえた明示的確定には儀礼的な再説明turnを挟みません。

既知の根拠を再利用し、新案・情報不足・関連code / upstream変更時だけ追加調査します。対話中は該当論点の質問・回答・判断・証拠と必須進行状態を差分更新し、派生summary集合・ReadinessはPendingに保ちます。完了時にまとめて全照合して `Finalization status: Validated` とし、新規sessionも正本の資料・row・証拠から再開します。古いPASSや未確認の資料変更をREADYに流用できません。

READY前にはTarget Mapとhandoff summaryを集合照合します。summaryの全Target IDはMapに実在し、Selected / Delegated-to-Adaptive / No-Change / Upstream-Decision-Required / Pendingの5集合は重複なくMap全体を覆い、各分類はrowのDispositionと一致する必要があります。Locked DecisionはSelectedかつ`Locked` rowだけを参照できます。all-AdaptiveではSelected / Pendingを`None`、Locked Decisionsなし、全Targetを`Adaptive-Owned`としてdelegated集合へ含めます。

`Locked`、`Discussed-Unlocked`、`Adaptive-Owned`の各Targetには、Target Map提示後のactual user turnと確認内容を記録する`Target Disposition Evidence`が一件必要です。複数Target委任とall-Adaptiveは同じturn referenceを各Target rowで再利用できますが、AIの推奨やsummaryから人間のDispositionを補完できません。

Plan Coverage Flow で使う場合は、この package と Plan Coverage package の両方を `copilot` / `codex` / `agent-skills` target へ導入し、flow 開始時に Design Pair を明示選択します。`plan-coverage-residual-flow` 選択と Design Pair implementation route 選択は別々の explicit evidence として保持します。

## Validation

```powershell
./apm-packages/design-pair-implementation-execution/scripts/validate.ps1
./apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs
git diff --check
```

static validator は mandatory turn stop、waiting schema、post-map user evidence、空集合 readiness の禁止、Plan Coverage / resume 伝播を確認します。実モデルの multi-turn behavior を static validation の PASS だけで証明済みとは扱いません。`tests/manual-model-smoke/README.md` の disposable fixture を使い、初回停止から disposition 後の Adaptive 開始までを別途記録します。

## Troubleshooting

- 初回 turn で `READY_FOR_ADAPTIVE_IMPLEMENTATION` が返った場合: handoff を READY として使用せず、`AWAITING_USER_INPUT / target-selection` へ修復し、Target Map 提示後の利用者応答を取り直します。
- upstream Plan の文言が `DP-Dxx` へ変換された場合: entry を `Upstream Binding Constraints` または `Upstream User Initial Positions` へ戻し、post-map confirmation evidence が得られるまで Locked Decision を作りません。
- resume で interaction stage、presentation evidence、user response evidence が欠ける場合: AI が補完せず `BLOCKED` / artifact repair とします。
- 利用者が全 Target を Adaptive に委ねたい場合: Target Map 提示後の明示応答を記録すれば、個別対話や人工的な Locked Decision は不要です。

## Agent Plugin artifact

process semanticsの正本はこのpackageの`.apm/**`です。Agent Plugin artifactはpackage rootへchecked-inせず、repository共通builderでtemporary stageへ生成します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package design-pair-implementation-execution
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package design-pair-implementation-execution
```

APMがsupported distributionです。direct deploymentのstatusとevidenceは`tests/agent-plugin/qualification.json`に記録し、未観測のbehaviorをPASSへ昇格させません。
