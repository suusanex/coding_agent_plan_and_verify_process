# Solution Shape Authoring

Goal Context と Decision Context から、詳細な実装 Plan へ進む前に、**構成・責務配置、機能配置、代表的な実行経路**を簡潔に表現した軽量な Markdown スケッチ「Solution Shape」を作成する独立した APM Skill です。

単独で利用でき、コード実装や目的レビューの実行を必須にしません。事前に作成された Solution Shape がある場合だけ、既存の `$persistent-purpose-review` へ任意に渡せます。

## Install

対象 repository の root で実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/solution-shape-authoring --target copilot,codex,agent-skills
```

## Use

1. 単独で利用する場合は、Goal Context・Decision Context や要望を添えて `$solution-shape-authoring` に軽量な構成スケッチ作成を依頼します。コード実装や `$persistent-purpose-review` は自動実行されません。
2. `$persistent-purpose-review` と任意連携する場合は、作成済み Solution Shape を既存の `schemaVersion: 1` 入力へ含めます（Solution Shape 自体が提案設計なら `proposal.body`、別の提案設計を理解する補助材料なら `evidence`）。Solution Shape がなくても通常の purpose review は成立し、この Skill で資料を作っただけでは `approvedDesign` に昇格しません。

特定のファイル名、見出し、表の行数、ページ数、専用図法（UCM / C4 / DFD 等）は下流の必須条件にしません。

## Package contents

| Content | Path |
| --- | --- |
| Authoring Skill | `.apm/skills/solution-shape-authoring/SKILL.md` |
| Examples & guide | Skill の `references/solution-shape-examples.md` |

## Agent Plugin artifact

process semantics の正本はこの package の `.apm/**` です。Agent Plugin artifact は package root へ checked-in せず、repository 共通 builder で一時 stage へ生成して検証します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package solution-shape-authoring
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package solution-shape-authoring
```

APM が supported distribution です。direct deployment の status と evidence は `tests/agent-plugin/qualification.json` に記録し、未観測の behavior を PASS へ昇格させません。
