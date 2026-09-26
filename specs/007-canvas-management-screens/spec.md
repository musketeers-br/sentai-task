# Feature Specification: Canvas Management Screens (frontend)

**Feature Branch**: `007-canvas-management-screens`

**Created**: 2026-09-26

**Status**: Draft

**Input**: Add the management screens the canvas is missing: a **Task catalog** screen over the
platform's Task Manager (spec 006) and **declared custom steps** in the flow editor (spec 005).
Frontend only; every value comes from the product's API, and no business rule is re-implemented in
the browser.

## Context and Problem

The contest theme is "Build Your Own Management Portal". The canvas already composes, validates,
schedules and runs flows (spec 002). It does not yet offer management screens:

- **The platform's Task Manager is invisible.** On 2026-09-25 a flow scheduled from the canvas
  created three tasks (`SentaiTask: 1#01..03`) that would fire at midnight and fail, and the
  operator could only see them in the platform's own portal. Spec 006 makes the catalog API tell the
  truth: real class, run-as user, status, suspended, SentaiTask origin, and a proven
  suspend/resume. Nothing shows it yet.
- **Declared custom steps cannot be composed.** Spec 005 adds declared step types with a parameter
  schema. The palette does not group them, the inspector has no form for their parameters, and the
  legacy free-text `custom` step still offers a class-name field.

A prototype exists for the catalog (`design/Catalog.dc.html`). There is none for the custom-step
additions, so this spec also lists what that prototype must show (see §Design brief).

## Objective

An operator can, from the canvas:

- open a **Task catalog** screen and find any scheduled task;
- see what each task really is and how it last went;
- recognise the tasks SentaiTask created and jump to their flow;
- suspend or resume a task.

The operator can also compose flows with **declared step types**, filling in their parameters in a
form built from the declared schema and seeing validation errors on the field they concern.

Every value shown is one the product's API returned. When the API does not provide a value, the
screen does not show one.

## Scope

### In scope

1. **Navigation**: the top bar gains *Flows* and *Task catalog*.
2. **Task catalog list**:
   - search, a namespace filter, and *All / Scheduled / Suspended / Destructive only*;
   - the count "N of M tasks";
   - sorted by next run;
   - only the columns the spec 006 API supports.
3. **Task detail**: namespace, class, run-as user, next and last run, the platform's status and
   last error, and recent runs when the API returns them.
4. **Suspend / Resume** per task, following the contract spec 006 proved on the platform.
5. **SentaiTask tasks marked**, with a link that opens their flow on the canvas.
6. **Palette "Custom" group** listing the declared step types from the step-type catalog.
7. **Inspector parameter form** generated from a declared type's parameter schema, with
   validation errors shown on the field.
8. **Destructive declared types** carry the same three signals as existing destructive steps.
9. **Legacy `custom` step**: shown as not supported, with its stored class name read-only and
   never editable.

### Out of scope

- Any backend change (specs 005 and 006 own the API).
- *New task*, editing or deleting a task, "run now", or changing a task's schedule.
- The *History* and *Work Queue Manager* screens shown in the prototype top bar. They remain for a
  later phase; their entries are not shown.
- Showing a declared step's report (`result`) or who ran it (`executedAs`) on the live-run screen.
  The run read carries both (spec 005), but displaying them is a later phase.
- Prototype fields the API does not provide: WQM category, privilege, current run GUID, per-run
  duration, and the invented job states (queued / running / paused / cancelled) of the catalog rows.

## Clarifications

### Session 2026-09-26

- **Q1 — Declared types that belong to an existing category** (`switch-journal` is `journal` and
  `purge-task-history` is `purge`, but both run in-process per spec 005): which palette group
  lists them?
  → **A**: the *Custom* group lists **every declared type** (executor "in-process") and nothing
  else. Such a node keeps its category's left-border colour on the canvas, so where it sits in the
  palette does not change what it looks like in a flow. The legacy `custom` type remains in the
  *Custom* group as not supported (FR-018). Types that call the platform's management API
  (`integrity-check` and the unavailable ones) stay in their category groups.

  *Default applied by the spec author: grouping by execution kind matches the user's wording
  "tipos declarados". Revisit at `/speckit-clarify` if needed.*

### Session 2026-09-26 (plan)

- The plan's four deviations are applied below; see [plan.md §Spec deviations](plan.md#spec-deviations-to-reflect-at-speckit-tasks).
- Parameter errors go on the field named by the finding's structured `parameter` (spec 005 T008,
  BD-1); findings without it stay at step level, verbatim; message text is never parsed
  ([research.md](research.md) R-4).
- An unchanged parameter is not stored; its declared default is the field's placeholder (R-7).
- The typed-confirmation input in the dispatch dialog is new (plan D-7).
- Screens are addressable through the page's query string (R-1).
- Local decisions found in the current code: [research.md §Other findings](research.md#other-findings-code-audit-against-fr-019-fr-013-and-fr-018) (FR-019 audit).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — See the platform's scheduled tasks (Priority: P1)

The operator opens *Task catalog* from the top bar and sees every task the platform reports, sorted
by next run, with name, namespace, class, next run, last finished, the platform's status and the
run-as user. Each task can be opened to see its detail.

**Why this priority**: this is the management-portal screen, and every other catalog action starts
here.

**Independent Test**: with the product running against the dev instance, open *Task catalog*. The
number of rows equals the API's `total`, and for a sample of tasks every visible value equals the
API's value for that task.

**Acceptance Scenarios**:

1. **Given** the operator is on the flow canvas, **When** they choose *Task catalog* in the top bar,
   **Then** the catalog screen opens. **When** they choose *Flows*, **Then** they return to the
   canvas with the flow they had open.
2. **Given** the catalog is open, **Then** rows are sorted by next run, earliest first. Tasks with no
   next run come last, and the order states "sorted by next run".
3. **Given** the built-in *Integrity Check* task, **When** it is shown, **Then** its class is the
   platform's task class, and its status and last error are shown exactly as the API returns them.
   A suspended task is visibly marked suspended.
4. **Given** a task whose last run failed, **When** its detail is opened, **Then** the platform's
   error text is shown in full and verbatim.
5. **Given** a task the API marks destructive, **Then** its row and detail carry the destructive
   seal. A task marked "destructiveness unknown" shows that it is unknown, not "safe".
6. **Given** the API reports a value as unavailable for a task, **Then** that value is shown as
   unavailable together with the platform's reason (or "no reason given"), and nothing is filled
   in.
7. **Given** the item read returns recent runs, **Then** the detail lists them with start,
   completion and outcome as returned. When the API returns none, the section says so. When the API
   omits the field, the section is not shown.

---

### User Story 2 — Recognise what SentaiTask scheduled and open its flow (Priority: P1)

Among the platform's tasks, the operator sees which ones SentaiTask created. From one of them they
open the flow and step it belongs to.

**Why this priority**: this is the real case of 2026-09-25. Tasks created by the product that would
fail were invisible from the product.

**Independent Test**: schedule a three-step flow, open *Task catalog*, and filter by the flow's
tasks. Exactly three rows are marked as SentaiTask tasks, and their link opens that flow on the
canvas.

**Acceptance Scenarios**:

1. **Given** tasks `SentaiTask: 1#01..03`, **Then** each row carries a SentaiTask mark with
   "flow 1 · step 01" (and so on) taken from the API's origin.
2. **Given** a marked task whose flow exists, **When** the operator follows its link, **Then** the
   canvas opens that flow.
3. **Given** a marked task whose flow no longer exists, **Then** the mark says the flow was not
   found, and there is no link.
4. **Given** a task that is not marked in the API, **Then** no SentaiTask mark is shown, whatever
   its name.

---

### User Story 3 — Filter and search the catalog (Priority: P2)

The operator narrows the list by text, namespace, *All / Scheduled / Suspended* and *Destructive
only*, and the header shows "N of M tasks".

**Why this priority**: this is the prototype's toolbar. With about 150 tasks, finding one needs it.

**Independent Test**: each filter, alone and combined, shows exactly the tasks the API returns for
those filters, and "N of M" equals the API's `matched` and `total`.

**Acceptance Scenarios**:

1. **Given** a search text, **When** it is typed, **Then** the list shows the API's result for that
   text, which matches on name and class and ignores case.
2. **Given** the namespace filter, **Then** its options are the namespaces present among the
   platform's tasks, plus *all*.
3. **Given** *Suspended*, **Then** only tasks the API reports suspended are shown. **Given**
   *Scheduled*, **Then** only tasks it reports as not suspended are shown.
4. **Given** *Destructive only*, **Then** only tasks marked destructive are shown. Tasks with unknown
   destructiveness are not included.
5. **Given** any combination of filters, **Then** the header reads "N of M tasks" with the API's
   counts.

---

### User Story 4 — Suspend and resume a task (Priority: P2)

From a task's detail, the operator suspends it (for example, one of the three that would fail at
midnight) or resumes a suspended one. The screen shows the platform's state after the call.

**Why this priority**: this is the only control the catalog offers, and spec 006 proved it on the
platform.

**Independent Test**: on the dev instance, suspend a temporary task from its detail. The detail and
the row show it suspended, and a fresh read agrees. Resume it, and both show it active.

**Acceptance Scenarios**:

1. **Given** a task that is not suspended, **Then** its detail offers *Suspend*. **Given** a
   suspended task, **Then** it offers *Resume*. Never both.
2. **Given** the operator suspends or resumes, **When** the API confirms, **Then** the row and
   detail show the state the API returned after the call. The next run is shown as returned: a
   suspended task keeps it (spec 006 R-3).
3. **Given** the platform refuses (for example, insufficient privilege or unknown task), **Then**
   the refusal is shown with the HTTP status and the platform's text verbatim, or "no reason given"
   when the platform gave none. The task's shown state is unchanged.
4. **Given** the API answers that the platform accepted the call but did not apply it, **Then** that
   message is shown as an error, and the shown state is the one the API reported.
5. **Given** a call is in progress, **Then** the button is disabled until the answer arrives, so it
   cannot be pressed twice.

---

### User Story 5 — Compose flows with declared custom steps (Priority: P1)

The operator finds declared step types in a *Custom* palette group, drops one on the canvas, and
fills its parameters in an inspector form built from the type's declared schema. Validation errors
appear on the field they concern.

**Why this priority**: declared steps are spec 005's capability, and without this screen they cannot
be composed.

**Independent Test**: with spec 005's catalog loaded, drag a declared type with parameters onto the
canvas. The inspector shows one field per declared parameter, with its label, type, required mark,
default and description. Enter an out-of-range value and validate: the error appears on that
field.

**Acceptance Scenarios**:

1. **Given** the step-type catalog lists declared types, **Then** the palette shows a *Custom* group
   containing exactly those types, each with its label and class. Unavailable ones are shown
   disabled with "not supported", as today.
2. **Given** a declared type with a parameter schema, **When** its node is selected, **Then** the
   inspector shows a parameter form with one field per parameter, in declared order. Each field has
   a real label, an input suited to its type (text, whole number, number, on/off), a required mark
   when required, the declared default shown as the field's placeholder when the value is absent,
   and the declared description as help text.
3. **Given** a declared type with no parameters, **Then** the form says the type takes no
   parameters.
4. **Given** validation returns parameter errors (missing, wrong type, out of range, unknown), **Then**
   each error that carries a structured `parameter` is shown on that field with the API's message
   verbatim; an error without `parameter` is shown at step level, verbatim. The message text is
   never parsed. The status bar counts it like any other validation error.
5. **Given** the operator changes a parameter, **Then** the value is saved with the flow as the
   step's parameters. An unchanged parameter is not stored: the key is omitted and the declared
   default is shown as the field's placeholder; the backend applies the default.

---

### User Story 6 — Destructive declared types and the legacy `custom` step (Priority: P2)

A declared type that the catalog marks destructive looks and behaves like every other destructive
step. The legacy free-text `custom` step can no longer be edited as a class name.

**Why this priority**: safety. Destructive signals must not depend on how a type is implemented,
and the legacy field must not suggest that typed text selects code (spec 005).

**Independent Test**: drop the declared destructive type (`purge-task-history`) and confirm the three
signals. Load a saved flow with a legacy `custom` step and confirm it shows as not supported,
with no editable class field.

**Acceptance Scenarios**:

1. **Given** a declared type marked destructive, **When** it is on the canvas, **Then** its node
   carries the hazard band, the DESTRUCTIVE seal, and requires typed confirmation before dispatch.
   These are the same three signals as existing destructive steps.
2. **Given** a saved flow containing a legacy `custom` step, **When** it is opened, **Then** the node
   is shown as not supported. The inspector shows its stored class name as read-only text with the
   reason, and there is no input to change it.
3. **Given** the palette, **Then** the legacy `custom` entry is visible in the *Custom* group as not
   supported and cannot be dragged.

### Edge Cases

- **Operator without task privilege**: the catalog shows the platform's refusal (HTTP status, and
  the platform's text or "no reason given") instead of a list. The rest of the canvas still works.
- **Many tasks** (about 150): the list stays usable, per SC-003.
- **Empty values**: an empty next run shows "—" with the meaning "none reported"; the same applies
  to an empty last finished. Timestamps are shown as the API returns them and never re-formatted
  into another time zone.
- **Status "1"**: shown as the platform's OK value (for example "OK (1)"). Any other status is shown
  verbatim. `lastError` "Success" is shown verbatim.
- **Invalid filter combination**: this cannot be produced from the controls. If the API still
  answers `INVALID_FILTER`, the message is shown.
- **Catalog refreshed elsewhere**: the list reflects the moment it was read. The header shows when
  it was last updated, and a refresh control re-reads it. There is no background polling.
- **Declared type removed from the catalog** while a flow still uses it: the node is shown as an
  unknown type, and validation reports it (existing behaviour).
- **Theme switch** on any new screen: both themes render every region, string and state mark
  (spec 002 US-6).

## Requirements *(mandatory)*

### Functional Requirements

**Navigation**

- **FR-001 — Top-bar navigation.** The top bar offers *Flows* and *Task catalog*. The current
  screen is indicated. Switching screens keeps the open flow and the theme.
- **FR-002 — Addressable screens.** The catalog screen, and a task's detail, can be reached
  directly by address, through the page's query string (`?view=catalog&task=<id>`), and the
  browser's back button returns to the previous screen.

**Task catalog (consumes spec 006)**

- **FR-003 — Columns.** Each row shows only values the catalog API returns: name, namespace, class,
  next run, last finished, the platform's status, suspended, run-as user, the destructive seal (or
  "destructiveness unknown"), and the SentaiTask mark. No column shows a derived job state.
- **FR-004 — Sorting.** Rows are ordered by next run ascending, and tasks without a next run come
  last. This is display order only; which tasks are shown is decided by the API.
- **FR-005 — Filters are passed to the API.** Search text, namespace, *All / Scheduled /
  Suspended* and *Destructive only* are sent to the catalog API. The screen shows exactly the items
  it returns, and "N of M tasks" uses the API's `matched` and `total`. The screen never filters or
  counts on its own.
- **FR-006 — Detail.** A task's detail shows name, id, namespace, class, run-as user, time period,
  next run, last started, last finished, status, last error, suspended, destructiveness and origin.
  It shows recent runs only when the API returns them. Every value is shown as returned.
- **FR-007 — Unavailable values.** A value the API lists as unavailable is shown as unavailable
  with the platform's reason, or "no reason given" if there is none. It is never left blank as if
  it were empty, and never filled in.
- **FR-008 — Suspend / Resume.** The detail offers exactly one of *Suspend* or *Resume*, according
  to the task's `suspended` value, using the catalog API's suspend call. After the answer, the row
  and detail show the state the API returned. A refusal shows the HTTP status and the platform's
  text verbatim. "Accepted but not applied" is shown as an error. The control is disabled while a
  call is pending.
- **FR-009 — SentaiTask origin.** A task carrying an origin shows "flow <id> · step <id>". When the
  flow exists, this links to the canvas with that flow open. When it does not, it says the flow was
  not found and has no link. Tasks without an origin are never marked.
- **FR-010 — Refusal of the whole list.** If the catalog read is refused, the screen shows the
  refusal (HTTP status and platform text, or "no reason given") and no rows.
- **FR-011 — Freshness.** The screen shows when the list was last read and offers a refresh. It
  re-reads after every suspend or resume. There is no background polling.

**Declared custom steps (consumes spec 005)**

- **FR-012 — Custom group.** The palette's *Custom* group lists every declared (in-process) type
  from the step-type catalog, plus the legacy `custom` entry as not supported. Other groups are
  unchanged.
- **FR-013 — Parameter form from the schema.** The inspector builds the parameter form only from the
  selected type's declared schema: name, type, required, default, bounds and description. No field
  is shown that the schema does not declare, and no parameter key is typed freely.
- **FR-014 — Inputs per type.** Text for `string`, a whole-number input for `integer`, a numeric
  input for `number` (with declared bounds shown), and an on/off control for `boolean`. Every field
  has a real label, matching spec 002 FR-016.
- **FR-015 — Errors on the field.** Parameter errors from validation (missing, wrong type, out of
  range, unknown) are shown on the field named by the finding's structured `parameter`, with the
  API's message verbatim. A finding without `parameter` is shown at step level, verbatim; message
  text is never parsed. The authority is the API's validation; the form only prevents input its
  control cannot hold.
- **FR-016 — Defaults.** An absent parameter shows the declared default as the field's
  placeholder, clearly marked as the default. Saving the flow stores only the parameters the
  operator set; an unchanged parameter's key is omitted and the backend applies the default.
- **FR-017 — Destructive declared types.** A declared type marked destructive carries the three
  signals of spec 002 FR-011 (hazard band, DESTRUCTIVE seal, typed confirmation before dispatch)
  at every zoom level. Dispatch collects one typed value per destructive step in the dispatch
  dialog and shows a 428 `detail` verbatim.
- **FR-018 — Legacy `custom`.** A legacy `custom` step is shown as not supported. Its stored class
  name is displayed read-only with the reason, and no control edits it. The palette entry cannot be
  dragged.

**Cross-cutting**

- **FR-019 — No business logic in the browser.** Destructiveness, origin, availability, filtering,
  counting and validation come from the API. The frontend only displays and orders them.
- **FR-020 — Theming parity.** Every new screen and control meets spec 002 US-6 in both themes: the
  same regions, strings and state marks, with no light value computed from its dark counterpart.
- **FR-021 — No regressions.** The existing frontend unit tests (48) and end-to-end tests (13)
  stay green. New end-to-end tests run against the dev container.

### Key Entities

- **Catalog task (as displayed)**: one platform task as the spec 006 API returns it. It has id,
  name, namespace, class, run-as user, time period, next run, last started, last finished, status,
  last error, suspended, destructive or unknown, an optional SentaiTask origin, optional
  unavailable values, and optional recent runs.
- **Declared step type (as displayed)**: a catalog entry from spec 005. It has type, label, class,
  category, destructive, available, and a parameter schema.
- **Parameter field**: one declared parameter rendered in the inspector. It has name, type,
  required, default, bounds, description, current value, and a validation error if any.

## Design brief — Part B prototype (prerequisite)

A prototype of the custom-step additions must exist in the product's design tool, built in the
visual system of `design/System.dc.html`, **before the plan** for this part. It must show, in
**both themes**:

1. **Palette** with a *Custom* group containing two available declared types (one with parameters,
   one without), one unavailable declared type (disabled, "not supported"), and the legacy `custom`
   entry (disabled, "not supported").
2. **A declared node on the canvas**: a normal one and a destructive one. The destructive one shows
   the hazard band, the DESTRUCTIVE seal and the category left border.
3. **Inspector parameter form** for a type with four parameters, one of each type (string,
   integer, number with bounds, boolean). Show:
   - required marks;
   - one parameter showing its default;
   - description help text;
   - one field in the error state with a verbatim message;
   - the "no parameters" variant.
4. **Legacy `custom` in the inspector**: not supported, with the stored class name read-only and
   the reason.
5. **Typed confirmation dialog** for a flow containing the destructive declared type. The
   typed-confirmation input is **new** (the current dialog has none): one field per destructive
   step, and a 428 error state.
6. **Status bar** counting a parameter error.

Part A follows the existing prototype `design/Catalog.dc.html`, with these differences from the
prototype:

- the *STATE* column becomes the platform's status plus a suspended mark;
- *New task*, *History* and *Work Queue Manager* are not shown;
- the detail drops WQM category, privilege, current run GUID and per-run duration;
- the detail adds class, time period, last started, last error, the SentaiTask origin and
  "destructiveness unknown".

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For every task shown on the dev instance, **100%** of displayed values equal the API's
  values for that task, checked by an end-to-end comparison. **0** values are shown that the API
  did not return.
- **SC-002**: After scheduling a flow of N steps, the catalog shows exactly **N** rows marked with
  that flow, and the operator reaches the flow on the canvas from one of them in **2 clicks or
  fewer** from the catalog.
- **SC-003**: With about 150 tasks, the catalog shows its first rows within **3 seconds** of being
  opened, and a filter change updates the list within **2 seconds**.
- **SC-004**: Suspend then resume of a temporary task is reflected on screen, and confirmed by a
  fresh read, after each action. A refusal shows the platform's HTTP status in **100%** of tested
  refusals.
- **SC-005**: For every declared type with parameters, the inspector shows **exactly** the
  declared fields: **0** missing and **0** extra. **100%** of parameter errors in the test matrix
  that carry `parameter` appear on their field; the rest appear at step level, verbatim.
- **SC-006**: A destructive declared type shows all **3** destructive signals in both themes.
- **SC-007**: Existing frontend tests stay green (unit **48/48**, end-to-end **13/13**), and each
  user story adds at least one end-to-end test against the container.
- **SC-008**: Paired dark/light screenshots of the catalog screen and of the parameter form pass
  the spec 002 US-6 checks.

## Assumptions

- Spec 006 is implemented as planned: fields, filters, counts, origin, `unavailable`, the proven
  suspend/resume, and `recentRuns` if its history task was not cut. The catalog screen does not
  depend on `recentRuns`.
- Spec 005 is implemented: the step-type catalog carries `label`, `executor`, `parameters[]` and
  `available`, and validation returns the `PARAM_*` codes with the step and parameter they concern.
- "Declared type" means a catalog entry whose executor is in-process (spec 005). Grouping follows
  Clarifications Q1.
- Sorting by next run is presentation only and uses the API's text value. Its timestamp format
  (`YYYY-MM-DD HH:MM:SS`) orders correctly as text.
- The operator is already signed in to the canvas (spec 002). Every catalog call uses their
  session. The screen caches no permission, and every action is decided by the platform.
- Refresh is manual (plus after actions), which matches the prototype's "updated N s ago".

## Dependencies

- **Spec 006** (task catalog API) for Part A.
- **Spec 005** (declared step types and parameter validation) for Part B.
- **The Part B prototype** in the design tool (§Design brief), before the plan for Part B.
- **The dev container** (IRIS 2026.2) for end-to-end tests.
- **Spec 002**: shell, sign-in, theming, destructive signals and validation display.
