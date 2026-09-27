# Research: Canvas Onboarding and Flow Management Usability

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Date**: 2026-09-27

Every finding marked **(probed)** was measured against the running compose stack
(`sentai-task-iris-1`, IRIS 2026.2, `_SYSTEM`) on 2026-09-27, with `curl`, `iris session` and
`iris-agentic-dev`. The probe flow (`plan010-probe-1790544431`, id 5126, one completed run) is
still on the dev instance with the other e2e residue. Its name can't clash with the example's
name.

---

## R-1 The flow list: the existing contract is enough

**Decision**: Use `GET /flows` (spec 002 contract, `FlowSummary`) unchanged. No API change, so
there is no `contracts/` directory for this feature.

**Findings (probed)**:

| FR-002 needs | `FlowSummary` field | Actual wire value |
|---|---|---|
| identifier | `id` | `"95"` (string) |
| name | `name` | as saved |
| revision | `revision` | `1` (number; `wire.ts` already tolerates strings) |
| last-saved time | `savedAt` | `"2026-09-26 09:29:13"` — platform format, not ISO 8601 |

- The backend orders by `name` (`sentai.rest.Dispatcher:ListFlows`). FR-002 wants
  most-recently-saved first, so the client sorts. `YYYY-MM-DD HH:MM:SS` sorts correctly as text;
  ties break on name. Sorting is presentation, not a workaround for a missing field.
- The dev instance holds **4,962** flows (e2e residue). The whole list is 663 KB and returns in
  60 ms. Client-side filtering over that is instant; rendering ~5k plain rows in a dialog is
  acceptable. No paging or server filter is needed (YAGNI). If this becomes a problem, the fix is
  a declared `?q=` parameter in `openapi.yaml`, not a client cache.
- `savedBy` and `nextRun` are present but not required by the spec; they are not shown.

**Alternatives rejected**:
- *Add `?sort=savedAt` to the API* — the client can order a list it already receives in full;
  a new parameter adds contract surface with no second consumer (YAGNI).
- *Cache the list between dialog openings* — the Key Entities say "never cached across
  sign-ins"; re-reading on each opening costs 60 ms and is always current.

---

## R-2 Platform refusals while managing flows (probed)

| Situation | Status | `detail` (shown verbatim) |
|---|---|---|
| `POST /flows` with a taken name (case-insensitive unique index `NameIndex`) | 409 | `A flow with this name already exists` |
| `PUT /flows/{id}?revision=<stale>` | 409 | `Flow was saved by someone else since it was loaded` |
| `GET /flows/{missing}` | 404 | `Flow '99999999' does not exist` |

**Decision**: These already travel as `ApiError { kind: 'problem' }` values and are rendered with
`describeError` (the platform's `detail`, unmodified). For FR-005's conflict hint, the canvas adds
a **separate** line ("Use Save as… to keep your version.") below the verbatim text when a *Save
flow* returns 409. It never rewrites the platform's words (Constitution III).

---

## R-3 Keeping the sign-in across a reload

### R-3.1 How the platform's refresh behaves (probed)

| Probe | Result |
|---|---|
| JWT lifetimes on `/api/admin` and `/csp/sentai/api/v1` | access **60 s**, refresh **900 s** |
| `POST /api/admin/refresh` with `{refresh_token}` and **no** `Authorization` header | **200** — a new pair |
| Replaying a refresh token that was already rotated | 401 |
| …and after that replay, the **newer** access token and refresh token | **both 401** |
| Two independent sign-ins; refreshing one | the other stays valid (200) |
| Refresh 70 s after sign-in (access token already expired), no `Authorization` header | **200** |

Three consequences:

1. **Only the refresh token needs to be kept.** The spec 001 note says refresh "requires the
   current access token"; in practice it doesn't. The access token (60 s) is never persisted.
   `Session.#renew` keeps sending the bearer for now (harmless, unchanged behaviour); the redeem-
   on-load path sends only the refresh token.
2. **The platform detects reuse and revokes the whole family.** A second holder that redeems an
   already-rotated token doesn't just fail: it signs the first holder out. This is the core of
   FR-013.
3. **Separate sign-ins are independent.** This is why the dispatch-time run sign-in (spec 002
   E-1) is unaffected, and why a copied tab must get its *own* sign-in rather than share one.

### R-3.2 Where the kept sign-in lives

**Decision**: `sessionStorage`, key `sentai.signin`, holding one record:
`{ "v": 1, "refreshToken": "<jwt>", "live": true|false }`. Nothing else.

**Rationale**: `sessionStorage` is per tab and is dropped when the tab closes (FR-010, SC-007),
survives reload and tab restore (FR-009), and is not sent to the server by the browser the way a
cookie is. The record holds one credential and one bookkeeping flag. There is no user name, role,
permission, capability or expiry in it (FR-011, Constitution III). The user name is taken from
the `sub` of the redeemed pair, from the platform, on every load.

**Alternatives rejected**:
- *`localStorage`* — outlives the tab and is shared by every tab: it breaks FR-010, FR-013 and
  SC-007.
- *A cookie (including `HttpOnly` set by the backend)* — needs a new backend login/refresh proxy
  (Constitution II surface, spec 002 FR-034 changes) and is shared across tabs, so it breaks
  FR-013.
- *IndexedDB* — per origin, not per tab; same problems as `localStorage` with more code.
- *Keep the access token too* — not needed (R-3.1). A token that can call the API directly
  would be sitting in storage for no benefit.

### R-3.3 Duplicated tabs (FR-013)

The browser copies `sessionStorage` when a tab is duplicated. The copy holds the same refresh
token the original tab still uses. If the copy redeems it, the platform rotates it, and at the
original's next proactive renewal (≤ 45 s) the original replays a revoked token. R-3.1 shows that
this revokes the whole family, so the original is signed out. Two tabs would also be sharing one
sign-in, which FR-013 forbids even if nothing broke.

**Decision — the "live" flag handover, and a copy signs in again.**

- While a page owns the kept sign-in, its record says `live: true`.
- On `pagehide`, which fires on reload, navigation away and tab close, the page writes
  `live: false`. It hands the credential to whichever page loads next in the same tab. On
  `pageshow` with `persisted` (back from bfcache) it takes the credential back (`live: true`).
- On load:
  - `live: false` → redeem the token. This is a reload or a restored tab.
  - `live: true` → another live page still owns this token, so this tab is a **copy**. Erase the
    copied record *without redeeming it* and show the sign-in form with "Sign in to continue in
    this tab." The copy's own sign-in then gets its own, independent token family (R-3.1 row 5).
  - no record → the normal sign-in form.
- Every rotation rewrites the record with the new token in the same synchronous step as
  `#accept`.

**Why this is enough**: a reload always runs `pagehide` before the next document's scripts, so a
reload is never mistaken for a copy. A duplicate is taken while the original is alive, so the copy
always sees `live: true`. The check is synchronous and needs no timeout. If a page dies without
`pagehide` (crash, killed process, browser quit), the next load sees `live: true` and asks to
sign in again. That is the safe failure. The token would be at most 15 minutes from expiry
anyway.

**Alternatives rejected**:
- *Per-tab id + `BroadcastChannel` ("is anyone using tab id X?")* — every load has to wait for
  replies with a timeout. A background tab that the browser has frozen or discarded can't
  answer, so the copy concludes "nobody owns it", redeems, and signs the original out. That is
  exactly the FR-013 failure, in the most common duplicate-tab situation (the original goes to
  the background). It is also more code, and it adds latency to every reload.
- *Web Locks (`navigator.locks`, exclusive lock named after a per-tab id)* — this detects a live
  owner correctly and survives crashes. But on reload the old document's lock is released
  asynchronously relative to the new document's scripts, so the new page must wait for it with a
  timeout. A timeout that is too short makes a reload look like a copy. A long one slows every
  reload. It is kept in reserve if the `pagehide` handover proves unreliable in a supported
  browser. The e2e suite would reveal that.
- *Detect a duplicate from `performance.getEntriesByType('navigation')[0].type`* — browsers
  report a duplicated tab inconsistently (`navigate` or `back_forward`), so this isn't a
  specified signal.
- *Let the copy redeem and have the original recover by signing in* — this breaks FR-013 by
  design.
- *Share one sign-in between tabs through `BroadcastChannel` (leader election)* — this breaks
  FR-013's "two tabs MUST NOT share one kept sign-in", and it is the most complex option.

### R-3.4 Redeeming on load and the "session ended" path (FR-012)

**Decision**: `Session` gets a `restore()` step, called once from `+page.svelte`'s `onMount`,
before anything reads `session.status`. While it runs, the status is a new `'restoring'` state,
and the page shows "Signing you back in…" instead of the sign-in form (SC-003: the form is
shown 0 times). Outcomes:

| Redeem result | Record | Screen |
|---|---|---|
| 200 → pair | rewritten (`live: true`, new token) | `signed-in`; `boot()` reads `flow`, `run`, `view` from the address as today |
| 401 / any non-2xx (expired, revoked, **instance restarted**, reuse-revoked) | erased | sign-in form with **"Your session ended — sign in again."** |
| network failure (instance down) | erased | the same message, followed by the network error text verbatim |

The address is never touched on this path. After the operator signs in, `boot()` reopens the
flow, run and screen that the address names (FR-012). An IRIS restart invalidates refresh
tokens, so it is an ordinary 401 on redeem, not an error page. This is verified manually in
quickstart §4, because restarting the shared stack inside the e2e suite would disrupt other
specs.

The record is also erased on `logout()`, on `expire()` (the platform answered 401 to a call), and
when a proactive renewal fails. These are the FR-010 "rejected" cases.

**Unchanged (FR-014)**: proactive renewal at `exp − iat − 15 s` (spec 002 FR-034);
`dedicatedToken()` for *Run now*, whose pair is never stored; the 401 → `expire()` path in
`api/client.ts`; the `SignIn expired` overlay mid-session.

### R-3.5 Refresh after the access token expired (probed)

This probe checks whether redeeming works when the access token expired while the tab was
closed or reloading, which is the "reloaded after a minute" case.

**Result**: 200. A reload works for as long as the refresh token lives (900 s since the last
rotation), not just within the 60 s access lifetime. In the first probe run, a refresh after
70 s failed with 401. That was not caused by expiry: the same probe had just replayed a rotated
token, which revoked the family (R-3.1 row 4). The clean rerun separated the two effects.
Consequence: a tab reloaded or restored more than 15 minutes after its last renewal shows
"Your session ended — sign in again.", which is the intended FR-012 path.

### R-3.6 Constitution III evidence

- Stored: one refresh token and a boolean. Stored nowhere: password (used once by `login()`,
  then cleared from the form state as today), access token, `sub`, roles, resources, step
  permissions, validation outcomes.
- Each request is authorized by the platform when it is made. Redeeming a token grants
  nothing; it only produces a credential that the platform then judges.
- Test: a unit test asserts that the serialized record has exactly the keys
  `v`, `refreshToken`, `live`. An e2e test reads `sessionStorage` and `localStorage` after sign-in and
  asserts that no value contains the password, the access token, or a key other than
  `sentai.signin`, `sentai.theme` or `sentai.guide.dismissed`.

---

## R-4 The example flow

### R-4.1 Composition, checked against the registry (probed)

`GET /catalog/step-types` on the dev instance:

| type | destructive | available | executor | parameters |
|---|---|---|---|---|
| `storage-headroom-check` | false | **true** | in-process | `minFreePercent` (optional, default 10) |
| `db-size-report` | false | **true** | in-process | none |
| `integrity-check` | false | true | platform-api | none — rejected, see below |
| `switch-journal` | false | true | in-process | none — **rejected: changes instance state** |

Cross-checked in IRIS with `iris-agentic-dev exec -n IRISAPP` against `sentai.registry.StepType`.
For both chosen types, `IsKnownType`, `IsAvailable` and `IsInstalled` return 1,
`IsDestructive` returns 0, and `GetExecutor` returns `in-process`. `minFreePercent` is declared
as `number`, 0–100, default 10, not required.

**Decision**: The example is two parallel steps with no edges, so both run in wave 1:

| id | type | taskName (English) | namespace | wqmCategory | parameters |
|---|---|---|---|---|---|
| `01` | `storage-headroom-check` | Storage headroom check | `%SYS` | `Default` | `{ "minFreePercent": 10 }` |
| `02` | `db-size-report` | Database size report | `%SYS` | `Default` | `{}` |

- Flow name: **`Example: storage health check`**, `defaultCategory: "Default"` (the stock WQM
  category; `SENTAI.DEFAULT` doesn't exist, see `docs/limitations.md`), side-by-side positions.
- **Probed end to end**: created → `POST /validate` → `{"errors":[],"warnings":[]}` → dispatched
  with a run credential → run `completed` in about 1 s, both steps `completed`, with no
  confirmation requested (neither type is destructive). This meets SC-005 on this installation.
- `minFreePercent: 10` is written explicitly, so the inspector shows a filled, valid value
  (FR-015 "all parameters pre-filled"). The value equals the registry's declared default (0–100),
  so validation and the probed run are unchanged. Probed again with the explicit value (flow
  5126, `PUT` then `POST /validate`): `{"errors":[],"warnings":[]}`. `db-size-report` declares
  no parameters.
- *Rejected additions*: `integrity-check` is non-destructive but runs a platform job over whole
  databases, which is slow on a real instance and works against SC-004's 2 minutes.
  `switch-journal` is declared non-destructive but switches the journal file, so it is not
  "read-only". The spec promises "safe, read-only checks".

**Risk**: `storage-headroom-check` fails by design when a database or journal directory has less
than 10% free. On such an instance the example reports a real finding, which is correct behaviour
but not "every step finished successfully". SC-005 is stated for a default installation. The
quickstart records the free space before the run.

### R-4.2 Where the definition lives

**Decision**: A versioned, typed **data constant** in the frontend,
`frontend/src/lib/flows/example.ts` (`EXAMPLE_FLOW_NAME`, `EXAMPLE_STEP_TYPES`,
`exampleDefinition(): FlowDefinition`). It is created through the existing
`POST /flows` with the operator's own sign-in.

**Rationale (Constitution II)**: The definition is *data* composed only of step types from the
closed, declared registry. It is reviewed in the source tree like any other code, and the backend
validates it against the flow schema and the registry on `POST` and on `/validate`, exactly like
a hand-built flow. It adds no capability, no new operation and no runtime-supplied code.
Creating it with the operator's own credential keeps authorization with the platform
(Constitution III): an operator who may not create flows gets the platform's refusal verbatim.
The backend needs no change, so there are no IRIS-side tests to add (FR scope: "frontend-first").

**Alternatives rejected**:
- *A declared backend operation `POST /flows/example`* — adds an operation, an `openapi.yaml`
  entry, ObjectScript and IRIS tests to produce something the existing `POST /flows` already
  produces. It would be justified only by a second consumer, such as a CLI that installs the
  example (YAGNI). It is also the more privileged shape, because the server would decide what to
  create on the operator's behalf.
- *Seed the example at install time (`iris.script` / `module.xml`)* — it would exist before any
  operator chose it, owned by the installer. It would be absent on instances installed before
  this release. Once deleted, it would not come back. The empty-canvas offer (FR-016a, "no saved
  flows") could then never trigger on a fresh install.
- *Ship it as a JSON file fetched at runtime* — this gives nothing over a typed constant and
  adds a load path and a failure mode.

### R-4.3 Idempotency (FR-017) — the name is the identity

**Decision**: `openExample()` runs in this order:

1. `GET /flows` (fresh). If a summary's name equals `EXAMPLE_FLOW_NAME` ignoring case (the
   platform's `NameIndex` is `SQLUPPER`), open that id.
2. Otherwise, `POST /flows` with `exampleDefinition()` and open the result.
3. If the `POST` answers **409**, another tab or operator created it in between. Repeat step 1
   and open the match. If there is still no match, show the platform's refusal verbatim.
   Any other refusal is shown verbatim too.

The platform's unique index guarantees that **there is never a duplicate**, whatever the race.
The client only decides whether to open or create. If an operator renamed their example, *Open
example flow* creates a fresh one under the well-known name. That is acceptable, since the Key
Entities identify the example by its name. Edits made to the example are kept (FR-018), because
it is opened, never overwritten.

### R-4.4 When the example is offered (FR-016, FR-019)

`exampleAvailable(registry)` is a pure function. It is true only when **every** type in
`EXAMPLE_STEP_TYPES` is in the registry with `available: true` and `destructive: false`. The
destructive check is defensive: if the registry ever reclassified a type, the offer disappears
instead of offering something unsafe. When it is false, the empty-canvas invitation shows only
*Start from scratch*, *Open flow…* shows only *New flow*, and the guide's step 2 shows its text
without the action button.

"No saved flows" (FR-016a/b) comes from a fresh `GET /flows` at boot and at each *Open flow…*.
If that read is refused, the invitation isn't shown and *Open flow…* shows the refusal
verbatim. The operator may not be able to list flows, and inviting them to create one on a
guess would imply a permission (Constitution III).

---

## R-5 Getting-started guide

**Decision**:
- **Dialog**: a native `<dialog>` opened with `showModal()`, like `DispatchDialog` and
  `ScheduleDialog`. `showModal()` gives the modal semantics (`aria-modal` is implied; set
  explicitly anyway for older assistive tech), makes the rest of the page inert so focus can't
  leave the dialog, and fires `cancel` on *Escape*. Also used: `aria-labelledby` on the
  "Getting started" heading, and `aria-describedby` on the current step's body. Focus starts on
  the step heading. The element that was focused when the dialog opened is remembered and focused
  again on `close`. Browsers restore focus on their own inconsistently, so this is done
  explicitly.
- **Steps**: six items in `lib/guide/steps.ts` (title and body, English, the Story 5 text).
  The index is component state. The controls are *Back* (disabled on step 1), *Next* (on steps
  1–5), *Get started* (on step 6), *Close* (every step), and a "Step n of 6" indicator
  (`aria-live="polite"`).
- **Preference**: `lib/guide/preference.ts`, pure functions over an injected
  `Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>`, with every access in `try/catch`,
  following `lib/shell/theme.svelte.ts`. The key is `sentai.guide.dismissed`, and `"1"` means
  dismissed. A read that fails means "not dismissed", and a write that fails is ignored
  (FR-024). The checkbox value is written **at close** (FR-022), and unticking it removes the key.
- **Visit memory**: `guide.svelte.ts` holds `shownThisVisit` in memory only. It is reset by
  `logout()`.
- **When it opens automatically (FR-020)**: only after an **interactive** sign-in
  (`session.login` succeeded; `session.origin === 'password'`), once `boot()` reaches `ready`, if
  the guide is not dismissed and not `shownThisVisit`. A reload that restores the kept sign-in
  (`origin === 'restored'`) is the same visit and doesn't reopen it. This matches scenario 5 ("not
  again during this visit, but on the next sign-in") and SC-006, which counts sign-ins. The
  mid-session "expired" overlay sign-in is interactive, but `shownThisVisit` stops a second
  opening.
- *Help → Getting started* opens at step 1 with the checkbox set from the stored preference
  (FR-023, scenario 6).
- When the guide and the empty-canvas invitation appear together, the dialog is in the top
  layer, so it is on top. The invitation stays in the canvas.

**Alternatives rejected**:
- *A hand-rolled `div role="dialog"` with a focus-trap library* — adds a dependency and
  reproduces what `showModal()` does natively. The product already uses `<dialog>`.
- *Remember "shown this visit" in `sessionStorage`* — it would survive a sign-out and sign-in in
  the same tab, contradicting scenario 5.
- *Store the preference on the platform (per operator)* — the Clarifications made it a
  per-browser display preference. A server setting would need a new declared operation for no
  requirement.
