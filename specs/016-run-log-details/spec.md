# Feature Specification: Flow Execution Log Detail

**Feature Branch**: `016-run-log-details`

**Created**: 2026-09-29

**Status**: In Progress

**Status note**: MVP (T001–T009 — step execution detail incl. result, addressed `?run=&step=`)
implemented and verified 2026-09-29. Remaining: T010 (log slice in panel), Phase 3 (US1 log
reading), Phase 4 (US3 filters — cut first), Phase 5 polish.

**Input**: User description (2026-09-29): "Implemente a exibição de logs com detalhes da
execução de cada flow na UI para que os usuários consigam ter visão do que ocorreu durante a
execução do flow." — requested as spec number 16, to avoid colliding with the specs currently
being developed in parallel (012–015).

## Context and Problem

The run view is where a flow's execution is visible: each step's state, its elapsed time, the
platform's failure reason when it failed, and a **RUN LOG** panel. Today that panel always says
"No log entries recorded for this run", because nothing writes entries yet — spec 012 defines
what the product records and when.

Even once entries exist, the panel as it stands answers "what happened" only partially:

1. **Nothing is guaranteed to arrive whole.** A long platform failure reason has no promise of
   being shown uncut, and an entry's text cannot be copied for a ticket.
2. **A step's own account is invisible.** When a step started and finished, where and as whom it
   ran, and the result it produced — the size report, the headroom findings — are carried by the
   run read but shown nowhere in the canvas. The only per-step facts on screen are a state and a
   duration.
3. **A busy run is a wall of text.** In a real nightly flow — parallel waves, tens of steps — a
   flat, unfilterable list of entries is not visibility; the one entry that matters has to be
   hunted by eye.

## Objective

Every flow execution the canvas shows — live, or opened after it ended — can be examined in
detail: the chronological log with nothing paraphrased, cut or hidden; one step's full execution
account (times, place, identity, result, verbatim failure reason, and its own slice of the log);
and filters that find the relevant entries fast.

## Relationship to Other Specs

- **Spec 012** (`run-log-history`, in development) owns what gets *recorded* in the log and when
  (its Story 1), the *Runs* history screen with filters and paging (Story 2), and the JSON export
  (Story 3). **This spec depends on 012's recording**: without entries there is nothing to read,
  and the sequencing dependency is declared here explicitly (Constitution V).
- This spec owns the *reading experience* on those same entries and the same panel: full-detail
  display, the per-step drill-down, and filtering. Where its baseline (entries in time order,
  live update, severity distinction) mirrors 012's FR-005, it is restated so the display contract
  is whole in one place; everything beyond that baseline is this spec's own.
- Nothing here changes what is recorded, who may read a run, retention, deletion, or the export.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The log, whole (Priority: P1)

In the run view — live, or opened after the run ended — the **RUN LOG** panel lists every
recorded entry in time order, newest visible. Each entry shows when it happened, which step it
concerns (when it concerns one), its severity — distinguishable by shape or marker and by its own
word, never by colour alone — and its message in full: a long platform failure reason wraps,
never truncates, and its text can be copied. While the run is live, entries appear without a
reload; the panel keeps the newest entry visible unless the operator has scrolled up, in which
case their place is kept and one action returns to the newest.

**Why this priority**: it is the core of "visibility of what happened" — every other story builds
on entries being readable, whole and honest.

**Independent Test**: dispatch the spec-010 example flow; while it runs, entries appear live;
when a step fails, its platform reason shows whole in the log and the entry's text can be copied.

**Acceptance Scenarios**:

1. **Given** a run with recorded entries, **Then** the panel lists them in time order, each with
   its time, its step (when the entry concerns one), its severity and its message.
2. **Given** entries of the three severities, **Then** each severity is distinguishable without
   colour alone — by a shape or marker and by its own word — in both themes.
3. **Given** an entry whose message is a long platform failure reason, **Then** the whole text is
   visible (wrapped, never cut) and can be copied exactly.
4. **Given** a live run, **Then** new entries appear in the panel within the view's normal
   refresh, without a reload, and the newest entry stays visible.
5. **Given** the operator has scrolled up in the log during a live run, **Then** a refresh does
   not move their position, and one action returns to the newest entry.
6. **Given** a run with no entries, **Then** the panel explains that honestly — as spec 012 words
   it for runs that predate recording — and is never presented as an error.
7. **Given** a finished run opened after it ended, **Then** the panel shows the same entries in
   the same way.

---

### User Story 2 - One step's execution, in full (Priority: P1)

The operator selects a step — its canvas node or its row in the step list — and sees that step's
execution account: its state; when it was queued, started and finished, and how long it took;
where it ran (local or which target server) and as whom; its failure reason whole and verbatim
when it failed; the result it produced, readable, when it produced one; and its slice of the log
— only the entries about that step, across all its attempts. A re-run step shows its latest
attempt as the account; every entry of every attempt stays in the slice, in time order.

**Why this priority**: "what happened during the execution" is asked most often about one step —
which failed and why, what it produced, where it ran. The step's result is invisible in the
canvas today even though the run read already carries it.

**Independent Test**: run a flow with a database size report and a failing integrity check; open
the report step's detail: its result is readable; open the failed step: the platform's reason is
whole and copyable, and its log slice shows only its own entries.

**Acceptance Scenarios**:

1. **Given** a selected step, **Then** its detail shows its state, its queued, started and
   finished times, its duration, where it ran and as whom.
2. **Given** a failed step, **Then** its failure reason appears whole, verbatim, and can be
   copied.
3. **Given** a step that produced a result, **Then** the result is shown readable in its detail;
   when the product stored it truncated, the detail says so, as the run read reports.
4. **Given** a selected step, **Then** the log shows only the entries about that step, in time
   order.
5. **Given** a step that was re-run, **Then** the detail shows the latest attempt, and the slice
   contains the entries of every attempt in time order.
6. **Given** the step detail is dismissed, **Then** the panel returns to the full log.
7. **Given** a running step, **Then** its detail reflects its live state within the view's normal
   refresh.

---

### User Story 3 - Find the entry that matters (Priority: P2)

In a busy run the operator narrows the log: by severity, to one step's slice (via that step's
detail), or both combined. The panel says how many entries match ("N of M"); one action clears
the filters. Filters change only what is shown — never the run — and, on a live run, new matching
entries keep appearing.

**Why this priority**: with few entries the flat list already works; filters earn their keep on
real flows with parallel waves and tens of steps.

**Independent Test**: run a flow with two parallel waves and one failing step; narrow the log to
errors: only failure entries are listed, with "N of M"; open the failed step: its slice; clear:
the full log returns.

**Acceptance Scenarios**:

1. **Given** the log panel, **When** the operator narrows by severity, **Then** only entries of
   that severity are listed, and the panel says how many entries match.
2. **Given** a severity filter and a selected step, **Then** both apply together on the slice.
3. **Given** filters are on, **Then** one action clears them and the full log returns.
4. **Given** a live run with filters on, **Then** a new matching entry appears within the view's
   normal refresh.
5. **Given** a filter that matches nothing, **Then** the panel says so honestly, without
   inventing entries and without showing an error.

### Edge Cases

- An entry whose severity the canvas does not know (one added later): shown as-is, with its own
  word, never dropped.
- A message with no spaces — one long token, or JSON inside a reason: it wraps without breaking
  the panel's layout; nothing is cut.
- Two entries in the same second: their relative order is stable across refreshes.
- A very long log (hundreds of entries) during a live run: scrolling stays smooth, refreshes keep
  the operator's position, and the rest of the run view stays responsive.
- A step whose stored result is the largest the product keeps: shown whole, wrapped, copyable.
- An entry with no step (a run-level fact): shown without a step; a step slice excludes it.
- Both themes, dark and light: the severity cues hold in each.
- Screen readers: severity and step are announced as text, never only by colour.
- A finished run opened from elsewhere (spec 012's history): the same panel, filters and step
  detail; there are no live updates to wait for.
- Selecting a step that has not started: its detail shows what is known — its state — and
  invents nothing for times, duration, place or identity.

## Requirements *(mandatory)*

### Functional Requirements

**The log panel**

- **FR-001**: The run view's log panel MUST show every recorded entry in time order, each with
  its time, the step it concerns (when it concerns one), its severity and its message.
- **FR-002**: Severity MUST be distinguishable without colour alone — by a shape or marker and by
  its own word — and MUST hold in both themes.
- **FR-003**: An entry's message MUST be shown whole: wrapping is allowed, truncation is not; a
  platform failure reason or refusal is never paraphrased (Constitution III); the operator MUST
  be able to copy an entry's text exactly.
- **FR-004**: While the run is live, new entries MUST appear in the panel within the view's
  normal refresh without a reload, and the newest entry MUST remain visible unless the operator
  has scrolled elsewhere.
- **FR-005**: A refresh MUST NOT change the operator's scroll position, and returning to the
  newest entry MUST be one action.
- **FR-006**: A run with no entries MUST get an honest explanation in the panel — including the
  runs-from-before-recording case, worded as spec 012 defines it — and MUST NOT be presented as
  an error.

**One step's account**

- **FR-007**: Selecting a step in the run view MUST show its execution detail: state, when it was
  queued, started and finished, its duration, where it ran, and as whom.
- **FR-008**: A failed step's reason MUST appear in its detail whole and verbatim, and MUST be
  copyable.
- **FR-009**: A step's stored result MUST be shown readable in its detail; when the product stored
  it truncated, the detail MUST say so as the run read reports; the result MUST be copyable.
- **FR-010**: A selected step MUST narrow the log to that step's entries — every attempt, in time
  order — while the detail shows the latest attempt; dismissing the detail MUST return the full
  log.
- **FR-011**: The step detail MUST show only what is known: a step that has not started shows its
  state and nothing invented for times, duration, place or identity.

**Filters**

- **FR-012**: The log panel MUST narrow by severity, composable with the step selection of
  FR-010, and MUST show how many entries match; one action MUST clear all filters.
- **FR-013**: Filters MUST affect only what is displayed; a live run with filters on MUST still
  gain matching entries within the normal refresh; a filter matching nothing MUST say so —
  neither an error nor invented entries.

**Language**

- **FR-014**: All new user-facing text MUST be in English.

### Key Entities

- **Log entry** (existing; recorded by spec 012 over spec 003's contract): time, step (optional),
  severity, message. This spec only reads it.
- **Step execution detail** (a view over the existing run read): state, queued, started and
  finished times, duration, where it ran, as whom, failure reason verbatim, stored result with its
  truncation markers, and the step's log slice.
- **Log view state**: which filters are on (severity, step) and where the operator is scrolled —
  screen state, kept only for as long as the view is open.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a run with 200 recorded entries, an operator finds the first error entry in at
  most 2 actions from the run view.
- **SC-002**: For every entry shown, 100% of its message characters are visible or copyable — a
  comparison between each entry as the product stored it and what the view shows finds no loss.
- **SC-003**: With 500 entries in the panel during a live run, the operator's scroll position
  survives every refresh, and the rest of the run view keeps updating live.
- **SC-004**: From a selected step's detail, an operator states where the step ran, as whom, how
  long it took and — when it failed — the platform's reason, in under 15 seconds.
- **SC-005**: For a run with a failed step, an operator who was away from the keyboard
  reconstructs what happened to that step without leaving the run view, in under 1 minute, using
  only the step detail and its log slice.
- **SC-006**: Every step result the run read carries is visible somewhere in the canvas (before
  this feature, none of them were).

## Assumptions

- Entries are recorded by spec 012's Story 1, over the log contract spec 003 already defines.
  This spec adds no recording; until 012 lands, the panel shows the honest empty state, and the
  display contract here is built against the same existing log read.
- The run read already carries each step's state, times, where and as whom it ran, its failure
  reason verbatim, and its stored result with truncation markers; making them visible adds no
  new recorded facts.
- The live view's refresh cadence is unchanged; "within the view's normal refresh" means that
  cadence, whatever it is today.
- Spec 012 keeps the *Runs* history screen, the flow → *Run history* link, the export, and the
  wording for runs that predate recording; a finished run opened from there gets this spec's log
  experience unchanged.
- Search over log text, and retention or deletion of runs and entries, are out of scope.
- All new user-facing text is in English.
