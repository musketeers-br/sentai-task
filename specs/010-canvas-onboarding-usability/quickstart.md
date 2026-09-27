# Quickstart — 010 Canvas Onboarding and Flow Management (acceptance)

This quickstart runs against the compose stack (`sentai-task-iris-1`, `http://localhost:52773/csp/sentai/`).
Evidence goes to `specs/010-canvas-onboarding-usability/evidence/`, and no token or password ever goes
into an evidence file. Credentials come from the environment (`IRIS_USER` and `IRIS_PASSWORD`,
default `_SYSTEM`), as in `frontend/tests/support.ts`.

Behaviour is defined in [spec.md](spec.md), design in [plan.md](plan.md), and the entities in
[data-model.md](data-model.md). There are no API changes, so there is no `contracts/`.

## Prerequisites

```bash
docker-compose up -d --build
```

```bash
cd frontend && npm ci && npm test && npm run check && npm run build
```

```bash
bash scripts/publish-canvas.sh
```

```bash
cd frontend && npx playwright test tests/us17* tests/us18* tests/us19* tests/us20* tests/us21*
```

```bash
cd frontend && npx playwright test
```

- Gate: the unit and e2e suites are all green. That includes the existing ones; `us7-catalog` is
  updated for the kept sign-in, see plan.md.
- The manual script below uses a **fresh browser profile** (or a private window), so the guide and
  storage start empty. Keep DevTools → Application → Storage open to watch `sessionStorage` and
  `localStorage`.
- For SC-004 and SC-005 on a *fresh default installation*, rebuild the stack from a clean volume.
  Before running, record the free disk space: `storage-headroom-check` fails by design below 10%
  free ([research R-4.1](research.md)).

---

## 1. Save as and New flow — SC-001 (US1)

1. Sign in. On the empty canvas, drop two steps and name the flow `QS A`, then *Save flow*. The
   meta reads `rev 1 · saved hh:mm`.
2. Edit the name field to `QS B` **without saving**. Expected: the notice "Renames this flow — use
   Save as… to keep a copy" appears. Put the name back to `QS A`, and the notice disappears.
3. Move a node, then choose *Save as…*, enter `QS B`, and confirm. Expected:
   - the canvas shows `QS B` at rev 1;
   - the address has a new `flow=` id;
   - *Open flow…* lists both `QS A` and `QS B`;
   - opening `QS A` shows its original layout (the moved node is back where it was) and its
     revision is unchanged.
4. *Save as…* again with the name `QS A`. Expected: the dialog stays open and shows **"A flow with
   this name already exists"** verbatim, with the name kept for editing.
5. Edit `QS B` (add a step), then choose *New flow*. Expected: a Save / Discard / Cancel dialog.
   - *Cancel* leaves everything as it was.
   - *New flow* again, then *Discard*, gives an empty canvas and a fresh
     `Untitled flow YYYY-MM-DD HH:MM:SS` name, and the address no longer has `flow=`.
   - Back returns to `QS B` (without the discarded step).
6. **SC-001 (manual, usability run)**: give 5+ operators the task "save your flow, then save it
   again under a second name". Record in `evidence/sc001-usability.md` how many end with two flows
   (target: 100%) and whether anyone reports a lost flow (target: none).

## 2. Open flow… — SC-002 (US2)

1. With `QS A` and `QS B` saved, open the product without `flow=` in the address (a new tab,
   `index.html`).
2. Click *Open flow…* (**action 1**). Expected:
   - rows show the name, `rev n` and the last-saved time, newest first;
   - no row is marked (nothing is open).
3. Type `qs a` in the filter (**action 2**). Expected: only `QS A` (case-insensitive).
4. Click `QS A` (**action 3**). Expected:
   - the canvas shows it, and the address names it;
   - after a reload, `QS A` is still open;
   - back and forward move between the addresses and the canvas follows.
5. Make an edit, *Open flow…*, and pick `QS B`. Expected: the Save / Discard / Cancel dialog.
6. Refusal: sign in as an operator without product rights (see `frontend/tests/iris.ts` for the
   recipe) and open *Open flow…*. Expected: the platform's reason, verbatim, in the dialog.
7. Open `index.html?flow=99999999`. Expected: the canvas loads, and the notice reads "Flow
   '99999999' does not exist", with *Open flow…* and *New flow* offered, not a failure page.
8. Record in `evidence/sc002-actions.json` the action count (≤ 3).

## 3. Kept sign-in — SC-003, SC-007 (US3)

1. Sign in and open `QS A`. In DevTools, `sessionStorage['sentai.signin']` holds **only**
   `v`, `refreshToken` and `live: true`. `localStorage` holds at most `sentai.theme` and
   `sentai.guide.dismissed`. Nothing contains the password, an access token, a role or a
   permission (FR-011). Record the key names, not the values, in `evidence/us3-storage-keys.json`.
2. **SC-003**: press F5 ten times, waiting for the canvas each time, and spread the reloads over
   more than 60 s so that at least one proactive renewal happens in between. Expected: the sign-in
   form is shown **0 times** ("Signing you back in…" may flash), and `QS A` is open after every
   reload.
3. *Run now* on `QS A`, then reload on the live-run view. Expected: the same run's view again.
4. **Duplicate tab (FR-013)**: right-click the tab and choose *Duplicate*. Expected:
   - the copy shows the sign-in form with "Sign in to continue in this tab.";
   - sign in there;
   - wait more than 60 s, then interact in **both** tabs: both stay signed in, and neither shows
     the expired overlay.
5. **Session ended (FR-012)**, done in two ways:
   - Leave the tab idle and closed-lid for more than 15 min (the refresh token lives 900 s), or
     change `refreshToken` in DevTools to garbage, then reload.
   - Restart IRIS (`docker-compose restart`), then reload.

   Expected in both cases:
   - the sign-in form with **"Your session ended — sign in again."**;
   - `sentai.signin` is erased;
   - after signing in, the same screen and flow are shown (and the run if `run=` was in the
     address).
6. **SC-007**:
   - *Sign out*, then reload. Expected: the sign-in form, and `sentai.signin` is absent.
   - Sign in, **close the tab**, then open the same URL in a new tab. Expected: the sign-in form.

## 4. Example flow — SC-004, SC-005 (US4)

On a **fresh default installation** (no flows):

0. Run `docker exec sentai-task-iris-1 df -h /usr/irissys/mgr` and record the free %.
   `storage-headroom-check` fails by design when any database or journal directory has less than
   10% free; that run is a real finding, not a defect.
1. Start a timer at the sign-in form. Sign in. Expected: the empty canvas shows *Open example
   flow* and *Start from scratch*, and the guide opens on top (close it or use its step 2).
2. *Open example flow*. Expected:
   - `Example: storage health check`;
   - two steps side by side, *Storage headroom check* and *Database size report*, with no edges,
     so they run in parallel;
   - no parameter to fill in.
3. **SC-005**: *Validate flow*. Expected: "Flow is valid — no errors, no warnings."
4. *Run now* and enter the password. Expected:
   - **no** typed-confirmation fieldset in the dialog;
   - the live-run view follows both steps to `completed`.
   Stop the timer when the run finishes. **SC-004: under 2 minutes** (manual, a first-time
   operator). Record `evidence/sc004-sc005.json` with the elapsed time, the validation report and
   the per-step states.
5. **FR-017**: *Open flow…* → *New flow* → *Open example flow* again. Expected: the same flow id.
   `GET /flows` has exactly one `Example: storage health check`.
6. Edit the example (move a node), then *Save flow*. Reopen it, and the edit is kept (FR-018).
7. **FR-019** (automated only, `us20`): with a step type routed as unavailable, no *Open example
   flow* appears in the invitation, in *Open flow…*, or in the guide.

## 5. Getting-started guide — SC-006 (US5)

1. In a fresh profile, sign in. Expected: *Getting started* opens once the canvas is ready, at
   "Step 1 of 6".
2. **Keyboard only**:
   - focus is inside the dialog;
   - Tab cycles within it;
   - *Next* ×5 shows Welcome → Open the example → Build a flow → Validate and run → Save, Save as,
     Open → Schedule and explore;
   - the last step shows *Get started*;
   - *Escape* closes it, and focus returns to where it was.

   A screen reader announces "Getting started, dialog".
3. Reload. Expected: the guide does **not** reopen (same visit). Sign out and sign in. Expected: it
   **does** reopen (the box was not ticked).
4. Tick *Don't show this again*, then *Close*.
5. **SC-006**: sign out and sign in 5 times, reloading in between. Expected:
   - 0 automatic openings;
   - each time, *Help → Getting started* opens it at step 1 with the box ticked.
6. Untick the box via *Help* and close. Sign out and sign in. Expected: it opens automatically
   again.
7. **FR-024**: in a window with site data blocked (Chrome: Settings → Site data → block for
   `localhost`), sign in. Expected: the guide opens and closes normally with no console error, and
   it opens again on the next sign-in.

---

## Automated vs manual summary

| SC | Automated (e2e) | Manual (this script) |
|---|---|---|
| SC-001 | `us17` (mechanism) | §1.6 usability run |
| SC-002 | `us18` (action count) | §2.8 |
| SC-003 | `us19` | §3.2 |
| SC-004 | `us20` (scripted path timing only) | §4.1–4.4 **first-time operator, timed** |
| SC-005 | `us20` (dev stack) | §4.3–4.4 fresh default install |
| SC-006 | `us21` | §5.5 |
| SC-007 | `us19` (sign-out, new page) | §3.6 real tab close; §3.4 real duplicate |
