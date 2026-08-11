# Design Pair Implementation Execution

利用者が明示的に選択した場合だけ、実装前に予定変更面を既存 code の file / symbol 単位で確認し、対話で明示的に確定した `Locked Decisions` を Adaptive Implementation へ渡す APM package です。

通常経路は `adaptive-implementation-execution` です。この package は課題の難易度、risk、規模から Design Pair を自動選択、推奨、提案しません。

## Flow

```text
ordinary Plan / Implementation Intent
  -> design-pair-implementation-execution [explicit selection only]
  -> bounded Target Map presentation
  -> AWAITING_USER_INPUT / target-selection [mandatory turn stop]
  -> user-selected discussion and disposition
  -> AWAITING_USER_INPUT / disposition-confirmation [when needed]
  -> tracked Design Pair handoff / READY_FOR_ADAPTIVE_IMPLEMENTATION
  -> adaptive-implementation-execution
       -> high-implementation-starter
       -> optional standard-implementation-completer
       -> high-implementation-starter on re-entry
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

Adaptive Implementation の HIGH / STANDARD orchestration と portable agent 定義は、この package へ複製しません。manifest dependency で既存 `adaptive-implementation-execution` skill と canonical agents を導入します。

## Fresh install

Design Pair は Adaptive Implementation の前段です。正式 target は `copilot`、`codex`、`agent-skills` です。Design Pair package単体のinstallだけでは、後段のHIGH / STANDARD concrete model mappingが完成した証拠になりません。

### GitHub Copilot CLI

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,agent-skills
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target copilot,agent-skills
```

配置後の確認:

- `.agents/skills/design-pair-implementation-execution/SKILL.md`
- `.agents/skills/adaptive-implementation-execution/SKILL.md`
- `.github/agents/high-implementation-starter.agent.md`
- `.github/agents/standard-implementation-completer.agent.md`

GitHub Copilot CLI では Design Pair skill を明示指定して multi-turn 対話を行い、tracked handoff が `READY_FOR_ADAPTIVE_IMPLEMENTATION` になった後だけ **新しい CLI 起動で** `--agent high-implementation-starter` を付けて Adaptive を開始します。Design Pair session の継続だけでは canonical HIGH agent 選択の証拠になりません。会話履歴ではなく tracked handoff を durable authority とします。waiting 中の別 session 再開でも handoff path を渡し、欠落・矛盾時は fail closed します。手順と実 multi-turn 証拠は `tests/manual-model-smoke/` を参照してください。正式 acceptance は GitHub Copilot CLI であり、VS Code UI 操作は必須ではありません。

**Issue #69 / #86 境界:** ordinary Plan + explicit Design Pair + Adaptive handoff は本 package の Copilot formal support です。Plan Coverage parent からの Design Pair runtime E2E は #86 の資格認定範囲です。

### Codex

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target codex,agent-skills
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target codex,agent-skills
```

APM が concrete model / reasoning / sandbox 設定を持たない custom agent TOML を生成する環境では、導入済みmoduleの共通 finalizer で HIGH / STANDARD profile を補完します。

```powershell
dotnet run --file .\apm_modules\suusanex\coding_agent_plan_and_verify_process\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs -- .
```

Copilot-only導入ではCodex profileが不要なため、finalizerの実行も不要です。`--dry-run`、`--check`、`--force`の保守手順は Adaptive package の `docs/install-guide.md` を参照してください。

通常 Plan Mode 後の起動例:

```text
$design-pair-implementation-execution を明示的に選びます。
直前の Plan の予定変更面を調査し、Target Map と内部設計判断候補を提示してください。
私が議論対象を回答するため、そこで停止してください。初期案や懸念があれば併記します。
対話で disposition が確定した後に Adaptive Implementation へ進んでください。
```

利用者が毎回「停止してください」と補足する必要はありません。最初の依頼が単に「実装してください」であっても、Skill は Target Map を提示し、`AWAITING_USER_INPUT / target-selection` を保存してその turn を終了します。Target Map 提示前の Plan / Issue / gold document や利用者の技術案は upstream constraint / initial position であり、Design Pair Locked Decision ではありません。

初回Target Mapはartifact linkやTarget名だけの一覧ではありません。各Targetの具体的file / symbol、current responsibility / invariant、requested changeとの関係、内部設計判断候補、expected modification / verification、evidence、open questionをuser-facingに提示してから選択を求めます。

初回応答は7列の`Design Pair Target Map`、Coverage evidence、Selection requestを含む固定Markdown構造を使います。handoff内だけに詳細を保存し、応答をTarget名の短い箇条書きへ圧縮することはできません。選択Targetの対話もCode locationからOpen questionsまでを固定blockで提示します。

利用者の応答は親フローや検証harnessで補完せず、そのままDesign Pairへ渡します。Target Mapに実在するTarget IDだけでも選択は成立します。Skillは選択Targetの具体的なcode evidence、alternatives / trade-offs、非binding proposal、validation expectationを提示し、同じTarget選択や初期案を再要求せず`AWAITING_USER_INPUT / disposition-confirmation`で停止します。未選択Targetの委任または分類は最終dispositionと合わせて確認します。`design-discussion`等の独自stageへ遷移せず、headerとReadiness Checkのuser evidenceを同じ内容へ同期します。

選択Targetの対話では、具体的file / symbol、現在の責務・invariant、caller / wiring / lifecycle / test seam、内部設計論点、代替案とtrade-off、根拠付きの非binding proposalまたはNo proposal理由、validation expectationをuser-facingに提示します。Target名やartifact linkだけを提示して利用者へ判断を委ねません。

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
