# Copilot CLI real-scenario qualification record

- Date: 2026-08-05 (Asia/Tokyo)
- Copilot CLI: `1.0.78`
- APM: `0.26.0`
- Package: `plan-coverage-residual-flow` `0.9.1`
- Remote source: `suusanex/coding_agent_plan_and_verify_process#8d7527cbf5c0172148346463fd6c61f25fb33e24`
- Install mode: `remote-package`
- Installed Skill SHA-256: `8814975edb2cc8ec48dc369c117d6e1cb9ca07ca59c0468151347841d873db3a`
- Full-package install: `PASS`
- Deployed `.agents/skills`, `.github/instructions`, `.github/agents`: `PASS`
- Lock source/ref/version/content hash/deployed Skill hash: `PASS`
- Unmanaged collision preservation: `PASS`
- Install boundary: `PASS`
- Skill discovery: `PASS`
- Local Skill-only evidence: not used for this record
- Real-scenario status: `INCOMPLETE`
- Qualification status: `REAL_SCENARIO_INCOMPLETE`

Route metadata remained:

```yaml
implementation_route: adaptive
implementation_route_source: default
design_pair_handoff: N/A
reentry_count: 0
previous_reentry_trigger: N/A
delegation_surface_reduced: N/A
```

The probes used real Copilot CLI JSONL sessions from a remote full-SHA
installation. No scenario was marked `PASS` from static fixtures or Skill
discovery alone. The CLI exposed natural-language route and negative
activation evidence, but did not expose all agent phase transitions or
production artifact completion.

| Scenario | Status | Real evidence |
| --- | --- | --- |
| Install and Skill discovery | `PASS` | Full-SHA install and `copilot skill list` succeeded. |
| Explicit `lite` | `PASS` | Session `bfb9052d-4b77-4bb5-a0a4-14018080a460`; Skill, explicit authorization, `lite`, and adaptive/default metadata reported. |
| Explicit `standard` | `PASS` | Session `e46dd15f-3171-470b-bbb1-5a21468ee1e5`; Skill, explicit authorization, `standard`, and adaptive/default metadata reported. |
| Generic no activation | `PASS` | Session `78f2e696-94fa-40a3-bc32-a7d49449e8ff`; no Plan Coverage Skill or custom agent activated. |
| Question/comparison/negation no activation | `PASS` | Session `3f2ad865-dabc-40c2-8329-62d9ec2c4f72`; no Skill or custom agent activated. |
| Durable authorization resume | `PASS` | Session `325c9c28-61a4-45a4-8369-3fccf55fe652`; complete durable tuple accepted and adaptive/default metadata reported. |
| Default Adaptive | `PASS` | Session `b4fc1784-d99f-4a71-b26d-bbacd971799f`; fresh intake reported adaptive/default and `reentry_count: 0`. |
| HIGH to STANDARD completion | `UNOBSERVABLE` | Session `25e023a4-1ab4-4d45-a6a0-31bb55922697`; requested/observed Terra, but incomplete handoff prevented an actual transition. |
| STANDARD to HIGH re-entry | `UNOBSERVABLE` | Session `1335e1cb-c56c-4d0e-b970-273218af85a6`; re-entry was described, but no actual phase transition was exposed. |
| Blocked / human decision / replan | `PASS` | Session `93031f62-5eb7-4317-b8c5-bddf79fe0c37`; `HUMAN_DECISION_REQUIRED` stopped implementation. |
| Architecture Slice Readiness | `UNOBSERVABLE` | Session `d9cd0b1c-5e06-4aee-890c-10d10799c1f7`; missing upstream authority stopped before readiness execution. |
| Compact Slice Record v2 two-slice | `UNOBSERVABLE` | Session `01ac7bc4-2236-4180-ad31-666f0ebfccc6`; missing v2 artifacts returned `BlockedByArtifactLayoutMismatch`. |
| Independent verification | `UNOBSERVABLE` | Session `06ea905c-8086-4e37-945d-58307c349bac`; missing Plan/ledger/binding evidence returned a blocked verdict. |
| Final Record through residual decision | `UNOBSERVABLE` | Session `31ad0566-0b12-4faf-afe3-7b680a04423f`; Final Record and upstream artifacts were absent. |
| New-session resume | `UNOBSERVABLE` | A separate process used `copilot --resume=325c9c28-61a4-45a4-8369-3fccf55fe652`; conversation resume was observed only, and artifact-authoritative process resume was not proven. |
| Stale/incomplete artifact failure | `PASS` | Session `aed962e2-93b9-446a-9e55-dbeee70bbee9`; `BLOCKED_BY_ARTIFACT_MISMATCH` stopped continuation. |
| Design Pair E2E | `BLOCKED` | Issue #69 canonical Copilot support is not merged. |

### New-session resume evidence declaration

- `copilot --resume=<session-id>`: `OBSERVED_ONLY` conversation resume
- Artifact-authoritative process resume: `NOT_PROVEN`
- Evidence bundle path and SHA-256: not committed
- Human acceptance must use a fresh session without conversation history and
  record prompt, command, output, artifact paths/hashes, changed files, and
  verdict sequence.

Remaining work is real execution evidence for the unobservable HIGH/STANDARD
phase transitions, Architecture Slice Readiness positive path, compact v2
positive path, independent verification, and Final Record/residual close path.
Design Pair remains blocked by #69 and was not implemented locally.
