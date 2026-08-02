# Limitations

- Codex-firstにあるlite / standard documentation level、core / audit artifact分離、profile TOML互換更新はCopilot fallbackへ未移植です。これらは後続issueで扱います。
- Codex-firstとstate、stop vocabulary、READY / close policyを共有していても、fallbackのtemplateやinstallerがCodex-firstの全機能に対応済みであるとは判断しません。
- GitHub Copilot の premium request 消費や課金は完全自動管理しません。
- 利用可能 model は VS Code、GitHub Copilot plan、organization policy に依存します。
- GitHub organization-level custom instructions の管理画面設定は自動化しません。
- 既存 `.github` customization の曖昧な merge は自動実行しません。
- secret、production、billing、external service operation は explicit approval なしに実行しません。
- `ManualVerificationRequired`、`NeedsHumanDecision`、`NeedsHigherModelReview` が残る場合は close しません。
- full-coverage 3層運用は standard route ではなく advanced route です。

