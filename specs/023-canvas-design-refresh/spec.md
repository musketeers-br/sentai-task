# Feature Specification: Canvas Design Refresh — Flow Chrome, Catalog Detail and Overview Attention

**Feature Branch**: `023-canvas-design-refresh`

**Created**: 2026-10-01

**Status**: Implemented <!-- Draft | Planned | In Progress | Implemented | Merged | Superseded by NNN — see "Spec status" in AGENTS.md -->

**Status note**: Implemented 2026-10-02 on branch `023-canvas-design-refresh` (based on `master`
with specs 018 and 019): 43 of 44 tasks; T042 (moderated usability run for SC-002/SC-003) is
`[external]`, owned by the product owner. Source: the Claude Design board "SentaiTask", section 05.
Clarified 2026-10-01 (2 questions); re-based after `/speckit-analyze` — US3 amends spec 019's
Overview (FR-002, FR-021, FR-024, FR-025, FR-027, FR-028 withdrawn). Full e2e suite: only the five
failures `master` already has (evidence/README.md).

**Input**: User description: "crie a spec 23 e gere o plano de melhorias do frontend sugerido pelo
claude design neste projeto. https://claude.ai/artifact/N68ws3dAuE8S9i1zf1esBG"

## Context

The canvas shipped by specs 002, 007, 010 and 012 works, but a design review of the running app
(Claude Design, 2026-09-20 board, proposal section 05) points at three places where the operator
has to work out for themselves what the screen means:

1. **The flow editor's top bar mixes two things.** The same bar holds the screen navigation, the
   theme, the user and *every* flow control (Open flow…, name, Save flow, More ▾, Validate flow,
   Run now, Schedule in Task Manager). At 1440 px it is full; spec 010 already had to move New flow
   and Save as… into a menu for lack of width. Disabled buttons explain themselves only in a
   tooltip. An empty canvas offers the ready-made example only on an instance with no saved flows;
   otherwise it is a blank grid, and the inspector is blank until a step is clicked.
2. **The Task catalog lists, but does not prioritise.** The rows and their marks are right, but
   the operator cannot see at a glance how many tasks are suspended, destructive or unclassified,
   and the detail of a task does not say why it is destructive or offer the next action (put it
   in a flow).
3. **The starting screen lists, but does not prioritise.** Spec 019 lands the operator on
   *Overview*: eleven cards, one per area. Nothing on it says "this instance has never been backed
   up", "two scheduled tasks are suspended" or "what runs in the next 24 hours", and a refused card
   is visible only by scanning all eleven. The catalog and spec 018 already answer all of it.

The proposal keeps the global top bar unchanged (spec 019 already added its Overview tab) and
changes only what sits under it. This spec
turns that proposal into user-observable behaviour, in three independently shippable slices.

## Clarifications

### Session 2026-10-01

- Q: Is the catalog detail's "Suspend" a new write, or does the catalog stay read-only? → A: In
  scope. Suspend/Resume is one toggle in the task detail, behind a simple confirmation (not the
  typed confirmation gate of destructive steps), made with the operator's own credential, the
  platform's refusal passed through unchanged. The detail marks tasks "created outside
  SentaiTask" when they did not come from a SentaiTask flow.
- Q: Is Overview the landing screen after sign-in? → A: Yes — on the condition that Overview
  states on screen everything it could not read (which reading, and why) instead of rendering an
  empty or partial band silently. *(2026-10-01: Overview as the landing screen was already
  delivered by spec 019, clarification Q1; the condition is kept as FR-029.)*

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The flow editor says what the flow is and what to do next (Priority: P1)

An operator opens Flows. Under the global top bar, a second bar belongs to the open flow only: its
name, whether it is saved ("unsaved", or "rev 3 · saved 20:14"), and the flow's own actions —
Open…, Save, Validate, Run now, Schedule and a "⋯" menu (New flow, Save as…, Run history). When an
action cannot be used, the reason is written beside it ("add a step to enable running"), not only
in a tooltip. On an empty canvas, a real empty state explains how to build the flow (drag a step
type; connect several outputs into one input to make a join, which runs those steps in parallel
and waits) and offers two ways to start: from a template, or from a task already in the catalog.
With nothing selected, the inspector shows the flow's own properties and says "Nothing selected —
click a step and its parameters appear here". The status bar counts steps, joins and destructive
steps, and shows snap and zoom.

**Why this priority**: The flow editor is the screen every operator uses and the one a judge sees
first. It needs no new backend, and it frees width the top bar no longer has.

**Independent Test**: Open Flows on a new, empty flow and on a saved flow, in both themes at
1440 × 900; check the two bars, the disabled reasons, the empty state, the inspector placeholder
and the status-bar counts against the flow's contents.

**Acceptance Scenarios**:

1. **Given** any screen, **When** the operator looks at the global top bar, **Then** it shows the
   same items on every screen — the mark, the screen tabs, Dark/Light, Help ▾, the user and Sign
   out — and no flow control.
2. **Given** Flows is open, **When** the operator looks under the global bar, **Then** a flow bar
   shows the flow's name (editable), its save state, and Open…, Save, Validate, Run now, Schedule
   and "⋯" (New flow, Save as…, Run history).
3. **Given** a flow with no steps, **When** the operator looks at Validate, Run now and Schedule,
   **Then** they are disabled and the text "add a step to enable running" is visible next to them
   without hovering.
4. **Given** a flow whose last validation failed, **When** the operator looks at Run now and
   Schedule, **Then** they are disabled and the visible reason points to the validation errors.
5. **Given** an empty canvas, **When** the operator looks at it, **Then** it explains drag-to-add
   and joins, shows a legend telling a sequence from a join, and offers "Start from a template" and
   "Import from the task catalog".
6. **Given** no step is selected, **When** the operator looks at the inspector, **Then** it shows
   the flow's name and WQM category and the "Nothing selected" explanation.
7. **Given** a flow with 4 steps, 1 join and 1 destructive step, **When** the operator looks at the
   status bar, **Then** it reads "4 steps · 1 join · 1 destructive" and shows the snap and zoom.
8. **Given** the palette, **When** a category holds more step types than fit, **Then** it shows its
   count, the first entries and "Show N more"; step types not supported in v1 are gathered under
   "N types not supported in v1 · Show" at the end, still listed when expanded.

---

### User Story 2 - The Task catalog points at what needs attention (Priority: P2)

An operator opens Task catalog. The header says "16 of 16 tasks · updated 3 s ago" with Refresh.
Beside the search and namespace filter, the state filter shows counts — All, Scheduled, Suspended
(2), Destructive (2) — and a separate "12 unclassified" marker that filters to the tasks whose
destructiveness is unknown. Rows are sorted by next run, with suspended and destructive marks as
today, and a footer repeats the totals. Selecting a row opens a detail panel: namespace, run-as
user, next and last run, the platform's description of the task, why it is destructive (when
it is) and the last five runs, or "No run recorded. This task has never executed on this
instance." The panel's main action is "Add to a flow". A Suspend/Resume toggle suspends or resumes
the task after a simple confirmation, and a "created outside SentaiTask" mark tells the operator
when the task was not made by a SentaiTask flow.

**Why this priority**: The catalog already has every value; this slice makes the dangerous and
the neglected tasks visible and connects the catalog to the editor. Suspend/Resume already exists
(spec 007); this slice changes how it is offered, and adds no new platform write.

**Independent Test**: On the dev instance (16 tasks, 2 suspended, 2 destructive, 12 unclassified),
open the catalog and check the counts, the unclassified filter, the order, the detail panel of a
destructive task and of a never-run task, and that "Add to a flow" opens the editor with that step.

**Acceptance Scenarios**:

1. **Given** the dev instance, **When** the catalog loads, **Then** the filter shows Suspended 2,
   Destructive 2 and "12 unclassified", and the footer reads "2 destructive · 2 suspended · 12
   unclassified".
2. **Given** the catalog, **When** the operator selects "12 unclassified", **Then** only the tasks
   whose destructiveness the API reports as unknown are listed.
3. **Given** no explicit sort, **When** the list shows, **Then** rows are ordered by next run, and
   tasks without a next run come last.
4. **Given** a destructive task is selected, **When** the detail opens, **Then** it shows why the
   task is destructive as the catalog states it, and says the classification is not editable here.
5. **Given** a task that never ran, **When** its detail opens, **Then** "Last 5 runs" reads "No run
   recorded. This task has never executed on this instance."
6. **Given** a task whose class is a declared step type, **When** the operator chooses "Add to a
   flow", **Then** Flows opens with that step on the canvas of the current flow (or a new one) and
   the flow is marked unsaved.
7. **Given** a task whose class is not a declared step type, **When** its detail opens, **Then**
   "Add to a flow" is disabled and the reason is visible.
8. **Given** the catalog was read N seconds ago, **When** the operator looks at the header, **Then**
   it says "updated N s ago", and Refresh reads again.
9. **Given** an active task is selected, **When** the operator turns the toggle to Suspend and
   confirms, **Then** the task is suspended with the operator's credential, the row and the
   detail show SUSPENDED after the catalog is read again, and the suspended count changes.
10. **Given** a suspended task, **When** the operator turns the toggle to Resume and confirms,
    **Then** the task is resumed and its next run shows again as the platform reports it.
11. **Given** the confirmation is open, **When** the operator cancels, **Then** nothing is sent and
    the toggle returns to its previous position.
12. **Given** the platform refuses the suspend to this operator, **When** the answer arrives,
    **Then** the detail shows the platform's HTTP status and message unchanged, and the toggle
    stays in its previous position.
13. **Given** a task whose name does not follow the SentaiTask origin pattern, **When** its detail
    opens, **Then** it shows the mark "created outside SentaiTask"; a task created by a SentaiTask
    flow shows no such mark.

---

### User Story 3 - Overview points at what needs attention (Priority: P3)

An operator signs in and lands on Overview (spec 019). Above 019's cards, three things are new:

1. **Unread summary** — when any reading could not be made, a line at the top lists each one
   (which area or band, and the platform's status and message), so a refused card is never found
   only by scanning.
2. **Needs attention** — a short list of findings, each with one action: "No backup has ever been
   taken on this instance" (last backup, uptime), "2 scheduled tasks are suspended" (names; Show in
   catalog), "12 of 16 tasks have no destructiveness classification" (Show them). When nothing needs
   attention it says so.
3. **Next 24 hours** — a time strip of scheduled tasks by half hour, with counts, destructive marked,
   suspended tasks counted apart, whether any flow is scheduled, and the next scheduled time after
   the strip.

Spec 019's eleven cards, reading view, *Run report* and *Schedule this check* are unchanged.

**Why this priority**: it turns the landing screen from a list into a to-do list, using reads the
product already makes; it is last because 019 already gives a working landing screen.

**Independent Test**: on the dev instance (never backed up, 2 suspended, 12 unclassified), open
Overview and check each band against the catalog and the summary; refuse one read and check the
unread summary names it while everything else renders.

**Acceptance Scenarios**:

1. **Given** an instance with no backup ever taken, **When** Overview loads, **Then** "No backup has
   ever been taken on this instance" is listed with the last backup and uptime as the summary
   reports them.
2. **Given** 2 suspended tasks, **When** the operator chooses "Show in catalog", **Then** the catalog
   opens filtered to suspended tasks.
3. **Given** 12 unclassified tasks, **When** the operator chooses "Show them", **Then** the catalog
   opens with the unclassified filter on.
4. **Given** tasks scheduled in the next 24 hours, **When** Overview loads, **Then** the strip shows
   each half hour that has tasks with its count and marks destructive ones.
5. **Given** the catalog read is refused, **When** Overview loads, **Then** Needs attention shows only
   the items it could read, Next 24 hours says it could not be read, the unread summary names the
   catalog read with the platform's status and message, and 019's cards render as before.
6. **Given** one area of the summary is refused, **When** Overview loads, **Then** the unread summary
   names that area, and its card shows the refusal as spec 019 defines.

---

### Edge Cases

- **Nothing needs attention**: the band says "Nothing needs attention" rather than disappearing,
  so its absence is never mistaken for a failed read.
- **A read is refused or unreachable**: each band and each row fails alone and shows the
  platform's refusal verbatim (HTTP status and message); the other bands still render. A refused
  read is never shown as zero or as "nominal".
- **No task in the next 24 hours**: the strip says "Nothing scheduled in the next 24 hours" and the
  next scheduled time, if any.
- **A catalog value the API did not send** (description, next run, destructiveness reason): the
  detail shows it as absent; it is never inferred or filled in by the canvas.
- **Unsaved changes** when "Add to a flow" or "Start from a template" would replace the open flow:
  the existing unsaved-changes guard (spec 010) asks first.
- **"Import from the task catalog" with an empty catalog**: the catalog opens and shows its
  existing empty state.
- **Narrow windows** below 1440 px: the flow bar wraps or collapses into "⋯" before any control
  becomes unreachable; no horizontal page scroll at the minimum supported width.
- **Suspend while the task is running**: whatever the platform does (accept or refuse) is shown as
  it answered; the canvas does not predict it.
- **Task changed by someone else** between the read and the toggle: after the action the catalog
  is read again, and the detail shows the platform's current state, not the assumed one.
- **Suspending a SentaiTask-created task** (a scheduled flow, spec 015): allowed; the confirmation
  says the flow's scheduled runs stop until it is resumed.
- **Template not available** (its step types are undeclared, unavailable or destructive, spec 010
  FR-019): "Start from a template" is hidden, as the example invitation is today.

## Requirements *(mandatory)*

### Functional Requirements

**Global shell (all stories)**

- **FR-001**: The global top bar MUST show the same items on every screen: the mark, the screen
  tabs, the theme switch, Help ▾, the signed-in user and Sign out. It MUST NOT hold flow controls.
- **FR-002**: *(withdrawn 2026-10-01 — delivered by spec 019: Overview tab first, own address.)*
- **FR-003**: Every changed screen MUST render in the dark and the light theme from the existing
  design tokens; no colour, size or radius is written outside the token source.
- **FR-004**: Every new control MUST be reachable and operable by keyboard, with a visible focus
  and an accessible name; state carried by colour (destructive, suspended) MUST also be carried by
  text or shape.

**Flow editor (User Story 1)**

- **FR-005**: On Flows, a flow bar under the global bar MUST show the flow name (editable, with the
  spec 010 rename note), its save state ("unsaved" or "rev N · saved HH:MM", plus "edited" when
  dirty), and the actions Open…, Save, Validate, Run now, Schedule and a "⋯" menu holding New flow,
  Save as… and Run history.
- **FR-006**: When Validate, Run now or Schedule is disabled, the reason MUST be visible as text in
  the flow bar without hovering: "add a step to enable running" for an empty flow, and a pointer to
  the validation errors when validation failed.
- **FR-007**: An empty canvas MUST show an empty state that explains adding a step by dragging and
  making a join by connecting several outputs into one input, with a legend for sequence and join.
- **FR-008**: The empty state MUST offer "Start from a template", which opens the spec 010 example
  flow under the same availability rules (hidden when not available), on any instance — not only
  one with no saved flows.
- **FR-009**: The empty state MUST offer "Import from the task catalog", which opens the Task
  catalog; choosing "Add to a flow" there (FR-017) returns to this flow.
- **FR-010**: With no step selected, the inspector MUST show the flow's own properties (name, WQM
  category) and the text "Nothing selected. Click a step on the canvas and its parameters appear
  here."
- **FR-011**: The status bar MUST show the counts of steps, joins and destructive steps in the open
  flow, and the canvas snap and zoom; the counts MUST change as the flow is edited.
- **FR-012**: The canvas MUST offer zoom in, zoom out and fit-to-view controls.
- **FR-013**: In the palette, each category MUST show its number of step types; a category longer
  than a set number of entries MUST show the first ones and "Show N more"; step types not supported
  in v1 MUST be gathered at the end under "N types not supported in v1" with Show, and stay listed
  (spec 004 D-1) when shown. Search keeps working across collapsed entries.
- **FR-014**: Each palette entry MUST show the step type's display name and, as secondary text, its
  catalog identifier, both as the step-type catalog provides them.

**Task catalog (User Story 2)**

- **FR-015**: The catalog header MUST show "M of N tasks" and how long ago the list was read, with
  Refresh. The state filter MUST show the number of suspended and of destructive tasks, and a
  separate "N unclassified" control MUST filter to tasks whose destructiveness the API reports as
  unknown. Every count MUST come from the API's answer, not from the rows currently displayed.
- **FR-016**: Rows MUST be ordered by next run by default, tasks with no next run last; a footer
  MUST repeat the order and the destructive, suspended and unclassified totals.
- **FR-017**: Selecting a row MUST open a detail panel with: name, class and id; namespace; run-as
  user; next run; last run; the platform's description; why the task is destructive (only
  when destructive, as the catalog states it, with "classified from the step-type registry · not
  editable here"); and the last five runs, or "No run recorded. This task has never executed on
  this instance." Any value the API does not send MUST be shown as absent.
- **FR-018**: The detail panel MUST offer "Add to a flow" when the task's class is a declared step
  type in the catalog. It adds that step type, with the step type's default parameters and the
  task's namespace and run-as user, to the open flow (or a new flow), marks it unsaved and opens Flows. When the class
  is not a declared step type, the action MUST be disabled with the reason shown.
- **FR-019**: The "Classify" affordance in the proposal MUST NOT let the operator change a task's
  destructiveness: classification comes only from the step-type catalog (Constitution II). It
  MUST filter to unclassified tasks and explain that a classification is added through the
  catalog, in a reviewed change.
- **FR-020**: The detail panel MUST offer one Suspend/Resume toggle reflecting the task's current
  suspended state as the API reports it. Changing it MUST ask a simple confirmation (task name,
  the action, and — for a SentaiTask-created task — that the flow's scheduled runs stop until
  resumed), not the typed confirmation gate of destructive steps. On confirm, the action MUST be
  made with the operator's own credential; on success the catalog is read again; on refusal the
  platform's HTTP status and message MUST be shown unchanged and the toggle MUST return to its
  previous position. The canvas MUST NOT hide or disable the toggle by predicting a refusal
  (Constitution III). When the suspended state is unavailable, the toggle MUST be disabled with
  the reason shown.
- **FR-020a**: The detail panel MUST mark a task "created outside SentaiTask" when the catalog
  reports no SentaiTask origin for it (spec 006/015 origin), and MUST show no mark otherwise.

**Overview attention (User Story 3)**

- **FR-021**: *(withdrawn 2026-10-01 — spec 019 owns the Overview header and Refresh; Refresh also
  re-reads the bands below.)*
- **FR-022**: Above spec 019's cards, a **Needs attention** band MUST list, each with one action:
  no backup ever taken (from the summary's `activity` headline: last backup and uptime; action:
  add a backup step to a flow, disabled with its reason while no step type of category `backup`
  is declared); suspended tasks (their names; action: catalog filtered to suspended); tasks
  without destructiveness classification ("U of N"; action: catalog filtered to unclassified).
  With none, it MUST say "Nothing needs attention".
- **FR-023**: A **Next 24 hours** band MUST show scheduled tasks by half hour with counts,
  destructive marked, the total and the number of destructive ones, suspended tasks counted apart,
  whether any flow is scheduled, and the next scheduled time after the strip when it ends early.
- **FR-024**: *(withdrawn 2026-10-01 — instance resources are spec 019's cards and reading view.)*
- **FR-025**: *(withdrawn 2026-10-01 — on-demand reports and Schedule this check are spec 019's.)*
- **FR-026**: Each new band MUST fail on its own: an item or band whose read failed shows the
  platform's HTTP status and message, never a zero, an empty list or "Nothing needs attention";
  spec 019's cards MUST render whatever happens to the bands.
- **FR-027**: *(withdrawn 2026-10-01 — spec 018 is part of the product.)*
- **FR-028**: *(withdrawn 2026-10-01 — delivered by spec 019, clarification Q1.)*
- **FR-029**: Overview MUST show, above the bands, an **unread summary** listing every reading it
  could not make: each refused or unreachable area of the summary and each failed band read, with
  the platform's status and message. Hidden only when the list is empty.

### Key Entities

- **Flow bar state**: the open flow's name, save state (unsaved / revision and saved time / edited)
  and, per action, whether it is enabled and the visible reason when it is not.
- **Flow summary**: counts of steps, joins and destructive steps in the open flow, and the canvas's
  snap and zoom.
- **Catalog summary**: total and matched tasks, counts of suspended, destructive and unclassified
  tasks, and the time of the read.
- **Task detail**: the catalog's values for one task (identity, namespace, run-as user, schedule,
  description, destructiveness and its reason, suspended state, origin — SentaiTask or
  outside — and recent runs), each either a value or absent.
- **Suspend action**: one requested change of a task's suspended state, its confirmation, and the
  platform's answer (accepted, or refused with status and message).
- **Unread reading**: one Overview reading that could not be made, and why.
- **Attention item**: a finding on the instance (its text, the values that support it, one action
  and where that action leads).
- **Schedule slot**: a half-hour window with the tasks scheduled in it, and how many are
  destructive or suspended.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: At 1440 × 900, every flow action (Open, Save, Save as, New, Validate, Run now,
  Schedule, Run history) is reachable in at most two clicks from Flows, and the global top bar is
  identical on all screens.
- **SC-002**: In a moderated run with 5 first-time users, at least 4 can say why Run now is disabled
  on an empty flow, and build and validate a two-step flow from the empty state, without help.
- **SC-003**: On the dev instance, a user identifies how many tasks are suspended, destructive and
  unclassified in under 10 seconds from opening the catalog.
- **SC-004**: From a catalog task whose class is a declared step type, a user has that step on the
  canvas in at most 2 clicks.
- **SC-005**: Every count shown on Overview and in the catalog matches the API's answer for the
  same read — 0 mismatches in the e2e evidence.
- **SC-006**: With the catalog read or any one summary area refused, every other band and card
  still renders, and the refused one shows the platform's status and message unchanged.
- **SC-007**: The two new bands are visible within 3 seconds of opening Overview on the dev instance.
- **SC-008**: Every changed screen passes an automated accessibility check with no serious or
  critical violations, in both themes.
- **SC-009**: A user suspends and then resumes a task from its detail in at most 4 clicks, and the
  catalog shows the platform's state after each action — verified in e2e on a task the test creates.
- **SC-010**: For every reading Overview could not make in the e2e runs, the top summary names it —
  0 empty bands without an explanation.

## Assumptions

- The Claude Design board (2026-09-20, section 05) is the visual reference: the evidence README
  records each screenshot next to the board it follows. The board's figures (16 tasks, 2 suspended,
  12 unclassified, iris-prod-01) are illustrative; the dev instance's real values are what tests
  check.
- The global top bar is "unchanged from the shipped app" per the board, except that flow controls
  move to the flow bar (spec 019 already added the Overview tab).
- "Start from a template" means the spec 010 example flow; a template gallery is out of scope.
- "Classify" is a filter plus an explanation (FR-019); classifying a task is a code change to the
  step-type catalog, reviewed in a pull request.
- The catalog API already returns suspended, destructive / unknown, recent runs and the task's
  class. The destructiveness reason comes from the step-type catalog (plan research R-4) and the
  description from the platform (R-3); nothing is inferred.
- Specs 018 (Instance Overview API) and 019 (Canvas Instance Overview) are merged. This spec amends
  019's screen only by adding bands above its cards; 018's API is consumed unchanged.
- The backup finding relies on the summary's `activity` headline (`lastBackup`, spec 018); there
  is no backup step type in the catalog today, so its action is disabled until one is declared.
- The minimum supported width is 1280 px (spec 002 sets none; its evidence is 1440 × 900); mobile
  layouts are out of scope.
- No new platform write: Suspend/Resume uses the spec 007 call unchanged. The e2e test suspends and
  resumes a task it creates itself, never a task the instance shipped with.
- The platform reports no WQM category and no privilege for a Task Manager task (probed
  2026-10-01, plan research R-3), so the board's two rows are not shown; printing a fixed
  privilege would be the canvas predicting authorization (Constitution III).
