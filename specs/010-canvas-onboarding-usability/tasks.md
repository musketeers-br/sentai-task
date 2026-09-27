# Tasks: Canvas Onboarding and Flow Management Usability

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [quickstart.md](quickstart.md). No `contracts/`: the API does
not change.

**Tests**: REQUIRED (TDD, Constitution V and Engineering Standards). In every story phase, the e2e
spec and the unit tests are written first and **seen failing for the reason the story fixes**.
Only then comes the implementation. Unit tests use vitest (`frontend/src/**/*.test.ts`; rune classes
use `*.svelte.test.ts`). E2e tests use Playwright against the compose stack (`sentai-task-iris-1`,
`http://localhost:52773/csp/sentai/`).

**Gate after every task that changes code** (from `frontend/`):
`npm run generate:tokens && npm test && npm run check && npm run build && bash ../scripts/publish-canvas.sh && npx playwright test <the phase's spec files>`.
Every phase ends with the full `npx playwright test`.

**Hard rules**:
- **No backend or `openapi.yaml` change.** Nothing under `src/sentai/**` or
  `specs/002-canvas-ui/contracts/openapi.yaml` is edited. If a task turns out to need one,
  **stop and flag it** before continuing (plan D-1, research R-1).
- Platform refusals are shown verbatim (Constitution III and IV). Components never call `fetch`
  or touch `sessionStorage` or `localStorage` directly. Only `lib/api/client.ts`,
  `lib/api/session.svelte.ts` and the injected-storage modules do.
- No password, access token, user name, role or permission in any storage (FR-011).
- All new UI text is in English (FR-026).
- E2e flows use unique names with a prefix (`us17-`, `us18-`, `us19-`, `us20-`, `us21-`) so that
  T061 can clean them up.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task).
- **[USn]**: the user story in spec.md (US1 Save as/New, US2 Open, US3 Kept sign-in,
  US4 Example, US5 Guide).
- Paths are relative to the repository root unless they start with `src/` or `tests/`, in which
  case they are under `frontend/`.

---

## Phase 1: Setup

**Purpose**: a known green baseline and the evidence folder.

- [X] T001 Create `specs/010-canvas-onboarding-usability/evidence/README.md` listing the evidence files this feature produces (us17…us21 JSON/PNG, sc001/sc004/sc005 records) and the rule "no token or password in evidence". Run the baseline gate from `frontend/` (`npm test`, `npx playwright test`) and record the counts in the README (expected: unit 89, e2e 31, all green).
- [X] T002 [P] Add a "no backend change" check to `specs/010-canvas-onboarding-usability/evidence/README.md`: `git diff --stat master -- src/ specs/002-canvas-ui/contracts/openapi.yaml` must print nothing. Run it now, and again in T062.

---

## Phase 2: Foundational (test infrastructure)

**Purpose**: the shared e2e sign-in helper, so the getting-started guide (US5) never blocks the
existing specs. There is no product change in this phase. The unsaved-changes guard (FR-006) is
built inside US1 (Phase 3), where its failing e2e is `us17` scenario 4 (Constitution V; plan
*Increments* row 1).

**⚠️ No user story phase starts before this phase is complete.**

- [X] T003 Update `tests/support.ts`:
  - `signIn`/`signInAt` gain an option `{ guide?: 'dismissed' | 'fresh' }`, default `'dismissed'`.
  - For `'dismissed'`, before `page.goto`, call `page.addInitScript(() => { try { localStorage.setItem('sentai.guide.dismissed', '1'); } catch {} })`. This way the getting-started guide (US5) never covers the canvas in existing specs.
  - `'fresh'` skips the seed; only `us21` uses it.
  - Run the full existing e2e suite: it stays green, 31/31 (the key is not read yet).

**Checkpoint**: the helper is ready, and the existing suites are green.

---

## Phase 3: User Story 1 — Save as a new flow, never overwrite by accident (P1) 🎯 MVP

**Goal**:
- *Save as…* creates a second flow from the current canvas and leaves the original untouched.
- *New flow* starts empty, behind the unsaved-changes guard (Save / Discard / Cancel), which is
  built here and reused by US2 and US4.
- The top bar warns that editing the name renames the open flow (FR-001 partly, FR-004, FR-005,
  FR-006, FR-007, FR-008).

**Independent test**: save `A`, then *Save as…* `B`. Both exist in `GET /flows` with their own
contents, and the canvas and address show `B`.

### Tests for US1 (write first, see them fail) ⚠️

- [X] T004 [P] [US1] **E2e first**: write `tests/us17-save-as-and-new.spec.ts`. Flow names are prefixed `us17-`. Scenarios:
  1. Save flow `us17-A-<ts>` with 2 steps, move a node, then *Save as…* `us17-B-<ts>`. Expect:
     - the canvas name is B, and the address `flow=` is B's id;
     - `GET /flows/{A}` still has A's revision and A's positions (without the move);
     - `GET /flows/{B}` has the moved position (scenario 1.1, FR-004, edge case "unsaved edits go to the new flow only").
  2. With A open, type a different name. The note `Renames this flow — use Save as… to keep a copy` is visible. Restore the name, and the note disappears (FR-005).
  3. *Save as…* with an existing name. The dialog stays open and shows `A flow with this name already exists` verbatim, with the typed name kept (scenario 1.5, FR-008).
  4. With unsaved edits, click *New flow*. The Save/Discard/Cancel dialog appears:
     - *Cancel* keeps the edits;
     - repeating with *Discard* gives an empty canvas, a name matching `/^Untitled flow \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/`, and no `flow=` in the URL; browser Back returns to the previous flow;
     - repeating with *Save* saves first, then clears (scenario 1.3/1.4, FR-006, FR-007).
  5. *Save as…* on a never-saved draft creates it under the entered name (edge case).
  6. A stale-revision *Save flow*: bump A's revision through the API, then save in the canvas. The verbatim `Flow was saved by someone else since it was loaded` is followed by the separate hint `Use Save as… to keep your version.` (edge case).
  7. At 1440×900, no top-bar control is clipped. Every button's bounding box lies inside the header's box.

  Write `evidence/us17-save-as.json` (ids, names, revisions; no tokens).
- [X] T005 [P] [US1] **Unit first**: write `src/lib/flows/guard.test.ts` covering these cases (data-model §3). Run it and see it fail (the module doesn't exist yet).
  - `needsGuard(false)` is `false` and `needsGuard(true)` is `true`.
  - `decide('save')` gives `{next:'save-then-proceed'}`, `decide('discard')` gives `{next:'proceed'}`, and `decide('cancel')` gives `{next:'stay'}`.
  - `afterSave(false)` gives `{next:'stay'}` (a failed save keeps the operator on the current flow) and `afterSave(true)` gives `{next:'proceed'}`.
  - Each `PendingSwitch` kind (`new`, `open`, `example`, `address`) passes through unchanged.
- [X] T006 [P] [US1] **Unit first**: write `src/lib/flows/list.test.ts` (US1 part). `defaultFlowName(new Date('2026-09-27T10:11:12'), [])` gives `Untitled flow 2026-09-27 10:11:12`. A case-insensitive clash in `takenNames` appends ` (2)`, then ` (3)`. Also add to `src/lib/api/wire.test.ts`: `fromWireFlowSummary` maps a string `id`, a numeric or string `revision` to a number, and `savedAt` `""`/absent to `null`.
- [X] T007 [P] [US1] **Unit first**: write `src/lib/flow/editor.svelte.test.ts`. Stub `fetch` with `vi.stubGlobal`, and sign in through a stubbed `/api/admin/login` so that `session.authorization()` is set. Cases:
  - `saveAs('B')` sends `POST /csp/sentai/api/v1/flows` with the current steps, edges, positions and `name:'B'` (no PUT), then `editor.id` is the new id and `savedName === 'B'`, `dirty === false`;
  - a 409 on `saveAs` returns `{ok:false}` with `detail` verbatim, and the editor's id, name, revision and dirty are unchanged;
  - `reset('X')` clears nodes, edges, id, revision, savedAt, savedName, report and notice, and sets `dirty=false`;
  - `renaming` is false for a draft, false when the name equals `savedName`, and true when a saved flow's name differs (ignoring surrounding whitespace);
  - a 409 on `save()` sets `conflictHint = true`, and a later successful save clears it.

### Implementation for US1

- [X] T008 [US1] Implement `src/lib/flows/guard.ts` (`PendingSwitch`, `GuardChoice`, `GuardStep`, `needsGuard`, `decide`, `afterSave`) so that T005 passes. The module is pure: no Svelte, no I/O.
- [X] T009 [US1] Create `src/lib/flows/UnsavedChangesDialog.svelte`, following `src/lib/shell/DispatchDialog.svelte`:
  - Native `<dialog>` with `showModal()` and `aria-labelledby` pointing at the title `Save changes to "<flow name>"?`.
  - Body text: "This flow has changes that are not saved."
  - Buttons: *Save* (primary), *Discard*, *Cancel*. *Escape* (`cancel` event) means *Cancel*.
  - Props: `open` (bindable), `name`, `onchoose(choice)`, `message: string | null`. `message` shows a verbatim save refusal (`role="alert"`) and keeps the dialog open.
- [X] T010 [US1] Wire the guard once in `src/routes/+page.svelte`:
  - Add `guarded(pending: PendingSwitch, proceed: () => Promise<void> | void)`:
    - when `!editor.dirty`, it runs `proceed` directly;
    - otherwise it opens `UnsavedChangesDialog`;
    - *Save* calls `editor.save()`. On failure, the dialog stays open with `editor.notice.text` verbatim (`afterSave(false)`). On success, it proceeds.
    - *Discard* proceeds, and *Cancel* closes the dialog.
  - Add a SvelteKit `beforeNavigate` handler. When the target URL's `flow` parameter differs from the current one and the editor is dirty, it calls `cancel()` and runs `guarded({kind:'address', url})` whose proceed is `goto(url)`. A one-shot `bypassGuard` flag stops that re-issued navigation from being guarded again.
  - Result: `us17` scenario 4 (Cancel / Discard / Save) passes.
- [X] T011 [US1] Implement `fromWireFlowSummary` in `src/lib/api/wire.ts`, and make `api.listFlows()` in `src/lib/api/client.ts` return `ApiResult<FlowSummaryView[]>`. Create `src/lib/flows/list.ts` with `FlowSummaryView` and `defaultFlowName(now, takenNames)` (seconds precision, local time, case-insensitive suffixing). Result: T006 passes.
- [X] T012 [US1] Extend `src/lib/flow/editor.svelte.ts` (data-model §2) so that T007 passes:
  - `savedName` is set in `load()` and in successful `save()` and `saveAs()`;
  - `renaming` is `$derived`;
  - `conflictHint` is set on a 409 from `save()` and cleared on success;
  - `saveAs(name): Promise<ApiResult<FlowDocument>>` does `createFlow(toDefinition({...toDocument(), id:null, name}))` and then `load()` on success. On failure the editor is untouched and there is no `notice` side effect; the dialog shows the error;
  - `reset(name)`;
  - the initial `name` uses `defaultFlowName(new Date(), [])`.
- [X] T013 [P] [US1] Create `src/lib/flows/SaveAsDialog.svelte`:
  - native `<dialog>` with the title "Save as a new flow";
  - a `Name` input, pre-filled `"<current name> copy"` and selected on open;
  - buttons *Save as* (primary, submit) and *Cancel*; *Escape* cancels;
  - the lead text "Creates a new flow from this canvas. The current flow is not changed.";
  - calls `editor.saveAs(name)`. On `{ok:false}` it shows `describeError(error)` verbatim (`role="alert"`) and stays open with the name kept. On success it calls `onsaved(id)`.
- [X] T014 [US1] Update `src/lib/shell/TopBar.svelte`:
  - add *New flow* before the name field and *Save as…* after *Save flow* (props `onnew`, `onsaveas`);
  - when `editor.renaming`, show a `role="status"` note `Renames this flow — use Save as… to keep a copy` next to the name, and set the same text as the *Save flow* button's `title`;
  - *Save as…* is enabled whenever the canvas has a name (including drafts).

  Show `conflictHint` as a second line `Use Save as… to keep your version.` under the error notice in `src/lib/shell/StatusBar.svelte`.
- [X] T015 [US1] Wire US1 in `src/routes/+page.svelte`:
  - `newFlow()` is `guarded({kind:'new'}, async () => {...})`. It reads `api.listFlows()` for taken names (or `[]` if refused), calls `editor.reset(defaultFlowName(new Date(), names))`, clears `watching`, and `goto`s (push) the URL without `flow` and `run`;
  - `SaveAsDialog`'s `onsaved(id)` does `goto(flowHref(id))` (push, so Back returns to the original);
  - the keyboard shortcut Ctrl/⌘+Shift+S opens *Save as…* on the Flows screen.

  Result: T004 passes.
- [X] T016 [US1] Phase gate: run the full unit + e2e suite. Save the evidence `evidence/us17-save-as.json`, plus a 1440×900 screenshot of the rename note (`evidence/us17-rename-note.png`), dark theme.

**Checkpoint**: US1 is demonstrable on its own (MVP): Save as, New flow, the rename notice and the guard all work.

---

## Phase 4: User Story 2 — Open a saved flow (P1)

**Goal**: *Open flow…* lists every flow, most recently saved first, with a case-insensitive
filter and the open flow marked. Picking one opens it and puts it in the address, behind the
guard. Refusals are shown verbatim, and a flow in the address that can't be read no longer blanks
the page (FR-001 complete, FR-002, FR-003, FR-006, FR-008).

**Independent test**: save two flows, then load the canvas without `flow=`. *Open flow…* → pick
the first → the canvas and address show it.

**Depends on**: US1 — T011 (the view-mapped `listFlows`), T015 (`newFlow()`, used by the
dialog's *New flow*) and the guard (T005, T008, T009, T010).

### Tests for US2 (write first, see them fail) ⚠️

- [X] T017 [P] [US2] **E2e first**: write `tests/us18-open-flow.spec.ts`, with flows prefixed `us18-`. Scenarios:
  1. Seed 2 flows with different `savedAt`, then open `index.html` without `flow`. *Open flow…* lists name, `rev n` and saved time. The newest of the two appears above the older. When a flow is open, its row has `aria-current="true"` (scenario 2.1, FR-002).
  2. Typing the upper-cased suffix of one name leaves only that row (scenario 2.2).
  3. Click the row. The canvas shows it and `flow=` names it. A **fresh page** at `signInAt(page2, '?flow=<id>')` opens the same flow (the shared link). `goBack` and `goForward` move the canvas with the URL (scenario 2.3, FR-003). The reload assertion belongs to `us19` (US3).
  4. With unsaved edits, picking another flow shows the guard. *Cancel* keeps the current flow (scenario 2.4).
  5. With `GET /flows` routed to `[]`: "No saved flows yet." plus a *New flow* button (scenario 2.5; the example button comes in US4).
  6. Signed in as an operator without product rights (`createOperatorWithoutTaskPrivilege` from `tests/iris.ts`, deleted in `finally`): the dialog shows the platform's refusal verbatim (scenario 2.6).
  7. `index.html?flow=99999999` reaches the canvas with the notice `Flow '99999999' does not exist` and an inline panel offering *Open flow…* and *New flow* (edge case, plan D-8).
  8. **SC-002**: count the user actions from the canvas to the open flow (click *Open flow…*, type, click the row) and assert ≤ 3. Write `evidence/us18-open-flow.json`.
- [X] T018 [P] [US2] **Unit first**: extend `src/lib/flows/list.test.ts`:
  - `orderBySaved` sorts `savedAt` descending in the platform format `YYYY-MM-DD HH:MM:SS`, puts `null` last, and breaks ties by name ascending;
  - `filterByName` is case-insensitive, trims, and an empty filter returns everything;
  - neither function mutates its input.
- [X] T019 [P] [US2] **Performance test first**: add a scenario to `tests/us18-open-flow.spec.ts`. Route `GET /flows` to 5,000 synthetic summaries (names `perf-00001…`, varied `savedAt`). Expect:
  - the dialog shows its first rows within 1 s of the click;
  - after typing `perf-04`, the list updates within 150 ms of the last keystroke (measured in-page with `performance.now()` around an `input` event, then waiting for the DOM with `requestAnimationFrame`);
  - a `PerformanceObserver({type:'longtask'})` records no task longer than 200 ms during open and filter.

  Record the timings in `evidence/us18-perf.json`.

### Implementation for US2

- [X] T020 [US2] Implement `orderBySaved` and `filterByName` in `src/lib/flows/list.ts` so that T018 passes.
- [X] T021 [US2] Create `src/lib/flows/OpenFlowDialog.svelte`:
  - native `<dialog>` with the title "Open flow";
  - it reads `api.listFlows()` on **every** opening (never cached) into the state union `loading | list | empty | refused`;
  - the filter input (`Filter by name`) is focused first;
  - a `<ul>` of row buttons shows name, `rev n` and `savedAt` as the platform reports it, in `orderBySaved(filterByName(...))` order, with `aria-current` on `currentId`;
  - a count reads "n of N flows";
  - `refused` shows `describeError` verbatim;
  - `empty` shows "No saved flows yet." and *New flow*;
  - props: `onpick(id)`, `onnew()`, `currentId`.

  Rows are a keyed `{#each}` of plain buttons (no per-row component, no per-row derived state), and the filtered list is one `$derived`.
- [X] T022 [US2] Add an *Open flow…* button (always visible, never in a menu, because of SC-002) to `src/lib/shell/TopBar.svelte`, right after *New flow*, with the prop `onopen`. In `src/routes/+page.svelte`:
  - mount `OpenFlowDialog`;
  - `onpick(id)` runs `guarded({kind:'open', flowId:id}, () => goto(flowHref(id)))` (push), and the existing address effect loads the flow;
  - `onnew` calls `newFlow()`;
  - Ctrl/⌘+O opens the dialog on the Flows screen (with `preventDefault`).
- [X] T023 [US2] Plan D-8 in `src/routes/+page.svelte` `boot()`: when `api.getFlow(flowId)` fails, don't set `phase='failed'`. Reach `ready` with an empty draft, set `editor.notice = {tone:'error', text: describeError(error)}` (verbatim), and show an inline panel in the canvas area with *Open flow…* and *New flow*.
- [X] T024 [US2] Make T019 pass. If the plain keyed list misses the thresholds, add windowed rendering to `OpenFlowDialog.svelte`. It renders only the visible rows plus a buffer, keeps a spacer for the scroll height, and keeps **every** flow reachable by scrolling and filtering (FR-002 "list every flow"). Don't truncate the list, don't add paging, and add no server parameter (no API change).
- [X] T025 [US2] **Top bar at 1440 px**: T004 scenario 7 must still pass with *New flow*, *Open flow…*, *Save flow* and *Save as…* all present. If it fails:
  - move *New flow* and *Save as…* into a `More ▾` menu button in `src/lib/shell/TopBar.svelte`, using the menu button pattern: `aria-haspopup="menu"`, `role="menu"` and `menuitem`, arrow keys, and *Escape* returning focus to the button;
  - keep *Open flow…* and *Save flow* as visible buttons;
  - update the selectors in `tests/us17-save-as-and-new.spec.ts` to open the menu first.

  Record which layout shipped in `evidence/README.md`.
- [X] T026 [US2] Phase gate: run the full unit + e2e suite and save the evidence `evidence/us18-open-flow.json` and `evidence/us18-perf.json`.

**Checkpoint**: US1 + US2 together make saving meaningful. Every flow can be reached in ≤ 3 actions.

---

## Phase 5: User Story 3 — A reload keeps the operator signed in (P2)

**Goal**:
- The tab keeps its sign-in across reloads and tab restores, holding only the refresh token and a
  live flag in `sessionStorage`.
- A duplicated tab never replays the copied token.
- A sign-in that can't be renewed shows "Your session ended — sign in again." and then restores the
  place named in the address.

(FR-009…FR-014; research R-3; data-model §5.)

**Independent test**: sign in, open a flow, reload → same flow, no sign-in form. Sign out and
reload → the sign-in form.

**Depends on**: none of US1 or US2 functionally, so this phase can run in parallel with them on a
separate branch. It touches `+page.svelte`, so rebase before merging.

### Tests for US3 (write first, see them fail) ⚠️

- [X] T027 [P] [US3] **Unit first**: write `src/lib/api/kept-sign-in.test.ts` using a `Map`-backed fake of `Pick<Storage,'getItem'|'setItem'|'removeItem'>`. Cases:
  - `readKept` on an empty store gives `{kind:'none'}`;
  - corrupt JSON, `v !== 1` or a missing `refreshToken` gives `{kind:'none'}` and the key is removed;
  - `live:true` gives `{kind:'copied'}`;
  - `live:false` gives `{kind:'kept', refreshToken}`;
  - a storage whose methods throw makes every function return `none` or no-op, never throwing;
  - `writeKept(storage, token)` stores **exactly** the keys `['live','refreshToken','v']` (sorted), and asserts no `access`, `sub`, `user`, `role` or `permission` key (FR-011);
  - `handOver(storage)` sets `live:false` and keeps the token;
  - `reclaim(storage)` sets `live:true`;
  - `eraseKept` removes the key.
- [X] T028 [P] [US3] **Unit first**: write `src/lib/api/session.svelte.test.ts` with stubbed `fetch` and an injected fake storage (the `Session` constructor or `attachStorage()` takes the storage; production passes `sessionStorage` behind try/catch). Cases:
  - `restore()` with `kept` sends `POST /api/admin/refresh` with body `{refresh_token}` and **no** `Authorization` header. On 200: `status==='signed-in'`, `origin==='restored'`, `user` taken from `sub`, and the record rewritten with the **new** token and `live:true`;
  - a 401 on restore gives `status==='signed-out'`, `ended==='Your session ended — sign in again.'`, and the record erased;
  - a network error gives the same `ended` text followed by the error message, and the record erased;
  - `copied` gives **no fetch at all** (the copied token is never replayed), the record erased, `status==='signed-out'`, and `ended==='Sign in to continue in this tab.'`;
  - `none` gives no fetch and `ended===null`;
  - while `restore()` is pending, `status==='restoring'`;
  - `login()` gives `origin==='password'` and writes the record;
  - every proactive renewal rewrites the token;
  - `logout()`, `expire()` and a failed renewal erase the record;
  - `dedicatedToken()` never writes the record (FR-014).
- [X] T029 [P] [US3] **E2e first**: write `tests/us19-kept-sign-in.spec.ts`. Scenarios:
  1. **Reload (SC-003)**: sign in, then open a seeded flow. Run `page.reload()` 10 times, spread over > 60 s (the waits are part of the test, so at least one proactive renewal falls in between). Before the first load, `page.addInitScript` installs a `MutationObserver` on `document` that increments a counter whenever an element `#user` (the sign-in *User* field) is attached, and stores the count in `sessionStorage['e2e.signInSeen']` so it survives reloads. After the 10 reloads, the count is `0`, and after each reload the flow name equals the seeded flow. Mark the test `test.slow()`.
  2. **Run view**: dispatch the seeded 1-step flow, reload on the live-run view, and the same run GUID's view is shown (scenario 3.2).
  3. **Sign out**: *Sign out*, then reload. The sign-in form is shown, and `sessionStorage.getItem('sentai.signin')` is `null` (scenario 3.3, SC-007).
  4. **New tab**: `context.newPage()` on the same URL shows the sign-in form (scenario 3.4, SC-007).
  5. **Duplicated tab (FR-013)**: with page A signed in, read A's `sessionStorage` record and start a request log on page B. Open B with `addInitScript` copying that record into its `sessionStorage` before load. Then:
     - B shows the sign-in form with `Sign in to continue in this tab.`;
     - B sent **no** `/api/admin/refresh` request (the copied token was never replayed);
     - sign in on B, wait 70 s, and interact in both pages: neither shows the expired overlay, and both can list flows.
  6. **Session ended**: sign in and open a flow. Replace the record's `refreshToken` with a token that was already rotated (take it from the record, wait for one proactive renewal, then write the old value back), and reload. Then:
     - the message is `Your session ended — sign in again.`;
     - the record is erased;
     - after signing in, the same `flow=` and `view=` are restored.
     
     Repeat with `?view=catalog` and with `run=` (FR-012).
  7. **bfcache, deterministic**: after sign-in, run `window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted:true}))`. The record's `live` is `false`. Then dispatch `new PageTransitionEvent('pageshow', {persisted:true})`. The record's `live` is `true`, the token is unchanged, and no `/api/admin/refresh` request was sent.

     **Real navigation**: go to `about:blank` and then `goBack()`. Whichever path the browser takes (bfcache or reload), the flow ends open, no sign-in form appears, and `live === true`.
  8. **Storage audit (FR-011)**: remove the test-only key `e2e.signInSeen` first (or run this scenario in a page without scenario 1's init script). After sign-in, `sessionStorage` has only `sentai.signin`, and its parsed keys are exactly `live`, `refreshToken` and `v`. `localStorage` keys are a subset of `sentai.theme` and `sentai.guide.dismissed`. No value in either store contains the password, the page's current access token (captured from the `Authorization` header of a product request with `page.on('request')`), `_SYSTEM`, `role` or `permission`. Write `evidence/us19-storage-keys.json` with key names only.
  9. **Reload during an in-flight save (edge case)**: open a saved flow at revision `r`, make an edit, and intercept `PUT /flows/{id}` with `page.route` without continuing it, so the request never reaches the server. Click *Save flow*, then `page.reload()` while the request is held. After the reload, there is no sign-in form and no error page; the canvas shows revision `r` and the pre-edit contents; and `GET /flows/{id}` also reports revision `r` (the last revision the server confirmed; the unconfirmed edit is lost).
- [X] T030 [P] [US3] **E2e, opt-in slow**: add the test `refresh token expired (>900 s)` to `tests/us19-kept-sign-in.spec.ts`, guarded by `test.skip(!process.env.SENTAI_SLOW, 'set SENTAI_SLOW=1: waits 905 s')` with `test.setTimeout(20 * 60_000)`. Steps: sign in on page A and read the record. Close A without letting it renew again (`pagehide` hands over `live:false`). Wait 905 s, then open a new page seeded with that record and the same URL. Expect `Your session ended — sign in again.`, and after sign-in the flow in the address is restored.

### Implementation for US3

- [X] T031 [US3] Implement `src/lib/api/kept-sign-in.ts`: `KEPT_KEY = 'sentai.signin'`, `readKept`, `writeKept`, `handOver`, `reclaim` and `eraseKept`, over the injected storage, with every access in try/catch. Result: T027 passes.
- [X] T032 [US3] Extend `src/lib/api/session.svelte.ts` so that T028 passes:
  - `SessionStatus` adds `'restoring'`;
  - new `origin: 'password' | 'restored' | null` and `ended: string | null`;
  - `restore()` redeems the refresh token alone;
  - `#accept` writes the record, and `logout`, `expire` and a failed `#renew` erase it;
  - `attachPageLifecycle(win)` registers `pagehide`, which calls `handOver`, and `pageshow`, which calls `reclaim` when `event.persisted` and signed in;
  - `#renew`, the timing, `REFRESH_MARGIN_SECONDS` and `dedicatedToken()` are unchanged (FR-014);
  - update the header comment ("Tokens live in memory only") to describe the kept refresh token and research R-3.
- [X] T033 [US3] In `src/lib/shell/SignIn.svelte`, add an optional `notice: string | null` prop, rendered above the form as `role="status"` text. The existing `expired` overlay text is unchanged. In `src/routes/+page.svelte`:
  - `onMount` calls `session.attachPageLifecycle(window)` and `void session.restore()` before anything else;
  - `status === 'restoring'` renders `<main class="message"><p>Signing you back in…</p></main>`;
  - `status === 'signed-out'` renders `<SignIn notice={session.ended} />`;
  - the `boot()` trigger is unchanged (`signed-in` and `idle`), so `view`, `flow` and `run` are restored from the address.

  Result: T029 passes.
- [X] T034 [US3] **Intentional change**: update `tests/us7-catalog.spec.ts` lines 56-63. Replace the comment "tokens are in memory only, so the reload asks for the sign-in again" with "a reload keeps the tab's sign-in (spec 010 US3)", remove the `await submitSignIn(fresh);` after `fresh.reload()`, and add `await expect(fresh.getByLabel('User')).toBeHidden();`. The assertions that the catalog is visible and the URL keeps `view=catalog` stay. If the `submitSignIn` import is now unused, drop it.
- [X] T035 [P] [US3] Document the kept sign-in in `docs/limitations.md` with a new bullet "Sign-in across reloads". It covers:
  - only the refresh token is kept, per tab (`sessionStorage`), and it ends with the tab or at sign-out;
  - a reload works up to 900 s after the last renewal, and after that "Your session ended — sign in again.";
  - a duplicated tab asks for its own sign-in and never uses the copied token;
  - **after a browser crash, a killed process or a browser quit (no `pagehide`), the restored tab asks to sign in again**, which is the safe failure (research R-3.3);
  - an IRIS restart ends every kept sign-in;
  - the run's sign-in at *Run now* is unchanged.
- [X] T036 [US3] Phase gate: run the full unit + e2e suite (including the updated `us7-catalog`) and save the evidence `evidence/us19-storage-keys.json`. Run T030 once with `SENTAI_SLOW=1` and record the result in `evidence/README.md`.

**Checkpoint**: F5 no longer signs the operator out, duplicated tabs are independent, and the address is always honoured.

---

## Phase 6: User Story 4 — Run a ready-made example flow (P2)

**Goal**: *Example: storage health check* is two parallel read-only steps. It is offered on the
empty canvas, in *Open flow…* when there are no flows, and in the guide. It is opened or created
without duplicates, validates with 0 errors, and runs to completion (FR-015…FR-019, SC-005;
research R-4; data-model §4).

**Independent test**: *Open example flow*, then *Validate flow* (0 errors), then *Run now*. Every
step is `completed`, and no typed confirmation is asked.

**Depends on**: US1 (the guard, `load`/`reset` semantics) and US2 (`OpenFlowDialog`'s empty
state, and `listFlows` returning views).

### Tests for US4 (write first, see them fail) ⚠️

- [X] T037 [P] [US4] **Unit first**: write `src/lib/flows/example.test.ts`. Cases:
  - `exampleDefinition()` uses only `EXAMPLE_STEP_TYPES`, has ≥ 2 steps and `edges: []` (all in wave 1), has `name === 'Example: storage health check'`, and every step has `namespace:'%SYS'`, `wqmCategory:'Default'` and the English `taskName`s `Storage headroom check` and `Database size report`. Step `01` has `parameters: { minFreePercent: 10 }` and step `02` has `parameters: {}`. Every *declared* parameter of every example step has a value within its min/max, checked against a registry fixture copied from the live catalog (FR-015);
  - `exampleAvailable(registry)` is false when a type is missing, when one has `available:false`, or when one has `destructive:true`, and true otherwise;
  - `findExample` matches `example: STORAGE health check` (case-insensitive) and returns `null` otherwise;
  - `openExample(api)` with a fake `{listFlows, createFlow}`:
    - (a) the list contains the example: returns its id, and `createFlow` is not called;
    - (b) not found: `createFlow` is called once and its id returned;
    - (c) `createFlow` returns 409: the flows are listed **again**, and the match's id is returned (FR-017);
    - (d) 409 and still no match: the 409 error is returned verbatim;
    - (e) `listFlows` refused: the refusal is returned and `createFlow` is not called.
- [X] T038 [P] [US4] **E2e first**: write `tests/us20-example-flow.spec.ts`. In `beforeEach`, delete any flow named `Example: storage health check`: find its id through `GET /flows`, then delete it with a new helper `deleteFlowWithRuns(flowId, expectedName)` in `tests/iris.ts`. The helper removes the flow's `sentai_model.StepRun` and `Run` rows, then calls `deleteFlow`. It **refuses to run outside the dev instance**, throwing before anything is executed unless all of these hold:
  - the Playwright base URL's host is `localhost` or `127.0.0.1`;
  - the container is the compose dev container (`SENTAI_CONTAINER` unset or `sentai-task-iris-1`);
  - inside the IRIS session, `$namespace` is `IRISAPP`, the flow `flowId` exists, and its name equals `expectedName`;
  - `expectedName` is `Example: storage health check` or starts with a test prefix (`us17-`, `us18-`, `us19-`, `us20-`, `us21-`, `perf-`, `QS `, `plan010-probe-`).

  The IRIS script checks the namespace and name and prints `REFUSED:<reason>` instead of deleting, and the helper then throws. In `beforeAll`, assert the guard itself: calling it with a non-test name or with `SENTAI_CONTAINER=other` throws `refused` and deletes nothing. Scenarios:
  1. With `GET /flows` routed to `[]`, the empty canvas shows the invitation with *Open example flow* and *Start from scratch* (scenario 4.1). *Start from scratch* hides the invitation.
  2. Unrouted: *Open example flow* (from the invitation with the list routed to `[]` for the first call only) opens a flow named `Example: storage health check`. It has 2 nodes, `Storage headroom check` and `Database size report`, and no edges. Selecting *Storage headroom check* shows `MinFreePercent` = `10` in the inspector, not a placeholder (scenario 4.2, FR-015).
  3. *Validate flow* shows `Flow is valid — no errors, no warnings.` (scenario 4.3, SC-005).
  4. *Run now*: the dispatch dialog has **no** `typed-confirmations` fieldset. Enter the password. The live-run view reaches `completed` for both steps (scenario 4.4, SC-005). Record the elapsed time from the first click to run completion in `evidence/us20-example.json` (SC-004 automated part).
  5. *New flow*, then *Open example flow* again: the same id, and `GET /flows` has exactly one flow whose name equals the example's, ignoring case (scenario 4.5, FR-017).
  6. Move a node, *Save flow*, reopen through *Open flow…*: the position is kept, and the example is listed like any flow (scenario 4.6, FR-018).
  7. **Hidden offer (FR-019)**: route `GET /catalog/step-types` so that `db-size-report` is (a) absent, (b) `available:false`, or (c) `destructive:true`. In each case, no *Open example flow* appears in the invitation or in the empty *Open flow…*, and *Start from scratch* or *New flow* remain.
  8. **List refused**: route `GET /flows` to 403 at boot. No invitation is shown.
  9. Open the example with unsaved edits: the guard appears (FR-006).

### Implementation for US4

- [X] T039 [US4] Implement `src/lib/flows/example.ts` so that T037 passes:
  - `EXAMPLE_FLOW_NAME`, `EXAMPLE_STEP_TYPES` and `exampleDefinition(): FlowDefinition` (positions `01` at `{x:40,y:160}` and `02` at `{x:360,y:160}` — side by side, clear of the canvas's top-left edge legend, parameters `01: { minFreePercent: 10 }` and `02: {}`, `joins: []`, `defaultCategory:'Default'`);
  - `exampleAvailable` and `findExample`;
  - `openExample(api: Pick<typeof api,'listFlows'|'createFlow'>): Promise<ApiResult<string>>`.

  It is data plus pure orchestration over the injected API, with no Svelte.
- [X] T040 [US4] Create `src/lib/flows/EmptyCanvasInvitation.svelte`: a card centred in the canvas with the heading "Start with a ready-made flow" and the text "Open a small example of safe, read-only checks and run it on this instance." It has *Open example flow* (shown only when `exampleAvailable`) and *Start from scratch* buttons, and props `showExample`, `onexample` and `ondismiss`.
- [X] T041 [US4] Wire US4 in `src/routes/+page.svelte`:
  - `boot()` calls `api.listFlows()` once and stores `noFlows = result.ok && result.value.length === 0`. A refusal means `noFlows = false`, so there is no invitation (research R-4.4);
  - the invitation renders when `noFlows && editor.id === null && editor.steps.length === 0 && !invitationDismissed`;
  - `openExampleFlow()` is `guarded({kind:'example'}, async () => { const r = await openExample(api); r.ok ? goto(flowHref(r.value)) : editor.notice = {tone:'error', text: describeError(r.error)} })`.
  - In `src/lib/flows/OpenFlowDialog.svelte`, the `empty` state adds *Open example flow* when a new prop `showExample` is true, calling `onexample`.

  Result: T038 passes.
- [X] T042 [P] [US4] Add a free-space check to `specs/010-canvas-onboarding-usability/quickstart.md` §4, before step 1: "Run `docker exec sentai-task-iris-1 df -h /usr/irissys/mgr` and record the free %. `storage-headroom-check` fails by design when any database or journal directory has less than 10% free; that run is a real finding, not a defect." Add the same sentence to `docs/limitations.md` under a new bullet "Example flow".
- [X] T043 [US4] Phase gate: run the full unit + e2e suite and save the evidence `evidence/us20-example.json` (validation report, per-step states, elapsed time; no tokens).

**Checkpoint**: a first-time operator can go from the empty canvas to a finished run without building anything.

---

## Phase 7: User Story 5 — Getting-started guide (P3)

**Goal**: a six-step modal guide. It opens after an interactive sign-in unless dismissed in this
browser, is reachable at any time from *Help → Getting started*, is fully keyboard-operable, and
keeps working when storage is blocked (FR-020…FR-025, SC-006; research R-5; data-model §6).

**Independent test**: in a fresh profile, sign in and the guide appears. Tick *Don't show this
again*, close, then sign out and in: it doesn't appear. *Help → Getting started* opens it.

**Depends on**: US4 (`exampleAvailable` and `openExampleFlow` for step 2's action) and US3
(`session.origin` for the auto-open rule).

### Tests for US5 (write first, see them fail) ⚠️

- [X] T044 [P] [US5] **Unit first**: write `src/lib/guide/preference.test.ts` with fake storage. Cases:
  - `isDismissed` is false on an empty store and true only for `"1"`;
  - `setDismissed(true)` writes `"1"` and `setDismissed(false)` **removes** the key;
  - with `getItem` throwing, `isDismissed` is false and doesn't throw;
  - with `setItem` or `removeItem` throwing, `setDismissed` doesn't throw (FR-024).
- [X] T045 [P] [US5] **Unit first**: write `src/lib/guide/guide.svelte.test.ts`. Cases:
  - `shouldAutoOpen` truth table: true only for `origin:'password'`, `dismissed:false` and `shownThisVisit:false`; `origin:'restored'` or `null` is always false;
  - `autoOpen()` sets `open`, `step=1` and `shownThisVisit=true`;
  - `openFromHelp()` gives step 1 with `dontShow = isDismissed()`, whatever `shownThisVisit` is;
  - `close()` writes `setDismissed(dontShow)` and restores nothing else;
  - `next()` and `back()` stay within 1..6;
  - `resetVisit()` (called on logout) clears `shownThisVisit`.
- [X] T046 [P] [US5] **E2e first**: write `tests/us21-getting-started.spec.ts`, signing in with `{ guide: 'fresh' }`. Scenarios:
  1. After sign-in, `getByRole('dialog', { name: 'Getting started' })` is visible once the canvas is ready. It shows `Step 1 of 6`. *Next* ×5 walks through the titles `Welcome`, `Open the example`, `Build a flow`, `Validate and run`, `Save, Save as, Open` and `Schedule and explore`, in that order. *Back* is disabled on step 1. Step 6 shows *Get started* instead of *Next*. *Close* is present on every step (scenarios 5.1–5.3, FR-021).
  2. **Accessibility (FR-025)**:
     - the dialog element has `aria-modal="true"`, and its accessible name is `Getting started`;
     - on open, `document.activeElement` is inside the dialog;
     - pressing Tab 15 times never moves focus outside the dialog (each `activeElement.closest('dialog')` is the dialog);
     - *Escape* closes it;
     - focus returns to the element that had focus before it opened. For the Help path, that is the *Help* button.
  3. The *Don't show this again* checkbox is unticked by default. Close without ticking, then `page.reload()`: the guide does **not** reopen (same visit, restored sign-in). Sign out and sign in: it **does** reopen (scenario 5.5).
  4. **SC-006**: tick the checkbox and close. Then 5 times: sign out, sign in, and wait for the canvas. The guide dialog is never visible. Each time, *Help → Getting started* opens it at `Step 1 of 6` with the checkbox ticked (scenarios 5.4, 5.6).
  5. Untick through *Help*, close, sign out and in: it opens automatically again (scenario 5.6).
  6. **Storage blocked (FR-024)**: use an `addInitScript` that replaces `localStorage.getItem`, `setItem` and `removeItem` with functions that throw. The guide opens and closes, there are no `pageerror` events and no console errors, and it opens again on the next sign-in (scenario 5.7).
  7. Step 2's *Open example flow* button opens the example (the guard applies) and closes the guide. With the step types routed so that the example is unavailable, the button is absent but the text remains.
  8. When the guide and the empty-canvas invitation appear together, the guide is on top (it is the top-layer dialog). After closing it, the invitation is visible (edge case).
  9. At 1440×900, with *Help ▾* added, the top-bar fit assertion from T004 scenario 7 still holds.

  Write `evidence/us21-guide.json` and `evidence/us21-guide-step1.png`.

### Implementation for US5

- [X] T047 [P] [US5] Create `src/lib/guide/steps.ts` with six `{ title, body, action? }` entries, in English, following Story 5 scenario 2 of spec.md word for word in meaning:
  1. Welcome
  2. Open the example, with `action: 'open-example'`
  3. Build a flow
  4. Validate and run
  5. Save, Save as, Open
  6. Schedule and explore
- [X] T048 [P] [US5] Implement `src/lib/guide/preference.ts` (`GUIDE_KEY = 'sentai.guide.dismissed'`, `isDismissed(storage)` and `setDismissed(storage, value)`, with every access in try/catch), following `src/lib/shell/theme.svelte.ts`. Result: T044 passes.
- [X] T049 [US5] Implement `src/lib/guide/guide.svelte.ts`: a `Guide` class with `open`, `step` and `dontShow` as `$state`, `shownThisVisit` as a plain memory field, and the methods `shouldAutoOpen`, `autoOpen`, `openFromHelp`, `next`, `back`, `close` and `resetVisit`. The storage is injected, and production uses `localStorage` behind try/catch. Export the singleton `guide`. Result: T045 passes.
- [X] T050 [US5] Create `src/lib/guide/GettingStartedDialog.svelte`:
  - native `<dialog>` with `showModal()`, `aria-modal="true"`, `aria-labelledby` pointing at the `h2` "Getting started", and `aria-describedby` on the step body;
  - on open, remember `document.activeElement` and focus the step heading (`tabindex="-1"`);
  - `cancel` (*Escape*) and every close path call `guide.close()` and then restore the remembered focus;
  - a "Step n of 6" indicator with `aria-live="polite"`;
  - *Back*, *Next* or *Get started*, and *Close*;
  - the checkbox *Don't show this again*, bound to `guide.dontShow`;
  - step 2's action button *Open example flow*, rendered only when the prop `showExample` is true, calls `onexample()`.
- [X] T051 [US5] Add a `Help ▾` menu button to `src/lib/shell/TopBar.svelte`, before the user name, on every screen. It uses the menu button pattern (`aria-haspopup="menu"`, `role="menu"`, a single `menuitem` *Getting started*, arrow keys, and *Escape* returning focus). The prop `onhelp` calls `guide.openFromHelp()`. Re-run the 1440 px fit check (T004 scenario 7). If it fails, apply the T025 `More ▾` fallback now.
- [X] T052 [US5] Wire US5 in `src/routes/+page.svelte`:
  - mount `GettingStartedDialog` on all ready screens;
  - an `$effect` fires once when `phase` becomes `ready`: if `guide.shouldAutoOpen({origin: session.origin, dismissed: isDismissed(...), shownThisVisit: guide.shownThisVisit})`, then call `guide.autoOpen()`. Because `origin` is `'restored'` on a reload and `'password'` after the form, **only an interactive sign-in auto-opens it**;
  - `signOut()` calls `guide.resetVisit()`;
  - step 2's `onexample` calls `guide.close()`, then `openExampleFlow()`.

  Result: T046 passes.
- [X] T053 [US5] Phase gate: run the full unit + e2e suite and save the evidence `evidence/us21-guide.json` and `evidence/us21-guide-step1.png` (dark and light).

**Checkpoint**: all five stories work, each demonstrable on its own.

---

## Phase 8: Polish, manual acceptance, cleanup and review

- [X] T054 [P] **Theming**:
  - check that the new components use only design tokens: `grep -nE "#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(" src/lib/flows/*.svelte src/lib/guide/*.svelte` must print nothing, and every colour is a `var(--color-…)`;
  - `src/lib/design/audit.test.ts` is unchanged (it audits `tokens.json`, and no token is added);
  - capture dark and light 1440×900 screenshots of *Open flow…*, *Save as…*, the unsaved-changes dialog, the invitation and the guide with `tests/theming.ts`, into `evidence/theming-*.png`.
- [X] T055 [P] **English text audit (FR-026)**: grep the new files in `src/lib/flows`, `src/lib/guide`, `src/lib/shell/TopBar.svelte`, `src/lib/shell/SignIn.svelte` and `src/routes/+page.svelte` for user-facing strings. Confirm they are English and match the spec's wording: "Renames this flow — use Save as… to keep a copy", "Your session ended — sign in again.", "Don't show this again", "Getting started", "Example: storage health check". Record the list in `evidence/README.md`.
- [X] T056 Full regression: `npm test`, `npm run check`, `npm run build`, `bash scripts/publish-canvas.sh`, then `npx playwright test` (all specs). Record the counts in `evidence/README.md` (expected about 130 unit and about 45 e2e, all green).
- [ ] T057 **Manual quickstart §1–§2 (SC-001, SC-002)**: follow `specs/010-canvas-onboarding-usability/quickstart.md` §1 and §2 in a real browser. Run the SC-001 usability session with at least 5 operators and write `evidence/sc001-usability.md` (the count of operators ending with two flows, and any report of a lost flow).
- [ ] T058 **Manual quickstart §3 (SC-003, SC-007, FR-013)** in a real Chrome with DevTools:
  - F5 ×10;
  - **close the real tab** and reopen the URL: the sign-in form;
  - **duplicate the real tab** (right-click → Duplicate): the copy asks to sign in; after signing in, both tabs survive more than 60 s;
  - `docker-compose restart`, then reload: "Your session ended — sign in again.";
  - simulate a crash by killing the renderer from `chrome://crashes` / Task Manager → *End process*, then reload: a sign-in is required, as documented in T035.

  Record the results in `evidence/sc003-sc007-manual.md`.
- [ ] T059 **Manual quickstart §4 (SC-004, SC-005)** on a **fresh default installation**:
  - `docker-compose down -v && docker-compose up -d --build`, then publish;
  - record the free space (T042);
  - a first-time operator goes from sign-in to the example run finishing, timed. SC-004 requires under 2 minutes;
  - validate: 0 errors; every step completed; 0 destructive confirmations.

  Write `evidence/sc004-sc005.json`.
- [ ] T060 **Manual quickstart §5 (SC-006, FR-024, FR-025)**: 5 sign-ins after ticking, *Help* each time, the storage-blocked window, and keyboard-only operation with a screen reader (VoiceOver: "Getting started, dialog"). Record the results in `evidence/sc006-manual.md`.
- [X] T061 **Clean up the dev instance's test flows**. Scope: only flows created by this feature. That means names starting with `us17-`, `us18-`, `us19-`, `us20-`, `us21-`, `perf-`, `QS A` and `QS B` from the quickstart, the e2e `Example: storage health check` if the quickstart doesn't need it, and **`plan010-probe-1790544431` (id 5126)**. Do not touch the other pre-existing e2e residue (~4,960 flows). Steps:
  - list the targets with `iris-agentic-dev query -n IRISAPP "SELECT ID, name FROM sentai_model.Flow WHERE name %STARTSWITH 'us17-' OR …"`;
  - **show the list and get confirmation before deleting**;
  - for flows with runs (id 5126 has one completed run, GUID `8BA23C4E-BABA-11F1-A439-4AA3AAEA2F3D`), delete the `StepRun` and `Run` rows first, then Edge, Join and Step, then the Flow, using `deleteFlowWithRuns` (T038), so its dev-instance guard applies;
  - confirm each id answers 404 on `GET /flows/{id}`;
  - record the deleted ids in `evidence/README.md`.
- [X] T062 **No-backend confirmation**: run the T002 command. `git diff --stat master -- src/ specs/002-canvas-ui/contracts/openapi.yaml` must be empty. If it isn't, **stop and flag it** to the user before review. There are no ObjectScript changes, so no `%UnitTest` run through `iris-agentic-dev` is needed. If the diff is not empty, run the affected IRIS tests with `iris-agentic-dev` and justify the change against Constitution II.
- [X] T063 **Constitution review** of the full diff against `.specify/memory/constitution.md` and plan.md's Constitution Check. Write `specs/010-canvas-onboarding-usability/evidence/constitution-review.md` with one line per principle, each citing files:
  - **I**: no component calls `fetch` or `*Storage` (`grep -rn "fetch(\|sessionStorage\|localStorage" frontend/src/lib/**/*.svelte frontend/src/routes`);
  - **II**: no new operation, and the example is data;
  - **III**: T027's key-set test, T029 scenario 8's audit, and refusals verbatim in T004, T017 and T038;
  - **IV**: every new async path returns `ApiResult` or a union;
  - **V**: each phase shipped with a failing test first. Link the commits or test runs if they exist; never commit on this project's behalf;
  - **VI**: the spec and constitution are untouched.

  Also check the Engineering Standards: SoC, YAGNI (no unused abstraction; the `More ▾` menu only if T025 needed it) and Reproducibility.

- [X] T064 **us15 SC-004 check narrowed to target credentials; spec 010 exception.** `tests/us15-targets.spec.ts` (spec 009) failed its last check, `not.toMatch(/eyJ…/)`, because spec 010 US3 keeps this tab's own refresh token in `sessionStorage["sentai.signin"]` (FR-009, FR-011). Spec 009 SC-004 only forbids *target* passwords and tokens. The check now: (1) captures the target's `accessToken`/`refreshToken` from the page's own `POST /targets/iris-target/sign-in` and asserts neither appears in local/session storage, cookies or the URL; (2) allows exactly one JWT, `sentai.signin.refreshToken`, and fails on any other; (3) keeps the password check unchanged. Also removes an order dependency: an idempotent `beforeAll` (`GET /targets/iris-target` → `POST` on 404, then set online), like `us16`'s, so us15 passes alone and in any order. Verified: us15 alone with the target deleted first; then us16 alone; then us15 alone — all green. Test-only; no product code changed.

---

## Dependencies & Execution Order

### Phase dependencies

```text
Phase 1 Setup ─▶ Phase 2 Foundational (support.ts) ─┬─▶ Phase 3 US1 (guard + Save as/New, MVP) ─▶ Phase 4 US2 ─▶ Phase 6 US4 ─▶ Phase 7 US5 ─▶ Phase 8
                                                     └─▶ Phase 5 US3 (independent; merge before Phase 7) ─────────────────────────────────────┘
```

- **US1** depends only on Foundational (the test helper). It builds the guard.
- **US2** depends on US1: T011 (`listFlows` views), T015 (`newFlow()`) and the guard (T005, T008, T009, T010).
- **US3** is functionally independent of US1, US2 and US4. It can be built in parallel after Phase 2, but it must be merged before US5, which reads `session.origin`.
- **US4** depends on US1 (the guard, `load`/`reset`) and US2's `OpenFlowDialog` and view-mapped `listFlows`.
- **US5** depends on US4 (`exampleAvailable`, `openExampleFlow`) and US3 (`origin`).

### Within each story

The e2e and unit tests are written first and seen failing. Then come the pure modules, then the
components, then the wiring in `+page.svelte`, and finally the phase gate.

## Parallel Opportunities

- **Phase 2**: a single task (T003).
- **US1**: T004 ∥ T005 ∥ T006 ∥ T007 (four test files); then T008 → T009 → T010 (the guard); T011 → T012; T013 ∥ T014 (different files) after T012; T015 last.
- **US2**: T017 ∥ T018 ∥ T019 are all test tasks. T017 and T019 are in the same file, so write them as one change or sequentially; T018 is truly parallel. Then T020 ∥ T021's markup, with T022 → T023 → T024 → T025.
- **US3**: T027 ∥ T028 ∥ T029 ∥ T030 (T029 and T030 share a file, so write them sequentially); T031 → T032 → T033; T034 ∥ T035 at any point in the phase.
- **US4**: T037 ∥ T038; T039 → T040 → T041; T042 is parallel to all of them.
- **US5**: T044 ∥ T045 ∥ T046; T047 ∥ T048; then T049 → T050 → T051 → T052.
- **Polish**: T054 ∥ T055; the manual runs T057–T060 can be spread over sessions; T061–T063 run last.

### Parallel example: US3

```text
Task: "T027 Unit first: src/lib/api/kept-sign-in.test.ts"
Task: "T028 Unit first: src/lib/api/session.svelte.test.ts"
Task: "T029 E2e first: tests/us19-kept-sign-in.spec.ts"
Task: "T035 Document kept sign-in in docs/limitations.md"
```

## Implementation Strategy

1. **MVP = Phases 1–3 (US1)**. This removes the only data-loss gap: the unsaved-changes guard,
   Save as, New flow and the rename notice. Demonstrate it with `us17` and quickstart §1.
2. **+US2**: saved work becomes reachable, and together with US1 the feedback's first two
   complaints are fixed.
3. **+US3**: F5 no longer signs the operator out. This can be developed alongside 1–2.
4. **+US4**: the one-click example.
5. **+US5**: the guide that ties everything together.
6. **Phase 8**: manual SCs, cleanup, the no-backend confirmation, and the Constitution review.

After each phase, stop and demonstrate before moving on: the phase's spec file green, plus the
matching quickstart section.

## Notes

- `[P]` means different files and no dependency on an incomplete task.
- Never commit or push on this project's behalf. Leave changes uncommitted for the user.
- If any task finds it needs a backend or `openapi.yaml` change, stop and flag it (hard rule).
