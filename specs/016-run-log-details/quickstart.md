# Quickstart: Flow Execution Log Detail

Pure frontend: after changing `frontend/`, publish the canvas and the run view picks it up. The
backend needs nothing new from this feature.

## Prerequisites

The compose stack up (`docker compose up -d`), the canvas published after the last change:

```sh
cd frontend && npm ci
npm run check          # svelte-check — must be clean
npm test               # vitest: stepdetail.test.ts, logview.test.ts (and the existing suites)
bash scripts/publish-canvas.sh
```

## 1. One step's execution, in full (US2 — the MVP)

1. Open **http://localhost:52773/csp/sentai/**, sign in (`_SYSTEM` / `SYS`).
2. Compose (or reuse) a flow: `01 db-size-report` → `02 storage-headroom-check`
   (`minFreePercent: 100`, which always fails on this stack) → *Run now*.
3. In the live run view, click step **01**'s node (or its row in the step list): the rail shows
   **STEP DETAIL** — state, queued/started/finished, duration, `on local · as _SYSTEM`.
4. When 01 completes, open it again: **RESULT** shows the databases report, readable. *Copy*
   pastes exactly the JSON shown.
5. Open step **02** after it fails: the platform's failure reason appears whole, and *Copy*
   pastes it exactly.
6. The address is `?run=<guid>&step=02`: reload keeps the selection; the detail's close affordance
   deselects and the address loses `step`.
7. A step still `queued` shows `—` for times, duration, place and identity — no invented values.

API check (what the view consumes):

```sh
TOKEN=$(curl -s -u _SYSTEM:SYS -X POST localhost:52773/api/admin/login -H 'Content-Type: application/json' -d '{}' | jq -r .access_token)
curl -s -H "Authorization: Bearer $TOKEN" localhost:52773/csp/sentai/api/v1/runs/<guid> | jq '.steps[] | {stepId, state, executedOn, executedAs, result, failureReason}'
```

## 2. The log, whole (US1)

> Entries appear only once spec 012's recording lands; until then the panel keeps its honest
> empty text and every affordance below is checkable with whatever entries exist.

1. In the same run view, the **RUN LOG** panel lists entries oldest-first, each
   `time · #step · SEVERITY · message`; the severity word is readable without colour, in dark
   and light themes.
2. Select the failed step: the panel narrows to **02**'s entries only; deselect: the full log
   returns.
3. Paste a long failure reason (or run with the target stopped): the message wraps, nothing is
   cut; *Copy* on the entry pastes the whole text.
4. Scroll up while the run is live: the list keeps your position across refreshes and
   *Jump to latest* returns to the newest in one click.

## 3. Find the entry that matters (US3 — the cuttable slice)

1. With entries present, narrow by severity: only matching entries are listed and the panel says
   "N of M entries".
2. Combine with a selected step's slice: both apply.
3. One action clears: the full log returns; a filter matching nothing says so honestly.

## End-to-end (acceptance)

```sh
npx playwright install chromium
npx playwright test tests/us27-step-detail.spec.ts     # no 012 dependency
npx playwright test tests/us28-log-panel.spec.ts        # entry-content assertions blocked-by-012
npx playwright test tests/us29-log-filters.spec.ts      # P2 — may be cut at the deadline
```

`us27` dispatches the §1 flow and asserts the detail, the copy round-trip and the address; evidence
PNG/JSON land in `specs/016-run-log-details/evidence/` with the README table.
