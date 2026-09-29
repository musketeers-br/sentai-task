# Feature Specification: Run Log and Run History

**Feature Branch**: `012-run-log-history`

**Created**: 2026-09-28

**Status**: Merged

**Status note**: PR #19. 21/21 tasks; regression record in evidence/.

**Input**: Competitor analysis (2026-09-28): the contest's *Logs* area is covered only by per-step
states and failure reasons. Review of the product: the live-run view has a **RUN LOG** panel that
always says "No log entries recorded for this run", because nothing ever writes a log entry
(spec 003 HANDOFF item 3); and past runs can only be reached with a link that names them (the
roadmap lists "run history in the canvas" as next). The API already lists runs (`GET /runs`) and
returns a run's log (`GET /runs/{guid}`), and the spec 002 contract already names a history view
(UI-004).

## Context and Problem

An operator who dispatches a flow sees each step's state live. Once the run ends, three things are
missing:

1. **What happened, in order.** The run log is empty. The operator cannot tell when each step
   started, when a target stopped answering, who asked to cancel, or when a re-run was requested,
   without comparing timestamps across nodes.
2. **Where are my earlier runs?** There is no list of runs in the canvas. A run that finished
   while the operator was away, or last night, is unreachable unless they kept its link.
3. **Keeping the evidence.** An operator who must show what ran (to an auditor, or in a ticket)
   has no way to take the run's record out of the product.

## Objective

Every run tells its own story in a chronological log written by the product as it runs. Operators
can find any past run from the canvas, filtered by flow and outcome, open it read-only with its
steps, results and log, and export it as a file.

## Clarifications

### Session 2026-09-28

- Q: What does the log record? → A: Facts the product observes or decides, each with the time,
  the step when there is one, and a severity: run dispatched (by whom, which flow revision),
  each step state change, the platform's failure reason verbatim, requests from operators
  (cancel, pause, re-run: who asked, and the platform's answer when it refused), target
  servers that stop or resume answering, and the run's end with its outcome. Nothing is
  paraphrased from the platform (Constitution III).
- Q: How much history is kept? → A: Everything already stored stays; this feature adds no
  deletion. The list shows the newest runs first, a page at a time.
- Q: Who may see which runs? → A: Whatever the platform lets the operator read. The product adds
  no filter by owner; if the platform refuses the read, its refusal is shown verbatim.
- Q: What about runs dispatched before this feature? → A: They appear in the history with their
  steps and results; their log says it was not recorded for runs before this version.
- Q: What format is the export? → A: One JSON file with exactly what the run view shows (run,
  steps, results, log), named after the flow and the run. A readable format for tickets (text) is
  out of scope.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The run log tells what happened, in order (Priority: P1)

An operator runs a flow. While it runs and after it ends, the **RUN LOG** panel lists what
happened: the dispatch, each step starting and finishing with its duration, failures with the
platform's reason, the join releasing or blocking the next step, and the run's outcome.

**Why this priority**: The empty panel is visible in every run, including the demo and the
screenshots voters see. It is also the product's answer for the *Logs* area.

**Independent Test**: Run the spec 010 example flow; when it ends, the log shows, in time order:
run dispatched by the operator (revision n, 2 steps), both steps started, both finished with
durations, and the run's final state.

**Acceptance Scenarios**:

1. **Given** an operator dispatches a flow, **Then** the first log entry says the run was
   dispatched, by whom, which flow revision, and how many steps.
2. **Given** a step changes state, **Then** an entry records the step, the new state and, for a
   finished step, its duration; a `failed` entry carries the platform's reason verbatim, at
   severity *error*.
3. **Given** a step's inputs failed and the join policy stops it, **Then** an entry says which
   step was not started and which input failed.
4. **Given** an operator cancels or pauses the run or a step, or re-runs a step, **Then** an entry
   records who asked and what; when the platform refused, the entry carries the refusal verbatim
   at severity *warning*.
5. **Given** a target server stops answering during a run, **Then** one *warning* entry records
   it with the transport error, and one *info* entry records when it answers again; repeated
   failed attempts in between do not add entries.
6. **Given** the run ends, **Then** the last entry states the run's outcome and the counts of
   completed, failed and cancelled steps.
7. **Given** the log panel of a live run, **Then** new entries appear within the view's normal
   refresh, and the panel shows entries in time order with the newest visible.

---

### User Story 2 - Find and open past runs (Priority: P1)

An operator opens the **Runs** screen and sees recent runs: flow name, outcome, when it started,
how long it took, who dispatched it, and step counts. They filter by flow or by outcome, open a
run, and see it exactly as the live view shows a finished run: steps with their states, results,
where each ran, and its log. From a flow, *Run history* opens the same list filtered to that flow.

**Why this priority**: Without it, runs are write-only from the canvas. It also gives scheduled
runs (spec 015) a place to be seen.

**Independent Test**: Run the example flow twice and another flow once; open *Runs*: three runs,
newest first; filter by the example flow: two; open the older one: its steps, results and log are
shown and no control acts on it.

**Acceptance Scenarios**:

1. **Given** runs exist, **When** the operator opens *Runs*, **Then** the newest runs are listed
   first, a page at a time, each with flow name, outcome, start time, duration, dispatched by,
   and counts of completed, failed and cancelled steps.
2. **Given** the list, **When** the operator filters by flow and/or outcome, **Then** only
   matching runs are listed, and the filter is kept in the address so reload and back keep it.
3. **Given** more runs than one page, **When** the operator asks for more, **Then** the next older
   page is appended without duplicates, even if new runs started meanwhile.
4. **Given** the operator opens a finished run, **Then** it is shown in the run view with its
   steps, results, where each step ran, and its log; *Pause*, *Cancel* and *Re-run* are not
   offered; *Back to runs* returns to the list with its filters.
5. **Given** the operator opens a run that is still running, **Then** it opens in the live view
   as today.
6. **Given** a flow is open on the canvas, **When** the operator chooses *Run history*, **Then**
   the *Runs* screen opens filtered to that flow.
7. **Given** the platform refuses to list runs, **Then** its reason is shown verbatim instead of
   an empty list.
8. **Given** a run dispatched before this feature, **Then** it is listed and opens normally, and
   its log panel says "No log was recorded for runs before this version."

---

### User Story 3 - Export a run (Priority: P3)

From any run view, the operator chooses *Export* and gets a JSON file with the run, its steps,
their results and the log, named after the flow and the run.

**Why this priority**: Useful for audit and tickets, and cheap once Stories 1 and 2 exist, but not
needed to see or understand a run.

**Independent Test**: Open a finished run, choose *Export*: a file named
`<flow-name>-<run-guid-prefix>.json` is saved; parsing it gives the same step states, results and
log entries as the view.

**Acceptance Scenarios**:

1. **Given** a run view, **When** the operator chooses *Export*, **Then** a JSON file downloads
   containing the run, every step run with its result and failure reason verbatim, and the log in
   time order.
2. **Given** a live run, **Then** *Export* saves the state at that moment and says so in the file
   (`"exportedWhile": "running"`).
3. **Given** the export, **Then** it contains no credential, token or password.

### Edge Cases

- A run with hundreds of steps or a long log: the list and the view stay responsive; the log panel
  scrolls.
- The platform's failure reason is very long: the log entry keeps it whole (the platform's text is
  never truncated); the panel wraps it.
- A step is re-run after a failure: the log shows both attempts; the view shows the latest attempt
  of each step as today.
- Two operators act on the same run: each request is logged with who made it.
- The clock of a target server differs from the primary: log times are the primary's, when the
  product observed the fact.
- The flow of a listed run was renamed: the list shows the flow's current name; the run view
  shows the flow as it is today (runs are not versioned copies of flows, as today).
- Filtering by a flow with no runs shows "No runs for this flow yet", with a way to clear the
  filter.
- A run whose log cannot be written (for example a failed write) still runs; the log is a record,
  never a gate.

## Requirements *(mandatory)*

### Functional Requirements

**Run log**

- **FR-001**: The product MUST append a log entry to a run, with time, step (when applicable),
  severity (*info*, *warning*, *error*) and message, for each of these facts: run dispatched (by
  whom, flow revision, step count); every step state change (for finished steps, the duration);
  a step not started because its join's inputs failed (which input); operator requests to cancel,
  pause or re-run (who, what, and the platform's refusal verbatim if any); a target server that
  stops answering and that answers again; a run credential renewal the platform refused; the
  run's end (outcome and step counts).
- **FR-002**: A failure reason or refusal from the platform MUST appear in the log verbatim and
  whole (Constitution III).
- **FR-003**: Repeated identical transport failures of the same target within one outage MUST
  produce one entry, not one per attempt.
- **FR-004**: Writing a log entry MUST NOT change the outcome of a run or a step; a failed write
  MUST NOT stop the run.
- **FR-005**: The run view's log panel MUST show entries in time order, update while the run is
  live, and distinguish severities visually and by text.

**Run history**

- **FR-006**: The canvas MUST offer a *Runs* screen listing runs newest first, a page at a time
  (default page size 50), with flow name, outcome, start time, duration, dispatched by, and
  completed/failed/cancelled step counts.
- **FR-007**: The list MUST filter by flow and by outcome (running, completed, failed, cancelled),
  and MUST keep the filter and the opened run in the address.
- **FR-008**: Paging MUST be stable: a next page never repeats or skips a run because new runs
  started.
- **FR-009**: Opening a finished run MUST show the run view read-only (no pause, cancel or re-run),
  with steps, results, where each step ran and the log, and a way back to the list.
- **FR-010**: The Flows screen MUST offer *Run history* for the open saved flow, opening *Runs*
  filtered to it.
- **FR-011**: A refusal to list or read runs MUST be shown verbatim.
- **FR-012**: Runs that predate this feature MUST be listed and opened; their empty log MUST be
  explained, not shown as an error.

**Export**

- **FR-013**: Any run view MUST offer *Export*, producing a JSON file with the run, all step runs
  with results and failure reasons, and the log in time order, named
  `<flow-name>-<first 8 characters of the run guid>.json`.
- **FR-014**: The export MUST NOT include credentials or tokens, and MUST mark a run exported while
  running.

**Language**

- **FR-015**: All new user-facing text MUST be in English.

### Key Entities

- **Log entry** (exists, now written): run, time, step (optional), severity, message.
- **Run summary** (list item): run guid, flow id and current name, flow revision, outcome, start,
  finish, duration, dispatched by, step counts by state.
- **Run page**: an ordered slice of run summaries plus a cursor that continues after the last one.
- **Run export**: a file with the run detail, as the view shows it, plus export time and whether
  the run was still running.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of runs dispatched after this feature have a non-empty log whose first entry is
  the dispatch and whose last entry (for a finished run) is its outcome.
- **SC-002**: For a run with a failed step, an operator identifies from the log alone which step
  failed first and the platform's reason, in under 30 seconds.
- **SC-003**: An operator finds a specific run from yesterday, knowing only its flow, in at most 3
  actions from the canvas.
- **SC-004**: The *Runs* screen shows its first page within 1 second with 5,000 runs stored.
- **SC-005**: An exported run, parsed, matches the view's step states, results and log entries
  exactly (100% of fields compared in the test).
- **SC-006**: During a 10-minute outage of a target server, the log gains at most 2 entries about
  it (stopped, resumed).

## Assumptions

- The existing log storage and its "newest first" read (spec 003 FR-025) are kept; the canvas
  orders entries for display.
- The existing run list contract (`GET /runs` with `flowId` and `limit`) is extended with an
  outcome filter, a cursor and summary fields; the Plan records the delta.
- Deleting runs, retention policies and searching log text are out of scope.
- The scheduled-run trigger (who or what started a run) is added by spec 015 to the same summary;
  this spec shows "dispatched by" as today.
- The live view's refresh cadence (polling) is unchanged.
