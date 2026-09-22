# Quickstart — Backend ObjectScript

Feature: `003-backend-objectscript` · Date: 2026-09-22

Validates that the backend described in this plan compiles, persists, validates, dispatches, and
allows tracking of a flow end to end against a real IRIS instance — it does not cover the frontend
(`002-canvas-ui`), which has its own quickstart.

## Prerequisites

- IRIS container already running (`docker-compose up -d`), `IRISAPP` namespace already
  provisioned.
- `sentai.*` package compiled in the container (via `zpm "load /home/irisowner/dev/ -v"`, the same
  mechanism `iris.script` already uses for `dc-sample`).
- Valid operator credentials on the instance (the same ones used by the administrative API from
  `001-validate-async-job-contract`).

## Build

```
zpm "load /home/irisowner/dev/ -v"
```

**Expected**: all `sentai.model.*`, `sentai.rest.*`, `sentai.validation.*`, `sentai.dispatch.*`,
`sentai.registry.*`, `sentai.wqm.*`, `sentai.catalog.*` classes compile with no error; the
`/csp/sentai/api/v1` CSP application is registered and requires authentication (`GET /flows`
without a token returns 401).

## Automated tests

```
zpm "test sentai-task -v -only"
```

**Expected**: every `sentai.unittest.*` suite (model, validation, dispatch, rest, registry)
passes — none of them require the real administrative instance (calls to the administrative API
are replaced by a test double, per `research.md` R-012).

## Verify — persistence and validation (P0)

1. `POST /flows` with the canonical five-step graph from `flow-definition.schema.json`.
   **Expected**: 201, `id` and `revision: 1` returned.
2. `GET /flows/{id}` — **Expected**: structure identical to what was submitted.
3. `PUT /flows/{id}` resending the same body plus an edge that would close a cycle.
   **Expected**: 422 with `ValidationReport.errors` citing the cycle; nothing persisted.
4. `POST /flows/{id}/validate`. **Expected**: `errors: []`, `warnings` may contain the
   precondition warning if the test environment has a directory mounted read-only.

## Verify — dispatch and execution (P1)

5. `POST /flows/{id}/dispatch`. **Expected**: 202, `Run` body with `guid`; `GET /runs/{guid}`
   immediately afterward shows all 5 `StepRun`s already carrying `guid` and `timeQueued`.
6. `GET /runs/{guid}/events` (or polling `GET /runs/{guid}` every 3s).
   **Expected**: the three verification steps transition to `running` in parallel; the purge step
   stays `queued` until all three complete.
7. `POST /runs/{guid}/steps/{stepGuid}/pause` on a step **outside** the purge family.
   **Expected**: 409, the step remains `running`.

## Verify — WQM and scheduling (P2)

8. `PUT /wqm/categories/SENTAI.NIGHT` with values violating the nesting invariant.
   **Expected**: 422.
9. `POST /flows/{id}/schedule` with `scheduleSpec`. **Expected**: 201, `taskIds` with one item per
   step, `nextRun` present.

## Teardown

No special action — state remains persisted in the already-existing `IRISAPP_DATA`; to clean up,
`docker-compose down` removes the container (the `./:/home/irisowner/dev` volume preserves the
code, not the IRIS data inside the container).

## What this quickstart does not cover

The task catalog (`/catalog/tasks*`, P3) is reducible and has no dedicated verification step here
— its absence does not invalidate the rest of the quickstart. The real feasibility of keeping the
SSE connection open (R-010, risk #3 in `research.md`) is only confirmed by running step 6 against
the target instance, not by reading this document.
