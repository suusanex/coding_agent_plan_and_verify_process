---
name: completion-notification-decorator
description: Optionally enrich the always-on completion notification for exactly one explicitly co-selected Codex primary process. Use only when the user explicitly invokes $completion-notification-decorator together with another process Skill in the same parent turn; ordinary notifications do not require this Skill.
---

# Completion Notification Decorator

Treat this Skill as an observational decorator for the current parent turn. Let the explicitly co-selected primary process run under its own contract. Do not select, start, route, reproduce, or replace that process.

Read `references/envelope-authoring-contract.md` before authoring the final envelope.

## Establish notification metadata

1. Confirm that the user explicitly selected this Skill in the same prompt as exactly one primary process Skill.
2. Record that co-selected Skill name verbatim as `primary_process`. Do not treat its internal agents as additional primary processes.
3. Resolve `repository` as `owner/name` when reliable repository context exists. Otherwise omit it and let the runtime resolve the current working directory.
4. Accept an optional notification title and a specific HTTPS `result_uri`. Do not invent a result URI.
5. If zero or multiple primary process Skills are selected, do not choose among them and do not interrupt any process that can still run safely. Omit the envelope and report the decorator metadata problem separately. The always-on runtime still persists its generic Local Spool item.

The literal `$completion-notification-decorator` selects optional metadata enrichment only. Notification targeting is always-on for every valid `agent-turn-complete` callback and does not depend on this token, a marker, or an envelope.

## Preserve the primary process

- Follow the primary process Skill as though this decorator were absent.
- Preserve its terminal verdict vocabulary exactly.
- Do not map, normalize, upgrade, downgrade, or independently assess its verdict.
- Do not add process agents, subagents, handoffs, artifacts, validation, acceptance gates, review logic, or next-step automation.
- Do not change a successful or stopped primary result because notification metadata or delivery failed.

## Append the envelope

After the primary process has produced its final user-facing result, append exactly one `completion-notification` fenced block. Set `observed_status` to the terminal status actually reported by the primary process. Keep the primary response intact before the block.

If the primary process does not expose a terminal status that can be copied without interpretation, omit the envelope. Do not invent a success or failure status. The runtime persists the generic callback-derived Local Spool item instead.

Local Spool persistence happens after the parent turn through the Codex `notify` callback. This Skill never calls a notification provider directly and never waits for persistence before returning the primary result.
