# Full Autonomous Plan-first Flow

要求が広い、複数のruntime sequenceが絡む、またはintegration testとruntime evidenceを広く設計してから実装したい場合に使うAPM processです。token costより網羅性を優先し、agentが大きなゴールまで自走する従来型のPlan-first flowを提供します。

bounded Planをsource of truthとして残件を明示判断したい場合は、[Plan Coverage Check and Residual Decision Flow](../plan-coverage-residual-flow/README.md)を使います。通常のPlanから実装だけを進めたい場合は、[Adaptive Implementation Execution](../adaptive-implementation-execution/README.md)を使います。

## Use when

- 機能全体のscopeが広い、または要求がまだ曖昧である
- 複数のruntime sequence、recovery、retry、rollback、データ整合性をまとめて扱う
- full runtime evidenceやintegration test designを人間が詳細にreviewしたい
- bounded passよりも、広い自律実行と網羅性を優先する

## Flow

1. `plan-generation.agent.md`で詳細Planを作る。
2. `plan-review.agent.md`でPlanをreviewする。
3. 必要に応じて`runtime-evidence.agent.md`と`integration-test-design.agent.md`で実行時証拠とintegration testを設計する。
4. 通常の実装agentで実装する。
5. `integration-test-verification-implementation.agent.md`で検証する。
6. `coverage-gap-resolution.agent.md`で残ったcoverage gapを扱う。

dependency、API、provider、既存実装との比較が重要な場合は、実装前に`implementation-contract-generation.agent.md`と`implementation-contract-review.agent.md`を追加できます。

## Package contents

このpackageの`apm.yml`は、full autonomous flowで使うroot `.github/agents/*.agent.md`を配布します。Plan Coverageのkernel、residual decision、compact slice executionはこのpackageの標準手順ではありません。

## Selection guide

| Need | Read |
| --- | --- |
| 広い要求をruntime evidenceとintegration test designまで含めて自走させる | この文書 |
| bounded Planを維持し、未解決項目を明示判断する | [Plan Coverage](../plan-coverage-residual-flow/README.md) |
| 既にあるPlanを実装する | [Adaptive Implementation](../adaptive-implementation-execution/README.md) |
