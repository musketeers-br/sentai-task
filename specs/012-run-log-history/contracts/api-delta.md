# API delta: Run Log and Run History

Additive changes to `specs/002-canvas-ui/contracts/openapi.yaml`. Existing clients keep working.

## `GET /runs`

Query parameters:

| Name | Type | Default | Rule | Error |
|---|---|---|---|---|
| `flowId` | string | — | exists today | — |
| `state` | `running \| completed \| failed \| cancelled` | — | new | 400 `STATE_UNKNOWN` |
| `limit` | integer | 50 | 1–200 (contracted before, now implemented) | 400 `LIMIT_OUT_OF_RANGE` |
| `before` | integer | — | new; returns runs with `seq < before` | 400 `CURSOR_INVALID` |

Response `200`: array of `RunSummary`, `seq` descending. Fewer than `limit` items means there is
no next page.

```yaml
RunSummary:
  allOf:
    - $ref: "#/components/schemas/Run"
    - type: object
      properties:
        seq: { type: integer, description: "Stable cursor; pass as `before` for the next page." }
        flowName: { type: string }
        totalDurationMs: { type: integer }
        stepCounts:
          type: object
          properties:
            queued: { type: integer }
            running: { type: integer }
            paused: { type: integer }
            completed: { type: integer }
            failed: { type: integer }
            cancelled: { type: integer }
```

Response `403`: the platform refused the read (`SQLCODE -99`), with its message verbatim in
`detail`.

## `GET /runs/{runGuid}`

Unchanged shape. `log` is now populated (data-model §2), still newest first; ties are ordered by
insertion (newest first).

## SSE (`GET /runs/{guid}/events`)

Unchanged. The stream still emits only `step-state-changed` and `run-terminal`: the
`log-entry` event type described in spec 003's SSE protocol was never implemented, and this
feature does not add it (the canvas polls `GET /runs/{guid}`, which carries the log). Recorded as
a known gap in `docs/limitations.md` (T020).
