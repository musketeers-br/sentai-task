# Phase 1 — Data model (Tracer Bullet slice)

Feature: `002-canvas-ui` · Plan slice: **Tracer Bullet** · Date: 2026-09-21

This file documents only the data this plan's slice touches: a hardcoded, compiled-in fixture
of 3 nodes and 1 edge, rendered with no backend call and no persistence. It is **not** a
replacement for [`contracts/data-model.md`](contracts/data-model.md), which remains the
authoritative entity model (`Flow`, `Step`, `Edge`, `Join`, `Run`, `StepRun`, `WQM category`,
the `^SentaiRun` registry) for every phase after this one. None of those entities are
constructed, persisted, or read by this plan.

---

## `TracerNode` (fixture only — not `SENTAI.Model.Step`)

| Field | Type | Notes |
|---|---|---|
| `id` | `string` | `"01"`, `"02"`, `"03"` — rendered as `#01`, `#02`, `#03`, matching UI-001's id format |
| `title` | `string` | Step name, e.g. `Integrity check — USER` |
| `category` | `"verification" \| "storage" \| "journal" \| "purge" \| "backup" \| "custom"` | Selects the left-border colour from [`tokens.json`](contracts/tokens.json) `category.*`; no other anatomy field is rendered this phase |

**Rules**

- Exactly 3 `TracerNode` entries exist, compiled into the bundle. The count is fixed by this
  plan's scope, not configurable.
- No field beyond `id`, `title`, `category` is read by the tracer-bullet's node component. The
  hazard band, namespace chip, database directory, timeout, WQM category, and handles from
  UI-001's full node anatomy (FR-006, FR-007) are deferred — see `research.md` §Deferred.

## `TracerEdge` (fixture only — not `SENTAI.Model.Edge`)

| Field | Type | Notes |
|---|---|---|
| `source` | `string` | A `TracerNode.id` |
| `target` | `string` | A `TracerNode.id` |

**Rules**

- Exactly 1 `TracerEdge` exists. It renders as a sequence edge only (`edge.sequence` token,
  1.5px, arrowhead) — no fan-in, no join diamond, since a fan-in requires ≥2 incoming edges on
  one target and this fixture has only one edge total.
- The edge is not user-created and cannot be deleted; there is no edge-drawing interaction in
  this phase (FR-002, FR-003 deferred).

## What is explicitly absent from this model

- No `Flow`, `Run`, `StepRun`, `Join`, or `WQM category` record exists anywhere in this phase —
  neither as an IRIS class instance nor as a client-side store.
- No field is mutable. There is no inspector, no edit, no save.
- No identifier here is a GUID from `$SYSTEM.Util.CreateGUID()`; `TracerNode.id` is a fixture
  literal, not a value the `^SentaiRun` registry would recognise.
