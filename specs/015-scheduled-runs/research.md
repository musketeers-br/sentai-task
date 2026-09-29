# Research: Scheduled Runs That Execute

## R-0 What happens today (code read, 2026-09-28)

- `POST /flows/{id}/schedule` → `FlowValidator.ValidateForSchedule` (refuses destructive and
  in-process steps) → `NativeScheduler.Schedule`: one `POST /api/admin/v2/task` **per step**, each
  with `TimePeriod: Daily`, `DailyFrequency: Once`, `DailyStartTime: 00:00:00` and
  `StartDate: tomorrow`, whatever the request said. `scheduleSpec` is stored as text on the flow.
  `nextRun` is `$ZDATETIME($HOROLOG,3)`, i.e. "now".
- `ScheduledFlowTask.OnTask`: only the root step's task acts. It calls
  `WaveDispatcher.Dispatch(flowId, [], "$SCHEDULER", …)` with **no token**. Validation then cannot
  read categories (`CATEGORY_NOT_FOUND`), and management-API steps would get 401. It returns `$$$OK`
  in every case, so the platform's task history shows success.
- Scheduling again creates new tasks without removing the old ones; there is no unschedule.

## R-1 IRIS Wallet in 2026.2 (to prove in T001)

Observed in the class dictionary (`%SYS`, 2026-09-28):
- `%Wallet.Collection` (`Name`, `UseResource`, `EditResource`, `Resource`; `Create`, `Modify`,
  `Delete`, `Exists`, `GetObject`, `List` query).
- `%Wallet.KeyValue` extends `%Wallet.Secret` (`Name`, `Secret`, `Secret64`; plus `Usage`,
  `AllowedHosts`, `RequireTLS`; class methods `Create`, `Modify`, `Delete`, `GetSecretValue`,
  `UpdateSecret`; instance methods `ApplyHTTP`, `ApplySOAP`, `CheckPermission`,
  `GetSQLGatewayCredentials`). The names suggest a key-value secret meant to be applied to HTTP
  requests (the `Usage` flags and allowed hosts), with permission checks against the collection.
- Management API routes (v2 URL map): `GET/PUT/DELETE /wallet/collection`,
  `GET /wallet/collections`, `GET /wallet/secrets?collection=`, `PUT/DELETE /wallet/secret`.

**T001 must establish and record**:
1. The `PUT /wallet/collection` and `PUT /wallet/secret` bodies (secret type, key/value, usage,
   allowed hosts), and that the operator's token is enough (and which privilege is needed).
2. That a process running as account A with `SentaiSchedule:U` can use the secret, and one without
   it gets a refusal (text recorded).
3. Whether `ApplyHTTP` can authenticate `POST /api/admin/login` (Basic) with a key-value secret
   holding the run-as user and password, restricted to the loopback host and the targets' hosts
   (`AllowedHosts`). If yes: D-3 preferred path. If no: the `GetSecretValue` fallback.
4. That `GET /wallet/secrets?collection=` never returns the value (also used by spec 013).

## R-2 Task Manager timing fields

The create body already used by `NativeScheduler` has `TimePeriod`, `TimePeriodEvery`,
`TimePeriodDay`, `DailyFrequency`, `DailyIncrement`, `DailyStartTime`, `DailyEndTime` and
`StartDate`. The mapping to confirm in T001, by creating one task per kind and reading
`task/info` for its next run:

| Kind | TimePeriod | TimePeriodDay | DailyFrequency / Increment | DailyStartTime |
|---|---|---|---|---|
| Daily at T | `Daily`, every 1 | "" | `Once` | T |
| Weekly on D at T | `Weekly`, every 1 | day digits (for example `"26"` for Mon and Fri; confirm the numbering) | `Once` | T |
| Monthly on day N at T | `Monthly`, every 1 | N | `Once` | T |
| Every H hours from T | `Daily`, every 1 | "" | `Several`, increment H hours (confirm the unit, minutes or hours) | T, `DailyEndTime` 23:59:59 |

`StartDate` = today (so a time later today fires today).

## R-3 Signing in at firing

- `AdminApiClient.Login(baseUrl, user, password)` exists (spec 008) and returns the token pair.
  With `ApplyHTTP` (R-1.3), a variant `LoginWithWalletSecret(baseUrl, secretName)` builds the
  request, lets the wallet apply the credential, and sends it. The product then only sees the
  answer (the tokens).
- The primary's base URL for loopback calls is the one `AdminApiClient` already uses.

## R-4 Identity of the firing process

- A `%SYS.Task` runs its `OnTask` as the task's `RunAsUser` in the task's namespace (IRISAPP).
  `JOB ..RunLoop` from there inherits that identity, and WorkMgr workers queued by the loop take the
  loop's identity (spec 005 R-1). Therefore in-process steps of a scheduled run run as the run-as
  account, and the platform authorizes them against that account (D-6). **T001** confirms this by
  scheduling the spec 010 example and reading `executedAs` of its steps.

## R-5 Why the history needs a trigger

- `dispatchedBy` alone cannot tell a scheduled run from a manual run by the same account. A
  `trigger` field is the smallest addition, and it defaults to `manual`, so existing runs stay
  correct.
