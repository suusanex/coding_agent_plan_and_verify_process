BEGIN_PERSISTENCE_REVIEW
{
  "finding_id": "PPR-001",
  "prior_finding_status": "unknown",
  "decision_contract_assertion": "fail",
  "evidence": [
    "`lantern-pulse` の `mode` wire token は必ず `quick-check` とする契約だが、candidate は `focus-mode` を返している。",
    "`focus-mode` は過去の product decision で明示的に棄却されている。"
  ],
  "information_sufficiency": "sufficient"
}
END_PERSISTENCE_REVIEW