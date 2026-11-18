# Goal Context Authoring

既存機能の改修では、影響する既存目的・利用場面を資料から限定的に継承し、根拠・権限と維持／追加／変更／廃止／未確認を区別します。改修Issueには継続文書の更新要否判定と、必要な変更を同じ実装PRへ反映する完了条件を含めます。変更なしなら理由付き更新不要とでき、自由形式入力とhuman reviewの任意性は維持します。

自然言語の資料から、後続の実装・目的達成reviewで利用できる自己完結したGoal Contextと、決定済み事項を引き継ぐDecision Contextを作るためのauthoring helperです。

この機能の中心資産はSkill内の`references/generation-prompt.md`です。APM packageはそのpromptと補助referenceを配布するための経路であり、promptの意味品質をmachine validationするものではありません。

Goal Contextはfree-form textです。このpackageのpromptやexampleを使わずに作成された文書も同じように利用できます。filename、拡張子、frontmatter、見出し、table、provenance tag、lifecycle、approval record、作成元は下流consumerの必須条件ではありません。

## Install

OSユーザー単位のglobal領域へ、任意のdirectoryから導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target copilot,codex,agent-skills --global
```

## Use

1. `~/.agents/skills/goal-context-authoring/references/generation-prompt.md`を任意のauthoring補助として使う、または別経路で文書を書く。
2. 元の問いとその後の具体化・合意・訂正から「誰のどんな困りごとが、どう変わるか」を取り出す。全機能が動いても困りごとが残る例を未達と判定できるか、原資料と照合する。達成判定が分かれる場合や、長い構想検討から新しい仕組みの中心目的を初めて推定する場合は、全文を書く前に短い目的案を確認する。利用者がすでに示した矛盾のない目的の再承認は不要。
3. 照合した目的を保ち、Goal Contextには代表場面で得たい結果と判定に必要な境界を、Decision Contextには明示的に固定済みのscope・採用判断・実装方針を残す。[作成例](.apm/skills/goal-context-authoring/references/goal-context-template.md)では、活動全体を見直せることと、そのために台帳を読むことを分けている。
4. Goal ContextとDecision Contextのどちらにも属さない経緯、roadmap、未解決事項を引き継ぎ目的で追加しない。
5. secret、credential、認証情報、不要な個人情報を除く。

このpackageはGoal Context / Decision Contextのsemantic regression testやvalidity validatorを提供しません。生成結果の意味が元資料と一致しているかは、必要な場面で内容そのものをreviewします。[会話4例での生成結果と照合記録](tests/purpose-extraction-samples.md)では、全文を生成した場合と目的確認で止めた場合を比較できます。

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

global update / uninstallと旧local配置の整理は[共通運用手順](../../docs/installation-and-maintenance.md#global-lifecycle)を参照してください。APM v0.26.0では標準runtime homeを利用します。
