# Completion notification envelope authoring contract

Append exactly one fenced JSON object after the unchanged primary-process response:

````markdown
```completion-notification
{"schema_version":1,"primary_process":"adaptive-implementation-execution","observed_status":"COMPLETED_BY_HIGH_MODEL","title":"implementation completed","repository":"owner/repository","result_uri":"https://github.com/owner/repository/pull/123"}
```
````

## Fields

| Field | Requirement |
| --- | --- |
| `schema_version` | Required integer. Use `1`. |
| `primary_process` | Required non-empty string. Copy the one explicitly co-selected primary process Skill name. |
| `observed_status` | Required non-empty string. Copy the primary process terminal status without reinterpretation. |
| `title` | Optional short notification title. |
| `repository` | Optional `owner/name` identifier. Omit when not reliable. |
| `result_uri` | Optional specific HTTPS result URL without userinfo. GitHub owner or repository root URLs are too coarse. |

The runtime generates `resume_uri` from the callback thread ID. Do not author it in the envelope. On Windows, a valid `result_uri` yields both a result action and a current-task action; it does not replace `resume_uri`.

## Failure behavior

- Missing or invalid envelope: the runtime records diagnostic state and suppresses notification delivery. A marker alone is not a terminal result.
- Invalid or coarse `result_uri`: the runtime omits it and retains the generated current-task resume link.
- Provider or runtime failure: the primary process response and terminal status remain authoritative. Notification delivery status is separate observational state.
