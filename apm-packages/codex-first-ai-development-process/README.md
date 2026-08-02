# Codex-first AI Development Process

Codexを第一優先にし、短い依頼からcost-awareなPlan-first routingへ入るためのAPM processです。利用者にprocess名、agent名、model tier、full-coverage分岐を選ばせず、`codex-first-cost-router`がrepository rules、既存artifact、stateを見て次のgateを決めます。

標準routeはfull-coverage 3層運用ではありません。通常の作業はboundedなcost-aware routeで進め、安全にbounded化できない場合、または熟練operatorが明示選択した場合だけadvanced full-coverage routeへ分けます。

## Use when

- 「このissueを進めて」「このバグを修正して」のような短い依頼からPlan-firstで進めたい
- READY前の実装禁止と、実装後のclose gateを明示したい
- 難しい判断、通常実装、read-heavy scanをmodel tier別に分担したい
- state artifactを使って別sessionから安全にresumeしたい

## Start

明示的に起動する場合:

```text
$codex-first-cost-router を使って、この issue を進めてください。
```

通常依頼を自動でCodex-firstへ入れる場合は、対象repositoryへpackageのinstructions、skills、agents、templatesを導入します。repo固有のbuild、test、security rulesとexplicit user instructionsは常に優先されます。

## Standard route

`codex-first-cost-router`はIntake、Plan、Risk、Scan、Contract、Implementation handoff review、Implementation、Verification、Closeから次のgateを選びます。非自明な実装は`high-implementation-starter`から開始し、completeなhandoffがある場合だけ`standard-implementation-completer`へ直列委譲します。構造判断が再発した場合はHIGH_MODELへ戻します。

抽象tierは次の責務を表します。実モデル名は組織の契約、利用枠、品質要求に応じてmappingします。

| Tier | Intended use |
| --- | --- |
| `HIGH_MODEL` | 曖昧な要求整理、難しいrisk判断、非自明な実装開始・再入場、危険なclose gate |
| `STANDARD_MODEL` | valid handoff後のbounded completion、通常verification、test update |
| `CHEAP_MODEL` | read-heavy scan、docs consistency、artifact format check、単純な局所修正 |

## Install

標準bootstrapはFile-based appで対象repositoryへ適用します。次のコマンドは、このsource repositoryのrootから実行します。

```powershell
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- <target-repository> --dry-run
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- <target-repository>
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- <target-repository> --check
```

`--dry-run`と`--check`はfileやdirectoryを作成しません。`--check`はcanonical agent contracts、Adaptive skillの完全な`refs/handoff.md`、Design Pair referencesが対象repositoryに存在してpackage sourceと一致することも検証します。既存APM向けの`scripts/provision-work-repo-agents.cs`はCodex-first bootstrapには使いません。

## Advanced route

full-coverageが必要な場合は、Plan CoverageのArchitecture Slice Readiness Gateとslice decompositionを通してから[full-coverage 3層運用](../token-aware-full-coverage-3layer/README.md)へ進みます。fresh decompositionは`compact-slice-record-v2`を使い、sliceでparent triageを再実行しません。

## Documentation

- [Process contract](docs/codex-first-ai-development-process.md)
- [User guide](docs/user-guide.md)
- [Maintainer guide](docs/maintainer-guide.md)
- [Bootstrap and merge policy](docs/bootstrap-and-merge-policy.md)
- [Team profile and launcher](docs/team-profile-launcher.md)
- [Advanced full-coverage route](docs/advanced-full-coverage-3layer.md)
- [Routing branch reference](../../docs/codex-first-routing-branching.md)
