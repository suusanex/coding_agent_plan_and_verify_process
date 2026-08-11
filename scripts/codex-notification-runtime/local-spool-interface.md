# Local Spool producer/consumer interface

## Purpose and scope

This document is the interface contract between the Codex completion callback producer and a component that reads the local queue. The producer writes one completed callback as one `spool-item-v1` JSON file. A consumer may watch or periodically scan the folder with an ordinary filesystem API or editor.

This release provides the producer side only. It does not provide an Inbox, consumer worker, user interface, notification delivery, acknowledgement store, search index, forwarding, or retention policy.

## Agent Execution Broker terminal event v1

`agent-execution-terminal-v1` は `spool-item-v1` と並存するBroker専用terminal eventである。既存のCodex callback producerは `spool-item-v1` を継続して使用し、Broker eventをそのsourceやURIへ偽装してはならない。

- schema: `agent-execution-terminal-v1.schema.json`
- source: `agent-execution-broker.run-terminal`
- identity: `agent-execution-broker:run:<run-id>:terminal`
- locator: `broker-run:<run-id>`。URIではなく、Inboxでの表示・コピーだけを許可する。
- publication: producerは同じspool directory内へtemporary fileを書き、final `.json` へatomic moveする。一runにつきterminal eventは一つだけである。

## Spool folder

The default folder is:

```text
%LOCALAPPDATA%\CodexNotificationRuntime\spool
```

Set `CODEX_NOTIFICATION_SPOOL_HOME` to an absolute path to use another folder. The producer creates the folder when it needs to write an item. A consumer should use the same resolved path and should not infer a different location from the runtime installation folder.

The folder is a filesystem queue, not a database. The producer does not create a lock file, acknowledgement file, index, or cursor file for consumers.

## File visibility and filename

Only files whose names end in `.json` are completed spool items. A completed filename has this shape:

```text
<occurred-at-utc>__<observed-status>__<repository>__<source-event-hash-prefix>.json
```

For example:

```text
20260802T051530.1234567Z__completed__owner-repository__4c4f4e9b5f3e6a12.json
```

The timestamp is UTC. Status and repository are normalized for a safe filename. The hash is derived from `source_event_id`; its prefix is normally 16 hexadecimal characters and may be extended when a filename collision must be disambiguated.

The producer writes a temporary file in the same folder, flushes it to disk, and atomically moves it to the final `.json` name. Temporary names are implementation details and may look like `.<final-name>.<random>.tmp`. Consumers must ignore every non-`.json` file and must never parse a temporary file as an item.

## Completed item schema

Each final file is UTF-8 JSON with one object and a trailing newline. The object has exactly these ten fields. `spool-item-v1.schema.json` is the machine-readable schema and is the authority for types and required fields.

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | integer, always `1` | Version of this persisted item contract. |
| `source` | string | Producer source; currently `codex.agent-turn-complete`. |
| `source_event_id` | string | Stable callback identity, currently `codex:<thread-id>:<turn-id>`. |
| `primary_process` | non-empty string | Process name associated with the callback; generic callbacks use `codex`. |
| `observed_status` | non-empty string | Status observed from the callback or a valid completion envelope. |
| `occurred_at` | RFC 3339 date-time string | UTC time assigned by the producer when it creates the candidate. |
| `title` | non-empty string | Human-readable title for the item. Treat it as untrusted display data. |
| `repository` | non-empty string | Repository identity resolved by the producer or supplied by a valid envelope. |
| `resume_uri` | string | Callback-derived `codex://threads/<thread-id>` URI. |
| `result_uri` | string or `null` | Optional specific HTTPS result resource. `null` means no result link was supplied. |

Example:

```json
{
  "schema_version": 1,
  "source": "codex.agent-turn-complete",
  "source_event_id": "codex:thread-123:turn-456",
  "primary_process": "codex",
  "observed_status": "TURN_ENDED",
  "occurred_at": "2026-08-02T05:15:30.1234567Z",
  "title": "owner/repository · codex · Codex turn completed",
  "repository": "owner/repository",
  "resume_uri": "codex://threads/thread-123",
  "result_uri": null
}
```

`notification_status` is deliberately not part of the final ten-field item. It is transient producer state and must not be required by a consumer reading completed files.

## Producer guarantees

The producer guarantees the following behavior for valid callback input:

1. A completed item is published as a single final `.json` file; a partially written JSON document is never published under a final filename.
2. Repeated callbacks with the same `source_event_id` converge to one persisted item. Concurrent attempts are serialized for the event identity, and a different event identity is not silently replaced by an existing item.
3. The final item uses UTC time, the ten fields above, and schema version `1`.
4. `resume_uri` is derived from the callback thread ID. An envelope cannot replace callback identity.
5. `result_uri` is either `null` or a specific HTTPS URL accepted by the producer. Generic, coarse, unsafe, or invalid envelope data falls back to a generic item.
6. Provider, filesystem, and timeout failures are fail-open for the Codex callback. The callback returns without changing the primary process result. A failed attempt may therefore produce no final `.json` file and may be retried by the producer.
7. The producer does not promise ordering by callback completion, filename enumeration order, or `occurred_at`. Consumers must apply their own ordering if required.

These guarantees apply to the producer artifact only. They do not guarantee that a consumer has read, displayed, acknowledged, or retained an item.

## Consumer responsibilities

A consumer or Inbox implementation is responsible for all behavior after a final `.json` file becomes visible.

### Discovery and safe reading

- Resolve the configured folder and watch it or poll it as appropriate for the host application.
- Enumerate only `*.json` files. Ignore `.tmp`, `.claim`, logs, unknown extensions, and other implementation files.
- Read after the final rename is observed. If a file is temporarily unavailable or malformed because of an external filesystem issue, retry or quarantine it according to the consumer's policy; do not rewrite it in place.
- Validate `schema_version` and the ten-field schema. A consumer should define an explicit policy for a future schema version rather than silently treating it as version 1.

### Idempotency and state

- Use `source_event_id` as the logical event identity and make processing idempotent. Filename equality alone is not the identity contract.
- Keep read, acknowledgement, display, retry, and error state outside the producer's JSON files. The producer does not maintain these states.
- Do not add fields to, rewrite, or rename a completed producer file. If a consumer needs an enriched representation, store a separate record keyed by `source_event_id`.

### Retention and cleanup

- Decide and implement retention, deletion, archival, backup, disk quota, and privacy handling. The producer does not delete completed spool items and does not define a TTL.
- Deleting or moving a `.json` file is a consumer/operator action. Coordinate that policy with any other consumer because the folder has no acknowledgement or lease protocol.
- Temporary files are not queue items. A consumer may ignore them permanently; any stale temporary-file cleanup must be conservative and owned by the component that can distinguish an abandoned write from an active producer.

### Presentation and downstream actions

- Treat `title`, `repository`, `observed_status`, and all URI values as untrusted data. Do not execute them as commands or assume that a URI is safe to open without the consumer's own policy.
- Decide how to present `result_uri` and `resume_uri`, including whether to show one, both, or neither.
- Implement Inbox grouping, notification delivery, search, forwarding, and user actions if those behaviors are required. None of them are implied by the presence of a spool file.

## Compatibility and evolution

`schema_version: 1` and the ten-field shape are the current contract. Consumers should preserve or quarantine files they cannot understand rather than deleting them as a side effect of an unsupported version. A future producer version may publish a new schema and corresponding documentation; it must not be inferred from filename formatting alone.

The producer/consumer boundary is therefore:

```text
Codex callback -> validate/normalize -> atomic final JSON in Spool folder | consumer-owned state, retention, Inbox, and presentation
```
