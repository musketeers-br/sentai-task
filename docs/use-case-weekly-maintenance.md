# Use case — the weekly maintenance window

*Read this in [Portuguese](use-case-weekly-maintenance.pt-BR.md).*

The flow this document walks through ships with the application as
**Weekly maintenance window** — the image build seeds it, so a fresh
`docker compose up -d` already lists it (see [The flow ships seeded](#the-flow-ships-seeded)).
It uses every step type the catalog marks `available: true` on IRIS 2026.2, each for the reason
its catalog entry states, and it exercises what makes a flow more than a list of tasks:
parallel waves, dependencies, fan-in joins, one validation gate, the typed confirmation of a
destructive step, and results kept per step.

## The problem it starts from

Integrity checks, journal switches, purges and disk checks usually live one-by-one in the
Task Manager, their order and their "what happens if one fails" in someone's head. If the disk
fills up overnight, the integrity check still runs and fails ugly. If it fails, nobody knows
whether the purge ran anyway. This use case turns that tacit runbook into a declared flow:

1. **Gate on disk headroom** — nothing heavy starts when there is no room for it.
2. **Snapshot the space** — a "before" picture, kept with the run.
3. **Fresh journal** — the window's work does not outgrow the current journal file.
4. **Verify in parallel** — two integrity checks as one wave.
5. **Close the window** — clean up old task history, only if everything above succeeded.

## Prerequisites

- The compose stack: `docker compose up -d` (the `iris` service is enough; no target servers
  are involved in this example).
- An operator account — on the dev image, `_SYSTEM` / `SYS`. Every call runs with the
  operator's own credential, and the platform's refusal is the step's failure reason,
  verbatim (Constitution III).
- **Validating** needs `%Admin_Manage:USE` and read on IRISSYS (it reads the WQM categories
  with the operator's token). The journal switch needs `%Admin_Operate:USE` — without it the
  platform refuses with its own `#921` text. The platform decides everything else.
- **Dispatch is manual in v1.** `purge-task-history`, `switch-journal`, `storage-headroom-check`
  and `db-size-report` are in-process steps, which are not schedulable
  (`IN_PROCESS_NOT_SCHEDULABLE`) — a scheduled run has no operator. Manual dispatch is the
  supported v1 path anyway.

## The squad and the attack plan

```
WAVE 1 — recon (read-only, in parallel)     WAVE 3 — the attack (in parallel)
  01 storage-headroom-check (15%)            04 integrity-check (USER)
  02 db-size-report                          05 integrity-check (%SYS)
        |                                           |
        v  fan-in ALL_MUST_SUCCEED                  v  fan-in ALL_MUST_SUCCEED
WAVE 2 — support                            WAVE 4 — closing the window
  03 switch-journal                          06 purge-task-history (keep 30d, %SYS)
                                              ! destructive: type "%SYS" at Run now
```

| Step | Type | Role, in the catalog's own words |
|---|---|---|
| 01 | `storage-headroom-check` (`minFreePercent: 15`) | "Warn when disk space is running low" — the gate: the README's own suggested pattern is to put it at the head, so the integrity checks behind it only start when there is room for them |
| 02 | `db-size-report` | "Report how much space each database and journal file occupies, to show where the growth is going" — the "before" snapshot, kept as the step's `result` |
| 03 | `switch-journal` | "Roll the journal over to a new file so a long-running maintenance window does not outgrow the current one" — before the heavy work, not after |
| 04 | `integrity-check` (USER) | "Check that the database's internal structures are sound" — a platform job with its own GUID and its own report |
| 05 | `integrity-check` (%SYS) | Same, in parallel — two independent jobs in one wave |
| 06 | `purge-task-history` (`keepDays: 30`) | "Delete the history of finished maintenance tasks, keeping the most recent days" — the window's closing move, and only if everything above succeeded; `keepDays: 30` keeps this window's own log entries |

Namespaces `USER` and `%SYS` exist on every IRIS instance, and `Default` is a built-in WQM
category — which is why the seeded flow validates clean on any install, not just the compose
stack.

## Composing it

### On the canvas

Drag the five step types from the palette onto the canvas (the in-process ones sit in the
palette's **Custom** group), then connect `01 → 03 ← 02`, `03 → 04`, `03 → 05`,
`04 → 06 ← 05`; edges that would close a cycle are refused as you draw. Two edges into one
node meet at a single diamond — that node waits for all of them.

You do not need to know the step types' names. The palette's search box takes the **job, not
the tool's name** — scores as measured on the dev stack's `all-minilm`:

| You type | SUGGESTED offers first |
|---|---|
| `check my globals are sound` | Integrity check (0.47) |
| `rotate the journal` | Switch journal (0.55) |
| `free up disk space` | Storage headroom check (0.59), Compact globals (0.49 — listed, but `available: false`, so un-addable) |

Nothing outside the closed catalog is ever suggested (Constitution II).

### Through the API

The JSON below is the flow the seed creates — it mirrors, byte for byte, the `XData
WeeklyMaintenance` block in [`src/sentai/demo/DemoFlows.cls`](../src/sentai/demo/DemoFlows.cls):

```json
{
  "schemaVersion": 1,
  "name": "Weekly maintenance window",
  "defaultCategory": "Default",
  "steps": [
    {"id": "01", "type": "storage-headroom-check", "taskName": "Storage headroom", "namespace": "%SYS", "parameters": {"minFreePercent": 15}, "timeoutMinutes": 10, "wqmCategory": "Default"},
    {"id": "02", "type": "db-size-report", "taskName": "Database size report", "namespace": "%SYS", "timeoutMinutes": 10, "wqmCategory": "Default"},
    {"id": "03", "type": "switch-journal", "taskName": "Switch journal", "namespace": "%SYS", "timeoutMinutes": 5, "wqmCategory": "Default"},
    {"id": "04", "type": "integrity-check", "taskName": "Integrity check - USER", "namespace": "USER", "timeoutMinutes": 45, "wqmCategory": "Default"},
    {"id": "05", "type": "integrity-check", "taskName": "Integrity check - %SYS", "namespace": "%SYS", "timeoutMinutes": 45, "wqmCategory": "Default"},
    {"id": "06", "type": "purge-task-history", "taskName": "Purge task history", "namespace": "%SYS", "parameters": {"keepDays": 30}, "timeoutMinutes": 10, "wqmCategory": "Default"}
  ],
  "edges": [
    {"source": "01", "target": "03"},
    {"source": "02", "target": "03"},
    {"source": "03", "target": "04"},
    {"source": "03", "target": "05"},
    {"source": "04", "target": "06"},
    {"source": "05", "target": "06"}
  ],
  "joins": [
    {"target": "03", "policy": "ALL_MUST_SUCCEED"},
    {"target": "06", "policy": "ALL_MUST_SUCCEED"}
  ],
  "canvasGeometry": {
    "viewport": {"x": 0, "y": 40, "zoom": 0.85},
    "nodes": {
      "01": {"x": 0, "y": 0, "width": 240},
      "02": {"x": 0, "y": 220, "width": 240},
      "03": {"x": 340, "y": 110, "width": 240},
      "04": {"x": 680, "y": 0, "width": 240},
      "05": {"x": 680, "y": 220, "width": 240},
      "06": {"x": 1020, "y": 110, "width": 240}
    }
  }
}
```

`canvasGeometry` is presentation only — the dispatcher never reads it; execution order comes
from the edges alone.

## Validate

```sh
TOKEN=$(curl -s -X POST -u _SYSTEM:SYS http://localhost:52773/api/admin/login | jq -r .access_token)
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  http://localhost:52773/csp/sentai/api/v1/flows/<flowId>/validate
# {"errors":[],"warnings":[]}
```

The seeded flow answers exactly that — verified on the dev stack. The same gate runs again at
dispatch, so a flow that fails here can never run. Findings land **on the node they concern**;
each carries a code:

| If you break... | The node shows |
|---|---|
| a step's category (`wqmCategory: "NONEXISTENT"`) | `CATEGORY_NOT_FOUND` |
| a declared parameter (`minFreePercent: 150`) | `PARAM_OUT_OF_RANGE` (with `parameter: minFreePercent`) |
| a key the type does not declare (`keepDays` on 02) | `PARAM_UNKNOWN` |
| a namespace that does not exist | `NAMESPACE_NOT_FOUND` |

## Dispatch

On the canvas: **Run now** asks for your password once (the run gets its own sign-in, renews
its credential by itself, and the password is never kept), and — because step 06 is
destructive — asks you to **type `%SYS`**, the namespace it acts on. The backend checks the
typed value; a mismatch is a 428 shown verbatim, and the dialog stays open.

Through the API, the same thing is two bodies: the typed confirmation, and the run credential
(without which the run stops when the platform's 60-second token expires):

```sh
PAIR=$(curl -s -X POST -u _SYSTEM:SYS http://localhost:52773/api/admin/login)
ACCESS=$(echo "$PAIR" | jq -r .access_token)
REFRESH=$(echo "$PAIR" | jq -r .refresh_token)

curl -s -X POST http://localhost:52773/csp/sentai/api/v1/flows/<flowId>/dispatch \
  -H "Authorization: Bearer $ACCESS" -H "Content-Type: application/json" \
  -d '{"confirmations": [{"stepId": "06", "typedName": "%SYS"}],
       "runCredential": {"refreshToken": "'"$REFRESH"'"}}'
# 202 {"guid": "<runGuid>", "state": "running", ...}
```

The run has **one identity**: the operator who dispatched it. In-process steps run as that
operator (`executedAs` says who), and the platform decides, at that moment, whether they may —
a refusal becomes the step's `failureReason`, word for word. A `runCredential` belonging to
someone else is refused with 403 `RUN_CREDENTIAL_USER_MISMATCH` before anything starts.

## Watch it run

On the canvas the waves light up in order: `01` and `02` together, then `03`, then `04` and
`05` together, then `06`. Over the API:

```sh
curl -N http://localhost:52773/csp/sentai/api/v1/runs/<runGuid>/events -H "Authorization: Bearer $ACCESS"
# event: step-state-changed ... event: run-terminal
```

- **Results are kept per step** (`GET /runs/<runGuid>` → `steps[].result`): 02's is
  `databases[]`, every database with `sizeMB` and `freeMB`; 04/05 carry the platform's own
  integrity-check report; 01's names each location it checked. A result larger than 8000
  characters keeps the first elements of its largest list and adds `"truncated": true`.
- **Cancel one step** (`POST /runs/<guid>/steps/<stepGuid>/cancel`) without touching its
  wave-sibling. Cancelling a running platform job makes IRIS log
  `ERROR #7802 … unexpectedly shut down` and report the container `unhealthy` — the run is
  fine; clear the alert with `do $SYSTEM.Monitor.Clear()` in `%SYS`.
- **Re-run a failed step** (`POST …/steps/<stepGuid>/rerun`) — only the dispatcher may
  (403 `RERUN_NOT_BY_DISPATCHER` for anyone else).

## When things go wrong — the product stays honest

- **Disk below 15%** — 01 fails, naming each location with its free percentage. Nothing
  downstream ever runs: the failure propagates through the `ALL_MUST_SUCCEED` join, and 03–06
  transition straight to `failed` with the reason "One or more required inputs failed". The
  run reports partial failure, never success (Constitution IV: a partially failed run is
  never reported as success).
- **The operator may not switch journals** — the platform refuses; its own `#921` text is the
  step's `failureReason`, nothing reinterpreted.
- **A typo in the confirmation** — 428 with the backend's `detail`, verbatim.
- **One integrity check hangs** — cancel it alone; its sibling keeps running; the join at 06
  never sees it succeed, so 06 does not run.

## The flow ships seeded

- **The compose image build seeds it.** After the module load, the build runs
  `iris-demo.script`, one `Do ##class(sentai.demo.DemoFlows).EnsureSeeded()` call, so a fresh
  `docker compose up -d --build` opens with the example in the flows list.
- **A `zpm "install sentai-task"` install ships the seeder, not the data.** One line in an
  `iris session`, in the module's namespace, creates the flow:

  ```objectscript
  Do ##class(sentai.demo.DemoFlows).EnsureSeeded()
  ```

- **Idempotent by name.** A flow of that name that already exists — edited or not — is
  returned untouched; the seed never clobbers an operator's work, and a removed demo is not
  resurrected by a later `zpm load`.
- **Removal** (the API has no flow deletion) is one call:

  ```objectscript
  Do ##class(sentai.demo.DemoFlows).Remove()
  ```

  A flow you have already dispatched is kept: `Remove` refuses with `SentaiFlowHasRuns`
  rather than orphaning the runs that hold its history.

Distributed targets (DPI-I-588 — a step running on another IRIS instance) get an example of
their own; see the README section *Target servers from the canvas* until then.

## References

- [README](../README.md) — flow model, declared step types, semantic step-type search
- [Known limitations](limitations.md) — the v1 support set and why dispatch is manual
- `src/sentai/registry/StepType.cls` — the closed catalog, the only place a capability is declared
- `src/sentai/demo/DemoFlows.cls` — the seeded flow definition (the JSON above mirrors its XData)
