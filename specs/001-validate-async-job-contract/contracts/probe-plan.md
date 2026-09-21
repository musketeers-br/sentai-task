# Contract: Probe Plan — the eleven ordered calls

**Feature**: 001-validate-async-job-contract
**Consumed by**: `scripts/validate-async-job-contract/run-spike.sh`

The eleven calls below MUST execute in the numbered order. Each call
produces exactly one evidence file (call 7 and call 8 produce three each,
one per sub-step; call 11 is an analysis over prior evidence).

The probe set is closed (Constitution Principle II). Adding a call means
extending this document; the script MUST NOT construct call paths from
input.

---
## 0. Get system info

- **Method / path**: `GET /api/admin/info`
- **Purpose**: Capture platform version, validate administrative privileges early, and capture the `privileges` map. Executed immediately after authentication (Call 1).
- **Captures**: `evidence/00-info.json`.
- **Records into script state**: platform version string (to populate `platform.version` on all envelopes).
- **Answers**: Q1 (version, and auth validation).


## 1. Authenticate

- **Method / path**: `POST /api/admin/login`
- **Purpose**: Establish an authenticated session; capture the response
  envelope and identify the session token field.
- **Body**: `{ "username": "<IRIS_USER>", "password": "<IRIS_PASSWORD>" }`
- **Captures**: `evidence/01-login.json`.
- **Records into script state**: session token (redacted before capture).
- **Answers**: Q1.

## 2. Refresh the session

- **Method / path**: `POST /api/admin/refresh`
- **Purpose**: Capture the session-renewal envelope.
- **Body**: whatever the platform's published contract specifies for
  refresh. If the platform accepts an empty body, send `{}`.
- **Captures**: `evidence/02-refresh.json`.
- **Records into script state**: new session token, replacing the old.
- **Answers**: Q1 (renewal mechanism).

## 3. List scheduled tasks

- **Method / path**: `GET /api/admin/v2/tasks`
- **Purpose**: Capture the list-shape envelope.
- **Captures**: `evidence/03-tasks-list.json`.
- **Records into script state**: an identifier of one task, taken from
  the first element of whichever array the response nests it under. That
  identifier feeds calls 4 and 5.
- **Answers**: Q2 (list read).

## 4. Read a single task

- **Method / path**: `GET /api/admin/v2/task?id={id}`
- **Purpose**: Capture the single-task read shape.
- **Query**: `id` = the identifier extracted in call 3.
- **Captures**: `evidence/04-task-single.json`.
- **Answers**: Q2 (single read).

## 5. Read a task's non-configurable info

- **Method / path**: `GET /api/admin/v2/task/info?id={id}`
- **Purpose**: Capture the info-shape envelope; identify which fields the
  info read carries that the single-task read does not.
- **Query**: `id` = the identifier extracted in call 3.
- **Captures**: `evidence/05-task-info.json`.
- **Answers**: Q2 (info read).

## 6. Start a long-running operation

- **Method / path**: `POST /api/admin/v2/database-dir/integrity-check`
- **Purpose**: Determine whether the platform returns an
  accepted-for-processing response with a job identifier, or completes
  synchronously.
- **Body**: minimal integrity-check request per the published contract.
  Target a directory that is safe on a fresh Community instance
  (typically the platform's own IRIS system database directory).
- **Captures**: `evidence/06-integrity-check-start.json` — includes the
  HTTP status code prominently (`202`/`200`/other tells the story).
- **Records into script state**: job identifier, if one was returned.
- **Answers**: Q3.

## 7. Observe the job

Three captures, in order, of `GET /api/admin/v2/async-result` (with the
job identifier from call 6, in the query string or a header per the
published contract). Polled at **1 s** intervals with a **120 s** ceiling
(both values are recorded in the compatibility statement).

- **7a — first**: the very first response. `evidence/07a-async-result-first.json`.
- **7b — mid-flight**: the first response after the first that reports
  the job as not yet settled and differs from 7a; if every response
  before settle is identical, the last non-settled response is captured
  here. `evidence/07b-async-result-midflight.json`.
- **7c — settled**: the first response reporting a terminal state, or —
  if the ceiling is hit — the last response captured before the ceiling.
  A ceiling hit is recorded in the compatibility statement as an
  open-risk-adjacent note. `evidence/07c-async-result-settled.json`.

**Answers**: Q4 (state, failure reason, timings).

**Note on failure reason**: If call 6 returns a job that settles as
success, the compatibility statement records that the failure-reason
field cannot be observed and states this as an open item for a future
spike, not as a spike-closing negative.

## 8. Job transitions

Three captures, in order, pointing to a dedicated job started specifically
for these transitions. To avoid a race condition with Call 6's natural
completion, the script ALWAYS starts a fresh `POST /api/admin/v2/database-dir/compact`
job and records this substitution in the compatibility statement.

- **8a — pause**: `POST /api/admin/v2/async-result/pause`. Captures
  `evidence/08a-async-result-pause.json` and one status read after.
- **8b — resume**: `POST /api/admin/v2/async-result/resume`. Captures
  `evidence/08b-async-result-resume.json` and one status read after.
- **8c — cancel**: `POST /api/admin/v2/async-result/cancel`. Captures
  `evidence/08c-async-result-cancel.json` and one status read after.

Each capture records the transition's response body and the immediate
post-transition state observed in a follow-up status read (nested inside
the same evidence file's `notes` array, or in the response body if the
platform returns it directly).

If the platform returns a "not supported" response for any of the three
(any 4xx or documented 501), the evidence file captures that response
verbatim and the compatibility statement records the transition as
unsupported.

**Answers**: Q4 (cancel, pause, resume).

## 9. Read worker-capacity categories

- **Method / path**: `GET /api/admin/v2/wqm-categories`
- **Purpose**: Capture the read shape.
- **Captures**: `evidence/09-wqm-categories.json`.
- **Records into script state**: one category name and its current value,
  for use in call 10.
- **Answers**: Q5 (readable).

## 10. Write a worker-capacity category and read it back

- **Method / path**: `PUT /api/admin/v2/wqm-category`
- **Purpose**: Write one value; then re-read the category list and
  confirm the write took effect.
- **Body**: category name from call 9, with a value that is legal per the
  published contract and *differs from the value read in call 9*, so the
  read-back can distinguish "took effect" from "no change".
- **Captures**: `evidence/10a-wqm-category-write.json` (the write) and
  `evidence/10b-wqm-categories-verify.json` (the read-back list).
- **Cleanup**: after read-back, the script issues one more `PUT` to
  restore the original value, and records it in the compatibility
  statement (not as an evidence file — the restore is a housekeeping
  step, not part of the contract capture).
- **Answers**: Q5 (writable, reads back changed).

## 11. Chaining-identifier analysis

- **Not a network call.** A `jq` analysis over `03-tasks-list.json`,
  `04-task-single.json`, and `05-task-info.json`, augmented by manual
  verification results (POST /v2/task with all 31 fields, GET /v2/task
  for created tasks, task 7 RunAfterGUID confirmation).
- **Purpose**: Determine whether the API exposes enough information to
  close the create→read→GUID cycle required for task chaining: after
  creating task A, can the app obtain A's GUID to write into task B's
  `RunAfterGUID`?
- **Captures**: `evidence/11-chaining-probe.json`. The file records:
  - `found: false` — the task's own GUID is not exposed by any read.
  - `predecessor_write_field`: `RunAfterGUID` exists on single-task read
    and is confirmed populated on pre-existing chained tasks (task 7).
  - `own_guid_exposure`: none of POST, GET single, GET list, or GET info
    expose the task's own GUID.
  - `post_v2_task_deviation`: POST requires all 31 fields (no defaults).
  - `manual_verification`: task 7 carries `RunAfterGUID=511A7F43-...`
    (task 1's GUID), confirming the field is functional for system tasks.
  - `conclusion`: chaining via the SysAdmin REST API alone is not
    possible for app-created tasks. Deferred from MVP.
- **Answers**: Q6 (partially — the write mechanism exists but the
  create→read→GUID cycle cannot close).

---

## Ordering constraints

- Call 1 blocks every subsequent call.
- Calls 3 → 4, 5 (single-task id feeds both).
- Call 6 → 7, 8 (job id feeds both).
- Call 9 → 10 (category name and value feed the write).
- Call 11 depends on 3, 4, 5 having been captured.

Reads that do not depend on earlier state (2 after 1) MAY be executed
concurrently in future revisions of this contract, but the initial
implementation MUST run them sequentially so a single-file failure is
attributable.

## What this document does not decide

- The exact request body of `/api/admin/v2/database-dir/integrity-check`
  (the published contract is authoritative). The script uses the smallest
  legal body it can construct.
- The exact response fields the platform will actually return. Those are
  the discovery this spike commits.
