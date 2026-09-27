# Implementation Plan: Canvas Onboarding and Flow Management Usability

**Branch**: `feat/spec010` (feature dir `010-canvas-onboarding-usability`) | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (3 clarifications, 26 FRs, 7 SCs). Frontend-first: the Svelte canvas
in `frontend/src`. The existing spec 002 API covers every need ([research R-1](research.md)), so
there is **no backend change, no `openapi.yaml` change, and no `contracts/` directory**.

## Summary

Four gaps, four increments:

1. **Save as / New flow / rename notice (US1)**. `FlowEditor` gains `saveAs(name)`
   (`POST /flows` from the current document, then the address switches to the new id), `reset()`,
   and a `renaming` flag that drives the notice "Renames this flow — use Save as… to keep a copy".
   *New flow*, opening a flow and opening the example all go through one unsaved-changes guard
   (*Save* / *Discard* / *Cancel*).
2. **Open flow… (US2)**. A dialog over `GET /flows`, sorted by `savedAt` descending, filtered by a
   case-insensitive name substring, with the open flow marked. Picking a flow puts it in the
   address. Refusals are shown verbatim.
3. **Kept sign-in (US3)**. Only the refresh token is kept, in `sessionStorage`, with a `live`
   handover flag. `pagehide` hands the token to the next load in the same tab. A duplicated tab
   finds the flag still set by the live original, so it erases the copied token without
   redeeming it and asks for its own sign-in. On load the page redeems the token with
   `POST /api/admin/refresh` (the refresh token alone works; probed) and `boot()` restores the
   screen, flow and run from the address. A failure shows "Your session ended — sign in again."
4. **Example flow and getting-started guide (US4, US5)**. *Example: storage health check* is a
   frontend data constant of two parallel read-only steps (`storage-headroom-check`,
   `db-size-report`). It was probed against this instance: validation gives 0 errors, and the run
   completes with both steps done in about 1 s. It is created through `POST /flows`, and its name
   is its identity (FR-017). The guide is a native modal `<dialog>` with six steps. Its
   "don't show again" preference is kept in `localStorage` with every access in try/catch; the
   "shown in this visit" flag is kept in memory.

## Technical Context

**Language/Version**: TypeScript 5.9, Svelte 5 (runes), SvelteKit 2 (`adapter-static`, one
prerendered page, `ssr = false`), as in specs 002, 007 and 009. The backend (ObjectScript on
IRIS 2026.2) is **not changed**.

**Primary Dependencies**: none new. `@xyflow/svelte` is unchanged.

**Storage**:
- `sessionStorage['sentai.signin']` holds `{v, refreshToken, live}`. It is per tab and dropped
  when the tab closes.
- `localStorage['sentai.guide.dismissed']` is `"1"` or absent, per browser.
- Nothing else is added, and nothing about permissions is stored.

**Testing**:
- vitest runs unit tests on pure modules, plus `*.svelte.test.ts` for rune classes with `fetch`
  stubbed.
- Playwright runs end-to-end tests against the compose stack (`sentai-task-iris-1`, port 52773).
- IRIS tests are not needed, because no ObjectScript changes. The registry assumptions the example
  depends on were verified with `iris-agentic-dev exec` against `sentai.registry.StepType`
  ([research R-4.1](research.md)).

**Target Platform**: current Chromium, Firefox and WebKit through Playwright's Chromium, as the
existing suite does. The static app is served by IRIS `ServeFiles` at `/csp/sentai/`.

**Project Type**: web application. The SvelteKit frontend talks to the IRIS REST backends
(`/api/admin`, `/csp/sentai/api/v1`).

**Performance Goals**:
- A reload restores the screen in under 1 s: one refresh call plus the existing `boot()` calls.
- *Open flow…* lists 5k flows (the dev instance has 4,962; the call takes 60 ms and returns
  663 KB) and filters them without a visible delay. Measured limits (tasks T019/T024), with 5,000
  flows:
  - the dialog shows its first rows within **1 s** of the click;
  - the list updates within **150 ms** of the last filter keystroke;
  - no main-thread task longer than **200 ms** during opening and filtering.
- SC-004: from sign-in to the example finishing in under 2 min. The probed run takes about 1 s.

**Constraints**:
- No backend or contract change.
- No password, access token, role or permission in storage.
- The platform's words are shown verbatim.
- All new UI text is in English.
- The top bar must still fit at 1440 px (spec 009 constraint).
- *Open flow…* must be one click, because of SC-002's 3-action budget.

**Scale/Scope**:
- 7 new pure or state modules.
- 4 new components.
- About 8 touched files.
- Unit tests grow from 89 to about 130.
- End-to-end tests grow from 31 to about 45, in 4 new spec files.

## Constitution Check

*GATE: evaluated before Phase 0 and re-evaluated after Phase 1 (see end). Every row passes; no
Complexity Tracking entries.*

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | Components → state classes (`flow/editor.svelte.ts`, `guide/guide.svelte.ts`, `api/session.svelte.ts`) → pure modules (`flows/list.ts`, `flows/guard.ts`, `flows/example.ts`, `guide/preference.ts`, `api/kept-sign-in.ts`). Only `api/client.ts` and `api/session.svelte.ts` perform HTTP. Browser storage is injected into the pure modules and wired at the edge (the session and guide singletons). No component calls `fetch` or `sessionStorage` directly. | ✅ |
| **II Closed Capability Set** | No new operation. The example is typed data built only from declared registry types, created through the existing `POST /flows`, and validated server-side like any flow ([R-4.2](research.md)). Nothing typed by the operator is evaluated. The guide's "open example" action calls a fixed function. | ✅ |
| **III Delegated Authorization** | The kept sign-in is one refresh token, which grants nothing: every request is still judged by the platform. No role, permission or capability is stored, and a unit test plus an e2e storage audit prove it ([R-3.6](research.md)). The example is created with the operator's own credential. If the list is refused, the invitation is hidden instead of guessing. Refusals (409 name clash, 409 revision, 404, 403) are shown verbatim; the conflict hint is an extra line, never a rewrite. | ✅ |
| **IV Errors as Values** | `saveAs`, `openExample`, `listFlows` and `session.restore` return `ApiResult` or tagged unions. The guard's save failure is a value that keeps the dialog open. Storage exceptions are caught at the storage edge (`kept-sign-in.ts`, `preference.ts`) and become `none` or `not dismissed`. | ✅ |
| **V Verifiable Increments** | Four increments, one per story group (see *Increments*). Each ships with its failing e2e first, then unit tests on its pure module. None is a "layer" ticket. Dependencies are declared: US4 needs US2's list and US1's guard; US5's step 2 needs US4's `exampleAvailable`. | ✅ |
| **VI Technology Agnosticism** | Technology choices appear only in this plan and research. The spec and constitution are untouched. | ✅ |
| SOLID / SoC | One reason to change per module: listing (`list.ts`), guarding (`guard.ts`), example data (`example.ts`), token keeping (`kept-sign-in.ts`), guide preference (`preference.ts`). The `+page.svelte` orchestration grows only by wiring. The guard is one component reused by four triggers. | ✅ |
| TDD | Every task starts with a failing test: a vitest case for pure logic, and a Playwright scenario for the observable behaviour (see *Testing Strategy*). | ✅ |
| YAGNI | No new endpoint, no server-side filter or paging, no cross-tab session sharing, no guide engine, no i18n layer. | ✅ |
| Reproducibility | No new toolchain. `docker compose up` plus `npm ci && npm run build`, as today. The quickstart uses only those. | ✅ |

## Decisions

### Flow management (US1, US2)

- **D-1 Contract reuse.** `GET /flows`, `GET /flows/{id}`, `POST /flows` and `PUT /flows/{id}` are
  used unchanged. `FlowSummary` already has `id`, `name`, `revision` and `savedAt`
  ([R-1](research.md)). `api.listFlows()` is changed to return `ApiResult<FlowSummaryView[]>`
  through `fromWireFlowSummary`, which keeps wire handling in one place, as `wire.ts` intends.
  The client sorts by `savedAt`. That is presentation of a complete list, not a workaround for a
  missing field.
- **D-2 Save as.** `editor.saveAs(name)` sends `POST /flows` with the current document under the
  new name. On success it calls `load(created)`, and the page **pushes** `?flow=<newId>`, so Back
  returns to the original. On failure, for example a 409 "A flow with this name already exists",
  the `SaveAsDialog` stays open, shows `describeError` verbatim and keeps the typed name
  (scenario 1.5). The editor is left unchanged. The dialog pre-fills `"<name> copy"`. On a draft,
  *Save as…* is the first save under the entered name.
- **D-3 New flow.** Passes through the guard, then `editor.reset(defaultFlowName(now, names))`,
  where `names` comes from a fresh `GET /flows`. If that call is refused, `names` is `[]` and the
  timestamp alone must be unique enough; the platform remains the judge of a clash. The page then
  **pushes** a URL without `flow` and `run`. The new default name uses seconds, which fixes
  today's minute-level clash.
- **D-4 Rename notice (FR-005).** `editor.savedName` records the confirmed name, and `renaming`
  is derived from it. The top bar shows an inline note next to the name field with
  `role="status"`: "Renames this flow — use Save as… to keep a copy". The *Save flow* button's
  `title` says the same. On a 409 from *Save flow*, the verbatim refusal is followed by "Use Save
  as… to keep your version." (edge case, [R-2](research.md)).
- **D-5 One unsaved-changes guard (FR-006).** `UnsavedChangesDialog` plus the pure `guard.ts`
  ([data-model §3](data-model.md)). There is one instance in `+page.svelte`, and
  `guarded(pending)` is the only way to switch documents. `beforeNavigate` sends history and link
  navigations that change `flow` through the same guard: it cancels, asks, then re-issues
  `goto(url)`. The dialog's buttons are *Save* (primary), *Discard* and *Cancel*, and its title is
  "Save changes to "<name>"?". *Escape* means *Cancel*.
- **D-6 Open flow… (FR-002, FR-003).** `OpenFlowDialog` reads the list fresh on each opening. It
  shows a filter input (focused first), a list of name, `rev n` and `savedAt` rows with
  `aria-current` on the open flow, and a count. The states are a tagged union: `loading`, then
  `list`, `empty` or `refused`.
  - `empty` offers *Open example flow* (when available) and *New flow* (scenario 2.5).
  - `refused` shows the verbatim reason (scenario 2.6).
  - Picking a flow runs `guarded({kind:'open', flowId})`, then `goto(flowHref(id))`, which pushes
    the address. The existing address-driven `switchFlow` effect loads the flow, so reload, back
    and forward agree.
- **D-7 Top bar (FR-001).** On the Flows screen: `[New flow] [Open flow…]`, then the name field
  with the rename note, then `[Save flow] [Save as…]`. Validate, Run and Schedule are unchanged.
  On **every** screen (Flows, Task catalog, Targets), a `Help ▾` menu button (menu: *Getting
  started*) sits before the user name (FR-023). *Open flow…* is
  a single click (SC-002). Shortcuts: Ctrl/⌘+S (existing), Ctrl/⌘+Shift+S for *Save as…* and
  Ctrl/⌘+O for *Open flow…* (the browser default is prevented only on the Flows screen). If the
  1440 px e2e fit check fails, *New flow* and *Save as…* move into a `More ▾` menu, and
  *Open flow…* and *Save flow* stay as buttons.
- **D-8 A named flow that can't be read.** Today `boot()` turns a 404 or 403 on `?flow=` into a
  full-page failure. It will instead reach `ready` with an empty canvas, the verbatim reason in
  the status notice, and an inline panel offering *Open flow…* and *New flow* (edge case).

### Kept sign-in (US3)

- **D-9 What is kept, and where.** Only the refresh token, in `sessionStorage['sentai.signin']`,
  as `{v:1, refreshToken, live}` ([R-3.2](research.md)). `session.svelte.ts` writes it in
  `#accept` (sign-in and every rotation) and erases it in `logout()`, in `expire()` and when a
  renewal fails (FR-010).
- **D-10 Duplicated tabs (FR-013).** Handled with the `live` handover
  ([R-3.3](research.md)).
  - `pagehide` sets `live:false`, and `pageshow` with `persisted` sets `live:true`.
  - On load, `live:true` means the tab is a copy of a live tab. The copy erases the record without
    redeeming and asks for its own sign-in ("Sign in to continue in this tab."). That sign-in
    gets its own, independent token family, which was probed.
  - The BroadcastChannel and Web Locks alternatives were rejected because they need timeouts and
    fail when a frozen original can't answer. The probe showed that replaying a rotated token
    revokes the original's whole family, so a wrong guess costs the original tab its sign-in.
- **D-11 Restore on load (FR-009, FR-012).** `session.restore()` is called in `onMount` before the
  sign-in form can appear.
  - While it runs, the status is `'restoring'` and the page shows "Signing you back in…", so the
    sign-in form appears 0 times (SC-003).
  - On success, `origin='restored'` and `boot()` restores `view`, `flow` and `run` from the
    address. This is the existing code, with D-8's softer failure.
  - On failure (401, other non-2xx, network, or an IRIS restart), the record is erased and
    `SignIn` gets `notice="Your session ended — sign in again."`, followed by the network error
    text verbatim when there is one. The address is untouched, so after sign-in `boot()` returns
    to the same place.
- **D-12 Unchanged (FR-014).**
  - Proactive renewal timing (spec 002 FR-034).
  - `dedicatedToken()` and the run's `runCredential`.
  - The `401 → expire()` path in `client.ts`.
  - The mid-session `SignIn expired` overlay.

  `#renew` keeps sending the bearer header. Only the new redeem-on-load path omits it, which was
  probed as accepted.

### Example flow (US4)

- **D-13 Composition.** Two parallel steps: `storage-headroom-check` ("Storage headroom check")
  and `db-size-report` ("Database size report"), with namespace `%SYS`, category `Default`,
  parameters filled explicitly (`minFreePercent: 10` on the headroom check; the size report has
  none), and no edges. The flow is named `Example: storage health check`
  ([R-4.1](research.md)). Both types are `in-process`, non-destructive and available. Probe:
  validation returned 0 errors, and the run completed with both steps done in about 1 s and no
  confirmation.
- **D-14 Where it lives.** A typed data constant, `lib/flows/example.ts`, created through the
  existing `POST /flows` with the operator's own sign-in. A declared backend operation and install
  seeding were rejected ([R-4.2](research.md)).
- **D-15 Idempotency (FR-017).** Find the example by name in a fresh list, ignoring case. If it is
  not there, create it. A 409 on create means list again and open the match. The platform's
  unique name index rules out duplicates ([R-4.3](research.md)). Opening the example goes
  through the guard (FR-006).
- **D-16 Offer (FR-016, FR-019).** `exampleAvailable(registry)` requires every type present,
  available and non-destructive. The example is offered in three places:
  - the empty-canvas invitation (`EmptyCanvasInvitation.svelte`: *Open example flow* and *Start
    from scratch*), shown when the canvas is an unsaved, step-less draft and the boot-time list
    was read and is empty;
  - *Open flow…* when the list is empty;
  - step 2 of the guide.

  When `exampleAvailable` is false, the example action is removed from all three places. If the
  flow list is refused, the invitation is not shown.

### Getting-started guide (US5)

- **D-17 Dialog.** `GettingStartedDialog.svelte` uses native `<dialog>` with `showModal()`,
  `aria-modal="true"` and `aria-labelledby` pointing at "Getting started". The body is described
  by `aria-describedby`.
  - Focus moves to the step heading on open. *Escape* fires `cancel`, which closes the dialog and
    saves the checkbox.
  - Focus returns to the element that was focused before the dialog opened.
  - The dialog shows "Step n of 6" (`aria-live="polite"`) and the controls *Back*, *Next*,
    *Close* and *Get started* (on step 6), plus the *Don't show this again* checkbox.
- **D-18 Preference and visit (FR-020, FR-022, FR-024).** Implemented in `guide/preference.ts`,
  following the `theme.svelte.ts` pattern, and `guide.svelte.ts` ([data-model §6](data-model.md)).
  - The guide opens automatically only after an interactive sign-in, once the page is ready,
    when it is neither dismissed nor `shownThisVisit`.
  - A reload that restores the sign-in is the same visit.
  - *Help → Getting started* always opens it at step 1.

## Project Structure

### Documentation (this feature)

```text
specs/010-canvas-onboarding-usability/
├── spec.md
├── plan.md              # this file
├── research.md          # R-1 … R-5 (probed findings, decisions, rejected alternatives)
├── data-model.md        # Flow summary, editor state, guard, Example flow, Kept sign-in, Guide preference
├── quickstart.md        # manual script SC-001 … SC-007 + automated commands
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks (not created here)
```

No `contracts/`: the API does not change.

### Source Code

```text
frontend/src/lib/
├── flows/                                   # NEW — flow management (US1, US2, US4)
│   ├── list.ts, list.test.ts                # FlowSummaryView, orderBySaved, filterByName, defaultFlowName
│   ├── guard.ts, guard.test.ts              # PendingSwitch, decide()
│   ├── example.ts, example.test.ts          # EXAMPLE_FLOW_NAME, exampleDefinition, exampleAvailable, findExample
│   ├── OpenFlowDialog.svelte                # NEW
│   ├── SaveAsDialog.svelte                  # NEW
│   ├── UnsavedChangesDialog.svelte          # NEW
│   └── EmptyCanvasInvitation.svelte         # NEW
├── guide/                                   # NEW — getting started (US5)
│   ├── steps.ts                             # six English steps
│   ├── preference.ts, preference.test.ts    # isDismissed / setDismissed over injected storage, try/catch
│   ├── guide.svelte.ts, guide.svelte.test.ts  # open/step/dontShow/shownThisVisit, shouldAutoOpen
│   └── GettingStartedDialog.svelte          # NEW
├── api/
│   ├── kept-sign-in.ts, kept-sign-in.test.ts  # NEW readKept / writeKept / handover / erase (injected storage)
│   ├── session.svelte.ts                    # TOUCH restore(), 'restoring', origin, ended; persist on #accept; erase on logout/expire
│   ├── session.svelte.test.ts               # NEW restore paths with stubbed fetch + fake storage
│   ├── client.ts                            # TOUCH listFlows → FlowSummaryView[]
│   └── wire.ts                              # TOUCH fromWireFlowSummary
├── flow/
│   ├── editor.svelte.ts                     # TOUCH savedName, renaming, conflictHint, saveAs, reset
│   └── editor.svelte.test.ts                # NEW saveAs/reset/renaming with stubbed fetch
├── shell/
│   ├── TopBar.svelte                        # TOUCH New flow, Open flow…, Save as…, rename note, Help menu
│   └── SignIn.svelte                        # TOUCH `notice` prop (session ended / copied tab)
frontend/src/routes/+page.svelte             # TOUCH restore on mount, guard, dialogs, beforeNavigate, D-8, auto-open guide
frontend/tests/
├── us17-save-as-and-new.spec.ts             # NEW US1
├── us18-open-flow.spec.ts                   # NEW US2
├── us19-kept-sign-in.spec.ts                # NEW US3 (+ storage audit, SC-003, SC-007)
├── us20-example-flow.spec.ts                # NEW US4 (SC-005)
├── us21-getting-started.spec.ts             # NEW US5 (SC-006, keyboard/a11y)
└── support.ts                               # TOUCH signIn tolerates the guide (dismiss via storage seed)
```

**Structure decision**: The frontend is the existing SvelteKit app. New feature code goes in two
new feature folders, `lib/flows` and `lib/guide`, following the pattern of `lib/catalog` and
`lib/targets`. The session change stays in `lib/api`, which is the only HTTP and credential edge.
`src/sentai/**` (ObjectScript) is not touched.

**Existing-suite impact**: The guide would appear after every e2e sign-in. `support.ts`'s
`signIn` therefore seeds `sentai.guide.dismissed=1` with `page.addInitScript`, and only
`us21` runs without the seed. One existing test changes on purpose. `us7-catalog.spec.ts:56-63`
reloads and then calls `submitSignIn`, because "tokens are in memory only". After US3 the reload
keeps the sign-in, so that test is updated in increment 3: the `submitSignIn` call and the
comment are removed, and the test still checks that the catalog view is kept. No other test calls
`reload()`.

## Increments (Constitution V)

| # | Increment (observable) | Depends on | First failing test |
|---|---|---|---|
| 1 | *Save as…* makes a second flow; *New flow* clears the canvas behind the guard; the rename notice appears (US1, P1) | — | `us17`: save A → Save as B → both exist via `GET /flows`, and the canvas and address show B |
| 2 | *Open flow…* lists, filters and opens flows behind the guard; refusals are verbatim; a named flow that can't be read is handled softly (US2, P1) | 1 (guard) | `us18`: two flows, open the list, filter, pick the first → the address names it |
| 3 | A reload keeps the sign-in and the place; a copied tab signs in on its own; the session-ended path (US3, P2) | — (parallel to 1–2) | `us19`: sign in, open a flow, `reload()` ×10 → no sign-in form, same flow |
| 4 | The example is offered, opened without duplicates, validated and run (US4, P2) | 1 (guard), 2 (list) | `us20`: *Open example flow* → validate 0 errors → *Run now* → every step completed |
| 5 | Getting-started guide (US5, P3) | 4 (`exampleAvailable` for step 2) | `us21`: fresh context → the guide opens; tick, close, sign in again → it doesn't open |

## Testing Strategy

**TDD**: In every task, the test is written first and seen failing, for the reason the task
fixes, before the code. The unit of test is the observable behaviour of the increment
(Constitution V). Pure logic gets a vitest case. The user-visible outcome gets a Playwright
scenario.

**Unit (vitest)**, about 40 new cases:
- `flows/list.test.ts`: order by `savedAt` (nulls last, name ties), case-insensitive filter,
  `defaultFlowName` suffixing on case-insensitive clashes, and wire mapping (numeric or string
  revision, `""` savedAt).
- `flows/guard.test.ts`: the three choices × the four triggers; *Save* failing → `stay`.
- `flows/example.test.ts`:
  - `exampleDefinition` uses only `EXAMPLE_STEP_TYPES`, has no edges, and has ≥2 steps in wave 1;
  - `exampleAvailable` is false when a type is missing, unavailable or destructive;
  - `findExample` matches case-insensitively.
- `api/kept-sign-in.test.ts`:
  - `none`, `copied` and `kept` classification;
  - corrupt JSON and wrong `v` → `none`;
  - storage throwing → `none`, no throw;
  - **the record's key set is exactly `v`, `refreshToken`, `live`** (FR-011);
  - handover flips `live`.
- `api/session.svelte.test.ts` (stubbed `fetch`, fake storage):
  - restore success → `signed-in` / `restored`, record rewritten with the new token and no
    `Authorization` header sent;
  - 401 → `signed-out` + ended notice + record erased;
  - network error → the same, plus the message;
  - `copied` → no fetch at all;
  - logout and expire erase the record;
  - `dedicatedToken` never writes the record.
- `flow/editor.svelte.test.ts` (stubbed `fetch`):
  - `saveAs` POSTs the current document under the new name and then holds the new id;
  - on a 409 the editor is unchanged and the error is returned verbatim;
  - `reset` clears everything;
  - `renaming` is true only for a saved flow whose name differs from `savedName`;
  - a 409 on `save` sets `conflictHint`.
- `guide/preference.test.ts`: read/write/remove; `getItem` or `setItem` throwing → no throw,
  not dismissed (FR-024).
- `guide/guide.svelte.test.ts`: `shouldAutoOpen` truth table; `openFromHelp` → step 1 with the
  checkbox from storage; close writes the checkbox; logout resets `shownThisVisit`.

**End-to-end (Playwright, compose stack)**, about 14 new scenarios:
- `us17` (US1):
  - Save as → two flows with their own contents, and A's revision unchanged;
  - rename notice;
  - New flow guard: Cancel, then Discard, then Save;
  - New flow → empty canvas with a fresh name and no `flow` in the address;
  - Save as with a taken name → verbatim 409, dialog still open;
  - top bar fits at 1440 px.
- `us18` (US2):
  - list order, marked open flow, filter;
  - pick → address; back and forward agree;
  - guard on pick when dirty;
  - refused list → verbatim reason (operator without privilege, from `iris.ts`);
  - empty list → example + New flow (`GET /flows` routed to `[]`, since the shared instance can't
    be empty);
  - SC-002 action count.
- `us19` (US3):
  - reload ×10 → the sign-in form never appears, and the same flow is open (SC-003);
  - reload on a live run → the run view;
  - sign out → reload → sign-in (SC-007);
  - a new page in the same context → sign-in (the tab-close model, SC-007);
  - **simulated duplicate**: copy `sessionStorage` into a second page with `addInitScript` while
    the first is alive → the second asks for its own sign-in, and the first renews again
    afterwards (waits past its 45 s renewal) without being signed out (FR-013);
  - ended path: the kept token is replaced with a revoked one → "Your session ended — sign in
    again." → sign in → the same flow (FR-012);
  - **storage audit**: after sign-in, `sessionStorage` and `localStorage` hold no password, no
    access token, and no keys other than the three declared ones (FR-011).
- `us20` (US4):
  - the example flow is deleted first with `deleteFlowWithRuns` in `tests/iris.ts`. That helper
    refuses to run outside the dev instance: the base URL must be localhost, the container must be
    the compose dev container, the IRIS namespace must be `IRISAPP`, and the flow's name must have
    a known test prefix (or be the example's name);
  - invitation on the empty state (routed list) → *Open example flow* → the flow named
    `Example: storage health check` with 2 parallel steps;
  - *Validate flow* → "no errors, no warnings";
  - *Run now* → the run sign-in, no typed-confirmation fieldset → every step `completed` (SC-005);
  - open the example again → the same id, and `GET /flows` has exactly one flow with that name
    (FR-017);
  - `step-types` routed with one type unavailable → no offer anywhere (FR-019).
- `us21` (US5):
  - fresh context → the guide opens once `ready`; Back, Next, "Step n of 6", the 6 titles in order;
  - keyboard only: focus inside, Tab stays inside, Escape closes, focus returns (FR-025);
  - tick → close → 5 sign-out/sign-in cycles → 0 auto-opens, and *Help → Getting started* opens
    at step 1 with the box ticked each time (SC-006);
  - close without ticking → no reopen in this visit, reopens on the next sign-in;
  - `localStorage` that throws (`addInitScript`) → the guide still opens and closes, no error in
    the console (FR-024).

**Routed responses in e2e.** `page.route` stands in only for instance states the shared stack
can't be put into (no flows at all; a step type unavailable). Every other scenario uses the real
API. This is test scaffolding, not a client workaround.

**IRIS-side tests**: none. No ObjectScript changes. The registry facts the example relies on were
checked with `iris-agentic-dev exec`, and `us20` re-checks them end to end against the live
registry on every run. If a later change adds a backend operation (rejected here), its `%UnitTest`
must be run with `iris-agentic-dev`.

**Commands**: `cd frontend && npm test && npm run check && npm run build`, then
`npx playwright test tests/us17* tests/us18* tests/us19* tests/us20* tests/us21*`, then the full
`npx playwright test` for regressions.

### Success criteria: automated vs manual

| SC | Automated | Manual (quickstart) |
|---|---|---|
| SC-001 two flows via Save as, none lost | ✅ `us17` (mechanism: two flows, original intact) | ✅ usability run: "100% of operators… none report losing" needs people |
| SC-002 reopen in ≤ 3 actions | ✅ `us18` counts the actions (click *Open flow…*, type, click row) | ✅ observed in the usability run |
| SC-003 10 reloads, 0 sign-in screens, same flow | ✅ `us19` | ✅ F5 ×10 in a real browser |
| SC-004 sign-in → example finished in < 2 min, first-time | ⚠ partly: `us20` times the scripted path | ✅ **manual**: a first-time operator on a fresh install, timed |
| SC-005 example validates 0 errors, all steps finish, 0 destructive confirmations | ✅ `us20` on the dev stack | ✅ on a fresh default installation |
| SC-006 ticked → 0 auto-opens over 5 sign-ins; Help always works | ✅ `us21` | ✅ |
| SC-007 sign-out / tab close leave no usable credential | ✅ `us19` (sign-out → reload; new page) | ✅ close a real tab, reopen the URL; duplicate a real tab (FR-013) |

## Risks

| Risk | Mitigation |
|---|---|
| A page killed without `pagehide` (crash, browser quit) leaves `live:true`, and the restored tab asks to sign in again | This is the safe direction; no token is misused. The refresh token is at most 900 s from expiry anyway. |
| A renewal in flight when the page unloads: the server rotated the token, but the response was lost | The next load's redeem fails → "Your session ended — sign in again." This is correct and rare (a 45 s cycle against a short window). |
| `storage-headroom-check` fails on an instance with < 10% free disk | This is a real finding and correct behaviour. The quickstart records free space. SC-005 is scoped to a default installation. |
| The top bar overflows at 1440 px | The e2e fit check; D-7 fallback: `More ▾` for *New flow* and *Save as…* |
| The guide pops up in every existing e2e sign-in | `support.ts` seeds the dismissed preference. Only `us21` exercises the guide. |
| The example is renamed by an operator, and *Open example flow* creates a new one | Accepted: the example's identity is its name (Key Entities). Still no duplicate by name. |
| `GET /flows` returns thousands of rows | It is 60 ms and 663 KB today. If that ever hurts, the fix is a declared `?q=` in `openapi.yaml` (R-1). |

## Complexity Tracking

No constitutional violations; nothing to justify.

## Post-Design Constitution Re-check

Re-evaluated after writing [research.md](research.md) and [data-model.md](data-model.md):

- **I**: storage is injected into pure modules and wired only in the session and guide
  singletons.
- **II**: no new capability; the example is data.
- **III**: the stored key set is pinned by a unit test and an e2e audit; the redeem grants
  nothing; refusals are verbatim.
- **IV**: every new path returns values; storage exceptions are caught at the edge.
- **V**: five observable increments, each with a failing e2e first.
- **VI**: technology only here.

**Gate: PASS.**
