# Completion Notification Decorator usage guide

## Responsibility boundary

The user-level runtime owns always-on callback targeting, callback-derived identity and link resolution, deduplication, Local Spool persistence, and fail-open behavior. The decorator owns only optional envelope authoring. The co-selected primary process owns all implementation, review, routing, artifacts, validation, handoffs, and terminal verdicts.

One parent turn has exactly one `primary_process`. Internal agents used by that process are not separate primary processes.

## Adaptive Implementation example

```text
$completion-notification-decorator
$adaptive-implementation-execution

このPlanを実装してください。
```

If Adaptive Implementation reports `IMPLEMENTATION_COMPLETED`, append:

````markdown
```completion-notification
{"schema_version":1,"primary_process":"adaptive-implementation-execution","observed_status":"IMPLEMENTATION_COMPLETED","title":"implementation completed","repository":"owner/repository","result_uri":"https://github.com/owner/repository/pull/123"}
```
````

If it reports `COMPLETED`, `REPLAN_REQUIRED`, `HUMAN_DECISION_REQUIRED`, or `BLOCKED`, copy that exact terminal status instead. Do not choose a status from the work yourself.

## Plan Coverage example

```text
$completion-notification-decorator
$plan-coverage-residual-flow

このIssueをPlan網羅チェック・残件判定フローで進めてください。
```

Copy the terminal verdict produced by the existing flow, for example `READY_TO_CLOSE_WITH_NO_RESIDUALS`, without changing its coverage, residual, or implementation decisions.

## Metadata rules

- `primary_process`: exactly the explicitly co-selected process Skill name.
- `observed_status`: exact terminal status from that process.
- `repository`: use `owner/name` only when known reliably; otherwise omit it.
- `title`: optional, short, and descriptive. It is not a verdict.
- `result_uri`: optional specific HTTPS resource such as a PR, review, Actions run, or artifact URL. Do not use a host, owner, or repository root.
- `resume_uri`: never author it. The runtime derives it from the callback thread ID.

The Local Spool JSON preserves both `result_uri` and the callback-derived `resume_uri` when available. Presentation, link actions, consumer state, and Inbox processing are outside this producer package. The decorator does not choose or start a counterpart task; review and implementation handoffs carry any later link handling explicitly.

## Fallback and failure

Every valid `agent-turn-complete` callback is a Local Spool candidate. `$completion-notification-decorator`, `[completion-notification]`, and the envelope are not targeting requirements. The runtime writes one 10-field `spool-item-v1` JSON item to its configured local folder; it does not start an Inbox, consumer, toast, or forwarder.

Without an envelope, the runtime persists a generic `TURN_ENDED` spool item. A fully valid envelope enriches process, status, title, repository, and optional result metadata. An invalid envelope, including one with an unsafe or coarse result URI, is ignored as a whole and falls back to the generic spool item. If delivery fails, the runtime records notification failure while returning exit code 0; the primary result remains unchanged.

## Ambiguous selection

When no primary process or more than one primary process is selected, do not choose or start one on the decorator's behalf. Allow any independently valid work to finish, omit the envelope, and report the metadata ambiguity. The always-on generic spool item still applies.
