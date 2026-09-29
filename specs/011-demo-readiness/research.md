# Research: Demo Readiness

Facts checked on the dev stack (`sentai-task-iris-1`, IRIS 2026.2 community) on 2026-09-28,
plus the items the first task (T001) must prove before the demo scripts are written.

## R-1 How the container serves HTTP

- **Observed**: port 52773 is served by an Apache `httpd` inside the container
  (`/usr/irissys/httpd/bin/httpd … -c Listen 52773`) with the web gateway. The gateway signs in to
  IRIS as `CSPSystem`, whose password is in `/usr/irissys/csp/bin/CSP.ini`.
- **Decision**: the demo does not publish 52773. Caddy on the compose network is the only public
  entry and proxies to `iris:52773`, so the gateway configuration stays as it is.
- **Alternative rejected**: editing the container's Apache configuration to block the portal.
  It would fork the base image's configuration and still publish the port.

## R-2 Which accounts must stop accepting the default password

- **Observed** (`SELECT Name, Enabled, Roles FROM Security.Users` in `%SYS`):
  `_SYSTEM` (%All), `SuperUser` (%All), `Admin` (Ensemble admin roles), `_Ensemble` (%All),
  `irisowner` (%All), all enabled; `CSPSystem` enabled with **no roles**; `UnknownUser` enabled
  with no roles and no password; `_PUBLIC` and `IAM` disabled.
- **Decision**: rule "enabled, has a password login, holds at least one role, and is not the demo
  account" → secret. This selects `_SYSTEM`, `SuperUser`, `Admin`, `_Ensemble` and `irisowner`
  today, and any account a later image adds. `CSPSystem` is excluded by the rule (no roles), which
  also keeps the gateway working (R-1).
- **To prove in T001**: after securing, `POST /api/admin/login` with `_SYSTEM:SYS` → 401 on both
  instances; the canvas still loads (gateway unaffected); `iris session iris -U %SYS` from the
  host still works (OS authentication for `irisowner` inside the container, which the scripts
  rely on). If the OS login breaks, the scripts switch to `iris session iris -U %SYS` with the
  secret on stdin.

## R-3 HTTPS without a host name

- **Decision**: with `DEMO_HOST` set, Caddy's automatic HTTPS obtains a certificate for that name
  (ports 80 and 443 must reach the VM) and redirects HTTP to HTTPS. Without it, the site address
  is `:80`, served over plain HTTP.
- **Why not self-signed HTTPS on an IP**: browsers warn loudly, which is worse for a voter than
  plain HTTP. The README tells the host to set a name (a free subdomain service works).
- **Edge case**: if the name does not resolve yet, Caddy keeps serving HTTP and retries issuance
  in the background. No restart is needed (spec edge case 1).

## R-4 Least privilege of the demo account (to prove in T001)

What the account must be able to do, and what the platform is known to require:

| Need | Known requirement (source) |
|---|---|
| Sign in to `/api/admin`, pass the product's token check | `GET /api/admin/info` answers 200 or 403 (spec 004) |
| Read and save flows, runs (IRISAPP tables) | SQL privileges on `sentai_model.*`, `%DB_IRISAPP_DATA:RW`, `%DB_IRISAPP_CODE:R` |
| Validate (WQM category read) | `%Admin_Manage:USE` and read on IRISSYS (docs/limitations.md) |
| Start and read an integrity check | to be measured: expected `%Admin_Operate:USE` |
| In-process `db-size-report`, `storage-headroom-check` | the queries they call, run as the operator (spec 005) |
| Task catalog read | `%Admin_Task:USE` or `%Admin_Operate:USE` (spec 006) |
| Sign in to the target | an account of the same name on `iris-target` with the integrity-check privileges there |

**Method**: create the role with the smallest candidate set, run the example and showcase flows as
`sentai-demo`, and add one resource at a time for each verbatim refusal until both complete. Then
confirm that `security-posture`-style reads (`GET /api/admin/v2/security/users`) are refused (no
`%Admin_Secure`), and that `purge-task-history` is refused at dispatch. Record the final set in
`evidence/t001-demo-role.md`.

**Risk**: `%Admin_Manage:USE` may allow changing WQM categories (spec 004 write path). This is
acceptable on a disposable demo: categories are recreated by nothing, but a changed category
cannot harm the host. The reset does not restore categories (YAGNI), and this is documented.

## R-5 Restart keeps the securing and the seed

- Passwords, roles, users and the `^sentai` globals live in IRIS databases inside the container's
  writable layer. `docker compose restart` and a VM reboot keep them; `docker compose down` (which
  removes the container) does **not**. The README says: never `down` the demo, use `restart`; to
  rebuild, run `up.sh` again (it re-secures and re-seeds).
- **To prove in T001**: `docker compose restart` on the demo project, then default password still
  refused and demo account still works.

## R-6 Keeping the example definition in one place

- The spec 010 example is a TypeScript constant (`frontend/src/lib/flows/example.ts`). The demo
  seed needs it server-side.
- **Decision**: duplicate it in `Demo.ExampleDefinition()` and test equality. `DemoTest` compares
  its step types, parameters, edges and join with a JSON fixture
  `tests/sentai/unittest/fixtures/example-flow.json`. The frontend unit test `example.test.ts`
  gains a case that compares `exampleDefinition()` with the same fixture file. If either side
  changes, one test fails.
- **Alternative rejected**: making the canvas fetch the example from the backend. That would add
  an API operation and change spec 010's frontend-only design.

## R-7 Reading `demo.json` before sign-in

- `/csp/sentai` is public (spec 010 decision, `sentai.web.StaticFiles` serves `/opt/sentai-web`).
  A `demo.json` beside `index.html` is served like any static file. It is absent on normal
  installations, so the request gets 404 and the canvas shows nothing.
- The file contains only the published demo account and the showcase name. It never contains the
  privileged secret.

## R-8 Cancel alert: which steps raise it

- Spec 008 T001 and `docs/limitations.md`: cancelling a running **platform job**
  (`POST /api/admin/v2/async-result/cancel`) ends its Work Queue Manager worker, and IRIS logs
  `ERROR #7802 … unexpectedly shut down` at severity 2. In-process steps are not ended by cancel
  (their worker keeps running and its late result is discarded), so they raise no alert.
- **Decision**: the notice depends on `executor === 'platform-api'` and `state === 'running'`, and
  applies to local and remote steps alike (the target records its own alert).
