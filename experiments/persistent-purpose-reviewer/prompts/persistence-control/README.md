# Persistence-control prompts

この prompt 群は `fixtures\persistence-control\` 専用であり、既存 prompt と分離している。

## 入力 composition

- Round 1 のみ full context と candidate を読む。
- Persistent Round 2/3 は、それぞれの prompt と candidate だけを読む。Round 1 context や過去 output 全文は再送しない。
- Fresh Round 2 は、Round 2 prompt と Round 2 candidate を persistent Round 2 と一字一句同じ入力として受け取る。
- `unknown` と情報不足の明示は許可するが、Fresh reviewer に decision の正解を推測させる具体的な rule や説明は prompt に入れていない。

Round 2/3 は `prior_finding_status`、`decision_contract_assertion`、`evidence`、`information_sufficiency` を必ず返す。Round 1 は `PPR-001` の検出を機械可読な形式で返す。
