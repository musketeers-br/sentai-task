# Implementation contract — SSE protocol

Feature: `003-backend-objectscript` · Date: 2026-09-22

`openapi.yaml` already contracts `GET /runs/{runGuid}/events` as `text/event-stream` with the body
typed generically (`type: string`). This file defines the concrete shape of the emitted events —
an implementation detail the REST contract deliberately left open, not a change to it.

## Shape of an event

Each SSE event follows the standard format (`event: <type>\ndata: <json>\n\n`), with `<json>` in
the following format:

```json
{
  "runGuid": "…",
  "eventVersion": 42,
  "type": "step-state-changed | log-entry | run-terminal",
  "at": "2026-09-22T03:14:07Z",
  "step": {
    "stepId": "04",
    "guid": "…",
    "state": "running",
    "progressCurrent": 3,
    "progressTotal": 10
  },
  "log": {
    "stepId": "04",
    "severity": "info",
    "message": "…"
  }
}
```

`step` is present only in `type: step-state-changed` events; `log` only in `type: log-entry`
events. A `type: run-terminal` event carries only `runGuid`, `eventVersion`, `at`, and the run's
final `state` (`completed | failed | cancelled`) — it is always the last event emitted before the
stream closes.

## Guarantees

- `eventVersion` is strictly increasing within a run (`sentai.model.Run.eventVersion`, R-010 in
  `research.md`); a client that reconnects can request everything since the last version seen via
  `?since=<eventVersion>` — but the minimal implementation of this plan does not require support
  for that parameter in v1, only the field on each event so loss can be detected.
- Every event an SSE client would receive is also visible via `GET /runs/{runGuid}` (the same
  persisted state) — the 3s polling fallback never diverges from what the stream would have
  delivered (the guarantee for the corresponding Edge Case in the spec).
- Target latency: up to 2 seconds between the state change occurring and the event being written
  (NFR-001) — the read loop of `sentai.rest.Dispatcher` (R-010) uses a 500ms check interval, five
  times smaller than the budget, to absorb variance without blowing it.

## Stream termination

The stream ends (cleanly closes the HTTP connection) in three situations:

1. The run reaches a terminal state — the server emits the `run-terminal` event and closes.
2. The client disconnects — detected via `%response.IsClientConnected()` on each loop iteration.
3. A maximum connection duration is reached (proposed: 10 minutes) — the server closes without
   error; the client reopens the connection (GET again) or falls back to the 3s polling. This
   limit exists so as not to hold an IRIS process indefinitely for a forgotten open browser tab —
   it is not a spec requirement, it is an operational safeguard of this plan, flagged here so that
   `tasks.md` makes it configurable rather than fixed in code.
