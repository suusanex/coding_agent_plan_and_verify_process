# Completion notification envelope authoring contract

Append exactly one fenced JSON object after the unchanged primary-process response:

````markdown
```completion-notification
{"schema_version":1,"primary_process":"adaptive-implementation-execution","observed_status":"IMPLEMENTATION_COMPLETED","title":"implementation completed","repository":"owner/repository","result_uri":"https://github.com/owner/repository/pull/123"}
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

The runtime generates `resume_uri` from the callback thread ID. Do not author it in the envelope. The Local Spool item preserves both `result_uri` and `resume_uri`; presenting links or consuming items is outside this producer contract.

## Failure behavior

- Missing envelope: the runtime persists a generic `TURN_ENDED` Local Spool item with the callback-derived `resume_uri`.
- Invalid envelope, including an invalid or coarse `result_uri`: the runtime ignores all enrichment fields and persists the generic spool item. It never loses the callback identity.
- Provider or runtime failure: the primary process response and terminal status remain authoritative. Notification delivery status is separate observational state.
