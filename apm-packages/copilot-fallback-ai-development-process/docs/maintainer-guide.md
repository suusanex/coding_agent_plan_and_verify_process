# Maintainer Guide

## Package boundary

この package は GitHub Copilot Chat in VS Code の repo-local customization を所有します。

既存 Codex-first package の本文を複製しすぎず、次だけを Copilot 用に再パッケージ化します。

- `copilot-cost-router`
- Copilot custom agents
- Copilot prompt files
- `.github/copilot-instructions.md`
- `.github/instructions/*.instructions.md`
- repo-local install / dry-run support

`high-implementation-starter`と`standard-implementation-completer`のcanonical contractとCopilot frontmatterはrepository root agents / Adaptive packageがsource of truthです。fallbackの同名templateは既存installer利用者向けの短いadapter mirrorであり、Adaptive validatorがHIGH-first、STANDARD direct-start禁止、verdict、route identity、Locked Decisions、Allowed edit surface、acceptance-to-work mapping、tracked re-entry metadata、Design Pair handoff / Decision ID、Implementation Self-Map Deltaを両側に要求します。

同名fileのcollision policyは、同内容ならno-op、異なる未管理fileは既定で保持、明示`--force`だけが置換です。APM導入fileはAPM lockfile、fallback local installerのfileはfallback templateがownerです。local installerは利用者変更を誤削除しないためremoveを自動化せず、Adaptive APM ownershipへのmigrationでは人が差分を確認します。

## Customization files

VS Code は workspace の `.github/copilot-instructions.md` を always-on instructions として読めます。`.github/instructions/*.instructions.md` は `applyTo` で補助 rules として使います。`.github/agents/*.agent.md` は custom agents、`.github/prompts/*.prompt.md` は slash command として使います。

## Model mapping maintenance

`COPILOT_HIGH_MODEL`、`COPILOT_STANDARD_MODEL`、`COPILOT_CHEAP_MODEL` は抽象 label です。frontmatter の `model` には例を入れますが、組織の契約、model policy、premium request、品質要求に合わせて更新してください。

## Release checklist

- README に導入方法と使い方がある
- installer の dry-run が既存 `.github` を上書きしない
- custom agents に `name`、`description`、`tools`、`model`、`handoffs` がある
- canonical agent 名 `high-implementation-starter` と `standard-implementation-completer` が存在し、root agent contract の HIGH start、valid handoff、HIGH re-entry、serial ownership と同期している
- Adaptive validatorがroot canonical agentsとfallback mirrorのcritical marker同期を検証する
- Adaptiveのstop verdictまたは`COMPLETED_BY_HIGH_MODEL`からverification agentへのhandoffを定義しない
- `copilot-standard-implementer` は legacy compatibility route として標準 handoff から外れている
- prompt files に `agent` と必要な `model` がある
- `ManualVerificationRequired`、`NeedsHumanDecision`、`NeedsHigherModelReview` が close blocker として説明されている
- full-coverage 3層運用が standard route ではなく advanced route として説明されている
- installer dry-run と適用後確認で canonical agent templates と Adaptive state fields が配布される

