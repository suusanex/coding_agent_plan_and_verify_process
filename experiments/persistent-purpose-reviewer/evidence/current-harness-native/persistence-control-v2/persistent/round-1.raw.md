BEGIN_PERSISTENCE_REVIEW
{
  "finding_id": "PPR-001",
  "finding_status": "active",
  "decision_contract_assertion": "fail",
  "evidence": ["product decision は lantern-pulse の mode wire token を必ず quick-check と規定しているが、candidate は focus-mode を返し、JSON でも focus-mode を送信している。focus-mode は明示的に棄却済みである。"],
  "information_sufficiency": "sufficient"
}
END_PERSISTENCE_REVIEW