# Quickstart: Scheduled Runs That Execute

On the dev stack with `iris-target` up, after `LoadDir`, the installer changes (resource
`SentaiSchedule` and wallet collection `SentaiTask`) and publishing the canvas.

## 1. Schedule from the canvas

1. Open *Example: storage health check* → *Schedule*.
2. Choose *Daily* at a time 2 minutes from now (instance local time, shown in the dialog). Run-as
   is prefilled with `_SYSTEM`; type its password. Read the wallet sentence. *Schedule*.
3. The dialog shows "Daily at HH:MM", the next run from the platform and "No scheduled run yet".
4. Wait for the time. Open *Runs*, filter *Trigger: scheduled*: one run, completed, dispatched by
   `_SYSTEM`, whose first log entry is "Run started by the schedule of flow Example: storage health
   check".

## 2. API

```bash
TOKEN=$(curl -s -u _SYSTEM:SYS -X POST localhost:52773/api/admin/login -H 'Content-Type: application/json' -d '{}' | jq -r .access_token)
API=localhost:52773/csp/sentai/api/v1
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' $API/flows/<id>/schedule \
  -d '{"schedule":{"kind":"hourly","everyHours":4,"startTime":"00:00"},"runAs":"_SYSTEM","password":"SYS","targetPasswords":[]}'
curl -s -H "Authorization: Bearer $TOKEN" $API/flows/<id>/schedule | jq
curl -s -X DELETE -H "Authorization: Bearer $TOKEN" $API/flows/<id>/schedule | jq
```

Check in the Task Manager (catalog screen, filter "SentaiTask"): exactly one task while scheduled,
none after the delete.

## 3. Failure is visible

Schedule a flow with run-as `sched-test` (an account created for the test), then change that
account's password on the platform. At the next firing: a failed scheduled run whose log reads
`Scheduled run could not start: could not sign in to primary: HTTP 401 …`, and the platform task
history shows the error.

## 4. Acceptance script

```bash
IRIS_USER=_SYSTEM IRIS_PASSWORD=SYS python3 scripts/schedule-evidence/acceptance.py   # ~10 min, fires real tasks
```

It covers SC-001 (5 firings, one remote), SC-003 (re-schedules and unschedule leave 0 tasks and
0 secrets), SC-004 (password changed → recorded failure) and SC-005 (next run equals the
platform's for the four kinds), and writes `specs/015-scheduled-runs/evidence/acceptance-<date>.json`
(no passwords).

## 5. Secret hygiene (SC-002)

`SecretHygieneTest` runs a full cycle with a sentinel password and scans `^sentai*`,
`^IRIS.Temp.sentai*`, `sentai_model.*` rows and the run logs: 0 hits. The e2e `us28` also checks
`sessionStorage`/`localStorage` after the dialog closes.
