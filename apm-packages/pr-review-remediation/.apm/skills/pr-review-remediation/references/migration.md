# Migration from `codex_copilot_pr_review_agent`

## Source baseline

- Repository: `suusanex/codex_copilot_pr_review_agent`
- Source commit: `8c3a92b9d63dcf2384f07360e4f845ced0f02156`
- Destination baseline: `suusanex/coding_agent_plan_and_verify_process` commit `d9f7317298fdcd39dec29dd662d38bcd82ecfd0f`

## Component disposition

| Source component | Disposition | Destination |
| --- | --- | --- |
| PR branch/commit/push/creation preparation | Retained and tightened | `pr-review-remediation` Skill Phase 1 |
| `collect-pr-review-context.cs` | Migrated and normalized | Skill `scripts/` |
| Copilot delayed review wait | Retained and correlated to head/review ID | collector `copilotReviewWait` |
| `local-reviewer` | Migrated as canonical read-only agent | root `.github/agents/` |
| `review-planner` | Migrated and made Adaptive-ready | root `.github/agents/` |
| review plan template | Replaced with finding ledger and canonical Implementation Intent | Skill `templates/review-plan.md` |
| installer/profile synchronization | Reworked for monorepo package conventions | package sync helper and existing Adaptive helper |
| implementation agent | Removed | existing `adaptive-implementation-execution` dependency |
| implementation result report | Removed | existing Adaptive output/handoff |

The former `spark-implementer` is not retained as an agent, alias, compatibility route, fallback, template owner, or profile. Its implementation responsibility is transferred to the existing Adaptive Implementation flow; the overall review remediation process still includes implementation and validation in a separate parent turn.

## Deliberately deferred

- Goal Context integration
- `purpose-reviewer`
- automatic next-turn startup
- source repository archive or redirect decision

