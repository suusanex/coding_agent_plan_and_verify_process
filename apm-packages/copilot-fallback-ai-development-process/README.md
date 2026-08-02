# GitHub Copilot Fallback AI Development Process

Codexの利用枠が尽きた場合、または環境上Codexを使えない場合に、GitHub Copilot Chat in VS CodeへfallbackするためのAPM processです。Codex-firstとstate、stop vocabulary、READY / close policyを共有しますが、導入先は`.codex/`ではなくVS Code Copilotが読む`.github/`配下です。

通常の第一選択は[Codex-first AI Development Process](../codex-first-ai-development-process/README.md)です。このpackageはCopilotを主経路にしたい場合、またはCodexからのfallbackが必要な場合に使います。

## Use when

- Codexを利用できず、同じcost-aware Plan-first方針をCopilot Chatで使いたい
- repository-localなcustom instructions、custom agents、prompt filesを導入したい
- READY前の実装禁止、stateful resume、close gateをCopilot側でも維持したい

## Install

既存`.github/`と`AGENTS.md`との衝突を確認するため、先にdry-runします。

```powershell
dotnet run --file .\scripts\install-copilot-fallback-local.cs -- <target-repository> --dry-run
dotnet run --file .\scripts\install-copilot-fallback-local.cs -- <target-repository>
```

同名のmanaged fileを上書きする必要がある場合だけ`--force`を使います。markerのない既存`.github/copilot-instructions.md`はmanual merge blockerとして停止します。

## Use

利用者は通常の依頼を行えます。明示入口が必要な場合はVS Code Chatのprompt fileを使います。

```text
/cost-route この issue を進めて
/resume-state
/verify-and-close
/fix-selected-residual RES-001
```

`copilot-cost-router`がrepository-local instructionsと既存artifactを読み、IntakeからCloseまでの次gateとmodel tierを決めます。full-coverage 3層運用は標準routeではありません。

## Model tiers and safety

| Tier | Intended use |
| --- | --- |
| `COPILOT_HIGH_MODEL` | 曖昧な要求整理、bounded Plan、high-risk triage、auth / security / production close判断 |
| `COPILOT_STANDARD_MODEL` | READY後の通常実装、通常verification |
| `COPILOT_CHEAP_MODEL` | read-heavy scan、docs consistency、trivial local fix |

READY前に実装せず、`ManualVerificationRequired`、`NeedsHumanDecision`、`NeedsHigherModelReview`が未決のままcloseしません。fake、stub、mock-only successをproduction successとして扱いません。

## Documentation

- [Fallback guide](docs/copilot-fallback-guide.md)
- [User guide](docs/user-guide.md)
- [Install guide](docs/install-guide.md)
- [Model tier mapping](docs/model-tier-mapping.md)
- [Limitations](docs/limitations.md)
- [Maintainer guide](docs/maintainer-guide.md)
