# T001 — Management API reads for the report steps (2026-09-29, dev stack, IRIS 2026.2)

All answers use `{status: {errors, summary}, console, result}`. Probed as `_SYSTEM`; the answer
shapes of users, services, audit, web applications and the dashboard are in research R-1.

## (a) Wallet shapes (research R-5)

A temporary collection `SentaiT001` (`UseResource` `%DB_USER`, `EditResource` `%DB_USER`) and a
key-value secret `SentaiT001.probe` were created in `%SYS` (`%Wallet.Collection.Create` needs both
resources), read through the API, then deleted.

- `GET /api/admin/v2/wallet/collections` →
  `[{"Name":"SentaiT001","EditResource":"%DB_USER:WRITE","UseResource":"%DB_USER:READ"}]`
- `GET /api/admin/v2/wallet/secrets?collection=SentaiT001` →
  `[{"Name":"SentaiT001.probe","Type":"%Wallet.KeyValue"}]`
- The secret's value appeared in **no** answer.
- An unknown collection answers 404 with `ERROR #5809` in `status.summary`.

The allow-lists of plan D-5 match (collections: `Name, UseResource, EditResource`; secrets:
`Name, Type`). An empty wallet lists `[]`.

## (b) Privileges

- `sentai-demo` (spec 011 demo role: `%Admin_Manage:U`, `%Admin_Operate:U`, no `%Admin_Secure`)
  gets **403** on `GET /api/admin/v2/security/users` (spec 011 T001 (c)). So the security posture
  report needs security administration; for such an operator it fails with the platform's
  refusal, verbatim (FR-003), which the README states.
- `_SYSTEM` reads all of them.

## (c) What "serious alerts" counts (research R-4)

| Moment | `$SYSTEM.Monitor.State()` | dashboard `Alerts.SeriousAlerts` |
|---|---|---|
| after two days of tests (2026-09-28) | 0 (after a clear) | 179 |
| after the container restarted (2026-09-29) | 2 (alert, from test runs) | 5 |
| right after `do $SYSTEM.Monitor.Clear()` | **0** | **5** (unchanged) |

- `Monitor.Clear()` resets the alert **state** but not the counter; an instance restart resets
  the counter. The dashboard exposes no alert-state field (`Status.SystemMonitor` is `false` in
  every case).
- **Decision** (research R-4, first branch): `maxSeriousAlerts` stays, default 0, and the type's
  description and `docs/limitations.md` say it counts serious alerts since the instance started.
