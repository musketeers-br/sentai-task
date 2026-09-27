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

---
