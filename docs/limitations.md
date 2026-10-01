# SentaiTask — Known limitations (v1), full list

SentaiTask v1 only promises what was proven on IRIS 2026.2 (spec `004-backend-hardening`):

- **Step types not yet proven.** `compact-globals`, `defragment-globals`, `purge-audit-records`
  and the legacy `custom` are still listed in `GET /catalog/step-types` with `available: false`,
  and saved flows that use them still load; validate, dispatch, schedule and rerun refuse them with
  `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`. `compact-globals` (`%SYS.Task.CompactGlobals`) and
  `defragment-globals` (`%SYS.Task.Defragment`) name classes that are not installed on 2026.2; the
  audit purge's class was corrected to the platform's `%SYS.Task.PurgeAudit`. Every other type
  runs: `integrity-check`, `switch-journal`, `purge-task-history`, `storage-headroom-check`,
  `db-size-report` (spec 005, see [Declared step types](../README.md#declared-step-types)) and the
  seven report steps of specs 013 and 020 (see
  [Report steps](../README.md#report-steps-security-web-applications-alerts-secrets)).
- **Operators who validate need `%Admin_Manage:USE` and read on IRISSYS.** Validation reads the
  WQM categories with the operator's token; with less, that read is refused and every step reports
  `CATEGORY_NOT_FOUND` — the message says the category "does not exist" when the platform actually
  refused the read (`%Admin_Operate:USE` alone is refused — spec 005 research R-10). On IRIS 2026.2
  those resources are also enough for the platform to allow the task-history purge (it refuses the journal switch without `%Admin_Operate:USE`) — the
  platform decides, not SentaiTask.
- **Schedules (spec 015).** Times are the instance's local clock. Overlapping runs of the same flow
  are not prevented. The flow list's next run is the platform's value as of the last schedule read
  or change; the schedule dialog always reads it live. A time already past today starts tomorrow.
  Destructive steps cannot be scheduled. The run-as account needs `SentaiSchedule:U`; without it the
  platform refuses the stored password (`ERROR #822`) and the attempt is recorded as a failed run.
- **Run credential.** A dispatched run calls the platform with an access token that expires 60 s
  after it was issued, and refreshing a token revokes the previous one. The canvas therefore asks
  for the password at *Run now*, dispatches under a separate sign-in, and passes that sign-in's
  refresh token (`runCredential`), with which the run renews its own credential until it ends —
  then both are erased. A dispatch **without** `runCredential` (e.g. plain `curl`) keeps the 60 s
  limit: later platform calls fail with 401, stored verbatim as the step's failure reason.
- **Management-API steps take no parameters.** The platform start request carries none, so
  `databaseDirectory` and similar fields do not choose what the platform operates on (they are
  still what the typed confirmation of a destructive step checks). Declared in-process and report
  steps do read their declared parameters.
- **Flows must name an existing WQM category.** Validation refuses an unknown category with
  `CATEGORY_NOT_FOUND`. The default for new flows, `SENTAI.DEFAULT`, does not exist on a stock
  instance, so set a category such as `Default`. Categories are read and edited through the API
  (`/wqm/categories`); the canvas has no category screen yet.
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
  - Types executed through the management API (`integrity-check`) and the report steps
    (`executor: "platform-read"`, specs 013 and 020) run on a target; declared in-process types
    (`switch-journal`, `purge-task-history`, `storage-headroom-check`, `db-size-report`) are
    refused with `STEP_TYPE_NOT_REMOTE_CAPABLE` (they would need SentaiTask installed there).
  - Targets are registered by hand: nothing is discovered from the mirror configuration, and
    nothing is placed by load.
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
- **Token check.** Every product request is first checked with the platform's
  `GET /api/admin/info`: 200 or 403 (an authenticated operator the platform refuses that read)
  pass; anything else is `401 Invalid or expired token`. What the operator may then do is decided
  by the platform at each call, and its refusal is returned verbatim (e.g. 403 with
  `platformStatus` from the catalog, or `SQLCODE -99` when the operator has no SQL privilege on
  the product's tables).
- **Scheduling creates the task through the platform.** `/schedule` creates the flow's one
  native task with `POST /api/admin/v2/task` and the operator's token (the platform accepts
  `%Admin_Task` or `%Admin_Operate`); a refusal is returned verbatim, and the passwords stored for
  that request are removed. The task runs as the schedule's run-as account. Tasks of the spec 001
  form (one per step) are removed on the flow's next schedule or unschedule; they never start a run.
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
- **Overview screen (spec 019).** It is the landing screen for an address that names no screen,
  flow or run. Auto-refresh exists only in the detail views (every 10 s, off by default, paused
  while the tab is hidden); the cards refresh on *Refresh*. A report run from a card is kept in the
  page's memory only and is gone after a reload. The overview is for the primary instance only.
- **Instance overview (spec 018).** Primary instance only: a `target` is refused with
  `OVERVIEW_PRIMARY_ONLY`. The management API reports no host CPU, host memory or console log
  (`messages.log`), so the overview shows instance resources only; a process's *CPU time* is the
  platform's per-process value. The license headline uses `license-usage`'s summary, which disagrees
  with the dashboard's `Licensing` counters at the same moment (measured 1 vs 13 units). Report areas
  show counts in the summary; findings appear only when the report is run. Web session ids, lock
  delete ids and a process's CSP session id are never returned. When the platform refuses with an
  empty status (as it does for a 403 on these reads), the product says `HTTP 403: no reason given`.
  Process actions record the operator, pid, action and the platform's answer; the record is history
  only and never decides a later action.
- **Report steps (spec 013).** Reads are instance-wide: the step's namespace is not used; on a
  target, they read that target's management API. The security report reads the roles of at most 200 enabled accounts (an *info* finding says how
  many were left out). The platform's `SeriousAlerts` counter is what the dashboard reports; on
  IRIS 2026.2 it keeps counting severe `messages.log` entries after `$SYSTEM.Monitor.Clear()`, so an
  instance that raised alerts since it started fails `system-alerts-check` at the default
  threshold 0 until it restarts or the threshold is raised. Reports never correct anything.
- **Security inventory (spec 020).** Certificate validity is what the platform reports for x509
  credentials; the platform reports none for certificate *files* named by SSL/TLS configurations,
  and SentaiTask does not open those files — register such a certificate as an x509 credential to
  have it checked. On an instance without OAuth, `oauth-inventory` completes with the platform's
  `ERROR #8864` text ("not configured"). Grant types are flagged only when the platform reports
  them (client configurations on IRIS 2026.2 did not return `grant_types` in the spike). The
  demo account has no `%Admin_Secure`, so on the public demo the three steps fail with the
  platform's 403. Per-item reads stop at 200 (an *info* finding says how many were not read).
- **Semantic search (spec 017).** The in-process search model loads in one worker process after the
  instance starts; until it is loaded (≈7–11 s measured, research R-2) searches answer `warming`
  and the palette keeps its local filter. The worker is started by the container image and, on any
  other install, by the first search. It serves searches one at a time (≈12 ms each, three
  concurrent callers ≈33 ms each), and holds ≈500 MB. A model that fails to load answers `error`
  until the configuration row changes or the worker is restarted.
- **Run log (spec 012).** Runs dispatched before this version have no log; the run view says so.
  The SSE stream still emits only `step-state-changed` and `run-terminal`: the `log-entry` event of
  spec 003's protocol was never implemented, and the canvas reads the log by polling the run.
  Log times are the primary's, when the product observed the fact.
- **Public demo (spec 011).** The demo account `sentai-demo` holds no security administration,
  so security reads are refused verbatim by design. The privileges an integrity check needs
  (`%Admin_Manage`, write on IRISSYS) also let the platform run the task-history purge and change
  platform settings reachable through the management API, such as WQM categories; on a
  disposable demo this is accepted, and the daily reset does not restore platform settings
  (it resets the product's flows and runs, the demo password and the alert state).

---
