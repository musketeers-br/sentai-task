# API delta: Canvas Design Refresh

One additive change to `GET /csp/sentai/api/v1/catalog/tasks` (spec 006). Everything else this
spec reads is an existing route: spec 006/007 catalog, spec 005 step types, and spec 018's
`/overview` routes, consumed as [its contract](https://github.com/musketeers-br/sentai-task/blob/master/specs/018-instance-overview-api/contracts/api-delta.md)
defines them, unchanged.

## `GET /catalog/tasks`

### Query

| Parameter | Values | Default | New |
|---|---|---|---|
| `q`, `namespace`, `filter`, `destructiveOnly` | as spec 006 | — | no |
| `unclassifiedOnly` | `0`, `1`, `true`, `false` | `0` | **yes** |

Any other value of `unclassifiedOnly` → `400` problem
`INVALID_FILTER: unclassifiedOnly must be one of 0, 1, true, false`, no platform call (same rule
and wording pattern as `destructiveOnly`).

### Response `200`

```json
{
  "total": 16,
  "matched": 12,
  "counts": { "suspended": 2, "destructive": 2, "unclassified": 12 },
  "items": [
    { "taskId": 8, "name": "Inventory Scan", "class": "%SYS.Task.InventoryScan",
      "description": "Run a scan of the system inventory on install or upgrade and on demand thereafter",
      "…": "every spec 006 field, unchanged" }
  ]
}
```

- `counts` is computed over all `total` tasks, **before** any filter, so it does not change when a
  filter changes.
- `description` is the platform single read's `Description`, verbatim; absent when that read
  failed or the platform sent an empty string. It is also returned by `GET /catalog/tasks/{taskId}`.
- Refusals are unchanged: a refused list read is the whole answer, verbatim (spec 006).

## `POST /catalog/tasks/{taskId}/suspend`

Unchanged (spec 007). Listed because the canvas now calls it only after a confirmation.

## Canvas addresses (UI contract)

| Address | Shows |
|---|---|
| `/csp/sentai/` | Overview (spec 019 default, unchanged) |
| `?view=overview` | Overview |
| `?view=flows` | Flows, empty or the last-opened flow |
| `?flow=<id>` (no `view`) | Flows with that flow — unchanged, old links keep working |
| `?run=<guid>` (no `view`) | Flows with that run — unchanged |
| `?view=catalog[&task=<id>][&filter=suspended][&unclassifiedOnly=1]` | Task catalog, filter preselected (Overview's "Show in catalog" / "Show them") — **new** |
| `?view=targets`, `?view=runs[&flowId=…]` | unchanged |

## `openapi.yaml`

`specs/002-canvas-ui/contracts/openapi.yaml`: `CatalogPage` gains `counts`, `CatalogTask` gains
`description`, `/catalog/tasks` gains `unclassifiedOnly`.
