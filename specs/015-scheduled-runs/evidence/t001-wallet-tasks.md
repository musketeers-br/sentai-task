# T001 — Wallet and Task Manager spike (2026-09-29, dev stack, IRIS 2026.2)

No secret value, password or token is recorded here. Every object the spike created (wallet
collections and secrets, users, roles, tasks, a spike class) was deleted afterwards.

## R-1 The IRIS Wallet can authenticate the sign-in without the product reading the password

- A collection needs both resources: `%Wallet.Collection.Create(name, .p)` with
  `p("UseResource")` and `p("EditResource")` (without `EditResource`: `ERROR #5659 … required`).
  The API lists them as `"UseResource":"%DB_USER:READ"`, `"EditResource":"%DB_USER:WRITE"`.
- A key-value secret `%Wallet.KeyValue.Create("<Collection>.<name>", .k)` with
  `k("Secret") = {"user": …, "password": …}` (JSON text) and `k("Usage") = "HTTP"`.
- `%Net.HttpRequest.UseSecret("<Collection>.<name>", "basic")` then `Post("/api/admin/login")`:
  the request's `Username`/`Password` are filled inside `%Wallet.KeyValue.ApplyHTTP`, which may
  only be called by `%Net.HttpRequest` itself (`$$$GetLIBCallingRoutine` check) and audits the use
  (`AuditUsage`). **Result: HTTP 200**, and after the call `h.Username` reads empty to the caller.
  → **Plan D-3 takes the preferred path**: the product never holds the run-as password in a
  variable at firing.
- `GET /api/admin/v2/wallet/secrets?collection=` lists `Name` and `Type` only, never the value
  (spec 013 T001).

## R-1.2 The platform restricts use by resource (the security premise — stop condition not hit)

A spike class ran in a JOB that signed in (`$SYSTEM.Security.Login`) as each of two temporary
users, then `UseSecret(…, "basic")` + login:

| Process user | Holds the collection's use resource (`%DB_USER:R`) | Outcome |
|---|---|---|
| `sentai_t015` | no | **`ERROR #822: Access Denied`** — refused by the platform before any request |
| `sentai_t015b` | yes | **HTTP 200** |

So a scheduled task running as an account that may not use the collection is refused by the
platform, and the refusal text (`#822`) is what the start-failure run records.

## R-2 Task Manager timing fields and the platform's next run

Created through `POST /api/admin/v2/task` (StartDate = tomorrow, 2026-09-30, a Wednesday), read
back with `GET /api/admin/v2/task/info?id=` (field `NextScheduled`), then deleted.

| Kind | Fields | `NextScheduled` |
|---|---|---|
| Daily at 03:00 | `TimePeriod: Daily`, `DailyFrequency: Once`, `DailyStartTime: 03:00:00` | 2026-09-30 03:00:00 |
| Weekly Mon + Fri at 22:30 | `TimePeriod: Weekly`, `TimePeriodDay: "26"` | 2026-10-02 22:30:00 (Friday) |
| Monthly on day 1 at 04:00 | `TimePeriod: Monthly`, `TimePeriodDay: "1"` | 2026-10-01 04:00:00 |
| Every 4 hours from 00:00 | `DailyFrequency: Several`, `DailyFrequencyTime: "1"`, `DailyIncrement: 4`, `DailyStartTime: 00:00:00`, `DailyEndTime: 23:59:59` | 2026-09-30 04:00:00 |

- **Weekday digits**: `1` = Sunday … `7` = Saturday (`"26"` = Monday and Friday). The product's
  schedule uses Monday = 1 … Sunday = 7 and converts.
- `DailyFrequencyTime` accepts `"0"`/`"1"` only (`"Hours"` → `ERROR #7205 … VALUELIST ',0,1'`);
  `"1"` with increment 4 gives the same next run as 240 minutes, so `1` = hours.
- `task/info` also returns `Error`, `LastStarted`, `LastFinished` and `Suspended`: the platform's
  own view of the last firing (FR-010's "task history shows the error").
- The scheduled runs start today when `StartDate` is today (the plan's R-2 note).

## R-4 Identity at firing

Not probed separately: a `%SYS.Task` runs `OnTask` as its `RunAsUser`, and WorkMgr workers queued
by the run loop take that identity (spec 005 R-1, proven for manual runs). The acceptance script
checks `executedAs` of an in-process step of a scheduled run.

## Findings of the acceptance runs (2026-09-29, after T001)

- **A collection's resources carry a permission.** Created with a bare resource name, the
  collection stored `UseResource = SentaiSchedule:READ` and `EditResource = SentaiSchedule:WRITE`,
  so a run-as account holding `SentaiSchedule:U` was refused at firing (`ERROR #822`). The
  installer now sets `SentaiSchedule:USE` and `SentaiSchedule:WRITE` explicitly (and corrects an
  existing collection); `%Wallet.Collection.Modify` accepts `:USE`. Run-as accounts need
  `SentaiSchedule:U`, operators who schedule `SentaiSchedule:W`.
- **A start in the past is refused.** `POST /api/admin/v2/task` with today's `StartDate` and a
  `DailyStartTime` already gone today answers `ERROR #7432: Start Date and Time must be after the
  current date and time` (found by e2e us28). The start date is now tomorrow in that case.
- **The task's last error is in `task/info` → `Status`** (its serialized `%Status`); `Error` stays
  empty after an `OnTask` that returned an error status.
