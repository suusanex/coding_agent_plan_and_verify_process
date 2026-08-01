# Goal Context Authoring

自然言語の資料から、後続の実装・目的達成reviewで利用できる自己完結したGoal Contextを作る任意のauthoring helperです。

Goal Contextはfree-form textです。このpackageのpromptやexampleを使わずに作成された文書も同じように利用できます。filename、拡張子、frontmatter、見出し、table、provenance tag、lifecycle、approval record、作成元は必須ではありません。

## Install

対象repositoryのrootで実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target codex,agent-skills
```

## Use

1. `.agents/skills/goal-context-authoring/references/generation-prompt.md`を任意のauthoring補助として使う、または別経路でGoal Contextを書く。
2. 利用できる資料に忠実な自然言語で、目的と望まれる変化を自己完結して説明する。
3. 必要に応じてproblem、利用状況、境界、目的を外す結果、unknownを加える。これらの見出しは任意です。
4. secret、credential、認証情報、不要な個人情報を除く。
5. 任意でreadability validatorを実行する。

```powershell
dotnet run --file .agents/skills/goal-context-authoring/scripts/validate-goal-context.cs -- --goal-context <path> --mode basic --format json
```

`draft`と`strict`は既存commandとの互換aliasで、`basic`と同じ検査を行います。人間reviewやapproval状態を要求しません。

validatorのPASSは、non-empty readable textであり高確度credential patternを検出しなかったことだけを示します。semantic fidelity、完全性、privacy safety、承認を証明しません。

## Package contents

| Content | Path |
| --- | --- |
| Authoring Skill | `.apm/skills/goal-context-authoring/SKILL.md` |
| Optional generation prompt | Skillの`references/generation-prompt.md` |
| Free-form interoperability contract | Skillの`references/goal-context-contract.md` |
| Optional example | Skillの`references/goal-context-template.md` |
| Optional quality checklist | Skillの`references/human-review-checklist.md` |
| Readability validator | Skillの`scripts/validate-goal-context.cs` |
| Package validator | `scripts/validate-goal-context-authoring.ps1` |
| APM install smoke | `scripts/test-apm-package-install.ps1` |

詳細は[usage and install guide](docs/usage-and-install-guide.md)を参照してください。
