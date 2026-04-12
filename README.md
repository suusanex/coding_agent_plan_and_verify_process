# coding_agent_plan_and_verify_process

GitHub CopilotでPlan First開発をするためのAgents（.github/agents/）です。

単純なPlanモードでは不十分と感じた点を、自分の用途向けに改善したものです。

## 想定する使用順序

1. plan-generation.agent.md
    1. この中で integration-test-design.agent.md と runtime-evidence.agent.md を呼び出す
1. plan-review.agent.md
1. （通常エージェントで実装） ※1
1. integration-test-verification-implementation.agent.md
1. coverage-gap-resolution.agent.md

### ※1 実装

通常はそのまま実装に入ればよいが、新しい実現方式の採用や、標準 API・既存 OSS・既存コードの比較検討が重要なケースでは、ここにオプションフェーズを追加できる。

これは、具体的な実装の中でも特に採用する API、ライブラリ、既存実装、設計パターンなどを検討するフェーズである。独自実装よりも適切な既存実装やベストプラクティスの採用を明示的に検討することで、AI による不要な車輪の再発明を避けることを狙う。

1. implementation-contract-generation.agent.md
1. implementation-contract-review.agent.md


