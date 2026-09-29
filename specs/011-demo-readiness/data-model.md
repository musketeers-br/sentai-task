# Data Model: Demo Readiness

No product entity changes. The demo adds markers, a record and two fixed flow definitions.

## 1. Demo marker

| Where | Value | Written by | Read by |
|---|---|---|---|
| `^sentai("config","demo")` (IRISAPP) | `1` | `Demo.Setup()` (from `up.sh`) | `Demo.Reset()`, `Demo.Status()` (refuse without it) |
| `/opt/sentai-web/demo.json` (container file) | see §2 | `up.sh` | canvas sign-in screen |

## 2. `demo.json`

```json
{ "account": "sentai-demo", "password": "sentai-demo-2026",
  "showcase": "Showcase: nightly checks across servers" }
```

Parsing (`frontend/src/lib/shell/demo-info.ts`): `parseDemoInfo(unknown): DemoInfo | null`. The
result is `null` unless all three fields are non-empty strings shorter than 200 characters. Any
fetch failure, non-200 answer or parse error also gives `null`, and the canvas then shows no hint.

## 3. Reset record

`^sentai("demo","lastReset") = $lb(at, outcome, detail)`

- `at`: `%TimeStamp` (UTC, `$ZDATETIME($ZTIMESTAMP,3)`)
- `outcome`: `"ok"` or `"failed"`
- `detail`: short text, for example `"removed 12 flows / 40 runs; seeded 0; target online"`

## 4. Outcome value of `Demo.*`

```json
{ "ok": true,
  "steps": [ {"name": "remove-visitor-flows", "ok": true, "detail": "12 flows, 40 runs"}, … ],
  "problems": [] }
```

`Status()` returns:

```json
{ "demo": true, "flows": 2, "runs": 5, "visitorFlows": 0, "visitorRuns": 0,
  "lastReset": {"at": "2026-09-29 06:00:02", "outcome": "ok", "detail": "…"} }
```

"Visitor" means any flow whose name is not one of the two seeded names, and any run of such a
flow. Runs of the seeded flows are kept by the reset (they show the demo was used) but are counted
separately in `runs`.

## 5. Seeded flows

Both are ordinary `sentai.model.Flow` rows, identified by exact name.

**Example: storage health check** (spec 010, identical to `exampleDefinition()`, checked by the
shared fixture, research R-6).

**Showcase: nightly checks across servers**

| Step | Type | Namespace / directory | Target | Timeout |
|---|---|---|---|---|
| 01 IC USER | integrity-check | USER, `/usr/irissys/mgr/user/` | — | 30 |
| 02 IC IRISAPP | integrity-check | IRISAPP, `/data/IRISAPP_DATA/` | — | 30 |
| 03 IC USER on iris-target | integrity-check | USER | `iris-target` | 30 |
| 04 Database size report | db-size-report | %SYS | — | 10 |

Edges `01→04`, `02→04`, `03→04`; join on `04` with `ALL_MUST_SUCCEED`; default category
`Default`; `runAsUser` empty (the dispatching operator).

## 6. Accounts (per instance)

| Account | Password | Roles | Set by |
|---|---|---|---|
| `_SYSTEM`, `SuperUser`, `Admin`, `_Ensemble`, `irisowner` | secret | unchanged | `secure-accounts.script` |
| `sentai-demo` | `sentai-demo-2026` | `SentaiDemo` | `demo-account.script` (also on reset) |
| `CSPSystem` | unchanged | none | — |

Role `SentaiDemo`: resources from T001 (research R-4); never `%Admin_Secure`, never `%All`.
