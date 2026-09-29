# SentaiTask — Known limitations (v1), full list

SentaiTask v1 only promises what was proven on IRIS 2026.2 (spec `004-backend-hardening`):

- **Available step types:** `integrity-check`, `switch-journal`, `storage-headroom-check`,
  `db-size-report` and `purge-task-history` (spec `005-declared-custom-steps`, see
  [Declared step types](../README.md#declared-step-types)). The others (`compact-globals`,
  `defragment-globals`, `purge-audit-records`, `custom`) are still listed in `GET /catalog/step-types` with
  `available: false`, and saved flows that use them still load. Validate, dispatch, schedule and
  rerun refuse them with `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`.
- **Operators who validate need `%Admin_Manage:USE` and read on IRISSYS.** Validation reads the
  WQM categories with the operator's token; with less, that read is refused and every step reports
  `CATEGORY_NOT_FOUND`. On IRIS 2026.2 those resources are also enough for the platform to allow
  the task-history purge (it refuses the journal switch without `%Admin_Operate:USE`) — the
  platform decides, not SentaiTask.
- **Scheduling is not operational.** `/schedule` validates the flow and registers native tasks
  (through the platform, see below), but scheduled runs cannot authenticate to the platform in v1 and are not a supported execution
  path. Use manual dispatch.
- **Run credential.** A dispatched run calls the platform with an access token that expires 60 s
  after it was issued, and refreshing a token revokes the previous one. The canvas therefore asks
  for the password at *Run now*, dispatches under a separate sign-in, and passes that sign-in's
  refresh token (`runCredential`), with which the run renews its own credential until it ends —
  then both are erased. A dispatch **without** `runCredential` (e.g. plain `curl`) keeps the 60 s
  limit: later platform calls fail with 401, stored verbatim as the step's failure reason.
- **Step parameters are not forwarded.** The platform start request carries no parameters, so
  `databaseDirectory` and similar fields do not choose what the platform operates on.
- **Flows must name an existing WQM category.** Validation refuses an unknown category with
  `CATEGORY_NOT_FOUND`. The default for new flows, `SENTAI.DEFAULT`, does not exist on a stock
  instance, so set a category such as `Default`.
- **Destructive steps need a typed confirmation; nothing is pausable.** `purge-task-history` is
  the one available destructive type: dispatch refuses it (428) until the operator types its
  database directory or namespace, which the canvas asks for at *Run now* (spec 007 T009). No
  v1-available type is pausable, so pause is implemented but cannot be reached over HTTP.
- <a id="cancel-alert"></a>**Cancelling a running platform job raises an IRIS alert.** Cancel is forwarded to the platform
  (`POST /api/admin/v2/async-result/cancel?id=`), which ends the job's Work Queue Manager worker;
  IRIS 2026.2 logs that as `ERROR #7802: Worker job/s '…' unexpectedly shut down` at severity 2,
  so the instance enters the *alert* state and the container's healthcheck reports `unhealthy`.
  The run and the platform are fine. Reproduced on a plain IRIS without SentaiTask (spec 008 T001,
  `iris-target`, 2026-09-27 09:57:50). Clear it with `do $SYSTEM.Monitor.Clear()` in `%SYS`.
  Since spec 011, the canvas says so before such a cancel (*Cancel wave* and a running
  management-API step's *Cancel* ask first); in-process and queued steps cancel without it.
- **Remote steps (spec 008, DPI-I-588).**
  - Only types executed through the management API can run on a target in v1 (`integrity-check`);
    declared in-process types are refused with `STEP_TYPE_NOT_REMOTE_CAPABLE` (they would need
    SentaiTask installed on the target).
  - A target must be `https://host:port` (TLS client configuration `SentaiTargets`, peer verified
    against the system CA bundle). `http` is accepted only for loopback targets, or when
    `^sentai("config","allowInsecureTargets")` is set — the demo image sets it for its compose
    network only; remove it anywhere else.
  - The operator needs an account of the **same user name** on each target; the target decides
    what it may do there.
  - The target status reports categories as the platform does: worker configuration, no queue
    length (the management API has none).
  - `/validate` checks a target's answers only when given a credential for it; otherwise it warns
    `TARGET_NOT_VERIFIED`. Dispatch always checks.
  - A target that does not answer is left alone for 30 s after each failed attempt, but each
    attempt still waits up to about 15 s (connection timeout). While it is down, the run's other
    steps advance more slowly and the remote step's timeout fires late: in the acceptance run a
    1-minute timeout failed the step about 2.5 minutes after it.
- **Step-type classes that do not exist on 2026.2.** `compact-globals` (`%SYS.Task.CompactGlobals`)
  and `defragment-globals` (`%SYS.Task.Defragment`) name classes that are not installed. They are
  unavailable anyway. The audit purge's class was corrected to the platform's
  `%SYS.Task.PurgeAudit`; it is still unavailable.
- **Token check.** Every product request is first checked with the platform's
  `GET /api/admin/info`: 200 or 403 (an authenticated operator the platform refuses that read)
  pass; anything else is `401 Invalid or expired token`. What the operator may then do is decided
  by the platform at each call, and its refusal is returned verbatim (e.g. 403 with
  `platformStatus` from the catalog, or `SQLCODE -99` when the operator has no SQL privilege on
  the product's tables).
- **Scheduling creates tasks through the platform.** `/schedule` creates each native task with
  `POST /api/admin/v2/task` and the operator's token (the platform accepts `%Admin_Task` or
  `%Admin_Operate`); a refusal is returned verbatim and tasks already created by the same request
  are deleted. The task runs as the operator who scheduled it.
- **A refused WQM category read is reported as `CATEGORY_NOT_FOUND`.** Validation says the
  category "does not exist" when the platform actually refused the read (operator without
  `%Admin_Manage:USE` and read on IRISSYS; `%Admin_Operate:USE` alone is refused — spec 005
  research R-10). Not changed yet.
- **Task catalog.** The list reads each task (two platform calls per task): 151 tasks take about
  0.4 s on the dev container. A task deleted between the list and its reads shows up with
  `unavailable` entries instead of values.
- **Sign-in across reloads (spec 010).** Only the refresh token is kept, per browser tab, in
  `sessionStorage` (with a flag saying whether a page of the tab is using it). It ends when the tab
  closes and is erased at sign-out and whenever renewing it fails. No password, access token, user
  name, role or permission is stored. A reload redeems it for up to 900 s after the last renewal
  (the platform's refresh lifetime); after that, or after an IRIS restart, the canvas says
  "Your session ended — sign in again." and, once signed in, returns to the screen, flow and run
  in the address. A **duplicated tab** starts with a copy of the original's token: it never uses
  the copy (replaying a rotated token makes the platform revoke the original's sign-in) and asks
  for its own sign-in. **After a browser crash, a killed renderer or a browser quit**, the tab has
  no chance to hand its token over, so the restored tab asks to sign in again — the safe failure.
  The separate sign-in asked at *Run now* is unchanged and never kept.
- **Example flow (spec 010).** *Example: storage health check* runs `storage-headroom-check` and
  `db-size-report` in parallel, read-only. `storage-headroom-check` fails by design when any
  database or journal directory has less than 10% free; that run is a real finding, not a defect.
  The example is identified by its name: renaming it and choosing *Open example flow* again creates
  a new one under the well-known name.
- **Public demo (spec 011).** The demo account `sentai-demo` holds no security administration,
  so security reads are refused verbatim by design. The privileges an integrity check needs
  (`%Admin_Manage`, write on IRISSYS) also let the platform run the task-history purge and change
  platform settings reachable through the management API, such as WQM categories; on a
  disposable demo this is accepted, and the daily reset does not restore platform settings
  (it resets the product's flows and runs, the demo password and the alert state).
- **Found by the spec 011 spike, being fixed (spec 011 T025).** A platform SQL refusal while
  reading a flow's steps is treated as "no steps" (validation passes, dispatch creates a run that
  never ends), and a platform job that ends `Failed` shows "Administrative job reported Failed"
  instead of the platform's own reason.

---
