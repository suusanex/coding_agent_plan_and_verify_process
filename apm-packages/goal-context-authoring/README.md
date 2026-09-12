# Goal Context Authoring

自然言語の資料から、後続の実装・目的達成reviewで利用できる自己完結したGoal Contextと、決定済み事項を引き継ぐDecision Contextを作るためのauthoring helperです。

この機能の中心資産はSkill内の`references/generation-prompt.md`です。APM packageはそのpromptと補助referenceを配布するための経路であり、promptの意味品質をmachine validationするものではありません。

Goal Contextはfree-form textです。このpackageのpromptやexampleを使わずに作成された文書も同じように利用できます。filename、拡張子、frontmatter、見出し、table、provenance tag、lifecycle、approval record、作成元は下流consumerの必須条件ではありません。

## Install

対象repositoryのrootで実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target copilot,codex,agent-skills
```

## Use

1. `.agents/skills/goal-context-authoring/references/generation-prompt.md`を任意のauthoring補助として使う、または別経路で文書を書く。
2. Goal Contextには、元の問題、期待成果、目的達成reviewに必要な境界だけを残す。
3. Decision Contextには、明示的に固定済みのscope・採用判断・実装方針だけを残す。
4. Goal ContextとDecision Contextのどちらにも属さない経緯、roadmap、未解決事項を引き継ぎ目的で追加しない。
5. secret、credential、認証情報、不要な個人情報を除く。

このpackageはGoal Context / Decision Contextのsemantic regression testやvalidity validatorを提供しません。生成結果の意味が元資料と一致しているかは、必要な場面で内容そのものをreviewします。

## Package contents

| Content | Path |
| --- | --- |
| Authoring Skill | `.apm/skills/goal-context-authoring/SKILL.md` |
| Generation prompt | Skillの`references/generation-prompt.md` |
| Free-form interoperability contract | Skillの`references/goal-context-contract.md` |
| Optional example | Skillの`references/goal-context-template.md` |
| Optional quality checklist | Skillの`references/human-review-checklist.md` |

詳細は[usage and install guide](docs/usage-and-install-guide.md)を参照してください。

## Agent Plugin artifact

process semanticsの正本はこのpackageの`.apm/**`です。Agent Plugin artifactはpackage rootへchecked-inせず、repository共通builderでtemporary stageへ生成します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package goal-context-authoring
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package goal-context-authoring
```

APMがsupported distributionです。direct deploymentのstatusとevidenceは`tests/agent-plugin/qualification.json`に記録し、未観測のbehaviorをPASSへ昇格させません。
