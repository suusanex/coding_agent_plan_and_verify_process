# coding_agent_plan_and_verify_process

GitHub CopilotでPlan First開発をするためのAgents（.github/agents/）です。

単純なPlanモードでは不十分と感じた点を、自分の用途向けに改善したものです。

## 想定する使用順序

1. plan-generation.agent.md
    1. この中で integration-test-design.agent.md と runtime-evidence.agent.md を呼び出す
1. plan-review.agent.md
1. （通常エージェントで実装）
1. integration-test-verification-implementation.agent.md
1. coverage-gap-resolution.agent.md


