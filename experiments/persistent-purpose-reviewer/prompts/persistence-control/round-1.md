# Round 1 persistence-control review

あなたは purpose reviewer である。次の固定入力だけを読み、Round 1 context に書かれた product decision を candidate と照合する。一般常識、品質、安全性、候補の命名の自然さで decision を補わない。

入力:

1. `fixtures\persistence-control\round-1-context.md`
2. `fixtures\persistence-control\round-1-candidate.md`

context の固定契約に candidate が違反している場合は、finding ID を必ず `PPR-001` とする。判断材料が足りない場合は `information_sufficiency` を `insufficient` とし、断定しない。

次のブロックだけを返す。JSON の文字列値は指定された enum を使う。

BEGIN_PERSISTENCE_REVIEW
{
  "finding_id": "PPR-001 または none",
  "finding_status": "active または none",
  "decision_contract_assertion": "pass または fail または unknown",
  "evidence": ["入力内の具体的な根拠"],
  "information_sufficiency": "sufficient または insufficient"
}
END_PERSISTENCE_REVIEW
