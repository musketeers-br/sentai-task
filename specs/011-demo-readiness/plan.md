# Implementation Plan: Demo Readiness — A Public Demo That Stays Up and a README That Sells in One Screen

**Branch**: `feat/spec011` (feature dir `011-demo-readiness`) | **Date**: 2026-09-28 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (5 clarifications, 21 FRs, 7 SCs). Mostly operations and
documentation: a compose override and three host scripts for the public demo, one ObjectScript
class that seeds, resets and reports on a demo instance, two small canvas changes (demo sign-in
hint, cancel alert notice) and a README restructure. The product API does not change, so there is
**no `contracts/` directory**.

## Summary

Five increments, one per story:

1. **README first screen (US1).** Reorder the top of `README.md`: badges → title and pitch →
   product picture → **Try it** → contest-area table → Motivation. The picture is a still PNG
   taken from the existing e2e evidence of a finished run (spec 014 replaces it with the animated
   GIF in place). The roadmap gains 010 as done and 012–015 as next.
2. **Safe public demo (US2).** `docker-compose.demo.yml` overrides the stack for a public machine:
   the IRIS services publish **no** host port, and a **Caddy** reverse proxy is the only public
   entry. It serves `/csp/sentai/*` and `/api/admin/*` and answers 404 to everything else, so the
   management portal is not reachable. It serves HTTPS automatically when `DEMO_HOST` is set.
   `scripts/demo/up.sh` refuses to run without `SENTAI_DEMO_SECRET`, starts the IRIS services,
   waits for them to be healthy, **secures** them (every enabled password account holding a role
   gets the secret, on both instances), creates the demo account and role, seeds the flows, and
   only then starts Caddy.
3. **Showcase flow and sign-in hint (US3).** `sentai.demo.Demo.Seed()` creates the spec 010
   example and **"Showcase: nightly checks across servers"**: three parallel integrity checks (two
   local databases and one on `iris-target`) → an `ALL_MUST_SUCCEED` join → `db-size-report`. The
   up script writes `/opt/sentai-web/demo.json` (`{"account": …, "password": …, "showcase": …}`);
   the sign-in screen reads it and shows the hint. On a normal installation the file does not
   exist (404), so nothing is shown.
4. **Reset and status (US4).** `scripts/demo/reset.sh` and `scripts/demo/status.sh` call
   `sentai.demo.Demo.Reset()` / `.Status()` on the primary and a small ObjectScript snippet on the
   target (which has no SentaiTask code). Reset refuses unless `^sentai("config","demo")` is set.
   A host cron line, documented in the README, runs the reset daily.
5. **Cancel alert notice (US5).** A pure helper `cancelRaisesAlert(run, flow, registry)` decides
   whether a running step is executed through the management API. *Cancel wave* shows the notice
   when it is true; a running management-API step's *Cancel* opens a confirmation with the same
   notice. The *Cancel* tooltip is corrected.

## Technical Context

**Language/Version**: ObjectScript on IRIS 2026.2 community (one new class); TypeScript 5.9 +
Svelte 5 for the canvas (two touched components, one pure module); POSIX shell for the host
scripts; Caddy 2 for the demo proxy; Markdown for the README.

**Primary Dependencies**: `caddy:2-alpine` image (demo override only; not used by the default
stack). No new npm or IPM dependency.

**Storage**:
- `^sentai("config","demo") = 1` marks a demo instance (set by `up.sh`, read by Reset/Status).
- `^sentai("demo","lastReset") = $lb(timestamp, outcome, detail)` is the reset record.
- `/opt/sentai-web/demo.json` is written in the container by `up.sh` (public: it holds only the
  published demo account).
- `SENTAI_DEMO_SECRET` and `DEMO_HOST` live in the host's `.env` (already gitignored).

**Testing**:
- IRIS `%UnitTest` for `sentai.demo.Demo` (seed idempotence, reset guard, reset result, status
  shape) in `tests/sentai/unittest/DemoTest.cls`, run with `zpm "test sentai-task -only"`.
- vitest for `cancelRaisesAlert` and the `demo.json` parser.
- Playwright `us22-cancel-alert-notice.spec.ts` and `us23-demo-sign-in-hint.spec.ts` against the
  dev stack.
- A shell acceptance script `scripts/demo/acceptance.py` for US2 and US4 against a demo stack
  started under a separate compose project name on alternate ports (the clean-checkout pattern
  used on 2026-09-27), so the dev stack is not touched.

**Target Platform**: A Linux VM with Docker Engine and Compose v2.24+ (for `!reset` in the
override). Development and acceptance on the team's Windows machine with Docker Desktop.

**Project Type**: Web application (IRIS backend + static canvas) plus deployment tooling.

**Performance Goals**: SC-002: demo up in < 15 min on a clean VM (image build dominates, about
6–8 min measured on the clean-checkout run). SC-004: showcase run finishes in < 60 s (the clean
smoke run of the same shape finished in about 20 s).

**Constraints**:
- The secret never appears in the repository, on a command line (it is passed on stdin), or in
  logs.
- The product never clears or masks the alert state itself (FR-020): only `reset.sh` does, as a
  host action.
- The default `docker compose up` stack is unchanged: the override is opt-in.
- UI text in English. The top bar is not touched.

**Scale/Scope**: 1 ObjectScript class (~200 lines) and its test; 1 compose override; 1 Caddyfile;
4 shell scripts; 1 pure TS module; 2 touched Svelte components; README top section and roadmap.
Unit tests 145 → ~155; e2e 65 → ~69; backend 269 → ~279.

## Constitution Check

*GATE: evaluated before Phase 0 and re-evaluated after Phase 1 (see end). No violations.*

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | Host scripts are an edge that calls one application-level class (`sentai.demo.Demo`); the class uses the existing model and never reaches into the REST layer. In the canvas, the pure `run/cancel-alert.ts` decides and the components only render. | ✅ |
| **II Closed Capability Set** | No new API operation. `sentai.demo.Demo` is not routed; it is invoked only from a host shell on the instance. The showcase flow is fixed data made of declared step types. `demo.json` is data read by the canvas, never evaluated. | ✅ |
| **III Delegated Authorization** | The demo account's powers come only from a platform role the platform enforces; the canvas shows its refusals verbatim. Nothing in the product checks "is this the demo account". The alert state is cleared only by the host's explicit reset (FR-020). | ✅ |
| **IV Errors as Values** | `Demo.Seed/Reset/Status` return a `%DynamicObject` outcome (`{ok, steps:[…], problems:[…]}`); the scripts print it and exit non-zero on `ok: false`. `cancelRaisesAlert` is a total function. | ✅ |
| **V Verifiable Increments** | Five increments, each with its failing test first (see *Increments*). Dependencies declared: US3's seed is called by US2's `up.sh` and US4's reset; US1's "Try it" block needs US2's address and account. | ✅ |
| **VI Technology Agnosticism** | Caddy, shell and cron appear only in this plan and research. | ✅ |
| SOLID / SoC | Securing accounts (`secure-*.script`), seeding (`Demo.Seed`), resetting (`Demo.Reset`), reporting (`Demo.Status`) and proxying (Caddyfile) are separate units. | ✅ |
| TDD | `DemoTest` and the two e2e specs are written and seen failing first; the shell acceptance script is written before `up.sh`/`reset.sh`. | ✅ |
| YAGNI | No uptime service, no product-level demo mode switch, no delete-flow API. | ✅ |
| Reproducibility | The demo is one command (`scripts/demo/up.sh`) on top of the existing compose file; the local quickstart stays three commands. | ✅ |

## Decisions

### README (US1)

- **D-1 Order.** Badges → `# 🦸 SentaiTask 戦隊` → pitch line → `assets/sentai-run.png` →
  `## 🚀 Try it` → `### Contest areas covered` (moved up from under Motivation) → `## 🌌 Motivation`
  (without the table) → rest unchanged.
- **D-2 Try it.** Three lines: the public demo address (placeholder `https://<DEMO_HOST>/csp/sentai/`
  replaced with the real one when US2 is live), the demo account, and the local quickstart:
  `git clone … && cd sentai-task`, `docker compose up -d --build`, open
  `http://localhost:52773/csp/sentai/` (sign in `_SYSTEM` / `SYS`). One sentence: "The local
  quickstart works even if the demo is down."
- **D-3 Area rows link to proof.** Each row gains a link to its README section or spec folder.
  Rows for 012–015 are **not** added here; each of those specs updates its own row when merged
  (FR-003).
- **D-4 Picture.** `assets/sentai-run.png`, copied from the existing evidence of a finished
  distributed run (`specs/009-canvas-distributed-targets/evidence/us3-remote-run.png`; if it is
  not legible at README width, `specs/002-canvas-ui/evidence/e1-demo-wave-completed.png`). Spec
  014 swaps it for `assets/sentai-run.gif` without moving it.

### Public demo (US2)

- **D-5 Override, not a fork.** `docker-compose.demo.yml` is used as
  `docker compose -f docker-compose.yml -f docker-compose.demo.yml`. It sets `ports: !reset []` on
  `iris` (so 1972, 52773 and 53773 are not published), adds `caddy` (ports `${DEMO_HTTP_PORT:-80}:80` and
  `${DEMO_HTTPS_PORT:-443}:443`, a volume for certificates, `restart: always`), and passes
  `DEMO_HOST` to it. `up.sh`, `reset.sh` and `status.sh` accept `--env-file <file>` (default
  `.env`) and honour `COMPOSE_PROJECT_NAME`, so the local acceptance can run a second, isolated
  demo stack next to the dev stack ([quickstart A](quickstart.md)).
- **D-6 Proxy allow-list.** Caddyfile (`demo/Caddyfile`):
  `{$DEMO_HOST::80} { @allowed path /csp/sentai/* /api/admin/*; handle @allowed { reverse_proxy iris:52773 }; handle { respond 404 } }`
  plus `redir / /csp/sentai/`. With a real host name, Caddy obtains and renews the certificate
  itself and redirects HTTP to HTTPS (spec US2-2). With no host name, the site is `:80` over
  plain HTTP ([R-3](research.md)).
- **D-7 Securing accounts.** `scripts/demo/secure-accounts.script` (ObjectScript, run in `%SYS`
  through `iris session` on each instance, secret on stdin): every user with `Enabled=1`, a
  password login and at least one role, except the demo account, gets the secret. On the running
  stack this is `_SYSTEM`, `SuperUser`, `Admin`, `_Ensemble` and `irisowner`
  ([R-2](research.md)). `CSPSystem` has no roles and its password is held by the web gateway's
  `CSP.ini`, so it is left alone. Changing it would break the gateway and gain nothing.
  `UnknownUser` has no password.
- **D-8 Demo account.** User `sentai-demo`, password `sentai-demo-2026` (published), role
  `SentaiDemo`, on both instances. The role holds exactly the resources the T001 spike proved
  necessary ([evidence](evidence/t001-demo-role.md)): primary `%DB_IRISAPP_CODE:R,
  %DB_IRISAPP_DATA:RW, %Admin_Manage:U, %DB_IRISSYS:RW, %Admin_Operate:U` plus SQL `SELECT,
  INSERT, UPDATE, DELETE ON SCHEMA sentai_model` and `EXECUTE ON %SYS.DatabaseQuery_FreeSpace`;
  target `%DB_USER:R, %Admin_Manage:U, %DB_IRISSYS:RW, %Admin_Operate:U`. It holds **no**
  `%Admin_Secure`. The account is recreated with the published password by every reset.
- **D-9 Order in `up.sh`.** (1) refuse without `SENTAI_DEMO_SECRET`; (2) `compose up -d --build
  iris iris-target --wait`; (3) secure both instances; (4) create the demo role and account on
  both; (5) `Demo.Setup(1)` on the primary (the explicit `1` is required, so an accidental call on a normal installation does nothing; it sets the demo marker, registers `iris-target`, seeds the
  flows, writes `demo.json`); (6) `compose up -d caddy`. Visitors can reach nothing before step 6
  (FR-006).
- **D-10 Reboot.** Every service has `restart: always`; Docker Engine is enabled at boot on the VM
  (documented). Securing and seeding persist in the IRIS databases, which live in the image's
  data directories. No init runs on restart ([R-5](research.md) checks that a restart keeps them).

### Showcase and hint (US3)

- **D-11 Showcase composition.** `Showcase: nightly checks across servers`, default category
  `Default`:
  - `01` integrity-check `USER` (`/usr/irissys/mgr/user/`)
  - `02` integrity-check `IRISAPP` (`/data/IRISAPP_DATA/` as in the clean-checkout smoke)
  - `03` integrity-check on `iris-target`
  - `04` `db-size-report`, after an `ALL_MUST_SUCCEED` join on 01–03.

  All four types are available and non-destructive today. Timeouts are 30 min.
- **D-12 Seed is idempotent.** `Seed()` finds each flow by exact name. If it is missing, or its
  steps differ from the shipped definition, it replaces it; otherwise it leaves it alone. The spec
  010 example uses the same definition as `frontend/src/lib/flows/example.ts`, duplicated in
  ObjectScript with a unit test that compares both through the API shape ([R-6](research.md)).
- **D-13 Hint source.** `demo.json` beside `index.html` in `/opt/sentai-web`. It is served by the
  existing public static file server, so it can be read before sign-in. The canvas fetches it once
  at the sign-in screen; any failure means "not a demo". The hint reads: "Demo account:
  `sentai-demo` / `sentai-demo-2026`. After signing in, open **Showcase: nightly checks across
  servers** from *Open flow…* and choose *Run now*."

### Reset and status (US4)

- **D-14 Reset.** `Demo.Reset()` (primary, guarded by the demo marker):
  1. deletes every flow not named like the two seeded flows, with its runs, step runs, log
     entries, edges and joins (same statements as the e2e `deleteFlowWithRuns`);
  2. runs `Seed()`;
  3. re-registers `iris-target` and sets it online;
  4. records `^sentai("demo","lastReset")`.

  `reset.sh` then, in `%SYS` on both instances, restores the demo account's password and runs
  `do $SYSTEM.Monitor.Clear()`. A `flock` on the host makes overlapping resets wait.
- **D-15 Status.** `Demo.Status()` returns `{flows, runs, visitorFlows, visitorRuns, lastReset}`.
  `status.sh` adds `docker inspect` health and `$SYSTEM.Monitor.State()` for both instances, and
  exits 1 if either is not healthy.
- **D-16 Daily schedule.** Host cron:
  `0 6 * * * cd /opt/sentai-task && scripts/demo/reset.sh >> /var/log/sentai-demo.log 2>&1`, and a
  twice-daily `status.sh` in the same way (SC-006). Documented in the README demo section.

### Cancel notice (US5)

- **D-17 Helper.** `frontend/src/lib/run/cancel-alert.ts`:
  `cancelRaisesAlert(steps: StepRunView[], flowSteps, registry): boolean` is true when a step run
  is `running` and its flow step's type has `executor === 'platform-api'` (local or on a target).
  `stepCancelRaisesAlert(stepRun, …)` applies the same test to one step.
- **D-18 Dialogs.** `RunScreen.svelte`: the existing *Cancel wave?* dialog gains a
  `<p class="notice" data-testid="cancel-alert-notice">` when the helper is true. `RunNode.svelte`:
  for such a step, *Cancel* opens a small confirmation dialog with the same notice (*Keep running*
  / *Cancel step*). The notice text: "IRIS records a cancelled platform job as an alert
  (severity 2), so the instance may report "unhealthy" until the alert is cleared. The run and
  the instance are fine. [Why](…/docs/limitations.md)". The link points at the GitHub
  `docs/limitations.md` anchor.
- **D-19 Tooltip.** "Asks the instance running this step to stop its job, and marks the step
  cancelled."

## Increments

| # | Story | First failing test | Then |
|---|---|---|---|
| 1 | US5 cancel notice | `cancel-alert.test.ts`; `us22` (notice present with running integrity check, absent with in-process only) | helper, two dialogs, tooltip |
| 2 | US3 seed | `DemoTest.TestSeedCreatesShowcase`, `TestSeedIsIdempotent`, `TestExampleMatchesCanvas` | `sentai.demo.Demo.Seed` |
| 3 | US4 reset/status | `DemoTest.TestResetRefusesWithoutMarker`, `TestResetRemovesVisitorFlows`, `TestStatusShape`; `acceptance.py` part B | `Reset`, `Status`, `reset.sh`, `status.sh` |
| 4 | US2 demo stack | `acceptance.py` part A (default password refused on both; portal 404; demo account runs showcase; missing secret refused) | override, Caddyfile, `secure-accounts.script`, `demo-account.script`, `up.sh` |
| 5 | US3 hint | `demo-info.test.ts`; `us23` (hint shown when `demo.json` exists, absent otherwise) | `SignIn.svelte` hint |
| 6 | US1 README | a README lint check in `acceptance.py` part C (order of headings, links resolve) | README edit, picture |

## Project Structure

### Documentation (this feature)

```text
specs/011-demo-readiness/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
├── analysis.md
└── tasks.md
```

### Source Code (repository root)

```text
docker-compose.demo.yml            # new: override for the public demo
demo/Caddyfile                     # new
scripts/demo/up.sh                 # new
scripts/demo/reset.sh              # new
scripts/demo/status.sh             # new
scripts/demo/secure-accounts.script   # new (ObjectScript for iris session, %SYS)
scripts/demo/demo-account.script      # new (ObjectScript for iris session, %SYS)
scripts/demo/acceptance.py         # new
src/sentai/demo/Demo.cls           # new: Setup, Seed, Reset, Status
tests/sentai/unittest/DemoTest.cls # new
frontend/src/lib/run/cancel-alert.ts (+ .test.ts)   # new
frontend/src/lib/shell/demo-info.ts (+ .test.ts)    # new
frontend/src/lib/run/RunScreen.svelte               # notice in Cancel wave
frontend/src/lib/run/RunNode.svelte                 # step cancel confirmation, tooltip
frontend/src/lib/shell/SignIn.svelte                # demo hint
frontend/tests/us22-cancel-alert-notice.spec.ts     # new
frontend/tests/us23-demo-sign-in-hint.spec.ts       # new
assets/sentai-run.png              # new
README.md                          # top section, demo section, roadmap
docs/limitations.md                # anchor for the cancel alert (existing text)
```

**Structure Decision**: The demo class lives in the product module (`src/sentai/demo/`) so that it
is tested with the rest of the backend. It is inert unless the demo marker is set. Everything that
only makes sense on a public machine (proxy, secrets, cron) stays in `demo/` and `scripts/demo/`,
outside the module.

## Complexity Tracking

No constitution violations.

## Constitution re-check after Phase 1

Re-evaluated after writing [research.md](research.md) and [data-model.md](data-model.md). The
reset deletes flows directly, but only as a host action behind the demo marker. It is not a
product operation (II) and it does not decide anyone's permissions (III). All rows still pass.
