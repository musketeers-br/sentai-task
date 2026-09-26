# Research — 007 Canvas Management Screens (Phase 0)

Sources:
- the frontend at `frontend/src` (SvelteKit 2, Svelte 5, `@xyflow/svelte`, static adapter);
- its tests: unit **48** (7 files), e2e **13** (6 specs);
- the contracts of specs 005 and 006;
- `design/Catalog.dc.html` and `design/System.dc.html`;
- the backend code the frontend talks to (read-only here).

## R-1 — Routing: addressable catalog and detail, back button, open flow kept

**Current code.** There is one prerendered route (`src/routes/+page.svelte`, `prerender = true`,
`ssr = false`, `adapter-static` with `fallback: undefined`). The canvas is served by
`sentai.web.StaticFiles`, which only answers files that exist. `src/hooks.ts` reroutes
`…/index.html` to `/` for that reason. The open flow and the watched run already travel in the query
string (`?flow=1&run=…`, written with `replaceState` from `$app/navigation`), because
"ServeFiles has no directory-index or SPA fallback" (comment in `+page.svelte`).

A path route such as `/csp/sentai/catalog/4` would need a new prerendered file per task, or an SPA
fallback in the web server. That is a backend change, which is out of scope.

SvelteKit's shallow `pushState`/`replaceState` store the **previous** `page.url` (see
`node_modules/@sveltejs/kit/src/runtime/client/client.js`, `pushState` → `PAGE_URL_KEY:
page.url.href`), so after a shallow push `page.url` does not describe the new screen.

**Decision.**
- The screen lives in the query string of the one page: `?view=catalog`, and for a task's detail
  `&task=<id>`. The flow canvas is the default (no `view`). `flow` and `run` are kept exactly as
  today.
- Navigation between screens uses `goto(url, { keepFocus: true, noScroll: true })`, a real client
  navigation to the same route. That gives a history entry for the back button, updates
  `page.url`, and keeps the page component mounted.
- The current screen is derived from `page.url.searchParams` (`$app/state`).
- The `FlowEditor` instance lives in `+page.svelte` and is not recreated. The open flow, including
  unsaved edits, and the theme survive switching screens (FR-001).
- The existing `syncUrl()` switches from shallow `replaceState` to
  `goto(url, { replaceState: true, keepFocus: true, noScroll: true })`. Everything then reads one
  consistent `page.url`.
- The first task's e2e test checks four cases:
  1. a deep link to `?view=catalog&task=<id>` opens the detail;
  2. back returns to the canvas with the same flow and its unsaved edit;
  3. forward returns to the catalog;
  4. a reload of `?view=catalog` works through `StaticFiles`.

**Alternatives rejected.**
- New SvelteKit routes: need a server fallback (backend change).
- Shallow `pushState` + `page.state`: a deep link carries no state, and `page.url` goes stale.
- A hash router: a second routing system next to the one the page already uses.

## R-2 — Where the namespace options come from (US-3.2)

The spec 006 API has no namespace list and no new endpoint is allowed. A filtered response shows
only the namespaces that survived the filter.

**Decision.** The options are the distinct `namespace` values of the **most recent unfiltered
response**, meaning one with no `q`, `namespace`, `filter` or `destructiveOnly`, plus *all*. They
are kept in memory while the catalog screen is mounted.
- The catalog opens with an unfiltered read, so this costs nothing extra.
- If the screen opens with filters already applied (a future deep link), one unfiltered read is
  made first.
- A refresh with no filters replaces the options.
- Reading distinct values that the API returned is display, not a rule (FR-019).

**Rejected.** Hard-coded namespaces, which is what the prototype shows. Namespaces from the
filtered list, which would lose options after the first filter.

## R-3 — Sorting by next run without reformatting values

Spec 006 R-5 shows that `nextRun` is `YYYY-MM-DD HH:MM:SS`, or `""` when there is none. For
run-after tasks the value is `""` and the meaning comes from `timePeriod` "Run After". The list's
old `"Runs After #1:00"` artefact is no longer returned, but the sort must not break on any text.
`nextRun` can also be **absent** when the info read failed (`unavailable`).

**Decision.** `orderByNextRun(items)` is a pure, stable function that never changes a value. The
buckets are:
1. values matching `^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}` → ascending text order, which is
   chronological for this format;
2. any other non-empty text → ascending text order;
3. `""` → "none reported";
4. absent (unavailable).

Ties break by `name`, then `taskId`. The footer says "sorted by next run". The function is
unit-tested on the R-5 values plus an absent value.

## R-4 — Showing `PARAM_*` errors on the field

**Current code.** `Finding = { stepId, code, message }` (`src/lib/flow/report.ts`). Spec 005
(`contracts/api-delta.md`) adds `PARAM_REQUIRED`, `PARAM_TYPE_MISMATCH`, `PARAM_OUT_OF_RANGE` and
`PARAM_UNKNOWN` in the **same shape**. The parameter name appears only inside the message text:
"Step '02' (purge-task-history): parameter 'keepDays' is required".

**Decision.** No text parsing.
- A finding is shown on a field **only** when it carries a structured `parameter` value equal to
  that field's declared `name`.
- Otherwise every finding of the step is shown **at step level**, at the top of the inspector's
  PARAMETERS section, verbatim. The status bar counts it as today.
- `PARAM_UNKNOWN` names a key the schema does not declare, so it is always shown at step level.

**Backend dependency (to register in spec 005, not worked around here).** The findings with codes
`PARAM_REQUIRED`, `PARAM_TYPE_MISMATCH` and `PARAM_OUT_OF_RANGE` need an additive
`"parameter": "<name>"` field. Until 005 provides it, SC-005's "100% on their field" cannot be met.
The step-level display is the honest fallback, and the frontend picks the field display up
automatically once the field exists (see plan §Spec deviations, and a unit test with and without
the field).

## R-5 — Session: the 60 s token for catalog calls and suspend

**Current code.** `src/lib/api/session.svelte.ts` renews proactively at `lifetime − 15 s` (FR-034 of
spec 002). Every call goes through `request()` in `src/lib/api/client.ts`, which uses
`session.authorization()`. A 401 calls `session.expire()`, and `+page.svelte` shows the `SignIn`
overlay. The token lives only in memory.

**Decision.** The catalog uses the same `request()`, and inherits both the proactive renewal and
the 401 behaviour. The catalog screen renders the same expired overlay as the canvas.
- A suspend or resume that returns 401 is **not retried automatically** after sign-in. The operator
  presses again, because a state change is never replayed on their behalf.
- A read is simply re-issued on the next refresh.
- One list read takes about 0.4 s for 150 tasks (spec 006 R-2), which is far inside one token.

## R-6 — Spec 005/006 availability on the container

**Checked in the repository (2026-09-26).**
- `sentai.catalog.TaskService` still returns the old shape (`className`, `state`, the old suspend
  path).
- `sentai.registry.StepType` still has 7 entries, with no `label`, `executor` or `parameters`.

Neither spec is implemented yet.

**Decision.**
- **Unit tests** use fixtures copied from the two `contracts/api-delta.md` files (real values, such
  as task 4 and task 1000 from 006). They are the source of truth for shapes until the specs land.
- **End-to-end tests run only against the container** with the spec delivered:
  - Part A e2e (US-1…US-4) depends on spec 006 tasks T001–T005;
  - Part B e2e (US-5, US-6) depends on spec 005 tasks 1–5 and on the Part B prototype.
- These dependencies are declared per task (Constitution V). No e2e test is written against a
  shape the container does not serve.

## Other findings (code audit against FR-019, FR-013 and FR-018)

| Where | What it does locally today | 007 decision |
|---|---|---|
| `palette/Palette.svelte` `ORDER` | Groups by the API's `category` in a fixed display order | Keep; display order only. Add the *Custom* group, keyed on the API's `executor === 'in-process'`, plus legacy `custom` (Clarifications Q1) |
| `flow/document.ts` `stepLabel(type)` | Derives a label from the type string | Use the API's `label` when present, falling back to the derived text for a catalog without `label` (pre-005). Presentation only |
| `inspector/Inspector.svelte` `PARAMETER_FIELDS` and `document.ts` `DEFAULT_PARAMETERS` | Hard-coded schema and default for `purge-audit-records` (`daysToKeep`, 30) | **Declared types**: replaced by the API schema (FR-013); no local default is written (R-7). **`purge-audit-records`** (platform-api, unavailable, no schema in 005's catalog) keeps the 002 behaviour, so e2e `us1`/`us2` stay green. **Dependency**: when 005's catalog declares that type's parameters, delete the local table |
| `inspector/Inspector.svelte` custom-class `<input>` | Operator types a class name | FR-018: read-only text plus "not supported". The input is removed |
| `inspector/Inspector.svelte` `consequence()` | Per-type consequence copy for destructive steps | Unchanged presentation copy (spec 002). Declared destructive types use the generic sentence |
| `canvas/StepNode.svelte`, `document.ts summarize` | `destructive` from the registry entry | Already API-driven; also valid for declared types (FR-017) |
| `shell/DispatchDialog.svelte` + `api.dispatch` | Sends `confirmations: []`, with **no typed-confirmation input** | **Gap.** Spec 002 FR-013 and spec 007 FR-017 need the third signal. With 005, `purge-task-history` becomes available and destructive, and dispatch would answer 428 with no way to confirm. Add one typed field per destructive step, with the backend as the judge: it compares against the database directory, or the namespace, per the openapi description. On 428, show the Problem's `detail` verbatim |
| `api/client.ts` `ApiError.problem` | Keeps `status/title/detail` only | Add `platformStatus` and `platformInfo`, passed through untouched (Constitution III). Refusals then show the platform's status object, and "no reason given" when it is empty |

## R-7 — Declared defaults

Spec 005's data model says the default is "applied when the key is absent", and the backend owns
that. Spec 007 US-5.5 says unchanged defaults are "sent as the schema's default".

**Decision.** The form shows the default as the field's placeholder, marked *default*. It **omits
the key** while the operator has not changed it, and removing the value removes the key again.
- The backend then applies the one authoritative default.
- The flow document never holds a copied default that could drift from the catalog.
- The stored parameters are exactly what the operator set (FR-016).

Recorded as a spec deviation for US-5.5.
