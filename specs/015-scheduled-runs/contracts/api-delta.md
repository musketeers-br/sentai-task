# API delta: Scheduled Runs That Execute

Changes to `specs/002-canvas-ui/contracts/openapi.yaml`.

## `POST /flows/{flowId}/schedule` (changed, breaking for the body)

Request:

```json
{ "schedule": { "kind": "weekly", "days": [6], "startTime": "03:00" },
  "runAs": "nightly-ops",
  "password": "<run-as password for this instance>",
  "targetPasswords": [ { "target": "iris-target", "password": "<run-as password there>" } ] }
```

- `schedule.kind`: `daily | weekly | monthly | hourly`; `days` (weekly, 1–7, Mon=1),
  `dayOfMonth` (monthly, 1–31), `everyHours` (hourly, 1–12), `startTime` (`HH:MM`).
- `targetPasswords` must name exactly the targets the flow's steps use.
- The old body (`scheduleSpec` string) is refused with 400 `SCHEDULE_FORMAT` and a message naming
  the new shape.

Responses:
- `201` `{ "taskId": 42, "nextRun": "2026-10-03 03:00:00", "describe": "Weekly on Sat at 03:00", "residue": [] }`
  (`residue` lists old items that could not be removed, with the platform's text).
- `422` validation report (as today), or `{ "code": "CREDENTIAL_REFUSED", "instance": "primary|<target>", "detail": "<platform text>" }`,
  or `{ "code": "TARGET_PASSWORDS_MISMATCH", "detail": "…" }`.
- `400` `SCHEDULE_FORMAT` / field errors `{ "code": "SCHEDULE_INVALID", "field": "days", "detail": "…" }`.
- `403` / other platform refusals verbatim (task create, wallet write).

The request body is never logged or echoed.

## `GET /flows/{flowId}/schedule` (new)

`200` `{ "scheduled": true, "schedule": {…}, "describe": "…", "runAs": "…", "targets": ["iris-target"],
"taskId": 42, "nextRun": "<from the platform now>", "lastRun": { "guid", "state", "startedAt" } | null,
"instanceTime": "<the instance's local time now>" }` or `{ "scheduled": false, "instanceTime": "…" }`. The dialog shows
`instanceTime` so the operator picks times in the instance's clock (spec edge case "Clock and time zone").

## `DELETE /flows/{flowId}/schedule` (new)

`200` `{ "removedTasks": [42, 17, 18], "removedSecrets": 2, "residue": [] }`. It is idempotent: an
unscheduled flow gives the same shape with empty lists.

## Runs

- `Run` and `RunSummary` gain `trigger: manual | scheduled`.
- `GET /runs` gains `trigger` (400 `TRIGGER_UNKNOWN` otherwise).

## Flows list

`FlowSummary.nextRun` is the last platform-reported next run for scheduled flows, else `null`.
