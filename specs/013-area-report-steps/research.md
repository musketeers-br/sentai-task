# Research: Area Report Steps

Probed on the dev stack (IRIS 2026.2 community) on 2026-09-28 with `_SYSTEM`. Scripts are kept in
the session scratchpad; the answers below are summarised, and T001 records them as evidence.

## R-1 The management API has the reads (dispatch class `%Api.Admin`, v2 URL map)

| Area | Call | Answer (200 unless noted) |
|---|---|---|
| Users | `GET /api/admin/v2/security/users` | `result: [{Name, FullName, Namespace, Routine, Type, Enabled}]` (no roles) |
| One user | `GET …/security/user?name=SuperUser` | `result: {Enabled, Roles: ["%All"], EscalationRoles, AccountNeverExpires, PasswordNeverExpires, ChangePassword, ExpirationDate, …}` (no password or hash) |
| Services | `GET …/security/services` | `result: [{Name, Enabled, Public, AuthenticationMethods: ["Password", "Unauthenticated", …], AllowedConnections, TwoFactorEnabled, …}]` |
| Audit | `GET …/security/audit/enabled` | `result: {Enabled: true}` |
| Web apps | `GET …/web-apps` | `result: [{Name, Namespace, Enabled, Type: "CSP" \| "System,CSP", Resource, AuthenticationMethods, IsSystemApp, DispatchClass}]` |
| Dashboard | `GET …/monitor/dashboard/main` | `result: {Performance, ECP, Status: {UpTime, LastBackup, SystemMonitor}, SystemUsage: {DatabaseSpace: "Normal", DatabaseJournal, JournalSpace, LockTable, WriteDaemon, JournalEntries, Processes, CSPSessions, BusyProcesses: […]}, Alerts: {SeriousAlerts: 179, ApplicationErrors: 0}, Licensing: {LicenseLimit, LicenseUse, LicenseUseHigh}, UpcomingTasks}` |
| Wallet | `GET …/wallet/collections` | `result: []` on the dev instance |
| Secrets | `GET …/wallet/secrets` | 400 `ERROR #40300: Query parameter 'collection' is required.`; with `?collection=` → to record in T001 |

All answers use the envelope `{status: {errors, summary}, console, result}`. A refusal is expected
to be 403 with `status.summary`, which the step reports verbatim, as the existing platform steps
do (`Administrative endpoint … returned HTTP 403: <summary>`).

**Observations that shape the rules**:
- Services that accept `Unauthenticated` on the dev instance: `%Service_Weblink` (disabled). The
  rule counts only **enabled** services.
- Web applications accepting `Unauthenticated`, enabled and **not** system: `/api/monitor`
  (REST, `%Api.Monitor`, no resource: by design for metrics scraping), `/csp/sentai` (our canvas:
  static files, no dispatch class), `/csp/user`, `/ui/interop`. The report will list our own
  canvas as a *medium* finding. That is truthful, and the README explains why it is public
  (spec 010 decision).
- The system flag: `Type` contains `System` for `/csp/sys*`, `/csp/broker` and `/csp/documatic`.
  `IsSystemApp` was `false` for all of them in the probe, so the rule uses
  `IsSystemApp OR Type contains "System"`.

## R-2 Privileges each read needs (to record in T001)

Not guessed here (Constitution III): T001 runs each read as `_SYSTEM`, as an operator with
`%Admin_Manage`/`%Admin_Operate` only, and as the spec 011 demo role, and records the answer of
each. The README lists the observed requirement per type as information, not enforcement.

## R-3 Bounding the number of reads

- The security report needs one read per enabled user to get roles. It caps the per-user reads at
  **200** enabled users, in name order. Beyond that it records `itemsOmitted` and an *info*
  finding "roles of n accounts not read (cap 200)". Result size (8,000 characters) is the other
  bound. Findings are protected from truncation (plan D-3).

## R-4 What "serious alerts" counts (to establish in T001)

- The dev instance reports `SeriousAlerts: 179` after two days of tests and cancels, while
  `$SYSTEM.Monitor.State()` was back to normal after `Monitor.Clear()`. So the counter is probably
  the number of severity ≥ 2 entries in `messages.log` since startup, and not reset by `Clear()`.
- **T001 must determine**: (a) whether `Monitor.Clear()` resets `SeriousAlerts`; (b) whether an
  instance restart does; (c) whether the dashboard exposes the alert **state**
  (`Status.SystemMonitor` was `false` while the state was normal).
- **Decision after T001**: if the counter only grows until restart, `maxSeriousAlerts` stays
  (default 0), and the type's description says it counts alerts since the instance started. The
  demo reset (spec 011) and the README then say that a restart clears it. If an alert-state field
  exists, the check uses it in addition, as the primary rule.

## R-5 Wallet shapes (to record in T001)

- Create a collection `SentaiT001` with one secret through the management API
  (`PUT /wallet/collection`, `PUT /wallet/secret`), read `GET /wallet/collections` and
  `GET /wallet/secrets?collection=SentaiT001`, record the field names (to fill the allow-list of
  plan D-5), check whether any answer carries the value, then delete both.
- The collection's resource fields (use/edit) are expected by analogy with `%Wallet.Collection`
  (`UseResource`, `EditResource`); confirm.

## R-6 Reuse of the in-process lifecycle

- `StartInProcessStep` sets `running` under the lock, queues a detached WorkMgr job in the step's
  category, and the worker writes the terminal state with `TransitionLocked` (the loser of a race
  with cancel or timeout records nothing). `SweepTimeouts` ends overdue in-process and remote
  steps. `platform-read` joins that set by changing the condition from "in-process" to "not
  platform-api".
- A remote `platform-read` step keeps `targetBaseUrl` frozen at dispatch (spec 008 FR-018), as
  remote platform steps do.
