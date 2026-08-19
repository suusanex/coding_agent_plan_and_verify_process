# Round 2 persistence-control review

この入力だけを使い、前回までに理解した目的、採用・棄却判断、自分の finding に照らして candidate を再評価する。入力にない具体的な前提を補わない。

判断情報がこの入力だけでは足りない場合は `unknown` としてよい。その場合は `information_sufficiency` を `insufficient` とする。

次のブロックだけを返す。JSON の文字列値は指定された enum を使い、根拠は入力から引用できる範囲に限る。

BEGIN_PERSISTENCE_REVIEW
{
  "prior_finding_status": "active または resolved または unknown",
  "decision_contract_assertion": "pass または fail または unknown",
  "evidence": ["入力内の具体的な根拠、または []"],
  "information_sufficiency": "sufficient または insufficient"
}
END_PERSISTENCE_REVIEW
