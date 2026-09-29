# Frontend Search Contract — 011

How the ranking becomes a palette. Pure module contract: `frontend/src/lib/palette/search.ts` has no
`fetch`, no DOM and no state, so every rule below is a vitest case in `search.test.ts`. The component
holds only the input, a debounce timer and the latest outcome.

Spec: [spec.md](../spec.md) · Plan: [plan.md](../plan.md) · Wire shapes:
[api-delta.md](api-delta.md)

---

## Why two filters, not one

Today's palette filters **synchronously and locally** on every keystroke (today's `className`
substring rule included). That behaviour is preserved exactly and is not replaced (FR-003, FR-005).
The ranking arrives from the server 150 ms later and *prepends a suggestion group* to the list the
local filter already produced (FR-002).

Two consequences that are part of the contract:

- **Nothing ever waits on the provider.** Typing is instant because the local filter needs no
  network. If the provider is unconfigured, unreachable, slow or incompatible, the palette looks
  exactly as it does today — the suggestion group simply never appears (FR-022–FR-026).
- **The existing `className` substring rule stays.** It is a local substring match on data the
  browser already has, not a capability the corpus can reach, so it is not in tension with the
  closed-set rule. The *semantic* path never reads a class name (FR-018, R-009). The implementer
  should extract it, not delete it.

---

## Pure module API

```ts
// lib/palette/search.ts
export type UnavailableReason =
	| 'not-configured' | 'unreachable' | 'slow' | 'incompatible' | 'error';

export type StepSearchOutcome =
	| { available: true; matches: { type: string; score: number }[] }
	| { available: false; reason: UnavailableReason };

/** Today's substring rule, extracted verbatim from Palette.svelte. */
export function filterLocally(registry: StepTypeInfo[], q: string): StepTypeInfo[];

/** Ranked identifiers → catalog entries, best first. Unknown identifiers are dropped. */
export function suggestionsFor(registry: StepTypeInfo[], outcome: StepSearchOutcome): StepTypeInfo[];

/** Today's grouped palette, with a leading `suggested` group and no duplicated entry. */
export function paletteSections(
	registry: StepTypeInfo[],
	q: string,
	outcome: StepSearchOutcome | null
): PaletteSection[];
```

`PaletteSection` widens today's `PaletteGroup`:

```ts
export type PaletteSection = { id: StepCategory | 'suggested'; types: StepTypeInfo[] };
```

`paletteGroups()` in `lib/flow/document.ts` is **unchanged**; the suggestion group is added by this
module on top of it. `StepCategory` itself is not widened — a *section* is the widened thing, so
grouping logic that switches on a category is untouched.

---

## Behaviour, as test cases

| # | Input | `paletteSections` |
|---|---|---|
| 1 | `q = ""`, `outcome = null` | exactly today's `paletteGroups(registry)`, no suggested group (FR-005) |
| 2 | `q = "integr"`, `outcome = null` | today's substring groups, no suggested group |
| 3 | `q = "rotate the journal"`, `available` with `[switch-journal .79]` | `{suggested: [switch-journal]}` first, then the same groups **minus** `switch-journal` (FR-003) |
| 4 | same, but the outcome arrived for an older keystroke | suggested group absent — the component never hands a stale outcome in; see below (FR-002) |
| 5 | `available: true, matches: []` | no suggested group; today's local groups (FR-008) |
| 6 | `available: false, reason: "unreachable"` | no suggested group; today's local groups (FR-023) |
| 7 | `matches: [{type: "not-a-real-type", score: 0.99}]` | **no suggested group** — the identifier matches nothing in `registry` and is dropped (R-011, FR-013) |
| 8 | the legacy `custom` entry ranks first | it appears in `suggested` and **still renders un-addable** — `available: false`, `disabled`, not draggable (FR-021) |
| 9 | two entries with the same score | order as the API returned it; the view model never re-sorts |

Rules that hold in every case:

- **Every element of every section is an element of the `registry` argument.** The view model cannot
  introduce a capability, because it can only reorder or drop what it was given (R-011).
- **No entry appears twice.** A suggested entry is removed from its category group.
- **The view model never re-scores and never applies a floor.** The floor is the API's; a match
  arriving here is already above 0.20.
- **`unavailable` and `[]` are the same shape on screen.** The reason is not a separate render path,
  so it cannot become a toast or an error state (R-007).

---

## Component contract (`Palette.svelte`)

The component's only new responsibilities are input timing and holding the outcome. The filtering
logic leaves the component.

```ts
let query = $state('');
let outcome = $state<StepSearchOutcome | null>(null);
let pending = 0;                       // debounce timer id
let sequence = createSequence();        // lib/catalog/catalog.ts, already exists

function oninput() {
	clearTimeout(pending);
	const q = query.trim();
	if (!q) { outcome = null; return; }        // never ask with an empty q (FR-005)
	pending = setTimeout(async () => {
		const ticket = sequence.next();
		const result = await searchStepTypes(q);
		if (sequence.isLatest(ticket)) {
			outcome = result.ok ? result.value : { available: false, reason: 'unreachable' };
		}
	}, 150);
}
```

- **150 ms** debounce (R-012). The `className`/type/label local filter still applies on every
  keystroke, unchanged, so the list is useful before any request is made.
- **Latest-wins** via the existing `createSequence()`; a slow response for an old keystroke is
  discarded, never applied (FR-002). There is no abort of an in-flight request — a superseded
  response is simply not used.
- **A failed request never reaches the palette as a failure.** `client.ts` returns
  `ApiResult`, and the component collapses `!ok` to `{available: false, reason: 'unreachable'}` on
  the line above — so a transport failure, a 5xx and an unparseable body are all indistinguishable
  from the operator's point of view, and none of them can masquerade as "no results"
  (FR-023, FR-025).
- `aria-labelledby`/`id` for the suggested group's heading follow the existing
  `cat-${group.category}` pattern, so it becomes `cat-suggested`.

## Rendering and tokens

The existing heading markup interpolates the section id twice:

```svelte
<span class="swatch" style:background={`var(--category-${group.category})`}></span>
{group.category.toUpperCase()}
```

so a `suggested` section reads `SUGGESTED` with `--category-suggested`. That token **does not exist
yet**: add a `suggested` entry to `specs/002-canvas-ui/contracts/tokens.json` and run
`npm run generate:tokens` (the generated `lib/design/tokens.{css,ts}` are gitignored — never hand-edit
them). An entry in the suggested group also carries `data-suggested="true"`, so an e2e test can assert
rank order without reading scores. `data-step-type`, `disabled`, `draggable` and the unavailable
styling are unchanged for every entry, suggested or not.

No description, tooltip or score is rendered (R-011). The suggestion group is the entire visible
change.

---

## Wire mapping (`api/client.ts`, `api/wire.ts`)

- `client.searchStepTypes(q: string): Promise<ApiResult<StepSearchOutcome>>` — calls
  `GET /catalog/step-types/search?q=` through the existing `request()`/`map()` helpers, so it returns
  the codebase's `ApiResult<T>` like every other client method rather than a bare value. It never
  throws into the component.
- The **component** is what turns `!result.ok` into a value:
  `outcome = result.ok ? result.value : { available: false, reason: 'unreachable' }`. A transport
  failure, a 5xx and a malformed body therefore all reach the palette as the same degraded state, and
  none of them can leave the outcome `undefined` in a way that could look like "no results"
  (FR-023, FR-025).
- `wire.fromWireStepSearch(body: unknown): StepSearchOutcome` — **validating**, in the style of the
  other `fromWire*` functions: an unrecognised `reason` becomes `reason: 'error'`, a malformed body
  becomes `{available: false, reason: 'error'}`. A malformed server answer degrades the palette; it
  never throws into the component (FR-023, Constitution IV).
- `wire.ts` gains **no `description` field on `StepTypeInfo`** (R-011). The catalog response may
  carry it; the frontend does not model it.
- A `400` from the API is not expected in normal operation (the component never sends an empty `q`).
  It arrives as `ApiResult` `!ok` and is collapsed to `unavailable` like any other failure, because a
  palette that shows today's list is always a correct answer.
