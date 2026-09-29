# Spec 011 — Evidence

No evidence file contains the privileged secret (checked with `grep` before each was written).

| File | Task | What it shows |
|---|---|---|
| [t001-demo-role.md](t001-demo-role.md) | T001 | Securing the privileged accounts; the least-privilege demo role found one platform refusal at a time; what the demo account cannot and can do; restart persistence; two product defects (fixed in T025) |
| [t016-acceptance.txt](t016-acceptance.txt) | T016 | `scripts/demo/acceptance.py` on an isolated demo stack: **24/24** (exposure, secured accounts on both instances, demo account, showcase run on two servers, `demo.json`, visitor → status → reset → status, restart) |

## Baseline (T002, 2026-09-29, before any spec 011 code)

- Backend (`zpm "test sentai-task -only"`, dev container): **269/269**.
- Unit (vitest): **145/145**.
- E2e: **65** in the spec 010 record (59 passed, 1 opt-in skipped; the 3 failures and 2 not run
  there needed `iris-target`, which is up here).

## After spec 011 (T022)

- Backend: **284/284** (+11 `DemoTest`, +2 `FailureReasonTest` for D2, +2 `ReadRefusalTest` for D1).
- Unit: **161/161** (+9 `cancel-alert`, +1 example fixture, +6 `demo-info`).
- E2e (full suite, 2026-09-29, `iris-target` up): **66 passed, 2 failed, 1 skipped** (the opt-in
  905 s expiry test). New specs `us22-cancel-alert-notice` (2) and `us23-demo-sign-in-hint` (2);
  `us4-live-run` updated to confirm the step cancel. The two failures:
  - `us21 storage blocked` — caused by spec 011: a normal installation answered `demo.json` with
    404, which the browser logs as a console error, and that test requires none. **Fixed**: the
    build ships a neutral `static/demo.json` (`{"demo": false}`) that `up.sh` overwrites on a
    demo; `us21` and `us23` re-run green (us23 now also asserts no console error).
  - `us19 duplicated tab` — not caused by spec 011 (see below).
- README check: `python scripts/demo/acceptance.py --readme` **4/4** (it was 1/4 before T020).

### Known, not caused by spec 011

- `us19 duplicated tab — … (FR-013)` fails on this machine with **and without** the spec 011
  sign-in change (checked by rebuilding the canvas without it): the test's 90 s budget (a
  deliberate 70 s wait plus two sign-ins and two *Open flow…* dialogs) runs out on the dev
  instance, which now holds about 4,900 flows. Left for a spec 010 follow-up.

## Team actions still open

- **T021 / T024**: bring the demo up on the VM (`scripts/demo/up.sh` with `DEMO_HOST`), put its
  address in the README *Try it* block and on the Open Exchange page, install the two cron lines,
  and record SC-002 (time to up) and SC-004 (visitor to showcase finished) here.
