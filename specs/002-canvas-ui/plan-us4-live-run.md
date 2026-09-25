# Plan: User Story 4 — Live Run (v1 scope)

**Spec**: [spec.md](spec.md) US4, [UI-002](contracts/ui/UI-002-live-run.md) · **Date**: 2026-09-25 ·
**Constraints**: spec 004 (only `integrity-check` runs; scheduling non-operational; 60 s run
credential, E-1)

## What v1 can actually do, measured on the dev instance (2026-09-25)

| Fact | Consequence for this screen |
|---|---|
| `integrity-check` on USER/IRISAPP takes ~51 s | Durations are tens of seconds; show `mm:ss.s`, not a spinner |
| Run credential expires 60 s after dispatch (E-1) | Steps started or still running past ~60 s fail with the platform's `HTTP 401` — shown verbatim. Fixed on the backend so they *fail* instead of staying `running` forever (commit `0d26a2a`) |
| SSE `/runs/{guid}/events` works with `fetch` + Bearer, but the web gateway gzips it and the stream breaks mid-run (`incorrect header check`) | Transport = **polling `GET /runs/{guid}` every 1 s** (NFR-001 ≤ 2 s; sse-protocol.md guarantees equivalence). Backend follow-up: disable gzip on the SSE response |
| Events carry no failure reason, times or log | Detail always comes from `GET /runs/{guid}` anyway |
| Re-run creates a new `StepRun` for the same step | Per step, show the most recent `StepRun` (latest `timeQueued`) |
| Timestamps are `YYYY-MM-DD HH:MM:SS` UTC (matched the `Date` header to the second) | Parse as UTC; browser and container share the host clock, so no skew correction |
| No v1-available type is destructive or pausable (spec 004 D-1) | No typed-confirmation dialog and no per-step *Pause* are built; a 428 is surfaced verbatim if it ever happens |
| Step cancel is not propagated to the platform job (spec 004 F-2) | *Cancel* is offered and labelled as stopping SentaiTask's tracking |
| `RUN LOG` entries are not written by the backend today | Rail shows the log when present, an honest empty state otherwise |

### Found while implementing (2026-09-25)

- **`/api/admin/refresh` revokes the previous access token** (probed: A → 401 right after
  refreshing to B; two independent logins coexist). A run dispatched with the screen's own token
  therefore died at the screen's next proactive refresh — observed at ~45 s, every run. *Run now*
  now asks for the password once and dispatches under a **separate login**, so the run keeps its
  full 60 s whatever the screen refreshes. The password is used for that request only, never kept.
- **A 4xx on a status check left the step `running` forever** (and the run never terminal) —
  fixed on the backend (`0d26a2a`); the step fails with `…returned HTTP 401`, verbatim.
- **A cancelled wave finalized as `completed`** — fixed on the backend: failed > cancelled >
  completed (Constitution IV).
- **GUID abbreviation**: IRIS GUIDs are time-based; steps created together share prefix and tail,
  so nodes show the first group (`2351463B…`), full value on hover and in the rail.

## Design

- **Entry**: *Run now* on the editor top bar → dispatch dialog (password → dedicated login, D-2
  style limitation note) → save if dirty → `POST /flows/{id}/dispatch` (`confirmations: []`) with the
  dedicated token → `index.html?flow=<id>&run=<guid>`. A 422 report lands on the canvas like
  validation.
- **Route**: `?run=<guid>` (with `?flow=`) renders the run view; same page, no router (ServeFiles).
- **Layout (UI-002)**: top bar (mark, state pill `RUN IN PROGRESS`/final state, flow name, short run
  GUID, *Pause wave*, *Cancel wave* with a confirmation naming the run, *Back to flow*); wave
  progress strip (one segment per step in flow order, hazard stripe for failed, running segment
  filled by progress when reported; count line `N completed · N failed · N running · N queued`;
  `ELAPSED`, `START`); read-only canvas of the flow's saved graph with per-node state chip
  (`StateShape`), times, `FAILURE REASON` verbatim + *Re-run step*, running elapsed + *Cancel*,
  queued `waits for #NN`; dashed failure-token edge out of a failed step; `JOIN POLICY` panel when a
  join input failed; right rail `RUN GUIDS`, per-step list, `STATES — SHAPE BEFORE COLOUR`,
  `RUN LOG`.
- **Pure logic** (`src/lib/run/run.ts`, vitest): latest StepRun per step, counts line, timestamp
  parsing, elapsed formatting, segment model, join-policy text.

## Verification

Playwright against the container (`tests/us4-live-run.spec.ts`): dispatch a short fan-in of
`integrity-check` steps from the UI, watch states reach `completed`, all six shapes rendered in the
key, count line format; a run with an unsupported step refused at dispatch; cancel wave with the
confirmation. Evidence `q6-live-run.png`, `q7-step-control.json`.
