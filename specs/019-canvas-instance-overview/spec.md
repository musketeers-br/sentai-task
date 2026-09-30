# Feature Specification: Canvas Instance Overview — Every Contest Area at a Glance

**Feature Branch**: `019-canvas-instance-overview`

**Created**: 2026-09-29

**Status**: Implemented <!-- Draft | Planned | In Progress | Implemented | Merged | Superseded by NNN — see "Spec status" in AGENTS.md -->

**Status note**: 2026-09-29. 31/31 tasks on top of spec 018 (fast-forwarded into this branch). vitest 236,
us29 7/7, backend 440/440; full e2e and the pre-existing us23 (`ollama` removed by spec 017) in
evidence/README.md.

**Input**: User description: "Canvas Instance Overview screens (frontend). Frontend only: the canvas
screens for spec 018. Every value comes from the product's API; no business rule is re-implemented
in the browser (same rule as specs 007 and 009). An Overview screen with one card per area, a detail
view per reading, report cards that run spec 013 reports on demand in the same viewer a run uses,
'schedule this check' through spec 018 and the spec 015 dialog, and — only if spec 018's process
actions shipped — suspend, resume and terminate with a typed confirmation."

## Context and Problem

1. **The first minute decides how coverage is judged.** Judges and voters open the canvas looking for
   the contest's six Management Portal areas. Today the canvas opens on an empty flow editor; four of
   the areas exist only as report steps (spec 013) that appear after composing and running a flow,
   and the operating-system area shows only disk readings. The product covers more than a first look
   suggests.
2. **Spec 018 makes every area readable in one call.** It adds seven instance readings (processes,
   locks, memory, activity, devices, licenses, web sessions), a per-area summary where each area
   carries its own outcome, the four spec 013 reports on demand, and "turn this area into a flow".
   None of it is visible without a screen.
3. **The canvas already has every building block but the screen.** The top bar switches between
   *Flows*, *Task catalog*, *Targets* and *Runs* by address; the run view already renders a report's
   summary and findings by severity (spec 013); the schedule dialog exists (spec 015); destructive
   actions already ask for a typed confirmation (spec 007). Refusals are already values the screens
   show verbatim.
4. **The orchestration story must stay in front.** Rival portals list things. SentaiTask's thesis is
   that every check can become a declared, scheduled flow. An overview that only lists would dilute
   it; one that offers "schedule this check" from every card reinforces it.

## Objective

After signing in, an operator sees one screen with a card per area — instance resources and the four
report areas — each showing its headline or the platform's own refusal. From any card they open the
full reading, run a report and read it in the same viewer runs use, or turn the check into a flow and
schedule it. The browser shows what the API says and decides nothing the API decides.

## Clarifications

### Session 2026-09-29

- Q: Which screen opens after sign-in when the address names no screen, flow or run? → A:
  *Overview*, in place of the empty canvas. Deep links (`?flow=`, `?run=`, `?view=`) keep opening
  what they name, and *Open example flow* stays one click away, from *Flows*.
- Alignment with spec 018 as clarified and planned on 2026-09-29 (no question asked; recorded so the
  two specs agree): the summary gives report cards **counts** (enabled accounts, web applications,
  serious alerts and application errors, wallet collections), never findings — findings appear only
  after *Run report*; only the four report areas map to a step type; a refused area is judged by the
  platform's answer, not by a list of "security" cards; the process list shows the platform's own
  per-process CPU time, labelled as the process's, never as host CPU.
- Q: After a report is run from its card, what does the card show back on *Overview*? → A: The last
  on-demand report's high/medium/info counts, when it ran, and a link that reopens it — kept in the
  tab's memory only (gone on reload, never written to browser storage); refreshing the summary does
  not clear it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See every area at a glance (Priority: P1) 🎯 MVP

An operator signs in and lands on *Overview*: eleven cards — Processes, Locks, Memory, Activity,
Devices, Licenses, Web sessions, Security posture, Web applications, System alerts, Secrets — each
with its headline from the spec 018 summary, or with the reason it could not be read.

**Why this priority**: It is the screen that shows the contest coverage in ten seconds, and every
other story starts from one of its cards.

**Independent Test**: Sign in as `_SYSTEM` and check that the eleven cards show the summary's
headlines; sign in as an operator holding only the `SentaiDemo` role (spec 011) and check that every
card whose read the platform refused shows that refusal verbatim (at least *Security posture*) while
every other card shows its headline.

**Acceptance Scenarios**:

1. **Given** a signed-in operator and a summary where every area is *ok*, **When** *Overview* opens,
   **Then** each card shows its area name, its headline values as the API returned them, and when it
   was read.
2. **Given** a summary where some areas are *refused*, **When** *Overview* opens, **Then** each
   refused card shows the platform's HTTP status and message verbatim, and the other cards are
   unaffected.
3. **Given** an area that is *unreachable*, **When** *Overview* opens, **Then** that card says the
   platform did not answer and shows the transport error, and offers *Retry* for the whole summary.
4. **Given** the product's API itself does not answer, **When** *Overview* opens, **Then** the screen
   shows the existing *unreachable* state, not eleven empty cards.
5. **Given** any card, **When** it is shown, **Then** no label says host CPU, host memory or console
   log.
6. **Given** *Overview* is open, **When** the operator chooses *Refresh*, **Then** the summary is read
   again and every card shows the new read time.

---

### User Story 2 - Open the full reading of an instance area (Priority: P1)

From a resource card, the operator opens a detail view with every row of that reading: a table they
can sort by any column and filter by text, with the read time, a manual refresh and an optional
auto-refresh.

**Why this priority**: The headline says "65 processes"; the operator's next question is always
"which ones?". It turns the overview into a working screen for the operating-system area.

**Independent Test**: Open *Processes*, sort by commands descending, filter by a namespace, and
compare the visible rows with the API's reading; turn auto-refresh on, hide the tab, and check that
no read happens while it is hidden.

**Acceptance Scenarios**:

1. **Given** the *Processes* card, **When** the operator opens it, **Then** a table lists every row of
   the reading with its columns as the API names them, sortable and filterable.
2. **Given** the *Memory* card, **When** it is opened, **Then** each row shows allocated, available,
   used and the used share, the share marked as computed by the product.
3. **Given** a detail view, **When** the operator turns auto-refresh on, **Then** the reading is read
   again at a fixed, stated interval, and reads stop while the browser tab is hidden and resume when
   it is visible again.
4. **Given** a reading that is refused while a detail view is open, **When** it refreshes, **Then**
   the table is replaced by the platform's refusal verbatim, not by the last rows it had.
5. **Given** a detail view, **When** the operator copies the address and opens it in another tab and
   signs in, **Then** the same detail view opens.

---

### User Story 3 - Run a report and read it where runs are read (Priority: P1)

From a report card (Security posture, Web applications, System alerts, Secrets), the operator runs
the report on demand and reads it in the same report viewer a run's step result uses: summary counts,
then findings high → medium → info, then the rows.

**Why this priority**: It makes four contest areas visible without composing a flow, and reusing the
run's viewer guarantees a report looks the same wherever it comes from.

**Independent Test**: Run *Web applications* from its card and open the same report from a one-step
run of `web-app-inventory`; check the two views show the same findings in the same order.

**Acceptance Scenarios**:

1. **Given** a report card, **When** the operator chooses *Run report*, **Then** the card shows that
   it is running, and when the answer arrives the report opens in the run's report viewer.
2. **Given** a report step type with parameters (the `system-alerts-check` thresholds,
   `failOnFindings`), **When** the operator runs it, **Then** they can set the parameters with the
   same form the inspector uses for that step type, and a value the API refuses shows the API's
   reason next to its field.
3. **Given** a report the platform refused, **When** it returns, **Then** the viewer shows a failed
   report with the platform's words verbatim.
4. **Given** an on-demand report, **When** the operator opens *Runs*, **Then** no new run is listed.
5. **Given** a report was run from its card, **When** the operator closes the viewer, **Then** the
   card shows that report's high/medium/info counts, the time it ran and *Open report*, alongside the
   summary's counts; *Refresh* updates the summary counts and leaves the report result; a page reload
   clears it.

---

### User Story 4 - Schedule this check (Priority: P2)

From a card or an open report whose area has a step type, the operator chooses *Schedule this
check*: the product creates a one-step flow through spec 018, the canvas opens it, and the existing
schedule dialog is offered. Areas without a step type do not offer the action.

**Why this priority**: It keeps the product's orchestration thesis visible from the overview. It
depends on Stories 1 and 3 only for its entry points.

**Independent Test**: From the *Secrets* card, schedule the check a minute ahead; see the flow on
the canvas, the schedule in the flow list, and a run producing the secrets report.

**Acceptance Scenarios**:

1. **Given** a report card, **When** the operator chooses *Schedule this check*, **Then** a new flow
   with one step of that type and the parameters they used opens on the canvas, and the schedule
   dialog opens over it.
2. **Given** the API returns validation findings for the new flow, **When** it opens, **Then** those
   findings are shown on the node exactly as for any other flow, and the schedule dialog is not
   opened until they are resolved.
3. **Given** a card whose area has no step type (the API says so), **When** it is shown, **Then** it
   offers no *Schedule this check* action.
4. **Given** the operator closes the schedule dialog without scheduling, **When** they go back to
   *Overview*, **Then** the flow they created is kept and listed in *Open flow…*, like any saved flow.

---

### User Story 5 - Act on a process (Priority: P3)

Only if spec 018 shipped process actions: from the *Processes* detail view, the operator suspends,
resumes or terminates a process. Terminate asks them to type the process id, as destructive steps
ask at *Run now*. The platform's answer is shown verbatim and the table is read again.

**Why this priority**: It makes the operating-system area manageable, not only visible, but it
exists only if the backend's spike proved the contract.

**Independent Test**: With spec 018's actions available, suspend and resume a disposable process
from the table, then try to terminate it without and with the typed process id.

**Acceptance Scenarios**:

1. **Given** spec 018's process actions are not available, **When** the *Processes* view is shown,
   **Then** no action control appears.
2. **Given** they are available, **When** the operator chooses *Terminate* on a row, **Then** a
   confirmation asks for the process id typed exactly, and the action is sent only when it matches.
3. **Given** any process action, **When** the platform answers, **Then** the answer is shown
   verbatim and the reading is read again, so the row shows the state the platform now reports.

---

### Edge Cases

- **The summary and a detail view disagree** (read at different moments): each shows its own read
  time; the canvas does not reconcile them.
- **An area has zero rows** (no web sessions): the card shows zero and the detail view says the
  platform returned no rows, not an error.
- **Very long tables** (thousands of locks): the detail view stays usable, sorting and filtering
  over all rows the API returned, without dropping rows silently.
- **The operator's session ends while Overview is open** (spec 010): the existing "Your session
  ended — sign in again." flow applies, and the operator returns to *Overview* or the detail view in
  the address.
- **Auto-refresh while a refusal is shown**: auto-refresh keeps trying at its interval and shows the
  new answer, success or refusal.
- **A report is run twice quickly**: the second request is not sent while the first is running for
  the same card.
- **Deep links from earlier specs** (`?flow=`, `?run=`, `?view=catalog|targets|runs`): they open
  what they name, never *Overview*.
- **Dark and light themes**: every card state (*ok*, *refused*, *unreachable*, running) is legible in
  both.

## Requirements *(mandatory)*

### Functional Requirements

**Navigation**

- **FR-001**: The top bar MUST offer *Overview* next to *Flows*, *Task catalog*, *Targets* and
  *Runs*, addressable in the page address like the other screens, and each detail view MUST be
  addressable too.
- **FR-002**: After sign-in with an address that names no screen, flow or run, the canvas MUST open
  *Overview*. Any address that names a screen, flow or run MUST open what it names. The empty canvas
  and *Open example flow* (spec 010) MUST stay one click away, from *Flows*.

**Overview**

- **FR-003**: *Overview* MUST show one card per area of the spec 018 summary, in a fixed order that
  groups instance resources and reports, from a single summary read.
- **FR-004**: Each card MUST show exactly the outcome the API gave for its area: headline values and
  read time when *ok*; the platform's HTTP status and message verbatim when *refused*; the transport
  error when *unreachable*. One card's failure MUST NOT affect another.
- **FR-005**: The canvas MUST NOT compute, reinterpret or threshold any headline value; formatting
  (units, thousands separators, percentages the API already returned) is the only transformation.
- **FR-006**: No label, tooltip or help text MAY promise host CPU, host memory or console log.

**Detail views**

- **FR-007**: Each instance area MUST have a detail view showing every row of its reading as a table
  with the API's columns, sortable by any column and filterable by text, with its read time.
- **FR-008**: A detail view MUST offer a manual refresh and an optional auto-refresh at a fixed,
  stated interval, off by default, that makes no read while the browser tab is hidden.
- **FR-009**: A refused or failed refresh MUST replace the table with the answer; stale rows MUST NOT
  be shown as current.

**Reports**

- **FR-010**: Each report card MUST run its report on demand through spec 018 and open the result in
  the same report viewer a run's step result uses.
- **FR-011**: Report parameters MUST be entered through the same parameter form the inspector uses for
  that step type, driven by the step type's declared schema from the API; the API's refusal of a
  value MUST be shown next to its field.
- **FR-012**: A card MUST NOT send a second report request while its first is running.
- **FR-012a**: A report card MUST keep its last on-demand report (counts by severity, run time, the
  report itself for *Open report*) in the page's memory only, until the page is reloaded or the report
  is run again; it MUST NOT be written to browser storage and MUST NOT be cleared by *Refresh*.

**Schedule this check**

- **FR-013**: Cards and open reports whose area the API maps to a step type MUST offer *Schedule this
  check*; others MUST NOT.
- **FR-014**: *Schedule this check* MUST create the flow through spec 018, open it on the canvas with
  the validation result the API returned, and open the existing schedule dialog only when that result
  has no errors.

**Process actions (P3, conditional)**

- **FR-015**: Process action controls MUST appear only when the API offers process actions, and MUST
  send only what the API defines.
- **FR-016**: *Terminate* MUST ask for the process id typed exactly before sending, with the same
  confirmation pattern destructive steps use at *Run now*; the platform's answer MUST be shown
  verbatim and the reading read again.

**Architecture and evidence**

- **FR-017**: Screen state MUST be a tagged value (list, refused, status, unreachable) held in pure
  view-model modules with unit tests; components MUST NOT call the network directly.
- **FR-018**: Nothing new MAY be stored in the browser beyond the spec 010 rules; auto-refresh
  preference, if kept, is a per-tab convenience only.
- **FR-019**: The README's *Contest areas covered* table MUST point at *Overview* for the areas it
  shows, and a still of *Overview* in both themes MUST be added to the README's media.
- **FR-020**: End-to-end tests MUST cover a fully privileged operator and an operator without
  security administration, and write their evidence (screenshots and read answers, no credentials)
  into this feature's `evidence/` with a README table.

### Key Entities

- **Overview card**: one area's view; attributes: area, group (instance resources or reports), state
  (*ok*, *refused*, *unreachable*, running), headline, read time, available actions.
- **Detail view**: one reading's table; attributes: area, rows and columns as returned, sort, filter,
  read time, auto-refresh on or off.
- **On-demand report view**: the run's report viewer, fed by a spec 018 on-demand report instead of a
  step result.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time operator signing in with an address that names nothing sees all eleven
  areas without any further click, and the screen is complete within 3 seconds on the dev stack.
- **SC-002**: Every value on *Overview* and in each detail view equals the API's answer for it, shown
  by end-to-end tests that compare the screen with the API read taken in the same test.
- **SC-003**: For an operator holding only the `SentaiDemo` role, 100% of the cards whose read the
  platform refused show its refusal verbatim, 100% of the other cards show their headline, and at
  least *Security posture* is refused.
- **SC-004**: From *Overview*, an operator schedules the *Secrets* check in under one minute and in
  no more than four actions, and its scheduled run produces the secrets report.
- **SC-005**: A report opened from *Overview* and the same report opened from a one-step run show the
  same findings in the same order.
- **SC-006**: With auto-refresh on and the tab hidden for one minute, 0 readings are requested.
- **SC-007**: Every address used by specs 007–015 still opens what it opened before (no deep link
  lands on *Overview*), and the existing frontend unit and end-to-end tests stay green, none removed.
- **SC-008**: Paired dark and light screenshots of *Overview* with ok, refused and running cards are
  in `evidence/`.

## Assumptions

- Spec 018's contract is merged before implementation starts; if its process actions (User Story 5
  of 018) are dropped, User Story 5 here is dropped too, and no control is shown.
- The overview is for the primary instance only, as in spec 018; target servers keep their own
  screen (spec 009).
- *Overview* is the default landing screen for an address that names nothing (clarification Q1);
  spec 010's onboarding (example flow, deep links, session return) is otherwise unchanged. The
  existing end-to-end tests that expect the empty canvas after sign-in are updated to open *Flows*
  explicitly, never removed.
- Auto-refresh uses one fixed interval chosen in the plan (in the order of 10 seconds), not an
  operator setting.
- The screen is built in the existing visual system and design tokens (spec 009 Q1 = A); no new
  component library.
- Charts over time are out of scope: spec 018 keeps no history. Logs, x509, SSL, OAuth, roles and
  resources screens are later features.
