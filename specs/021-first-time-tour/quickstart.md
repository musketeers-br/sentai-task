# Quickstart — 021 First-Time Canvas Tour (acceptance)

This quickstart runs against the compose stack (`sentai-task-iris-1`, `http://localhost:52773/csp/sentai/`).
Evidence goes to `specs/021-first-time-tour/evidence/`, and no token or password ever goes into an
evidence file. Credentials come from the environment (`IRIS_USER` and `IRIS_PASSWORD`, default
`_SYSTEM`), as in `frontend/tests/support.ts`.

Behaviour is defined in [spec.md](spec.md), design in [plan.md](plan.md), entities in
[data-model.md](data-model.md), and the UI contract the tests enforce in
[contracts/tour.md](contracts/tour.md). There are no API changes.

## Prerequisites

```bash
docker compose up -d --build
```

```bash
cd frontend && npm ci && npm test && npm run check && npm run build
```

```bash
bash scripts/publish-canvas.sh
```

```bash
cd frontend && npx playwright test tests/us30*
```

```bash
cd frontend && npx playwright test
```

- Gate: unit, `us30` and the **full** suite green — the full run is SC-002: the *Getting started*
  dialog (us21) must behave exactly as before the tour.
- e2e drives the baked bundle, so `publish-canvas.sh` must run after the last build.
- The manual script below uses a fresh browser profile (or a private window) so the spec 010
  guide state starts clean. The tour itself has no state to reset (FR-010).

---

## 1. The button and the three marks — SC-001 (US1)

1. Sign in. If the *Getting started* dialog opens, close it — the tour never opens by itself
   (FR-009); the **Tour** button is in the top bar, before *Help*.
2. Click **Tour**. Expected, in order:
   - mark 1: the spotlight frames the **STEP TYPES** palette; the card reads "This is the
     palette — drag a step onto the canvas."; the indicator reads "1 of 3";
   - *Next* → mark 2: the spotlight frames the canvas; "Connect two steps to create a
     dependency."; "2 of 3";
   - *Next* → mark 3: the spotlight frames *Validate flow* and *Run now* together; "Validate
     the flow, then run it."; "3 of 3"; the primary control is **Done** (no *Next*).
3. *Done* closes the tour. Click **Tour** again: identical, from "1 of 3" (FR-010).
4. Take screenshots (both themes) for evidence.

## 2. Skip and Escape — US2

1. Click **Tour**, then *Skip* on mark 1: the tour is gone at once, the canvas is fully usable.
2. Click **Tour**, press *Escape* on mark 2: gone, and focus is back on the **Tour** button.
3. Nothing changed anywhere: reopen and everything behaves exactly the same (FR-010).

## 3. Keyboard-only pass — SC-003 (FR-006)

1. Put the mouse away. Reach the **Tour** button by *Tab* and press *Enter*.
2. Focus starts inside the card; *Tab* never leaves the dialog; *Enter* on *Next* advances;
   *Escape* skips; focus returns to the button each time.

## 4. The tour never sits over a non-editing canvas — US3 (FR-011)

1. Click **Tour**, then the *Task catalog* tab: the tour is gone.
2. On Flows, click **Tour**, then *Sign out*: the tour is gone; the sign-in screen is clear.
3. Sign in again; with the tour open, the empty-canvas invitation (fresh instance or an empty
   flow list) stays visible under the veil and is still there after *Done* (FR-007).
4. In a window narrowed to ~1024 px, take the tour: the card stays fully inside the viewport
   (edge case).

## 5. SC-002 — the *Getting started* dialog is untouched

In the same fresh profile: sign out, sign in with the password again — the guide still opens
automatically per spec 010, ticks and all. With the tour merged, this is also what the full e2e
run proves (`us21` green, unedited).

## 6. SC-004 — first-time operators (manual)

Three people who have never used SentaiTask each get a fresh profile and this instruction only:
"Sign in and use the product." Count how many, unprompted or after at most noticing the **Tour**
button, complete add-a-step → connect-two-steps → *Validate flow* → *Run now* with no help
beyond the tour's marks. Record the count in `evidence/README.md` (3 of 3 is the bar; the
input's "why it wins" says the marks alone must carry the clarity).

---

## Evidence table (fill on completion)

| Check | Artifact |
|---|---|
| The three marks, anchored, dark and light | `evidence/us30-tour-mark{1,2,3}-{dark,light}.png` |
| Tour state + messages in order | `evidence/us30-tour.json` (e2e `envelope`) |
| SC-004 usability spot-check | `evidence/README.md` |
