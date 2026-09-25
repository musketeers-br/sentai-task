# Quickstart — Backend ObjectScript

> **Superseded for v1** by [`specs/004-backend-hardening/quickstart.md`](../004-backend-hardening/quickstart.md).
> Kept as the T070 record: its canonical flow uses step types that spec 004 blocks.

Feature: `003-backend-objectscript` · Date: 2026-09-22

Validates that the backend described in this plan compiles, persists, validates, dispatches, and
allows tracking of a flow end to end against a real IRIS instance — it does not cover the frontend
(`002-canvas-ui`), which has its own quickstart.

This quickstart also reflects the post-validation scope reduction recorded in `plan.md` and
`HANDOFF.md`: scheduling is supported only for **non-destructive** flows in v1. Any flow containing
one or more destructive steps MUST be refused by `/schedule` with an explicit blocking error, and
MUST NOT create any native `%SYS.Task` entry.

## Prerequisites

- IRIS container already running (`docker-compose up -d`), `IRISAPP` namespace already
  provisioned.
- `sentai.*` package compiled in the container (via `zpm "load /home/irisowner/dev/ -v"`, the same
  mechanism `iris.script` already uses for `dc-sample`).
- Every WQM category the flow's steps name must already exist on the instance (the built-ins are
  `Default`, `SQL`, `Utility`); an unknown category fails the step at enqueue with the platform's
  message. `SENTAI.NIGHT` from the canonical example must be created on the platform first.
- Valid operator credentials on the instance (the same ones used by the administrative API from
  `001-validate-async-job-contract`).
- A clean or known test environment. If this instance was used before the persistence-reference bug
  fix, record and, if appropriate, clean orphaned `flow = 0` artifacts before treating the results
  below as final operational evidence.

## Build

```bash
zpm "load /home/irisowner/dev/ -v"
```

**Expected**: all `sentai.model.*`, `sentai.rest.*`, `sentai.validation.*`, `sentai.dispatch.*`,
`sentai.registry.*`, `sentai.wqm.*`, `sentai.catalog.*` classes compile with no error; the
`/csp/sentai/api/v1` CSP application is registered and requires authentication (`GET /flows`
without a token returns 401).

## Automated tests

```bash
zpm "test sentai-task -v -only"
```

**Expected**: every `sentai.unittest.*` suite (model, validation, dispatch, rest, registry)
passes — none of them require the real administrative instance (calls to the administrative API
are replaced by a test double, per `research.md` R-012).

## Verify — persistence and validation (P0)

1. `POST /flows` with the canonical five-step graph from `flow-definition.schema.json`.
   **Expected**: 201, `id` and `revision: 1` returned.

2. `GET /flows/{id}`.
   **Expected**: structure identical to what was submitted.

3. `PUT /flows/{id}` resending the same body plus an edge that would close a cycle.
   **Expected**: 422 with `ValidationReport.errors` citing the cycle; nothing persisted.

4. `POST /flows/{id}/validate`.
   **Expected**: `errors: []`, `warnings` may contain the precondition warning if the test
   environment has a directory mounted read-only.

## Verify — dispatch and execution (P1)

5. `POST /flows/{id}/dispatch`.
   **Expected**: 202, `Run` body with `guid`; `GET /runs/{guid}` immediately afterward shows all
   5 `StepRun`s already carrying `guid` and `timeQueued`.

6. `GET /runs/{guid}/events` (or polling `GET /runs/{guid}` every 3s).
   **Expected**: the three verification steps transition to `running` in parallel; the purge step
   stays `queued` until all three complete.

7. `POST /runs/{guid}/steps/{stepGuid}/pause` on a step **outside** the purge family.
   **Expected**: 409, the step remains in its current non-paused state.

## Verify — WQM and scheduling (P2)

8. `PUT /wqm/categories/SENTAI.NIGHT` with values violating the nesting invariant.
   **Expected**: 422.

9. `POST /flows/{id}/schedule` using the canonical flow **if it contains a destructive step**.
   **Expected**: 422 `ValidationReport` with one `DESTRUCTIVE_NOT_SCHEDULABLE` error per destructive
   step (naming its `stepId`), clearly stating that destructive flows are not schedulable in v1;
   **no native `%SYS.Task` entry is created** (`SELECT COUNT(*) FROM %SYS.Task WHERE Name
   %STARTSWITH 'SentaiTask: <flowId>#'` returns 0).

10. `POST /flows/{id}/schedule` using a validated **non-destructive** flow.
    **Expected**: 201, `taskIds` with one item per step, `nextRun` present.

## Teardown

No special action is required for persisted flow/run data — state remains in the already-existing
`IRISAPP_DATA`. However:

- if step 10 created native `%SYS.Task` entries, remove them after verification so the instance
  does not retain test scheduling artifacts
- if step 9 was executed, confirm that no `%SYS.Task` entry was created before considering the test
  successful
- if a sanitation procedure was executed for orphaned historical records, preserve the before/after
  evidence and the exact cleanup command or script used

To stop the local container:

```bash
docker-compose down
```

This removes the container; the `./:/home/irisowner/dev` volume preserves the code, not the IRIS
data inside the container.

## What this quickstart does not cover

- The task catalog (`/catalog/tasks*`, P3) is reducible and has no dedicated verification step here
  — its absence does not invalidate the rest of the quickstart.
- The real feasibility of keeping the SSE connection open (R-010, risk #3 in `research.md`) is only
  confirmed by running step 6 against the target instance, not by reading this document.
- The persisted `scheduleSpec` is not yet, by itself, proof that native `%SYS.Task` scheduling
  fields were correctly derived from it; that mapping remains an implementation point to validate
  explicitly.