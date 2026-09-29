# Quickstart: Demo Readiness

How to check each story by hand once it is implemented.

## A. Local acceptance of the demo stack (US2, US3, US4)

Run on the development machine under a separate compose project and alternate ports, so the dev
stack is not touched (the clean-checkout pattern from 2026-09-27):

```bash
export COMPOSE_PROJECT_NAME=sentai-demo-check DEMO_HTTP_PORT=8080 DEMO_HTTPS_PORT=8443
printf 'SENTAI_DEMO_SECRET=%s\n' "$(openssl rand -base64 24)" > .env.demo-check
scripts/demo/up.sh --env-file .env.demo-check          # no DEMO_HOST → plain HTTP on :8080
scripts/demo/acceptance.sh --base http://localhost:8080
```

`acceptance.sh` checks, printing PASS/FAIL per line:

1. `up.sh` without a secret exits non-zero before starting anything.
2. `GET /csp/sentai/` → 200; `GET /csp/sys/UtilHome.csp` → 404; `GET /api/atelier/` → 404.
3. `POST /api/admin/login` as `_SYSTEM:SYS` → 401; the same inside the compose network against
   `iris-target:52773` → 401.
4. `POST /api/admin/login` as `sentai-demo` → 200; `GET /api/admin/v2/security/users` with that
   token → 403 (no security administration).
5. The showcase flow exists, validates with 0 errors, and a run with the demo account's password
   for the primary and the target completes; step 03 reports `executedOn: iris-target`.
6. `GET /csp/sentai/demo.json` → 200 with the three fields.
7. Create a visitor flow and run then cancel an integrity check; `status.sh` reports 1 visitor
   flow and the alert state; `reset.sh` → ok; `status.sh` reports 0 visitor flows, no alert, both
   healthy, exit 0; `_SYSTEM:SYS` is still refused on both instances and the demo account still
   signs in (FR-012).
8. `docker compose restart`; checks 3 and 4 still hold.

Clean up with `docker compose -p sentai-demo-check down -v` and delete `.env.demo-check`.

## B. On the public VM

```bash
git clone https://github.com/musketeers-br/sentai-task.git /opt/sentai-task && cd /opt/sentai-task
printf 'SENTAI_DEMO_SECRET=%s\nDEMO_HOST=%s\n' "<long random secret>" "demo.example.org" > .env
scripts/demo/up.sh
crontab -e   # add the two lines from the README "Public demo" section
```

Then open `https://demo.example.org/`: it redirects to `/csp/sentai/`, and the sign-in screen
shows the demo account hint.

## C. Cancel notice (US5), on the dev stack

1. Open any flow with an integrity check, choose *Run now*, and while the check runs, choose
   *Cancel wave*: the dialog shows the alert notice with a *Why* link.
2. Open the spec 010 example (in-process steps only), choose *Run now*, then *Cancel wave*
   quickly: no notice.
3. On a running integrity-check node, hover *Cancel* (new tooltip) and click it: a confirmation
   with the notice appears; *Keep running* leaves it running.
4. After the cancel, clear the alert with `do $SYSTEM.Monitor.Clear()` in `%SYS`.

## D. README (US1)

Open the README on GitHub at 1440×900: pitch, picture, *Try it* and the start of the area table
are within the first screen and a half. Every link in *Try it* and in the table resolves.
