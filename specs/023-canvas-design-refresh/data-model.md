# Data Model: Canvas Design Refresh

Nothing new is stored. §1 is the only change to an API response; §2–§8 are canvas view models in
pure modules (`lib/<domain>/*.ts`), each built from API values and never filling in a value the
API did not send (spec 007 `Value<T>`: `value | absent | unavailable`).

## 1. Catalog page (API, additive) — `GET /catalog/tasks`

```text
CatalogPage {
  total:   number          // unchanged
  matched: number          // unchanged
  items:   CatalogTask[]   // unchanged, plus `description` below
  counts: {                // NEW — over every task the list read enumerated, before filters
    suspended:    number   // suspended = true
    destructive:  number   // destructive = true
    unclassified: number   // destructiveUnknown = true
  }
}
CatalogTask.description?: string   // NEW — the platform's `Description`, verbatim; absent when the
                                   // single read failed or the platform sent none
```

Filter: `unclassifiedOnly ∈ {0,1,true,false}` (default `0`) keeps tasks with
`destructiveUnknown = true`; combines with `filter`, `q`, `namespace`, `destructiveOnly` by AND.
A task whose info read failed (`suspended` absent) is counted in none of `suspended`.

## 2. FlowBarState (`lib/flow/flowbar.ts`)

```text
FlowBarState {
  name:      string
  saveState: { kind: "unsaved" } | { kind: "saved"; revision: number; savedAt: "HH:MM"; edited: boolean }
  actions:   Record<"validate" | "run" | "schedule", { enabled: boolean; reason: string | null }>
}
```

Rules (FR-006): no steps → all three disabled, reason `"add a step to enable running"`;
`scheduleBlocked` (validation failed) → run and schedule disabled, reason
`"fix the validation errors in the status bar"`; validating → validate disabled, reason `null`
(the button says "Validating…"). One reason is shown for the group when they share it.

## 3. CanvasStatus (`lib/flow/document.ts`)

Already shipped: the status bar shows `formatSummary` and `snap 8 px · zoom NN%`. This spec only
exports `SNAP = 8` so the canvas grid and the status bar share one value.

## 4. PaletteView (`lib/palette/search.ts`)

```text
PaletteGroupView { id; total: number; shown: StepTypeInfo[]; hidden: number }
PaletteView      { groups: PaletteGroupView[]; unsupported: StepTypeInfo[] }
collapseSections(sections: PaletteSection[], { limit = 3, expanded, searching }): PaletteView
```

Over `paletteSections` (so the spec 011 *suggested* group is a section like any other).
`limit` = 3 available entries per category; `unsupported` = every `available = false` entry;
categories left with no available entry are dropped. While searching nothing is restructured:
the sections come back as they are, with unsupported entries inline as before.

## 5. CatalogSummary and TaskDetail additions (`lib/catalog/catalog.ts`)

```text
CatalogSummary { total; matched; counts: Value<{suspended; destructive; unclassified}>; readAt: Date }
DestructiveReason =
  | { kind: "stepType"; text: string }               // consequence() of the matched step type
  | { kind: "flow"; flowId: string }                 // SentaiTask flow task, destructive by a step
  | null                                             // not destructive
OutsideMark = boolean                                // true ⇔ origin absent ("created outside SentaiTask")
AddToFlow   = { ok: true; step: StepDraft } | { ok: false; reason: string }
StepDraft   { type: string; namespace?: string; runAsUser?: string }   // defaults from the type
SuspendToggle {
  checked: boolean | null                            // null when `suspended` is unavailable → disabled
  confirm: { title: string; body: string; action: "suspend" | "resume" } // body adds the flow
                                                                       // warning when origin present
}
```

`counts` is `unavailable` when an older API omits it (then the filter shows no numbers, never 0).
`readAt` drives "updated N s ago".

## 6. Overview attention (`lib/overview/attention.ts`, extends spec 019)

Spec 019's model (`lib/overview/overview.ts`: `AreaCardView`, `CardState` = `ok | refused |
unreachable`) is read, never redefined.

```text
OverviewAttention {
  attention: Band<AttentionItem[]>
  next24h:   Band<ScheduleStrip>
  unread:    UnreadReading[]          // FR-029 — from 019's card states + the two bands
}
Band<T> = { kind: "loading" } | { kind: "ready"; value: T } | { kind: "unread"; reason: UnreadReason }
UnreadReading { what: string; reason: UnreadReason }      // what = area label or "Task catalog"
UnreadReason  =
  | { kind: "refused"; httpStatus: number; text: string } // platform's message verbatim
  | { kind: "unreachable"; text: string }
AttentionItem { id: "backup" | "suspended" | "unclassified"; text: string; detail: string;
                action: { label: string; to: ScreenLink } | { label: string; disabledReason: string } }
ScheduleStrip { slots: { start: "HH:MM"; count: number; destructive: number; suspended: number }[];
                total: number; destructive: number; suspended: number;
                flowScheduled: boolean; nextAfter: string | null }
```

Rules:
- An attention item exists only from a successful read: backup needs the `activity` card `ok`;
  suspended and unclassified need the catalog read. `ready([])` ("Nothing needs attention") only
  when both reads succeeded; otherwise the band shows the items it could read plus, in place, what
  it could not read.
- Next 24 hours is `unread` when the catalog read failed — never `ready` with no slots.
- `unread` has exactly one entry per `refused`/`unreachable` card and per `unread` band, text
  verbatim; empty list → the summary is hidden.
- Backup item: `lastBackup` empty or "Never" (as the platform reports) → item; its action is
  disabled with "no backup step type is declared" while the registry has none in category `backup`.

## 7. Screen (`lib/shell/screen.ts`)

Unchanged — spec 019 already has `'overview'` and the default resolution (research R-5).

## 8. State transitions — Suspend toggle

```text
idle --toggle--> confirming --cancel--> idle
                 confirming --confirm--> pending --ok--> idle (re-read item + list)
                                         pending --fail--> error(message verbatim) (toggle unchanged)
error --toggle--> confirming
```

`pending`/`ok`/`fail` are the existing `reduceSuspendAction`; `confirming` is new and sends nothing.
