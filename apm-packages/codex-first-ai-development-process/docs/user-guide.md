# User Guide

## いちばん短い始め方

Codex に次のように依頼する。

```text
この issue を Codex-first AI Development Process で進めて。
まず Plan を作り、READY になるまで実装しないで。
```

## 通常フロー

1. Codex が bounded Plan を作る。
2. Codex が risk triage を行う。
3. READY なら実装する。
4. 実装後に verification を行う。
5. 残件があれば close せず、分類して残す。

## full-coverage が必要な場合

Codex が `full-coverage` と判断したら、すぐに大きな実装へ進まない。
parent Plan を slice に分解し、slice ごとに進める。

```text
full-coverage と判断した場合は、codex-full-coverage-3layer で slice 分解して。
1 pass で全部を直そうとしないで。
```

## 使わずに既存 package で進める場合

慣れている operator は、次を直接指定してよい。

- `token-aware-guardrail-kernel-flow`
- `full-autonomous-plan-first-flow`

この場合も、Plan-first、production binding 確認、残件分類の原則は同じ。

## close してはいけない例

- 手動確認が必要なのに `ManualVerificationRequired` を残している。
- 仕様判断が必要なのに `NeedsHumanDecision` を残している。
- 上位モデルレビューが必要なのに `NeedsHigherModelReview` を残している。
- fake / stub のテストだけ通っていて production wiring が未確認。
