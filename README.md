[![Gitter](https://img.shields.io/badge/Available%20on-Intersystems%20Open%20Exchange-00b2a9.svg)](https://openexchange.intersystems.com/package/sentai-task)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat&logo=AdGuard)](LICENSE)
[![InterSystems IRIS](https://img.shields.io/badge/InterSystems-IRIS%202026.2-blue.svg)](https://www.intersystems.com/)
[![ObjectScript](https://img.shields.io/badge/Backend-ObjectScript-3b4b9c.svg)](https://docs.intersystems.com/)
[![Embedded Python](https://img.shields.io/badge/Embedded-Python-3776ab.svg?logo=python&logoColor=white)](#-where-sentaitask-uses-embedded-python-and-why)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ed.svg?logo=docker&logoColor=white)](#docker)
[![IPM](https://img.shields.io/badge/IPM-sentai--task-00b2a9.svg)](#ipm)

<p align="center">
  <img src="./assets/sentai-task.png" alt="SentaiTask 戦隊 — red ranger holding a wrench and an IRIS crystal" width="320">
</p>

# 🦸 SentaiTask 戦隊

**Visual orchestration for InterSystems IRIS maintenance tasks**: compose checks, purges and
journal switches as a flow, run them in parallel waves that converge at join points, on this
instance and on other IRIS servers, and watch every step live.

<p align="center">
  <img src="./assets/media/sentai-run.gif" alt="SentaiTask running a flow: three integrity checks, one of them on a second IRIS server, and two security reports run in parallel, converge on a join, and the final report opens with its findings; then the run log and the run history" width="880">
</p>

<p align="center">
  <img src="./assets/media/stills/overview.png" alt="The Overview screen: eleven cards — processes, locks, shared memory, activity, devices, licenses, web sessions, security posture, web applications, system alerts and secrets — each with its headline read now from the instance" width="880">
</p>

## ⚖️ For judges: two minutes

**What is different here.** The other portals *show* you the instance. SentaiTask *runs work on
it*: maintenance steps composed as a flow, dispatched several at a time as real Work Queue Manager
jobs, on this instance and on other IRIS servers, each one followed to a terminal state. Nothing is
simulated — every call goes to the platform's own management API (`/api/admin`) with **your**
credential, and when the platform refuses, its answer is shown word for word.

### Ninety seconds, Docker only

```sh
git clone https://github.com/musketeers-br/sentai-task.git && cd sentai-task
docker compose up -d --build
# then open http://localhost:52773/csp/sentai/ and sign in as _SYSTEM / SYS
```

1. **Overview** opens first — eleven cards, each read now from the instance. On *Security posture*,
   press **Run report**: a flow step runs and opens its findings in the viewer a run uses.
2. **Flows → Open example flow**, then **Validate flow**, then **Run now**.
3. **Watch the canvas.** Steps in the same wave turn green together; a diamond is a join, and the
   step after it waits for every input. *That parallelism is the product.*
4. Open **RUN LOG**: who dispatched the run, each step's start, end and duration, and any failure in
   the platform's own words. **Export** saves the whole run as JSON.
5. Press **Schedule in Task Manager**: the flow becomes one native IRIS task, and its runs come back
   marked *scheduled* in the history.

No public demo to reach, no second service to wait for, no model to download at run time: the image
carries everything. ([Docker](#docker) · [IPM: `zpm "install sentai-task"`](#ipm))

### If you have two more minutes

| Look at | Why it matters | Where |
|---|---|---|
| A step running on **another IRIS server** | Implements [DPI-I-588 *Distributed Work Manager*](https://ideas.intersystems.com/ideas/DPI-I-588), an idea with **Community Opportunity** status, with nothing installed on the far side | [Target servers](#-implements-dpi-i-588-distributed-work-manager) |
| Typing a database directory to confirm a **destructive** step | The backend checks the value; destructive flows cannot be scheduled at all | [On the canvas](#on-the-canvas) |
| Signing in as a user without `%Admin_Task` | Every call carries the operator's own credential — SentaiTask never re-implements IRIS permissions | [Core pieces](#core-pieces) |
| Describing a job in the palette search | Intent search ranks the catalog by meaning, embedded **inside IRIS** via `%Embedding.Config`, offline | [Semantic step-type search](#-semantic-step-type-search-and-the-embedding-provider) |
| The report steps | Security posture, permissions, web applications, secrets, certificate expiry, OAuth and system alerts — each one a step you can schedule | [Report steps](#report-steps-security-web-applications-alerts-secrets) |

### The honest parts

- **[Contest areas covered](#contest-areas-covered)** — nine areas, each row linking to the screen
  or spec that proves it.
- **[Known limitations](#%EF%B8%8F-known-limitations-v1)** — what is *not* proven on IRIS 2026.2 is
  listed, including the four step types still marked `available: false`.
- **[Running the tests](#-running-the-tests)** — 268 backend test methods against a double of the
  management API, plus canvas unit tests and Playwright acceptance tests that drive real runs.
- Built across 20 specs, each with its evidence kept in [`specs/`](specs/).
- Written up on the Developer Community: [the walkthrough in English](https://community.intersystems.com/post/sentaitask-%E6%88%A6%E9%9A%8A-your-iris-maintenance-tasks-assembled-squad) and [a versão em português](https://pt.community.intersystems.com/post/sentaitask-%E6%88%A6%E9%9A%8A-tarefas-de-manuten%C3%A7%C3%A3o-do-iris-reunidas-como-um-esquadr%C3%A3o).

---

## 🚀 Try it

- **Public demo**: a stable address is being set up for the voting week; it will be listed here.
  Sign in as **`sentai-demo`** / **`sentai-demo-2026`**, open **Showcase: nightly checks across
  servers** from *Open flow…* and choose *Run now*. The demo is reset every day.
- **On your machine, in three commands** (Docker only):

  ```sh
  git clone https://github.com/musketeers-br/sentai-task.git && cd sentai-task
  docker compose up -d --build
  # then open http://localhost:52773/csp/sentai/ and sign in as _SYSTEM / SYS
  ```

  The local quickstart works even when the public demo is down. *Open example flow* on the empty
  canvas runs a ready-made, read-only flow in about a second.

  The first build also installs the palette's intent search inside IRIS — CPU-only Python packages
  and a small language model, about 1.9 GB of image, once, at build time (about four minutes for the
  whole build). There is no second service to wait for: intent search ranks about seven seconds
  after the container reports healthy.

### Contest areas covered

| Management Portal area | What SentaiTask offers | Proof |
|---|---|---|
| **Task management** | Flows of tasks with dependencies and fan-in joins; dispatch, live tracking, cancel and rerun per step; native Task Manager catalog with filters, suspend and resume; schedules that run: one native task per flow, running as a run-as account whose password lives in the IRIS Wallet | [How to use](#-how-to-use), [spec 006](specs/006-task-catalog-api/) |
| **Operating system** | Instance resources on demand: processes (with suspend, resume and terminate), locks, shared memory, activity counters, devices, license use and web sessions — the management API reports no host CPU or memory, so none is shown. Disk: `storage-headroom-check` (Embedded Python) and `db-size-report` as flow steps | the [Overview](#overview-the-landing-screen) screen, [spec 018](specs/018-instance-overview-api/), [spec 019](specs/019-canvas-instance-overview/), [Declared step types](#declared-step-types) |
| **Work Queue Manager** | Read and edit WQM categories, the worker pools every step runs on | [API at a glance](#api-at-a-glance) |
| **Logs** | Every run writes its own log (dispatch, each step start and end with its duration, the platform's failure reason verbatim, joins that stopped a step, who asked to cancel, targets that stopped answering, the outcome); a *Runs* screen finds any past run by flow and outcome, and *Export* saves one as a file | [Runs and run log](#runs-and-run-log), [spec 012](specs/012-run-log-history/) |
| **Security and permissions** | `security-posture-report` as a flow step: enabled accounts and their roles, `%All` holders, services open to unauthenticated connections, auditing off, on any server. `permissions-inventory`: every role with the resources it grants, every resource with what the public may do, risky combinations flagged. Every call runs with the operator's own IRIS credential; the platform's refusal is shown verbatim | [Report steps](#report-steps-security-web-applications-alerts-secrets), [spec 013](specs/013-area-report-steps/), [spec 020](specs/020-security-inventory/) |
| **Web applications / REST** | `web-app-inventory`: every web application, whether it is a REST endpoint, its resource and authentication; anonymous endpoints are findings | [Report steps](#report-steps-security-web-applications-alerts-secrets) |
| **Monitoring and alerts** | `system-alerts-check` gates a flow on the platform's serious alerts, application errors and resource statuses | [Report steps](#report-steps-security-web-applications-alerts-secrets) |
| **Secrets** | `secrets-inventory`: the IRIS Wallet's collections, their protecting resources and secret names, never a value. `certificate-expiry-check`: x509 certificates and SSL/TLS configurations, failing when one expires within N days — schedule it and the flow warns before an outage. `oauth-inventory`: OAuth 2.0 server, clients, server definitions and resource servers ("not configured" is a normal state) | [Report steps](#report-steps-security-web-applications-alerts-secrets), [spec 020](specs/020-security-inventory/) |
| **Distributed work** | A flow step can run on another IRIS instance (a *target server*), tracked and with its result collected on the primary | [DPI-I-588](#-implements-dpi-i-588-distributed-work-manager) |

---

## 🌌 Motivation

IRIS maintenance jobs such as integrity checks, journal switches, purges and compaction are
usually scheduled one at a time in the Task Manager. Their order, their dependencies and "what
happens if one fails" are kept in someone's head or in a runbook.

Other portals list tasks one by one. **SentaiTask orchestrates them**: it turns that tacit
knowledge into a declared, validated, observable flow:

- ✅ **Compose** a flow as a graph: steps run in parallel waves and fan in at join points.
- ✅ **Validate before running**: cycles, unknown or unsupported step types, missing parameters,
  missing namespaces, unknown WQM categories, read-only databases.
- ✅ **Dispatch and track**: every step becomes a platform job with its own GUID, state and
  verbatim failure reason, followed live on the canvas (the API also streams it over
  Server-Sent Events).
- ✅ **Stay honest**: the product only offers what the target IRIS instance was proven to do (see
  [Known limitations](#%EF%B8%8F-known-limitations-v1)).

Like a *sentai* squad, each step has its own role, and the flow decides when they move together.

---

## 🛠️ How It Works

SentaiTask is an ObjectScript backend on top of the IRIS management API (`/api/admin`), plus a
canvas UI that IRIS serves itself. It does not reimplement the platform's permissions: every
platform call is made with the operator's own credential (Constitution III, *Delegated
Authorization*).

### Core pieces

1. **Flow model** (`sentai.model`): Flow, Step, Edge, Join, Run, StepRun and LogEntry, persisted
   in IRIS. Edges are acyclic and fan-in joins use `ALL_MUST_SUCCEED`.
2. **Step-type registry** (`sentai.registry.StepType`): a closed, compiled catalog. No code is ever
   taken from input. Each type declares whether it is destructive, pausable and **available on the
   target platform**.
3. **Validator** (`sentai.validation.FlowValidator`): a single gate shared by validate, dispatch
   and schedule, so a flow that fails `/validate` can never be run.
4. **Wave dispatcher** (`sentai.dispatch.WaveDispatcher`): creates the Run and one StepRun per
   step in a single transaction, enqueues eligible steps on the step's WQM category, starts the
   platform job and follows it to a terminal state.
5. **REST API + SSE** (`sentai.rest.Dispatcher`): `/csp/sentai/api/v1`, with password + JWT
   authentication and no unauthenticated access.
6. **Declared steps** (`sentai.steps`): in-process step types, compiled classes extending
   `%SYS.Task.Definition`; disk readings use Embedded Python (see
   [below](#-where-sentaitask-uses-embedded-python-and-why)).
7. **Canvas UI** (`frontend/`): SvelteKit + Svelte Flow, compiled to static files in a Node stage
   of the `Dockerfile` and served by IRIS's own web server at `/csp/sentai/` through
   `sentai.web.StaticFiles`, behind the IRIS password (no unauthenticated web app). No Node
   process runs in the shipped container; the page talks only to the two APIs above.

### Architecture overview

```
┌─────────────────────────────────────────────────────────────┐
│                 Operator (curl / canvas UI)                 │
└─────────────────────────┬───────────────────────────────────┘
                          │ Bearer token from /api/admin/login
                          ▼
┌─────────────────────────────────────────────────────────────┐
│            REST  /csp/sentai/api/v1  (sentai.rest)          │
│   flows · validate · dispatch · runs · events (SSE) · wqm   │
└──────────┬──────────────────────────────┬───────────────────┘
           │                              │
           ▼                              ▼
┌──────────────────────┐      ┌───────────────────────────────┐
│   FlowValidator      │◀─────│   WaveDispatcher              │
│   one gate for       │      │   Run + StepRuns (1 tx)       │
│   validate/dispatch/ │      │   waves → %SYSTEM.WorkMgr     │
│   schedule           │      │   (per WQM category)          │
└──────────┬───────────┘      └──────────────┬────────────────┘
           │ categories                      │ start / poll / pause
           ▼                                 ▼
┌─────────────────────────────────────────────────────────────┐
│          IRIS management API  /api/admin  (platform)        │
│   wqm-categories · database-dir/integrity-check ·           │
│   async-result                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 Prerequisites

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [Docker Desktop](https://www.docker.com/products/docker-desktop) with Docker Compose
- **InterSystems IRIS 2026.2**. The container image built by this repo is the verified target.
- **Disk and memory:** about 10 GB for the two images (`iris` 5.9 GB, `iris-target` 3.7 GB), and
  about 450 MB of memory for the search worker inside `iris`. No GPU is used or needed.

---

## 🛠️ Installation

### Docker

```sh
git clone https://github.com/musketeers-br/sentai-task.git
cd sentai-task
docker-compose up -d --build
```

The build compiles the canvas, loads the `sentai-task` module and registers the REST application
`/csp/sentai/api/v1` on **http://localhost:52773**. It also installs the palette's intent search
inside IRIS (CPU-only Python packages and the `all-MiniLM-L6-v2` model, run offline) and the image
starts its worker when IRIS starts — there is no separate model service.

**A stack built before this change** keeps the old provider row until it is rebuilt: its row names an
`ollama` service that no longer exists, so intent search answers `unreachable` and the palette keeps
its local filter. `docker compose up -d --build` moves it over (every build starts a fresh instance
with the in-process row); `docker compose up -d` alone does not. When the container is up, open

**http://localhost:52773/csp/sentai/**

Sign in to the canvas with your IRIS user (`_SYSTEM` / `SYS` on this dev image). That sign-in
exchanges the password for short-lived API tokens; only the renewal token is kept, for the
current browser tab (spec 010), and the password is never stored.

> **What is public and what is not:** the page itself (HTML, JS, CSS) is served without
> authentication by `sentai.web.StaticFiles`, which only reads the canvas build and holds no
> data. Its code lives in a small database, `SENTAIWEB`, and the app's role `SentaiWebPage` only
> lets the anonymous request enter the namespace (read on its default globals database). Every
> flow and run goes through the REST API, which always requires a token.

### IPM

In an IRIS instance with the IPM client:

```objectscript
USER>zpm "install sentai-task"
```

The app runs immediately; the palette narrows by entry text. The module installs no Python
package, downloads no model and writes no configuration: **semantic** search ("describe the job,
get the step type") stays off until you add one row in `%Embedding.Config`, in the namespace the
module runs in. Until then the palette simply stays on its local filter; everything else works.

**In-process, no extra service** (what the Docker image does). Three steps on the IRIS host:

```sh
# 1. The packages, CPU-only, in ONE command into a directory Embedded Python imports from.
#    The index order matters: from PyPI alone, or in two commands, pip pulls the CUDA build of
#    torch (5.4 GB instead of 1.3 GB).
pip3 install --target <iris>/mgr/python     --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple     torch sentence-transformers
# 2. The model (88 MB), once, into a directory the IRIS user can read.
<iris>/bin/irispython -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2', cache_folder='<iris>/mgr/sentai-models', device='cpu')"
# 3. Run IRIS with HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1 in its environment: the model then
#    loads from its files only (with no route to the model hub, the first load otherwise waits
#    minutes).
```

```sql
INSERT INTO %Embedding.Config (Name, EmbeddingClass, Configuration, VectorLength, Description)
VALUES ('sentai-steps', 'sentai.search.LocalEmbedding',
        '{"modelName":"sentence-transformers/all-MiniLM-L6-v2","cachePath":"<iris>/mgr/sentai-models"}',
        384, 'Step-type search, in-process');
```

The `INSERT` checks that the packages import and the model is in `cachePath`, and says which is
missing. The first search afterwards answers `warming` and starts the worker that holds the model
(≈450 MB, loads in about seven seconds); searches after that rank. The platform's own
`%Embedding.SentenceTransformers` is not recommended: it reloads the model on every call (≈3.4 s
per search).

**Alternatives, all the same one row:** `sentai.search.EmbeddingService` with any
OpenAI-compatible `Configuration` — an [ollama](https://ollama.com) you run (it also installs
natively; no container needed) or any server speaking `POST /v1/embeddings` — or
`%Embedding.OpenAI` for a hosted provider, which **sends the operator's query text off the
machine**. Delete the row to drop semantic search again; nothing else changes.

### Public demo (hosts)

A public machine runs the same compose stack behind a proxy that forwards only the canvas and
the management API calls the canvas makes; the management portal and every other web
application answer 404, and IRIS publishes no port of its own (spec 011).

```sh
git clone https://github.com/musketeers-br/sentai-task.git /opt/sentai-task && cd /opt/sentai-task
printf 'SENTAI_DEMO_SECRET=%s
DEMO_HOST=%s
' "<long random secret>" "demo.example.org" > .env
scripts/demo/up.sh
```

- `up.sh` refuses to start without `SENTAI_DEMO_SECRET`. It gives that secret to every privileged
  account on both instances, creates the demo account `sentai-demo` / `sentai-demo-2026` with
  least privilege ([what it may do](specs/011-demo-readiness/evidence/t001-demo-role.md)), seeds
  the example and showcase flows, and only then opens the proxy. With `DEMO_HOST` set the proxy
  obtains an HTTPS certificate for it; without it, the demo answers on plain HTTP.
- The demo account holds no security administration. The platform still lets it purge task
  history, because the privileges an integrity check needs allow that too; on a disposable demo
  this is accepted.
- Keep it clean and watch it (cron on the host):

  ```cron
  0 6 * * *    cd /opt/sentai-task && scripts/demo/reset.sh  >> /var/log/sentai-demo.log 2>&1
  0 */12 * * * cd /opt/sentai-task && scripts/demo/status.sh >> /var/log/sentai-demo.log 2>&1
  ```

  `reset.sh` removes visitor flows and runs, restores the showcase and the demo password, and
  clears the IRIS alert state on both instances; `status.sh` exits non-zero when an instance is
  unhealthy.
- Never `docker compose down` the demo (it removes the containers and their data): use
  `restart`, or run `up.sh` again to rebuild, re-secure and re-seed.

---

## 💡 How to Use

### Overview (the landing screen)

After sign-in the canvas opens on **Overview** (spec 019): eleven cards, one per management area,
read now with your own credential through the [instance overview API](#instance-overview).
Above the cards (spec 023):

- **Could not read …** — listed at the top only when some reading failed: each refused or
  unreachable area, or the task catalog, with the platform's answer, so a refused card is never
  found only by scanning.
- **Needs attention** — no backup ever taken (from *Activity*), suspended scheduled tasks
  (**Show in catalog**) and tasks the step-type catalog cannot classify (**Show them**), each with
  one action. "Nothing needs attention" appears only when both reads succeeded.
- **Next 24 hours** — the Task Manager's next runs by half hour on the instance's own clock, with
  destructive and suspended ones marked and the next run after the window.
- **Instance resources** — *Processes*, *Locks*, *Shared memory*, *Activity*, *Devices*,
  *Licenses*, *Web sessions*. **Open** shows every row the platform returned as a table you can sort
  and filter, with an optional *Auto-refresh every 10 s* that pauses while the tab is hidden. On
  *Processes*, **Suspend**, **Resume** and **Terminate** go to the platform; terminate asks you to
  type the process id.
- **Security posture, Web applications, System alerts, Secrets** — the card shows a count; **Run
  report** runs the spec 013 report on demand and opens it in the same viewer a run uses, and the card
  keeps its counts until you reload. **Schedule this check** turns it into a one-step flow and opens
  the schedule dialog.
- A card the platform refused shows the platform's answer (`HTTP 403 — …`) and the others still load.
  *Flows* is one click away; every older address (`?flow=`, `?run=`, `?view=…`) opens what it names.

### On the canvas

1. **Compose.** Drag an available step type (*Integrity check*, *Switch journal*, *Storage
   headroom check*, *Database size report*, *Purge task history*) from the palette onto the canvas (the others are
   listed but marked *not supported in v1*, see [Known limitations](#%EF%B8%8F-known-limitations-v1)).
   Drag from a step's right handle to another step's left handle to connect them; edges that would
   create a cycle are refused as you draw. Several edges into one step meet at a single diamond:
   that step waits for all of them. Click a step to edit it in the inspector, then **Save flow**.
   Declared steps (*Switch journal*, *Purge task history*, *Storage headroom check*, *Database size
   report*) sit in the palette's **Custom** group; their inspector form is generated from the
   parameter schema the API declares, shows each default as a placeholder, and puts a validation
   error on the field it concerns.
2. **Validate flow.** Errors (unknown namespace or category, unsupported type, missing parameter)
   appear on the affected node and block running; warnings, such as a read-only database, are
   shown but do not block.
3. **Run now.** You are asked for your password once: the run gets its own sign-in and renews its
   credential by itself for as long as it runs. The password is not kept. A destructive step also
   asks you to type the database directory (or namespace) it acts on; the backend checks the value
   and, if it does not match, its answer is shown as is.
4. **Watch.** The live-run view shows each step's state, elapsed time and, if it fails, the
   platform's own failure message. Cancel one step without touching the others, or *Cancel wave*
   for the whole run.

The **Dark / Light** switch in the top bar changes theme on every screen.

### Runs and run log

- **RUN LOG** in the run view tells the run's story, oldest first: who dispatched it, each step
  starting and finishing (with its duration), the platform's failure reason in quotes, a join
  that kept a step from starting (naming the input), cancel/pause/re-run requests and their
  answer, a target that stopped or started answering again, and the outcome.
- The **Runs** tab lists runs newest first, 50 at a time (*Load more*), with flow, outcome, start,
  duration, who dispatched it and step counts. Filter by flow and outcome; the filters live in the
  address. *More → Run history* on a flow opens the list filtered to it. A finished run opens
  read-only, with *Back to runs*.
- *Export* in any run view saves `<flow>-<run>.json`: the run, every step with its result and
  failure reason, and the log. Nothing from the session is in it.
- API: `GET /csp/sentai/api/v1/runs?flowId=&state=&trigger=&limit=&before=` (spec 012 contract).
  A run started by a schedule is marked *scheduled* (`trigger`), and the list filters by it.

### Schedules

*Schedule in Task Manager* in the top bar schedules the open flow: daily, weekly (chosen days),
monthly (a day of the month) or every 1–12 hours, at a time in the **instance's clock** (the dialog
shows the instance's current time).

- **One native task per flow**, named `SentaiTask: <flowId> <flow name>`, created through the
  platform's management API with your token (the platform decides whether you may). It runs as the
  **run-as account** you name, and when it fires it runs the flow exactly as *Run now* does. The run
  is marked *scheduled* in the history.
- **The run-as password is checked by signing in** on this instance, and on each target server the
  flow uses (one password per target), **then kept only in the IRIS Wallet** — collection
  `SentaiTask`, protected by the resource `SentaiSchedule`. SentaiTask never stores, logs or shows
  it; at firing the platform applies it to the sign-in request itself.
- **Grants (by the administrator):** `SentaiSchedule:U` to run-as accounts (to use the stored
  password), `SentaiSchedule:W` to operators who schedule (to write it). The installer creates the
  resource and the collection and grants them to nobody.
- **See, change, remove:** reopening the dialog shows the schedule, the platform's next run and the
  last scheduled run. *Update* changes the timing, *Renew credential* keeps it with new passwords
  (after a password change), *Unschedule…* removes the task and the stored passwords. Each change
  leaves exactly one task.
- **When a scheduled run cannot start** (the password was changed, the account lost
  `SentaiSchedule:U`, the flow no longer validates), a failed run records why, in the platform's
  words (`Scheduled run could not start: …`), and the Task Manager's history shows the error.
- Destructive steps cannot be scheduled (they need a typed confirmation at *Run now*).
- API: `GET/POST/DELETE /csp/sentai/api/v1/flows/{id}/schedule`
  ([contract](specs/015-scheduled-runs/contracts/api-delta.md)). Example:

```bash
curl -s -X POST http://localhost:52773/csp/sentai/api/v1/flows/1/schedule \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"schedule": {"kind": "weekly", "days": [6], "startTime": "03:00"},
       "runAs": "nightly-ops", "password": "<run-as password>",
       "targetPasswords": [{"target": "iris-target", "password": "<run-as password there>"}]}'
# 201 {"taskId": 42, "nextRun": "2026-10-03 03:00:00", "describe": "Weekly on Sat at 03:00", "residue": []}
```

### The Task catalog screen

**Task catalog** in the top bar shows the platform's Task Manager: every scheduled task on the
instance, not only SentaiTask's (spec `007-canvas-management-screens`, over the spec 006 API).

- **Only the platform's values.** Class, run-as user, next and last run, status and suspended are
  shown as the API returns them. A value the platform refused to read says *unavailable*, with the
  platform's reason; nothing is filled in. Rows are sorted by next run.
- **Filters are the API's.** Search, namespace, *All / Scheduled / Suspended* and *Destructive
  only* are sent to the API, and "N of M tasks" is its count.
- **Detail and origin.** Click a task for every field plus its recent runs. A task SentaiTask
  scheduled is marked *SentaiTask · flow 1 · step 01*, and its detail links to that flow on the
  canvas, or says *flow not found* when the flow is gone.
- **Suspend / Resume.** The one that applies is offered; the platform decides, and a refusal is
  shown as the platform worded it (for example `HTTP 403 — no reason given` without
  `%Admin_Task`).
- **Addressable.** `?view=catalog&task=4` opens a task's detail directly; back and forward work.

![The Task catalog with a destructive task open](specs/007-canvas-management-screens/evidence/sc008-catalog-dark.png)

![Composing a flow: three integrity checks fan in to a fourth, then a fifth](specs/002-canvas-ui/evidence/q1-flow-composition.png)

![A live run: completed, cancelled, running and queued steps at once](specs/002-canvas-ui/evidence/q6-live-run.png)

### Target servers from the canvas (DPI-I-588)

**Targets** in the top bar manages the other IRIS instances a step can run on (spec
`009-canvas-distributed-targets`, over the spec 008 API):

- **Register** a target (name, `https://host:port` address, description), edit, delete, and switch
  it online or offline. Every refusal is shown as the API worded it.
- **Live state.** Type your password for the target and *Read state*: its IRIS version and Work
  Queue Manager categories, as the target reports them — or *unreachable* with the transport
  error. The password and the target's tokens are used for that one read and not kept.
- **Run on.** In the inspector, an integrity check can run on *Local* or any online target; the
  node then carries the target's name. Step types that cannot run remotely say so.
- **Run now** asks one more password per target the flow uses. The live run shows where each step
  runs (*on local*, *on iris-target*) and as whom.

![A run with one step on iris-target](specs/009-canvas-distributed-targets/evidence/us3-remote-run.png)

### With the API

#### 1. Get a token

The API uses the same 60-second JWT as the IRIS management API:

```sh
TOKEN=$(curl -s -X POST -u _SYSTEM:SYS http://localhost:52773/api/admin/login | jq -r .access_token)
```

#### 2. Compose a flow

Two integrity checks run in parallel and fan in to a third:

```sh
curl -s -X POST http://localhost:52773/csp/sentai/api/v1/flows \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "schemaVersion": 1,
    "name": "nightly-checks",
    "defaultCategory": "Default",
    "steps": [
      {"id": "01", "type": "integrity-check", "taskName": "IC USER",    "namespace": "USER",    "wqmCategory": "Default"},
      {"id": "02", "type": "integrity-check", "taskName": "IC IRISAPP", "namespace": "IRISAPP", "wqmCategory": "Default"},
      {"id": "03", "type": "integrity-check", "taskName": "IC %SYS",    "namespace": "%SYS",    "wqmCategory": "Default"}
    ],
    "edges": [ {"source": "01", "target": "03"}, {"source": "02", "target": "03"} ],
    "joins": [ {"target": "03", "policy": "ALL_MUST_SUCCEED"} ]
  }'
```

#### 3. Validate, dispatch and watch

```sh
curl -s -X POST http://localhost:52773/csp/sentai/api/v1/flows/<flowId>/validate  -H "Authorization: Bearer $TOKEN"
# {"errors":[],"warnings":[]}

curl -s -X POST http://localhost:52773/csp/sentai/api/v1/flows/<flowId>/dispatch  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"confirmations": []}'
# 202 {"guid": "<runGuid>", "state": "running", ...}

curl -N http://localhost:52773/csp/sentai/api/v1/runs/<runGuid>/events -H "Authorization: Bearer $TOKEN"
# event: step-state-changed ... event: run-terminal
```

Steps 01 and 02 start together. Step 03 stays `queued` until both complete.

A run dispatched like this keeps the 60-second token it was given. To let it run longer, sign in
separately for the run and add that sign-in's refresh token to the body,
`"runCredential": {"refreshToken": "…"}`, while sending its access token in `Authorization`. The
run then renews its own credential and erases it when it ends. The canvas does this for you.

#### API at a glance

| Area | Endpoints |
|---|---|
| Flows | `GET/POST /flows` · `GET/PUT /flows/{id}` · `POST /flows/{id}/validate` · `POST /flows/{id}/dispatch` · `GET/POST/DELETE /flows/{id}/schedule` |
| Runs | `GET /runs` · `GET /runs/{guid}` · `GET /runs/{guid}/events` (SSE) · `POST /runs/{guid}/cancel` · `POST /runs/{guid}/pause` |
| Steps | `POST /runs/{guid}/steps/{stepGuid}/cancel` · `…/pause` · `…/rerun` |
| Catalog | `GET /catalog/step-types` · `GET /catalog/step-types/search?q=…` · `GET /catalog/tasks` · `GET /catalog/tasks/{id}` · `POST /catalog/tasks/{id}/suspend` |
| WQM | `GET /wqm/categories` · `GET/PUT /wqm/categories/{name}` |
| Targets | `GET/POST /targets` · `GET/PUT/DELETE /targets/{name}` · `POST /targets/{name}/online` · `POST /targets/{name}/sign-in` · `GET /targets/{name}/status` |
| Overview | `GET /overview` · `GET /overview/readings/{area}` · `POST /overview/reports/{stepType}` · `POST /overview/areas/{area}/flow` · `POST /overview/processes/{pid}/{suspend\|resume\|terminate}` · `GET /overview/process-actions` |

Validation errors come back as `{"errors": [{"stepId", "code", "message"}], "warnings": [...]}`,
with codes such as `CYCLE_DETECTED`, `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`, `CATEGORY_NOT_FOUND`
and, for declared step types, `PARAM_REQUIRED`, `PARAM_TYPE_MISMATCH`, `PARAM_OUT_OF_RANGE`,
`PARAM_UNKNOWN` (each also carries `parameter`) and, on `/schedule`, `DESTRUCTIVE_NOT_SCHEDULABLE`.

#### Report steps (security, web applications, alerts, secrets)

Seven read-only step types (specs 013 and 020, `executor: "platform-read"`) read the **management
API of the instance the step runs on** with the operator's credential for it, so they run on target
servers too, and apply fixed rules. Each stores a report: `summary` (counts by severity), `findings`
(severity, rule, item, detail) and `details`. The run view opens any step's result with **Result**.

| Type | Reads | Findings | Parameters |
|---|---|---|---|
| `security-posture-report` | users and each enabled user's roles, services, audit flag | `ALL_ROLE_HOLDER` (high), `AUDIT_DISABLED` (high), `UNAUTHENTICATED_SERVICE` (medium) | `failOnFindings` (fail on any high) |
| `web-app-inventory` | web applications | `ANONYMOUS_REST_ENDPOINT` (high), `ANONYMOUS_APPLICATION` (medium): enabled, not system, unauthenticated allowed, no resource | `failOnFindings` |
| `system-alerts-check` | the main monitoring dashboard | `SERIOUS_ALERTS_OVER`, `APPLICATION_ERRORS_OVER`, `STATUS_NOT_NORMAL` — the step fails on any | `maxSeriousAlerts` (0), `maxApplicationErrors` (0), `requireNormalStatus` (true) |
| `secrets-inventory` | wallet collections and their secrets' names | `UNPROTECTED_COLLECTION` (medium) | — |
| `certificate-expiry-check` | x509 credentials and each one's certificate validity; SSL/TLS configurations | `CERT_EXPIRED` (high), `CERT_EXPIRING` (medium) — the step fails on either; `CERT_VALIDITY_UNKNOWN`, `CONFIG_VALIDITY_NOT_REPORTED` (info) | `warnDays` (30, 1–365) |
| `permissions-inventory` | roles (each one's resources and granted roles), resources | `PUBLIC_WRITE_OR_USE_SENSITIVE` (high: public W or U on `%DB_…`, `%Admin_…`, `%Development`), `PUBLIC_WRITE_OR_USE` (medium), `ROLE_GRANTS_ALL` (high) | `failOnFindings` |
| `oauth-inventory` | OAuth 2.0 server and its clients, server definitions and their client configurations, resource servers | `OAUTH_PASSWORD_GRANT`, `OAUTH_NON_HTTPS_ADDRESS` (medium, loopback excepted) | `failOnFindings` |

- Reports copy only named fields from the platform's answers; no password, hash, token or secret
  value can reach a result. The platform decides what the operator may read: reading users and
  services needs security administration privileges, and a refusal fails the step verbatim.
- **A certificate that expires, caught before it does (spec 020).** Put *Certificate expiry check*
  (*Warn days* 30) in a flow and schedule it weekly: the week a certificate enters the last 30 days,
  the scheduled run fails and its log and result name the certificate and its expiry date. Only
  certificates registered as x509 credentials carry a validity the platform reports; SSL/TLS
  configurations that point at certificate files are listed with "validity not reported".
- The security inventories read with security administration privileges, as the platform decides
  (observed on IRIS 2026.2): roles, resources and certificates need `%Admin_Secure:U`; OAuth needs
  `%Admin_OAuth2_Client:U`, `%Admin_OAuth2_Server:U` and `%Admin_OAuth2_Registration:U` (server
  clients). Without them the step fails with the platform's 403, or keeps what it could read and
  marks the rest `INCOMPLETE_READ`. Totals are
  kept in `summary` (roles, resources, credentials, configurations) even when the details are cut to
  fit the stored result. Private keys, key passwords and client secrets are never read into a result.
- The canvas's own page `/csp/sentai` is anonymous by design (it serves only static files) and the
  web application inventory reports it; that finding is expected.

#### Instance overview

Spec 018: every contest area readable on demand, on the primary instance, with the operator's own
credential. The area list is compiled (`sentai.overview.Areas`); a request can only name one of its
ids, never a platform path.

| Area | `GET /overview` headline (from one read) | Detail |
|---|---|---|
| `processes` | count, busiest process by commands | `GET /overview/readings/processes` — pid, user, namespace, routine, state, commands, globals, *CPU time (process)*, what the platform allows (`CanBeSuspended`, `CanBeTerminated`) |
| `locks` | count | `…/readings/locks` |
| `memory` | shared memory used (%) of the platform's `Total` row, most used consumer | `…/readings/memory` (`SMHUsedPercent` computed from the same answer) |
| `activity` | uptime, last backup, global refs/s, busy processes | `…/readings/activity` (system usage, dashboard, seize counters) |
| `devices` · `web-sessions` | count | `…/readings/devices`, `…/readings/web-sessions` (never the session id) |
| `licenses` | units in use and authorized (`license-usage` summary) | `…/readings/licenses` |
| `security` · `web-apps` · `alerts` · `secrets` | enabled accounts · web applications · serious alerts and application errors · wallet collections | `POST /overview/reports/{stepType}` runs the spec 013 report on demand (same code, same findings, no run) |

- Each area of the summary carries its own outcome — `ok`, `refused` (the platform's HTTP status
  and `platformStatus` verbatim) or `unreachable` — so an operator without security administration
  still sees every instance area. The summary makes 10 platform reads for 11 areas (≈0.25 s on the
  dev stack) and never runs a report.
- `POST /overview/areas/{area}/flow` turns a report area into an ordinary one-step flow
  (`Check: <label>`) that passes the validation gate and can be scheduled with `/schedule`.
- Process actions call `POST /api/admin/v2/process/<action>?id=<pid>` as the platform's contract
  requires (proved in [spec 018 evidence](specs/018-instance-overview-api/evidence/)); terminate
  answers `428` until the body carries `{"confirmation": "<pid>"}`. Every action that reached the
  platform is recorded (`GET /overview/process-actions`), accepted or refused; the product never
  refuses a pid on its own.

#### Declared step types

Besides `integrity-check` (run through the platform's management API), some step types are
**declared**: an entry in the closed catalog (`XData Catalog` in `sentai.registry.StepType`,
`executor: "in-process"`) names a class extending `%SYS.Task.Definition` and the schema of the
parameters it takes. A step of that type runs the class's `OnTask()` on a Work Queue Manager worker
of the step's category, inside IRIS.

| Type | Class | Parameters | Notes |
|---|---|---|---|
| `storage-headroom-check` | `sentai.steps.StorageHeadroomCheck` | `minFreePercent` number 0–100, default 10 | Read-only. Fails when a database directory or the journal directory has less free disk than the threshold, naming each location and its free %. Embedded Python (`shutil.disk_usage`). |
| `db-size-report` | `sentai.steps.DatabaseSizeReport` | — | Read-only. `result.databases` lists every database with `sizeMB` and `freeMB` (`%SYS.DatabaseQuery:FreeSpace`). |
| `switch-journal` | `%SYS.Task.SwitchJournal` | — | Starts a new journal file. Needs `%Admin_Operate:USE`; without it the platform's `#921` text is the failure reason. |
| `purge-task-history` | `%SYS.Task.PurgeTaskHistory` | `keepDays` integer ≥ 0, default 30 | Destructive (typed confirmation, not schedulable). Available since the canvas asks for the typed confirmation at *Run now* (spec 007 T009). |

- **Adding one** is a code change reviewed in a pull request: write the class (extending
  `%SYS.Task.Definition`, optionally with a `Result` property holding JSON text) and add one catalog
  entry with its `parameters`. Nothing an operator types ever selects code: the class comes from
  the catalog by the step's `type`, properties are set by iterating the declared schema, and a
  legacy `custom` step's `customClass` is never read on any execution path.
- **Identity.** A declared step runs **as the operator who dispatched the run**: the worker takes
  the identity of the run loop that queued it. The platform decides, at that moment, whether that
  operator may do the work, and its refusal is the step's failure reason, verbatim. Each step shows
  who ran it in `executedAs` (`GET /runs/{guid}` → `steps[]`). A run has one identity:
  `/dispatch` with a `runCredential` of another user is refused with 403
  `RUN_CREDENTIAL_USER_MISMATCH` before any run exists, and only the dispatcher may re-run a step
  (403 `RERUN_NOT_BY_DISPATCHER`). In a scheduled run, declared steps run as the schedule's
  run-as account (spec 015).
- **Timeout.** `timeoutMinutes` (60 when 0) counts from the moment the step becomes `running`,
  which includes the time spent waiting for a worker under the category's limits. A timed-out or
  cancelled step's work may still finish in the background; its late result is discarded.
- **Result.** A class's `Result` is shown as `result` in the run read (`{}` when none), at most
  8000 characters: a larger report keeps the first elements of its largest list and adds
  `"truncated": true, "omitted": <n>`.

#### 🔎 Semantic step-type search and the embedding provider

The palette's search box also accepts a sentence — "free up disk space", "rotate the journal" —
and offers the closest catalog entries first, above today's list. The ranking is cosine similarity
between the query's embedding and the description each catalog entry carries, so what a
capability is *for* in the operator's terms is what makes it findable.

Try it in the palette's search box: type the **job**, not the tool's name — the closest entries
appear under **SUGGESTED** within a beat of the last keystroke (scores below as measured on the
dev stack with `all-MiniLM-L6-v2` running inside IRIS; `q` is the query, `matches` rank best-first
and only what clears the 0.20 floor):

| You type | SUGGESTED offers first |
|---|---|
| `free up disk space` | Storage headroom check (0.59), Compact globals (0.49) |
| `get rid of old audit records` | Purge audit records (0.71), Purge task history (0.33) |
| `rotate the journal` | Switch journal (0.55) |
| `check my globals are sound` | Integrity check (0.47) |

The same query over the API:

```sh
curl -s -H "Authorization: Bearer $TOKEN" --get \
  --data-urlencode 'q=free up disk space' \
  http://localhost:52773/csp/sentai/api/v1/catalog/step-types/search
# {"available":true,"matches":[{"type":"storage-headroom-check","score":0.59}, …]}
```

Two answers that look empty but are working correctly: `order me a pizza` answers
`{"available":true,"matches":[]}` — nothing in the catalog is close, and below the floor the
palette offers nothing rather than something wrong; and a lone keyword like `structure` stays
below the floor too (one word against nine full sentences) — **intent sentences are the semantic
path, keywords are today's substring path** (which keeps working underneath: typing `journal`
still narrows to Switch journal on every keystroke, before any request).

The embedding provider is **a row in the platform's `%Embedding.Config` table, never code**. With
no row at all the app runs exactly as before — search narrows by entry text, and nothing about the
palette changes (that is also the state CI runs in). On the dev stack this row is **installed by the build** (`iris-provider.script`), so
`docker compose up -d` comes up with search working and nothing manual; delete the row to run the
stack without a provider, and it stays deleted until the next image rebuild.

One row, in `IRISAPP`, is the whole setup. The dev and demo images install this one — the model
runs **inside IRIS** (spec 017), from files baked into the image, with no network at run time:

```sql
INSERT INTO %Embedding.Config (Name, EmbeddingClass, Configuration, VectorLength, Description)
VALUES ('sentai-steps', 'sentai.search.LocalEmbedding',
        '{"modelName":"sentence-transformers/all-MiniLM-L6-v2","cachePath":"/usr/irissys/mgr/sentai-models"}',
        384, 'Step-type search, in-process');
```

`Configuration` names the model and the directory it is cached in: `modelName`, `cachePath`, and an
optional `pythonPath` (an extra directory to import the Python packages from). The row's validating
trigger rejects a configuration whose packages do not import or whose model is not in `cachePath`,
at insert time, with a message that says which. One process, `sentai.search.EmbeddingWorker`, holds
the model and answers every search (see [Where SentaiTask uses Embedded Python](#-where-sentaitask-uses-embedded-python-and-why));
the image starts it right after IRIS, and the first search starts it anywhere else.

**Your own model server instead** — for example an [ollama](https://ollama.com) you run — is the
same one row with `sentai.search.EmbeddingService`, which speaks the OpenAI-compatible
`POST /v1/embeddings`:

```sql
INSERT INTO %Embedding.Config (Name, EmbeddingClass, Configuration, VectorLength, Description)
VALUES ('sentai-steps', 'sentai.search.EmbeddingService',
        '{"host":"my-ollama","port":11434,"https":0,"path":"/v1/embeddings","model":"all-minilm"}',
        384, 'Step-type search, my ollama');
```

Its `Configuration` is the endpoint: `host`, `port`, `https` (`0`/`1`), `path` (normalized onto a
leading slash), `model`, and an optional `apiKey` (sent as `Authorization: Bearer …` only when
present); the trigger rejects a configuration missing `host`, `path` or `model`. Changing the row
rebuilds the stored corpus with the new provider on the next search, so two models' vectors are
never compared.

**Pointing at a different provider is a row change, not a code change.** The table names the class:
`%Embedding.OpenAI` (a hosted provider) is a row in the same table with its own `Configuration`, and
`sentai.search.EmbeddingService` speaks the OpenAI-compatible shape any such provider serves. The
platform's `%Embedding.SentenceTransformers` works too but is not recommended here: it loads the
model again on every call (≈3.4 s per search measured, spec 017 research R-1), where
`sentai.search.LocalEmbedding` loads it once.

> **A hosted provider sends the operator's query text off the machine.** What you type into the
> palette's search box travels, as the request body, to whatever host the row names. The default
> in-process provider keeps it inside IRIS, and a model server you run keeps it on your network; a
> hosted one does not — that is the trade-off, and it belongs to whoever writes the row. If the provider is unconfigured, unreachable, too slow,
> still loading its model (`warming` — the first seconds after the instance starts, while the
> in-process provider's model loads), or returns vectors the stored corpus cannot compare with, the
> answer is today's palette — no error, no toast, and never a masquerading "no results". The next
> search after `warming` ranks as usual.

#### 🐍 Where SentaiTask uses Embedded Python, and why

`sentai.steps.StorageHeadroomCheck` reads the free disk of every database directory and of the
journal directory with Python's `shutil.disk_usage`. Asking the filesystem how much room is left
is Python's natural job, and it works the same on every OS IRIS runs on. What is IRIS's own stays
in ObjectScript: the list of directories comes from the platform, the threshold comparison and the
`%Status` contract are ObjectScript, and a failure names each location with its free percentage.

It is a real step, not a demo: put it at the head of a nightly flow and the integrity checks behind
it only start when there is room for them.

**The semantic search model (spec 017).** Intent search embeds text with `sentence-transformers`
inside the instance, because the model library is Python. It runs in one process,
`sentai.search.EmbeddingWorker`, which loads the model once and answers every search (≈12 ms each)
— loading it in each web-server process would cost ≈500 MB and a ≈10 s load per process. Python
does two things there: load the model and encode a text. ObjectScript owns everything around them:
starting and stopping the process, the `$SYSTEM.Event` exchange with `sentai.search.LocalEmbedding`
(the provider the configuration row names), the timeouts, and every failure as a value
(`warming`, `slow`, `error`). The model is loaded from its local files only, with no code allowed
to arrive with it.

#### The task catalog: the platform's Task Manager, as the platform reports it

`GET /catalog/tasks` lists every scheduled task on the instance, not only SentaiTask's. Every value
is the platform's own, read with **your** token. Anything the platform did not report is absent;
nothing is filled in (spec `006-task-catalog-api`).

```sh
curl -s "http://localhost:52773/csp/sentai/api/v1/catalog/tasks?q=integrity&filter=suspended" \
  -H "Authorization: Bearer $TOKEN"
# {"total": 22, "matched": 1, "items": [{"taskId": 4, "name": "Integrity Check", "namespace": "%SYS",
#   "class": "%SYS.Task.IntegrityCheck", "runAsUser": "_SYSTEM", "timePeriod": "Weekly",
#   "nextRun": "2026-09-28 02:00:00", "lastStarted": "", "lastFinished": "", "status": "1",
#   "lastError": "", "suspended": true, "destructive": false, "destructiveUnknown": false, ...}]}
```

**Where each value comes from.** The platform's management API: the list read says which tasks
exist; the single read gives `class`, `runAsUser` and `timePeriod`; the info read gives `status`,
`lastError`, `lastStarted`, `lastFinished`, `nextRun` and `suspended`. The item read
(`/catalog/tasks/{id}`) also returns `recentRuns`.

- The in-process path (`%SYS.Task` objects) is deliberately not used. On IRIS 2026.2 it does not
  check `%Admin_Task`: a user without that privilege could read every task and suspend one, while
  the management API refuses the same user with 403.
- The platform's list read is lossy, so it is never used for values. It reports every suspended
  task as `Suspended: false`, and it truncates `NextScheduled` to minutes (`"Runs After #1:00"`
  for run-after tasks).

**Reading the values.**

| Field | What it means |
|---|---|
| `status` | `"1"` means OK. After a failed run, it is the platform's own error text for its stored status, the same text as the portal and the history show |
| `lastError` | The platform's `Error` field verbatim. It reads `"Success"` after a successful run and is empty after a failed one; the failure text is in `status` |
| `nextRun` | Verbatim, and `""` when the platform has none (for example a run-after task; see `timePeriod`). A suspended task keeps its `nextRun` |
| `description` | The platform's own `Description` (single read), verbatim. Absent when the platform sent none or the read failed |
| `destructive` / `destructiveUnknown` | From the step-type catalog only. A class the catalog does not name is `destructiveUnknown: true`, never a guess. SentaiTask's own scheduled tasks take it from the step they run |
| `origin` | `{flowId, stepId, flowExists}` on tasks named `SentaiTask: <flowId>#<stepId>` (the product's generator) |
| `unavailable` | Lists the fields a failed per-task read would have given, with the platform's HTTP status and its `status` object verbatim |
| `recentRuns` | Item read only: up to 5 executions from the platform's history, with its own keys. There is no duration, because the platform's precision is minutes |

`isDestructive` and `lastRun` remain as deprecated aliases of `destructive` and `lastFinished`.

**Filters.** `q` (name or class, case-insensitive), `namespace`, `filter=all|scheduled|suspended`
("scheduled" means not suspended), `destructiveOnly=0|1|true|false` and
`unclassifiedOnly=0|1|true|false`. A task whose destructiveness is unknown is excluded by
`destructiveOnly` and is exactly what `unclassifiedOnly` keeps. Other values → 400
`INVALID_FILTER`. `total` and `matched` give "N of M"; `counts` gives `suspended`, `destructive`
and `unclassified` over every task, before any filter, so they do not change when a filter does.

**Suspend and resume.** `POST /catalog/tasks/{id}/suspend` with `{"suspended": true|false}` calls
the platform's `task/suspend` or `task/resume`, then reads the task again.

- The answer is 200 with the task as re-read.
- The platform answers 200 even when its suspend fails internally, so if the re-read shows the old
  state the answer is 502 `SUSPEND_NOT_APPLIED`, with the platform's read attached.

**Privilege and refusals.** The operator needs `%Admin_Task` for reads and for suspend/resume.
That `%Admin_Operate` alone is enough for reads is only what the platform's source suggests; it
was not proven.

- A refusal comes back with the platform's HTTP status and its `status` object as
  `platformStatus`.
- On 2026.2 a 403 carries no reason, and none is added.

---

## 🌐 Implements DPI-I-588 (Distributed Work Manager)

InterSystems Ideas [DPI-I-588 "Distributed Work Manager"](https://ideas.intersystems.com/ideas/DPI-I-588)
asks for work dispatched in the background to any reachable IRIS server — for example an async or
failover mirror member — with status checks, results collected on the primary, and management of
each target. SentaiTask implements it inside its existing model (spec
[`008-distributed-targets`](specs/008-distributed-targets/spec.md)): **a flow step can name a
target server**, and the run follows it exactly as it follows a local step.

```sh
# 1. Register the target (the compose stack ships one: iris-target)
curl -X POST -H "$H" -d '{"name":"iris-target","baseUrl":"http://iris-target:52773"}' $API/targets
# 2. Sign in to it through the primary — returns the target's own token pair, keeps nothing
curl -X POST -H "$H" -d '{"user":"_SYSTEM","password":"…"}' $API/targets/iris-target/sign-in
# 3. Its state and load, as the target reports them
curl -H "$H" -H "X-Sentai-Target-Authorization: Bearer <target access token>" $API/targets/iris-target/status
# 4. A step with "target": "iris-target"; dispatch with one credential per target used
#    ... "targetCredentials": [{"target": "iris-target", "refreshToken": "<target refresh token>"}]
```

**What is implemented**

- **Remote dispatch.** A step on a target starts its job on that instance's management API and is
  followed with the same states and live events; each step run says where it ran (`executedOn`).
  Proven with the demo flow — two integrity checks on the primary and one on `iris-target`, fanning
  in — whose remote report names the target machine
  ([evidence](specs/008-distributed-targets/evidence/t008-demo-run.json)).
- **Results on the primary.** The job's own report is kept as the step's `result`.
- **Targets and their state.** Register, edit, delete; a live status read (reachable, IRIS version,
  Work Queue Manager categories and their worker configuration, as the target reports them); an
  operator-set *online/offline* flag — an offline target is refused at validation and dispatch.
- **Control.** Cancel and pause are forwarded to the instance running the job.
- **Failures as values.** `TARGET_NOT_FOUND`, `TARGET_OFFLINE`, `TARGET_UNREACHABLE` (transport
  error verbatim), `TARGET_REFUSED`, `STEP_TYPE_NOT_REMOTE_CAPABLE`, `TARGET_CREDENTIAL_MISSING`,
  `TARGET_CREDENTIAL_USER_MISMATCH`. A target that stops answering mid-run fails only its step,
  after the step's timeout, with the last transport error.

**What is deliberately different**

- **A closed catalog, no arbitrary code.** The idea mentions calling any method or `$$` function
  remotely. SentaiTask does not: only step types from its declared catalog run on a target, and no
  code, method or class name is ever taken from input (Constitution II).
- **The operator's own credential per target.** There is no service account and no stored
  password: the operator signs in to each target used by a flow; the credential lives only for the
  run, in non-persistent storage, and is erased at its end. The target alone decides what the
  operator may do there.
- **Placement is the operator's.** Each step names its target; nothing is placed automatically.

**What is future**

- Declared in-process steps on a target (they need SentaiTask installed there).
- Discovering targets from the mirror configuration and their mirror role.
- Callbacks from the target; load-based placement.
- A queue length per category: the platform's management API does not report one today
  ([T001 evidence](specs/008-distributed-targets/evidence/t0-summary.md)).

---

## ⚠️ Known limitations (v1)

SentaiTask v1 only promises what was proven on IRIS 2026.2. The main points:

- **Step types not yet proven:** `compact-globals`, `defragment-globals`, `purge-audit-records` and
  the legacy `custom` are listed with `available: false` and refused with
  `STEP_TYPE_NOT_SUPPORTED_ON_TARGET`. Every other type in the catalog — the integrity check, the
  journal switch, the task-history purge, the storage and size reports and the seven report steps —
  runs.
- **Remote steps (DPI-I-588):** management-API types (`integrity-check`) and the report steps run on
  a target; declared in-process types do not (they would need SentaiTask installed there). Targets
  must be `https` unless loopback — the compose demo allows `http` on its own network only.
- **Schedules use the instance's clock**, overlapping runs of the same flow are not prevented, and
  flows with a destructive step cannot be scheduled (they run by hand, with typed confirmation).
- **Long runs need a run credential.** The canvas handles it at *Run now*; a plain `curl` dispatch
  without `runCredential` stops after the platform's 60-second token.
- **Flows must name an existing WQM category**, such as `Default`. Categories are read and edited
  through the API only; the canvas has no category screen yet.
- **Validating needs `%Admin_Manage:USE` and read on IRISSYS**; the platform decides the rest.
- **The overview is for the primary instance only**, and shows instance resources only: the
  management API reports no host CPU, host memory or console log.
- **Semantic search warms up.** For the first seconds after the instance starts (≈7–11 s measured)
  the search model is loading and intent search answers `warming` — the palette behaves as it does
  without semantic search. One worker process serves every search, one at a time (≈12 ms each).

The complete list, with the reasons behind each point, is in
[`docs/limitations.md`](docs/limitations.md).

---

## 🧪 Running the tests

```sh
docker exec -it sentai-task-iris-1 iris session iris -U IRISAPP
```

```objectscript
IRISAPP>zpm "load /home/irisowner/dev"
IRISAPP>zpm "test sentai-task -only"
```

The suite (`sentai.unittest.*`, 268 methods) runs against a test double of the management API, so
it never starts real platform jobs through the admin API.

Some tests ask the Work Queue Manager for a category that does not exist, on purpose, to check
that the step fails with the platform's own message. IRIS logs each of those refusals at severity
2, which puts the instance in the *alert* state, so Docker then reports the container as
`unhealthy` (its healthcheck accepts only `ok` and `warn`). **Cancelling a running step does the
same:** SentaiTask forwards the cancel to the platform (`async-result/cancel`), and IRIS 2026.2 ends
the job's worker, which its Work Queue Manager logs as `ERROR #7802 … unexpectedly shut down`
(severity 2) — a plain IRIS with nothing installed logs it too
([evidence](specs/008-distributed-targets/evidence/t0-summary.md)). SentaiTask does not clear the
alert itself, since that would hide real ones. After running the suite, or cancelling steps, on an
instance you keep using, clear the state:

```objectscript
%SYS>do $SYSTEM.Monitor.Clear()
```

The canvas has unit tests and end-to-end acceptance tests (these need Node 20+ on your machine and
the container running):

```sh
cd frontend
npm ci
npm test                    # unit tests (vitest)
npx playwright install chromium
npm run test:e2e            # acceptance tests against http://localhost:52773
```

The acceptance tests drive real runs, so they take about six minutes; screenshots and captures
land in [`specs/002-canvas-ui/evidence/`](specs/002-canvas-ui/evidence/) and
[`specs/007-canvas-management-screens/evidence/`](specs/007-canvas-management-screens/evidence/).
Some catalog tests create a temporary IRIS user through `docker exec` (container
`sentai-task-iris-1`, or `SENTAI_CONTAINER`) and delete it at the end. After changing the
frontend, `bash scripts/publish-canvas.sh` copies a fresh build into the running container.

---

## 🗂️ Project Structure

```
sentai-task/
├── src/sentai/
│   ├── model/          # Flow, Step, Edge, Join, Run, StepRun, Category, LogEntry, Schedule, Target…
│   ├── registry/       # StepType: closed catalog (destructive / pausable / available / remoteCapable)
│   ├── validation/     # FlowValidator: the single gate for validate, dispatch and schedule
│   ├── dispatch/       # WaveDispatcher, AdminApiClient, executors, RunNarrator (run log)
│   ├── steps/          # Declared in-process steps (StorageHeadroomCheck uses Embedded Python)
│   │   └── reports/    # Read-only report steps: security, web apps, alerts, secrets, certificates, OAuth
│   ├── schedule/       # ScheduleService, Timing, Wallet (run-as credential in the IRIS Wallet)
│   ├── targets/        # TargetService: target servers (DPI-I-588)
│   ├── overview/       # OverviewService, Readings, ProcessActions: the instance overview
│   ├── search/         # Semantic step-type search, in-process embeddings (Embedded Python)
│   ├── wqm/            # CategoryService: WQM read/write passthrough
│   ├── catalog/        # TaskService: native Task Manager catalog
│   ├── demo/           # Demo and showcase flows
│   ├── rest/           # Dispatcher: REST API + SSE
│   └── web/            # StaticFiles: serves the canvas build
├── tests/sentai/unittest/   # %UnitTest suites + AdminApiDouble
├── frontend/           # Canvas UI: SvelteKit + Svelte Flow, built to static files
├── docs/               # Full known-limitations list, use cases
├── design/             # Canvas UI prototypes (spec 002)
├── specs/              # Spec-driven history, one directory per feature (001 → 020)
├── scripts/sanitation/ # Reviewed cleanup of historical test residue
├── module.xml
└── docker-compose.yml
```

---

## 🎖️ Credits

SentaiTask is developed with 💜 by the **Musketeers Team**:

- [José Roberto Pereira](https://community.intersystems.com/user/jos%C3%A9-roberto-pereira-0)
- [Henry Pereira](https://community.intersystems.com/user/henry-pereira)
- [Henrique Dias](https://community.intersystems.com/user/henrique-dias-2)

![3Musketeers-br](./assets/3musketeers.png)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

## 🎬 Bonus: Musketeers Sentai

When the flow validates clean, the squad suits up.

![Musketeers as a sentai squad](./assets/muskteers-rangers.jpg)

