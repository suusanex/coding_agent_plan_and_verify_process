# Completion Notification Decorator usage guide

## Responsibility boundary

The decorator owns only target declaration and envelope authoring. The co-selected primary process owns all implementation, review, routing, artifacts, validation, handoffs, and terminal verdicts. Codex invokes the `notify` callback after the parent turn; the callback runtime owns link resolution, deduplication, provider delivery, delivery status, and fail-open behavior.

One parent turn has exactly one `primary_process`. Internal agents used by that process are not separate primary processes.

## Adaptive Implementation example

```text
$completion-notification-decorator
$adaptive-implementation-execution

このPlanを実装してください。
```

If Adaptive Implementation reports `COMPLETED_BY_HIGH_MODEL`, append:

````markdown
```completion-notification
{"schema_version":1,"primary_process":"adaptive-implementation-execution","observed_status":"COMPLETED_BY_HIGH_MODEL","title":"implementation completed","repository":"owner/repository","result_uri":"https://github.com/owner/repository/pull/123"}
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

On Windows, a valid `result_uri` produces two actions: `結果を開く` opens that resource and `このタスクを開く` opens the callback's Codex task. Without `result_uri`, only the task action is shown. The decorator does not choose or start a counterpart task; review and implementation handoffs carry that link explicitly.

## Fallback and failure

The runtime recognizes `$completion-notification-decorator` in the original input as the target declaration. `[completion-notification]` remains available for callers that cannot preserve the Skill token.

The runtime delivers only a valid terminal `completion-notification` envelope. A selected marker without an envelope is recorded as `awaiting-terminal-envelope` and does not display a notification. An invalid envelope is recorded as `invalid-envelope` and is also suppressed. If delivery fails, the runtime records notification failure while returning exit code 0; the primary result remains unchanged.

## Ambiguous selection

When no primary process or more than one primary process is selected, do not choose or start one on the decorator's behalf. Allow any independently valid work to finish, omit the envelope, and report the metadata ambiguity. No completion notification is delivered without a valid terminal envelope.
