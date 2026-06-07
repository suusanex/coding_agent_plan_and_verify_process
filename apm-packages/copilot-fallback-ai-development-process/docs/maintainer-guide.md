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

## Customization files

VS Code は workspace の `.github/copilot-instructions.md` を always-on instructions として読めます。`.github/instructions/*.instructions.md` は `applyTo` で補助 rules として使います。`.github/agents/*.agent.md` は custom agents、`.github/prompts/*.prompt.md` は slash command として使います。

## Model mapping maintenance

`COPILOT_HIGH_MODEL`、`COPILOT_STANDARD_MODEL`、`COPILOT_CHEAP_MODEL` は抽象 label です。frontmatter の `model` には例を入れますが、組織の契約、model policy、premium request、品質要求に合わせて更新してください。

## Release checklist

- README に導入方法と使い方がある
- installer の dry-run が既存 `.github` を上書きしない
- custom agents に `name`、`description`、`tools`、`model`、`handoffs` がある
- prompt files に `agent` と必要な `model` がある
- `ManualVerificationRequired`、`NeedsHumanDecision`、`NeedsHigherModelReview` が close blocker として説明されている
- full-coverage 3層運用が standard route ではなく advanced route として説明されている

