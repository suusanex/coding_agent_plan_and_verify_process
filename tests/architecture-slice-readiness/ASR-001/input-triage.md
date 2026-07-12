# ASR-001 Change Risk Triage

- Profile: `full-coverage`
- Immediate next agent: `architecture-slice-readiness.agent.md`

| Trigger | Status | Evidence |
| --- | --- | --- |
| Multiple participants | Present | control plane / worker / observer / human gate |
| Durable and derived state | Present | desired state and observation coexist |
| Cross-run identity | Unclear | Plan requires continuity but defines no owner |
| Retry / release | Unclear | terminal release sequence is absent |
| Shared capacity | Present | worker slots are shared |
