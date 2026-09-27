# Data Model: Canvas Onboarding and Flow Management Usability

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Research**: [research.md](research.md)

No persisted backend entity changes. The four entities below are frontend views or small
client-side records. Two of them are the only things this feature writes to browser storage.

---

## 1. Flow summary (read-only view of `GET /flows`)

Module: `frontend/src/lib/flows/list.ts` (pure).

| Field | Type | Source | Rule |
|---|---|---|---|
| `id` | `string` | `FlowSummary.id` | `String(...)`; identity for opening and for "currently open" |
| `name` | `string` | `FlowSummary.name` | shown as-is; the platform guarantees it is unique case-insensitively |
| `revision` | `number` | `FlowSummary.revision` | number or string on the wire → number (`toNumberOrNull`, `0` if absent) |
| `savedAt` | `string \| null` | `FlowSummary.savedAt` | kept in the platform's own format `YYYY-MM-DD HH:MM:SS`; `""` → `null` |

Operations (pure, unit-tested):
- `fromWireFlowSummary(w) → FlowSummaryView`.
- `orderBySaved(list)`: sorts by `savedAt` descending (text order is chronological in this
  format), with `null` last and name ascending on ties (FR-002).
- `filterByName(list, text)`: keeps names containing `text.trim()`, ignoring case, so an
  empty filter keeps everything (scenario 2.2).
- `defaultFlowName(now, takenNames)` gives `Untitled flow YYYY-MM-DD HH:MM:SS`, with ` (2)`, ` (3)`… added
  while the name clashes case-insensitively with a name in `takenNames` (FR-007). The
  names only help avoid a clash: the platform still refuses a clash on save, and its refusal is
  shown verbatim.

Lifetime: read fresh each time *Open flow…* opens and once at boot (to get the "no saved flows"
fact). Kept only in the dialog's component state and never cached across openings or sign-ins
(Key Entities).

## 2. Editor document state (extension of `FlowEditor`)

Module: `frontend/src/lib/flow/editor.svelte.ts`. New fields and derived values:

| Member | Kind | Meaning |
|---|---|---|
| `savedName` | `$state<string \| null>` | the name as last confirmed by the platform (`load`, `save`, `saveAs`); `null` for a never-saved draft |
| `renaming` | `$derived` | `id !== null && savedName !== null && name.trim() !== savedName` — drives the FR-005 notice |
| `conflictHint` | `$state<boolean>` | set when *Save flow* returns 409; shows "Use Save as… to keep your version." under the verbatim refusal |

New methods, each returning a value (Constitution IV) and never throwing across the boundary:

| Method | Effect | Result |
|---|---|---|
| `saveAs(name)` | `POST /flows` with `toDefinition({...toDocument(), id: null, name})`, which carries the current steps, edges, positions and default category, unsaved edits included; on success `load(created)` | `ApiResult<FlowDocument>`: on failure the editor is **unchanged** (same id, name, revision, dirty) and the error goes back to the dialog |
| `reset(name)` | clears nodes and edges; `id = null`, `revision = 0`, `savedAt = null`, `savedName = null`, `report = null`, `notice = null`, `dirty = false`; sets `name` | `void` |

State transitions of the open document:

```text
                 reset(defaultName)                 save() ok
  ┌─────────┐  ◀──────────────────  any  ┌───────────────┐ ─────────▶ ┌──────────┐
  │  draft  │ ────── save() ok ────────▶ │  saved(clean) │ ◀───────── │ saved    │
  │ id=null │ ────── saveAs(n) ok ─────▶ │  id, savedName│  edit ──▶  │ (dirty)  │
  └─────────┘                            └───────────────┘            └──────────┘
                                                ▲  saveAs(n) ok: load(new) — new id, the
                                                │  original is untouched on the server
                                                └── load(doc): Open / example / address
```

- **Save as on a draft** behaves like the first *Save flow*, but with the entered name (edge case).
- **Save as with unsaved edits** puts the edits only in the new flow. The original keeps its last
  saved revision because no `PUT` is sent (edge case).

## 3. Unsaved-changes guard

Module: `frontend/src/lib/flows/guard.ts` (pure) + `frontend/src/lib/flows/UnsavedChangesDialog.svelte`.

```ts
type PendingSwitch =
  | { kind: 'new' }
  | { kind: 'open'; flowId: string }
  | { kind: 'example' }
  | { kind: 'address'; url: URL };           // back/forward or a link that changes `flow`
type GuardChoice = 'save' | 'discard' | 'cancel';
type GuardStep = { next: 'proceed' } | { next: 'stay' } | { next: 'save-then-proceed' };
```

- `needsGuard(dirty)`: the dialog appears only when the open flow has unsaved edits (FR-006).
- `decide(choice)` returns `save` → `save-then-proceed`, `discard` → `proceed`, or
  `cancel` → `stay`.
- `afterSave(ok)` is the second step of `save-then-proceed`: `afterSave(true)` returns
  `{next:'proceed'}`, and `afterSave(false)` returns `{next:'stay'}`. On `stay`, the dialog stays
  open and shows the verbatim refusal, and the switch is not made.
- One instance in `+page.svelte`, used by the *New flow* command, the *Open flow…* pick, *Open
  example flow*, and SvelteKit `beforeNavigate` when a navigation changes the `flow` parameter.
  `beforeNavigate` covers back/forward and catalog origin links: the navigation is cancelled, the
  guard runs, and the target URL is re-issued after *Save* or *Discard*.

## 4. Example flow

Module: `frontend/src/lib/flows/example.ts` (pure data + two pure functions).

| Item | Value |
|---|---|
| `EXAMPLE_FLOW_NAME` | `Example: storage health check` |
| `EXAMPLE_STEP_TYPES` | `['storage-headroom-check', 'db-size-report']` |
| `exampleDefinition()` | `FlowDefinition`: steps `01` *Storage headroom check* and `02` *Database size report*, both `namespace: '%SYS'`, `wqmCategory: 'Default'`; parameters `01: { minFreePercent: 10 }`, `02: {}`; `edges: []`, `joins: []`, so the two steps run in parallel; `defaultCategory: 'Default'`; positions side by side |
| `exampleAvailable(registry)` | every `EXAMPLE_STEP_TYPES` entry present **and** `available` **and** not `destructive` (FR-019) |
| `findExample(summaries)` | the summary whose name equals `EXAMPLE_FLOW_NAME` ignoring case, or `null` (FR-017) |

Identity: the name. The platform's unique `NameIndex` makes a duplicate impossible. On a 409 from
create, the client lists the flows again and opens the match ([research R-4.3](research.md)).
Once created, the example is an ordinary flow (FR-018), with nothing special stored.

## 5. Kept sign-in

Module: `frontend/src/lib/api/kept-sign-in.ts` (pure, over an injected storage); wired by
`frontend/src/lib/api/session.svelte.ts`.

Storage: `sessionStorage['sentai.signin']`, JSON:

| Field | Type | Meaning |
|---|---|---|
| `v` | `1` | record version; any other value is treated as absent and erased |
| `refreshToken` | `string` | the current refresh token of **this tab's** sign-in; rewritten on every rotation |
| `live` | `boolean` | `true` while a page in this tab owns it; `false` after `pagehide` (handover to the next load) |

Nothing else is stored: no user name, access token, password, roles, resources, permissions,
capabilities or expiry (FR-011, Constitution III). A unit test pins this key set.

Read on load, `readKept(storage)`:

| Stored | Result | Session action |
|---|---|---|
| nothing / unparseable / `v ≠ 1` | `{ kind: 'none' }` | erase; normal sign-in form |
| `live: true` | `{ kind: 'copied' }` (another live page owns it, so this is a duplicated tab) | erase **without redeeming**; sign-in form, "Sign in to continue in this tab." |
| `live: false` | `{ kind: 'kept', refreshToken }` | redeem via `POST /api/admin/refresh` (refresh token only) |

`Session` status machine (the new pieces are `restoring` and the `origin` and `ended` fields):

```text
 load ─▶ restoring ──redeem 200──────▶ signed-in (origin='restored')
            │ └─redeem 401/5xx/net───▶ signed-out (ended: "Your session ended — sign in again.")
            └─copied / none──────────▶ signed-out (ended: null | copied note)
 signed-out ──login ok──▶ signed-in (origin='password')      ── writes record live:true
 signed-in ──renew ok──▶ signed-in                            ── rewrites refreshToken
 signed-in ──renew fail / 401 on a call──▶ expired            ── erases record
 any ──logout──▶ signed-out                                   ── erases record
 pagehide ──▶ record.live=false        pageshow(persisted) ──▶ record.live=true
```

`dedicatedToken()` (the run's sign-in) is unchanged and never touches the record (FR-014).

## 6. Guide preference and visit memory

Module: `frontend/src/lib/guide/preference.ts` (pure, injected storage) and
`frontend/src/lib/guide/guide.svelte.ts` (state).

| Item | Where | Type | Rule |
|---|---|---|---|
| dismissed | `localStorage['sentai.guide.dismissed']` | `"1"` or absent | written **at close** from the checkbox: ticked → `"1"`, unticked → removed (FR-022); every access is in `try/catch`, so a read that fails means not dismissed and a write that fails is ignored (FR-024) |
| `shownThisVisit` | memory (`guide.svelte.ts`) | `boolean` | set when the guide auto-opens; reset on `logout()`; never persisted |
| `open`, `step` (1–6), `dontShow` | memory | — | `openFromHelp()` gives step 1 with `dontShow = isDismissed()` (FR-023) |

Auto-open rule, `shouldAutoOpen({ origin, dismissed, shownThisVisit })`, is pure: true only when
`origin === 'password'`, `!dismissed` and `!shownThisVisit`. It is evaluated once, when the page
phase becomes `ready` (FR-020).

Guide content: `frontend/src/lib/guide/steps.ts`, six `{ title, body }` entries in English, in
the order of Story 5, scenario 2. Step 2 carries `action: 'open-example'`, which is shown only when
`exampleAvailable(registry)`.
