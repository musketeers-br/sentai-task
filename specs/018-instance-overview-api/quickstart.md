# Quickstart: validate the Instance Overview API

**Feature**: 018-instance-overview-api. Contract: [contracts/api-delta.md](contracts/api-delta.md).

## Prerequisites

```sh
docker compose up -d            # iris (primary) and iris-target
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
zpm "load /home/irisowner/dev"
zpm "test sentai-task -only"
EOF
```

Green ends with `All PASSED`; the count is the previous suite (268 on master, 2026-09-29) plus this
feature's tests.

```sh
B=http://127.0.0.1:52773/csp/sentai/api/v1
T=$(curl -s -u _SYSTEM:SYS -X POST http://127.0.0.1:52773/api/admin/login | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
H="Authorization: Bearer $T"      # tokens live 60 s: fetch a new one per scenario
```

## Scenarios

| # | Story / SC | Command | Expect |
|---|---|---|---|
| 1 | US1, SC-001 | `curl -s -H "$H" $B/overview/readings/processes` | 200, `rows` ≈ the row count of `GET /api/admin/v2/processes` taken at the same moment (±5 %), `readAt` set, no `ID`/`DeleteID`/`CSPSessionID` anywhere |
| 2 | US1 | `…/readings/memory` | every row has `SMHUsedPercent` (null where `SMHAllocated` is 0); `computed` lists it |
| 3 | US1, SC-005 | `…/readings/..%2Fapi%2Fadmin%2Finfo`, `…/readings/security`, `…/readings/nope` | 404 `UNKNOWN_READING`; no platform call (unit test proves it with the double) |
| 4 | US2, SC-002 | `time curl -s -H "$H" $B/overview` | < 3 s, 11 entries, all `ok` for `_SYSTEM` |
| 5 | US2, SC-003 | same as a temporary account holding only the `SentaiDemo` role (spec 011, `scripts/demo/demo-account.script`) | `security` refused; every refused entry carries `platformStatus` verbatim, every allowed entry is `ok`; record which areas were refused |
| 6 | US3, SC-004 | `curl -s -X POST -H "$H" -H 'Content-Type: application/json' -d '{}' $B/overview/reports/web-app-inventory` then a one-step run of `web-app-inventory` | same findings (rule, severity, item); `GET /runs` count unchanged by the first call |
| 7 | US3 | `…/overview/reports/integrity-check` | 422 `STEP_TYPE_NOT_A_REPORT`, no platform call |
| 8 | US4, SC-007 | `POST $B/overview/areas/secrets/flow`, then `POST /flows/{id}/schedule` a minute ahead | 201 with a flow `Check: Secrets inventory` and a validation with 0 errors; the scheduled run completes with the secrets report |
| 9 | US4 | `POST $B/overview/areas/processes/flow` | 409 `AREA_HAS_NO_STEP_TYPE`, no flow created |
| 10 | FR-018 | `…/overview?target=iris-target` | 400 `OVERVIEW_PRIMARY_ONLY` |
| 11 | US5, SC-008 | spike first (research R-7); then on a disposable process: suspend, re-read, resume, terminate without and with `{"confirmation": "<pid>"}`; `GET $B/overview/process-actions` | 428 without confirmation and no record; with it, the platform's answer and one record per call that reached the platform |

## Evidence

Record each scenario's status and timing in `specs/018-instance-overview-api/evidence/README.md`
(table: scenario, command, result, date). No token, password or session id in any file.
