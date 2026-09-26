# Data Model — 007 Canvas Management Screens (frontend view models)

No persistence and no backend change. The types below are built from API responses in the adapter
module (`src/lib/api/wire.ts`), which is the only module that knows wire shapes. Components receive
only these types.

**The absence rule:** a field the API did not send stays **absent**, never `""` or `false`. Absent,
empty and present are rendered differently.

## CatalogTaskView (spec 006 item)

| Field | Type | From (wire) | Rendering |
|---|---|---|---|
| `taskId` | number | `taskId` | Shown as `ID <n>` in the detail |
| `name` | string | `name` | |
| `namespace` | string | `namespace` | Mono |
| `className` | `Value<string>` | `class` | Mono. The old `className` key is never read (it was the list's `Type`) |
| `runAsUser` | `Value<string>` | `runAsUser` | Mono |
| `timePeriod` | `Value<string>` | `timePeriod` | Detail only, verbatim ("Weekly", "Run After", …) |
| `nextRun` | `Value<string>` | `nextRun` | Verbatim; `""` → "—" with the title "none reported" |
| `lastStarted` | `Value<string>` | `lastStarted` | Detail only |
| `lastFinished` | `Value<string>` | `lastFinished` | Column **LAST RUN** |
| `status` | `Value<string>` | `status` | `"1"` → "OK (1)" (spec edge case). Anything else is shown verbatim, full text in the detail |
| `lastError` | `Value<string>` | `lastError` | Verbatim, including "Success". Detail only |
| `suspended` | `Value<boolean>` | `suspended` | A "SUSPENDED" mark (text plus glyph, never colour alone) |
| `destructive` | `'yes' \| 'no' \| 'unknown'` | `destructive` + `destructiveUnknown` | `yes` → DESTRUCTIVE seal. `unknown` → "destructiveness unknown" mark. `no` → nothing |
| `origin` | `{ flowId, stepId, flowExists } \| absent` | `origin` | "flow 1 · step 01". A link to `?flow=1` when `flowExists`, otherwise "flow not found" |
| `recentRuns` | `RecentRun[] \| absent` | `recentRuns` (item read only) | Absent → no section. `[]` → "No runs reported". Otherwise a list |

`Value<T>` = `{ kind: 'value'; value: T } | { kind: 'unavailable'; reason: UnavailableReason } |
{ kind: 'absent' }`.

- A field listed in `unavailable[i].fields` becomes `unavailable`, with that entry's `httpStatus`
  and `platformStatus`.
- A field that is simply missing, and not listed there, is `absent`, rendered as "—" with the
  title "not returned".
- `UnavailableReason = { read: 'single'|'info'|'history'; httpStatus: number; text: string }`.
  `text` is the platform's `errors[].error` values joined by "; ", or **"no reason given"** when
  there are none. The 2026.2 403 has `{"errors":[],"summary":""}`.

**RecentRun**: `{ start: LastStart, completed: Completed, status: Status, result: Result, user:
Username, loggedAt: LogDatetime }`. Every value is a verbatim string, and no duration is computed
(spec 006 R-4).

Deprecated wire aliases (`isDestructive`, `lastRun`) are **not read**. The adapter uses the new
names only.

## CatalogPage (list response)

`{ total: number; matched: number; items: CatalogTaskView[]; readAt: Date }`.

- The header reads "`matched` of `total` tasks".
- `readAt` feeds "updated N s ago". This is a local clock label and involves no polling.
- Items are displayed in `orderByNextRun(items)` order (research R-3).

**CatalogFilters**: `{ q: string; namespace: string | 'all'; state: 'all'|'scheduled'|'suspended';
destructiveOnly: boolean }` → query `q`, `namespace` (omitted for *all*), `filter`, and
`destructiveOnly=1|0`. **NamespaceOptions**: the distinct `namespace` values of the latest
unfiltered page (research R-2).

## CatalogScreen state

```
idle ─open─▶ loading ─200─▶ ready(page, selected?) ─filter/refresh─▶ loading …
                     └─4xx/5xx─▶ refused(status, reason)       (FR-010: no rows)
ready ─select task─▶ ready + detail(loading → task | notFound(reason) | refused(reason))
detail ─Suspend/Resume─▶ acting (button disabled, FR-008)
        ─200─────▶ detail(task from body) + list re-read           (FR-011)
        ─4xx/502─▶ detail + actionError(status, reason) + item re-read + list re-read
```

- **Out-of-order responses**: each list request carries a sequence number, and only the latest
  applies.
- **Search**: debounced (300 ms), so typing does not fire one platform read per key.

## StepTypeInfo (extended; spec 005 catalog entry)

The existing fields stay (`type`, `className`, `category`, `destructive`, `pausable`,
`available`). New fields:

| Field | Type | From | Notes |
|---|---|---|---|
| `label` | string \| absent | `label` | Palette and node title. Absent (pre-005) → the existing `stepLabel(type)` |
| `executor` | `'platform-api' \| 'in-process' \| absent` | `executor` | `in-process` puts the type in the *Custom* group (Clarifications Q1) |
| `parameters` | `ParameterSpec[] \| absent` | `parameters` | Absent → no declared schema (legacy 002 behaviour for `purge-audit-records`). `[]` → the "takes no parameters" variant |

**ParameterSpec**: `{ name; type: 'string'|'integer'|'number'|'boolean'; required: boolean;
default?: unknown; min?: number; max?: number; description: string }`.
- The wire `property` is **not** carried: it is a backend concern.
- An entry with an unknown `type` is shown as a read-only "unsupported parameter type" row. It is
  never turned into a free-text input.

## ParameterField (inspector form row)

Derived from `ParameterSpec`, the step's `parameters[name]` and the report's findings.

| Field | Source |
|---|---|
| `id` | `insp-param-<name>`, with a real `<label for>` (002 FR-016) |
| `control` | `string` → text; `integer` → number with `step=1`; `number` → number with `min`/`max`; `boolean` → checkbox |
| `value` | `parameters[name]` when present. Otherwise empty with placeholder `default: <default>` (research R-7) |
| `required` | Mark "required" (text, not colour) |
| `bounds` | "min–max" hint when declared |
| `help` | `description` verbatim |
| `error` | Findings of this step whose `parameter === name`. This needs spec 005's additive `parameter` field (research R-4) |

**Step-level findings**: every finding of the step that has no matching `parameter`, listed
verbatim at the top of PARAMETERS.

**Writes**:

| Control | Input | Stored |
|---|---|---|
| text | any | the string |
| integer | a whole number | `Number` |
| number | a finite number | `Number` |
| checkbox | checked / unchecked | boolean |
| any | cleared | the key is deleted |

The frontend never checks `min`, `max` or `required`. The API's validation does (FR-015). The
input attributes only stop characters the control cannot hold.

## Legacy `custom` step

The step's `customClass` is shown as read-only text next to "Not supported: steps run only declared
types (spec 005)". There is no input, and `setText('customClass')` is removed. The palette entry
stays in the *Custom* group, disabled, because `available: false` comes from the API.

## DispatchConfirmation (typed confirmation, third destructive signal)

For each step whose registry entry is `destructive: true`, the dispatch dialog shows one required
text input, labelled with the step and "type the database directory (or namespace) to confirm".
The value is sent as `confirmations: [{ stepId, typedName }]`.

The backend decides whether it matches (`WaveDispatcher.CheckConfirmations`). A 428 answer shows
its `detail` verbatim and keeps the dialog open.
