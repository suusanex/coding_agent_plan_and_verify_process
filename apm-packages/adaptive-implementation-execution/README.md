# Adaptive Implementation Execution

Planから、現在の親がビルド可能な構造コードを作成し、人の実際の構造承認後に子が詳細実装・テスト・検証を完成するAPM packageです。

## Flow

```text
Plan / explicit Design Pair READY
 -> current parent (selected model): compare / structure code / production build
 -> AWAITING_STRUCTURE_REVIEW: present code and END TURN
 -> actual user approval + handoff readiness
 -> bounded-residual-implementation-owner: detail implementation / tests / validation
 -> IMPLEMENTATION_COMPLETED
    or NEEDS_DECISION_SURFACE_REENTRY -> same parent -> structure revision / build / review stop
```

親自身が`decision-surface-implementation-owner`の契約を読みます。別の上位agent・model pin・切替sessionはありません。親はI/F・共有型・日本語XML契約・依存登録・主要なクラス間呼出順序とデータ受渡しを書き、末端の詳細本体は明示的に未実装とします。既存処理は再利用し、不要な抽象化は追加しません。

人に示した時点でそのturnを終了します。実際の応答まで詳細実装も子の起動も行いません。承認と子へ渡せる状態を別々に確認し、ほぼ既存再利用でも同じ停止を守ります。子は入力検査・本体・局所helper・tests / mock / 検証を所有します。構造の実質変更だけを元親へ返し、局所修正は再承認不要です。

## Install / start

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

```text
/adaptive-implementation-execution plans/issue-123.md を実装してください。
```

親の選択済みmodelをそのまま使用します。子だけCodex `gpt-6-luna` / Copilot `GPT-6 Luna (copilot)`の設定を持ちます。

## Package contents

- [Skill](.apm/skills/adaptive-implementation-execution/SKILL.md)
- [親の構造契約](.apm/agents/decision-surface-implementation-owner.agent.md)
- [子の詳細実装契約](.apm/agents/bounded-residual-implementation-owner.agent.md)
- [handoff / durable review state](.apm/skills/adaptive-implementation-execution/refs/handoff.md)
- [Usage Guide](docs/usage-guide.md) / [Install Guide](docs/install-guide.md)
- [検証境界](docs/examples/adaptive-routing-validation.md)

## Breaking change in 0.7.0

0.6以前の上位直接完了・別上位起動・全decision解消後のtransferを置換しました。旧handoffを自動変換しません。進行中runは旧版で完了するか、元intentから新規に構造レビューを行います。既存の親projectionにmodel pinが残る場合、package管理下の旧projectionを確認して削除・再導入します。ユーザー独自設定を自動上書きしません。

既存比較と実装後diff照合、Design Pair Locked Decisions、route identity、Plan Coverage bindingsは維持します。Plan Coverage全体・Design Pair対話・最終独立reviewは再設計しません。APMがsupported distributionであり、過去のdated実model証拠を0.7の挙動保証へ流用しません。

子のCodex設定の正本は [codex-profile-overlays.json](codex-profile-overlays.json) です。

Copilot CLIの非対話起動は[本文pathを明示する起動例](docs/usage-guide.md#copilot-cliの非対話起動)を使います。slash名だけではSkill未読で進むケースを観測しています。
