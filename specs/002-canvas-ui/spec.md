# Feature Specification: Canvas UI

**Feature**: 002-canvas-ui

**Created**: 2026-09-21

**Status**: Implemented

**Deadline**: 2026-09-27 (InterSystems Programming Contest)

## Scope

SentaiTask Canvas UI delivers a visual flow-composition and execution surface for InterSystems
IRIS maintenance operations. This spec covers five of the seven screens in the design export:
[UI-001 Flow Canvas](contracts/ui/UI-001-flow-canvas.md) (compose a DAG of steps, inspect and
validate it, schedule it), [UI-002 Live Run](contracts/ui/UI-002-live-run.md) (execute a flow
with real-time per-step state and per-step/per-wave control),
[UI-005 WQM Category](contracts/ui/UI-005-wqm-category.md) (read and edit Work Queue Manager
worker ceilings), [UI-006 Design System](contracts/ui/UI-006-design-system.md) (the normative
sheet for state shapes, tokens, typography, edges and handles — referenced by every other
screen, not a route), and [UI-007 Theming Parity](contracts/ui/UI-007-theming-parity.md) (the
light theme, designed independently rather than derived). The execution model is a flow
persisted and dispatched through the product's own `SENTAI.*` ObjectScript classes — flow,
step, edge and run persistence, wave dispatch, and the `^SentaiRun` GUID registry — not the
SysAdmin REST API's task-creation surface, whose GUID-exposure gap was closed as *not viable*
in spec 001.

This spec cuts UI-003 Task Catalog and UI-004 Run History/Timeline, and their data-model
entities, to spec 003. Within the five screens kept, join policy is fixed at
`ALL_MUST_SUCCEED` (no per-join configuration), precondition evaluation is limited to a single
hard-coded check — database-directory mount status — rather than a general `SENTAI.Precondition`
engine (see Clarifications), and the custom step type is declared in the type registry and
selectable from the palette, but always fails validation until a real subclass exists (see
Clarifications). Out of scope entirely: AI/LLM features of any kind, log analysis,
telemetry-based remediation, semantic search, mobile or responsive layout, multi-user
concurrency, and the prohibited reactive loop (telemetry → LLM hypothesis → action).

## Clarifications

### Session 2026-09-21

- Q: When the only precondition check available in v1 is namespace existence (no
  `SENTAI.Precondition`), how should validation handle the "precondition not met" scenario that
  UI-001 requires as binding evidence? → A: Implement a minimal precondition check anyway (e.g.,
  whether the step's database directory is mounted read-only), scoped outside the general
  `SENTAI.Precondition` engine, solely to satisfy the UI-001 canonical example.
- Q: With the join policy fixed at `ALL_MUST_SUCCEED`, what state does the join (target) step
  reach when a required input fails? → A: The join transitions to `failed`, with
  `failureReason` naming the input step that failed — it reuses the existing six-state closed
  set rather than introducing a seventh state.
- Q: Does the product's own REST API (`SENTAI.REST.Dispatcher`, base `/csp/sentai/api/v1`) use
  the same 60-second SysAdmin token mechanism, or a separate CSP/IRIS session? → A: The same
  60-second JWT login/refresh mechanism is used for every call, both SysAdmin and
  `SENTAI.REST.Dispatcher` — one authentication model across the whole product.
- Q: Should the `custom` step type appear in the UI-001 palette in v1, given it has no real
  `%SYS.Task.Definition` subclass behind it? → A: `CUSTOM` appears in the palette and can be
  dragged onto the canvas; validation always blocks it with an explicit error ("Custom step
  requires a class") until a subclass is declared — never a silently incomplete state.

## Execution Flow

The operator's journey through the five screens, end to end:

1. **Compose** — on [UI-001](contracts/ui/UI-001-flow-canvas.md), drag step types from the
   palette onto the canvas, connect edges to form a DAG, and configure each step's identity,
   parameters and destructive marking through the inspector.
2. **Validate** — request validation; the canvas runs cycle detection and precondition checks
   and reports errors and warnings in the status bar. Warnings do not block scheduling; errors
   do.
3. **Schedule** — invoke *Schedule in Task Manager*; the ObjectScript backend compiles the
   flow's steps into native `%SYS.Task.Definition` entries.
4. **Dispatch** — trigger a run; every step already has a `StepRun` row with a GUID and
   `TimeQueued` before dispatch returns, and the platform's Work Queue Manager begins
   executing the first wave.
5. **Monitor** — on [UI-002](contracts/ui/UI-002-live-run.md), watch per-step state transition
   through all six states, read progress and failure reasons, and pause, resume, cancel or
   re-run at the step or wave level.
6. **Review** — read the run's outcome from the right rail's per-step list and run log while
   the run screen is open. A persisted, browsable run history across past runs is **deferred**
   to spec 003 (UI-004); this spec does not deliver a history route.

## Questions to Answer

Each question is a capability the implementation must demonstrate with committed evidence,
following the pattern of spec 001. Every question closes with a reproducible artifact, not a
verbal report.

### Q1 — Flow composition

Can the operator drag steps from the palette, connect edges, and see the DAG rendered with a
fan-in edge, matching [UI-001](contracts/ui/UI-001-flow-canvas.md)?

### Q2 — Node anatomy

Does a custom node match the anatomy in UI-001 — hazard band (destructive only), namespace
chip, database directory, timeout, WQM category, and left/right handles — with the step-type
category colour on its left border, never a state colour?

### Q3 — Inspector

Does clicking a node open the inspector with the sections from UI-001 in order —
`SELECTED STEP` → `IDENTIFICATION` → `PARAMETERS` → destructive block (if any) → `OUTPUT`?

### Q4 — Validation

Does the canvas validate the graph — cycle detection, precondition warnings, destructive
marking — and report the result in the status bar in the format `N steps · N join · N
destructive` plus `N precondition not met (#NN)`?

### Q5 — Schedule

Does *Schedule in Task Manager* compile the flow to native IRIS task definitions via the
`SENTAI.*` ObjectScript backend, returning task identifiers and the next run time?

### Q6 — Live run

Does dispatching a flow show real-time per-step state — all six states reachable — with the
wave progress bar matching [UI-002](contracts/ui/UI-002-live-run.md), including the count line
`N completed · N failed · N running · N queued`?

### Q7 — Per-step control

Do pause, resume and cancel work at both the per-step and per-wave level, with state
transitions reflected in the UI within 2 seconds (NFR-001)?

### Q8 — Token lifecycle

Does the auth layer refresh the 60-second access token (spec 001 deviation: `exp - iat = 60`)
transparently during a long polling session — for every call, including
`SENTAI.REST.Dispatcher` calls, not only the SysAdmin API — with no user-visible interruption?

### Q9 — WQM

Can the operator read and edit category ceilings matching
[UI-005](contracts/ui/UI-005-wqm-category.md), including the four-bar nesting diagram and the
recomputed prediction sentence?

### Q10 — Theming

Do both the dark theme (default) and the light theme render correctly per
[UI-006](contracts/ui/UI-006-design-system.md) and [UI-007](contracts/ui/UI-007-theming-parity.md),
with every applicable token from [`contracts/tokens.json`](contracts/tokens.json) applied and no
light value computed from its dark counterpart?

## User Scenarios & Testing

### User Story 1 — Flow Composition (Priority: P1)

An operator opens the flow canvas, drags step types from the palette onto the canvas, connects
them into a DAG including a three-into-one fan-in, and sees each node render its full anatomy —
category colour, namespace, database directory, timeout, WQM category and handles.

**Why this priority**: Without composition there is no flow to run. This is the minimum
demonstrable artifact.

**Independent Test**: Build the five-step canonical graph from UI-001 on a fresh canvas and
verify it renders as specified. Covers Q1 + Q2.

**Acceptance Scenarios**:

1. **Given** an empty canvas, **When** the operator drags an `integrity-check` step from the
   palette, **Then** a node appears with the category colour on its left border and empty
   handles on both edges.
2. **Given** three integrity-check nodes and one purge-audit node, **When** the operator draws
   an edge from each integrity-check node to the purge node, **Then** the three edges converge
   into one shared diamond junction at the purge node's input handle.
3. **Given** a destructive step type is placed, **When** the node renders, **Then** it shows
   the hazard band, the `DESTRUCTIVE` text seal, and its left border in the step-type category
   colour — never a state colour.

---

### User Story 2 — Inspector and Validation (Priority: P1)

An operator clicks a node, edits its identification, parameters and destructive confirmation
setting through the inspector, then requests validation and reads the result from the status
bar.

**Why this priority**: Configuration and validation gate scheduling; without them the canvas is
a drawing tool, not an orchestrator.

**Independent Test**: Click a node, edit its `TaskName` and `Timeout (min)`, request
validation against a flow containing an intentionally unmet precondition, and verify both the
inspector fields and the status bar count. Covers Q3 + Q4.

**Acceptance Scenarios**:

1. **Given** the canvas is loaded, **When** the operator clicks a node, **Then** the inspector
   opens with sections in order: `SELECTED STEP`, `IDENTIFICATION`, `PARAMETERS`, destructive
   block (if applicable), `OUTPUT`.
2. **Given** a destructive step is selected, **When** the operator reads the destructive block,
   **Then** it states the consequence in plain words and shows the checked
   *"Require the database name to be typed before running"* control.
3. **Given** a step's precondition is not met on the live instance, **When** the operator
   requests validation, **Then** the node shows the warning panel with the condition in plain
   words and the status bar reports `1 precondition not met (#NN)`, and scheduling remains
   available.
4. **Given** the edge set contains a cycle, **When** the operator requests validation, **Then**
   the status bar reports the cycle as an error and *Schedule in Task Manager* is blocked.

---

### User Story 3 — Schedule (Priority: P1)

An operator, having validated a flow with no errors, invokes *Schedule in Task Manager* and the
flow's steps are compiled into native IRIS task definitions.

**Why this priority**: Scheduling is the bridge from composition to execution; without it a
validated flow is inert.

**Independent Test**: Validate a flow with zero errors, click *Schedule in Task Manager*, and
verify task identifiers and a next-run time are returned. Covers Q5.

**Acceptance Scenarios**:

1. **Given** a flow with no validation errors, **When** the operator clicks
   *Schedule in Task Manager*, **Then** the backend returns one task identifier per scheduled
   step and a `nextRun` timestamp.
2. **Given** a flow with at least one validation error, **When** the operator attempts to
   schedule, **Then** the action is unavailable and the status bar's error count explains why.

---

### User Story 4 — Live Run and Per-Step Control (Priority: P1)

An operator dispatches a flow and watches it execute on the live-run screen: every step's state
is visible in real time, a failed step shows its failure reason verbatim, and the operator can
pause, resume, cancel or re-run at the step level, or pause/cancel the whole wave.

**Why this priority**: Execution and control is the core value proposition — the operator acts
on the platform, not just reads from it.

**Independent Test**: Dispatch the canonical five-step flow, observe at least four of the six
states live (completed, failed, running, queued), pause and cancel one running step
independently of the rest of the wave, and verify the join policy panel appears once an input
has failed. Covers Q6 + Q7 + Q8.

**Acceptance Scenarios**:

1. **Given** a flow is dispatched, **When** the run screen loads, **Then** every step already
   has a `StepRun` GUID and `TimeQueued`, and the wave progress bar shows one segment per step
   with the count line `N completed · N failed · N running · N queued`.
2. **Given** a step is running, **When** the operator clicks its per-step *Pause*, **Then**
   only that step transitions to `PAUSED` and the rest of the wave is unaffected.
3. **Given** a step is running, **When** the operator clicks its per-step *Cancel*, **Then**
   only that step transitions to `CANCELLED`; sibling steps continue (scenario 7 of UI-002).
4. **Given** a join's input step has failed, **When** the canvas renders the join, **Then** the
   `JOIN POLICY` panel states the `ALL_MUST_SUCCEED` policy and names the input that failed, and
   the join step itself transitions to `failed` with a `failureReason` naming that input.
5. **Given** a step has failed, **When** the operator reads its `FAILURE REASON` panel,
   **Then** the string is shown byte-for-byte as IRIS produced it, with a *Re-run step* action
   available.
6. **Given** a run's polling session exceeds 60 seconds, **When** the access token expires
   mid-session, **Then** the auth layer refreshes it transparently and no state update is
   missed or delayed beyond 2 seconds (NFR-001).
7. **Given** the top bar's *Cancel wave* is clicked, **When** the operator confirms the
   destructive-styled confirmation naming the run, **Then** dispatch of not-yet-started steps
   stops and cancellation is requested for anything running.

---

### User Story 5 — Resource Ceiling Management (Priority: P2)

An operator opens the WQM category screen, reads the nesting diagram and the recomputed
prediction sentence, edits a ceiling, and sees the impact notice before saving.

**Why this priority**: Resource management is a secondary function that protects the execution
in User Story 4; it does not itself gate composition or scheduling.

**Independent Test**: Open the WQM screen for a category with at least one dependent flow,
change `MaxActiveWorkers`, verify the nesting diagram and prediction sentence recompute, and
save. Covers Q9.

**Acceptance Scenarios**:

1. **Given** the WQM screen is open, **When** the operator reads it, **Then** all four bars
   (`MaxTotalWorkers`, `MaxWorkers`, `MaxActiveWorkers`, `DefaultWorkers`) render in descending
   order with widths proportional to `MaxTotalWorkers`.
2. **Given** the operator changes a field's value, **When** the change is entered, **Then** the
   prediction sentence beneath the diagram recomputes without a page reload.
3. **Given** the operator enters values that violate
   `defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers`, **When** save is
   attempted, **Then** the invariant is reported as a validation error, not a warning, and the
   save is blocked.
4. **Given** valid changed values, **When** the operator clicks *Save category*, **Then** the
   impact notice's task count and in-flight-runs rule are shown before the write completes.

---

### User Story 6 — Theming Parity (Priority: P2)

An operator switches the theme control between `Dark` and `Light` on any screen and every
region, string, and state shape renders identically in structure while colour tokens differ per
theme, per [UI-007](contracts/ui/UI-007-theming-parity.md).

**Why this priority**: Theming parity is cross-cutting evidence that the token system (UI-006)
was applied consistently rather than retrofitted; it depends on the other screens existing.

**Independent Test**: Render the flow canvas in both themes at the contract viewport and diff
structurally. Covers Q10.

**Acceptance Scenarios**:

1. **Given** the flow canvas is rendered in dark theme, **When** the operator switches to
   light, **Then** every structural region, string and state shape from UI-001 is still
   present, and only colour, elevation and selection treatment differ.
2. **Given** both themes are rendered, **When** every token in `tokens.json` is inspected,
   **Then** no light-theme value equals the computed inverse of its dark-theme value.

---

### Edge Cases

- What happens when the operator tries to schedule a flow with a validation error present? The
  action is unavailable; the status bar names the error and the affected step.
- What happens when a step's precondition becomes unmet between validation and dispatch? The
  dispatch-time evaluation is authoritative (spec 001 R-006 pattern); the run reflects the
  actual outcome, not the stale validation result.
- What happens when a destructive step's typed confirmation does not match the required name?
  Dispatch is refused (HTTP 428 per [`openapi.yaml`](contracts/openapi.yaml)) and the operator
  is told which step's confirmation failed.
- What happens when a step type cannot honour pause (per its registry entry)? The per-step
  *Pause* action is not offered for that step; *Cancel* remains available.
- What happens when an access-token refresh fails mid-run (e.g., the IRIS instance restarted)?
  The UI shows a re-authentication prompt rather than silently dropping state updates.
- What happens when the WQM nesting invariant is already violated on read (pre-existing bad
  data)? The screen still renders the current values and flags the violation as an error before
  any save is attempted.
- What happens when a join has more than three incoming edges? All incoming edges still
  converge into exactly one diamond junction at the target, per UI-001.
- What happens when a `custom` step is placed and validated without a `customClass` value? The
  status bar reports it as a blocking error ("Custom step requires a class"), never a silently
  passing or partially-configured state.

## Requirements

### Functional Requirements

- **FR-001**: The canvas MUST let the operator drag step types from the palette onto the
  canvas, creating a node per drop. This includes the `CUSTOM` category from UI-001; a `custom`
  node can be placed and configured, but its `customClass` field has no default and validation
  MUST reject it with an explicit error until a class name is supplied. *(UI-001; Constitution
  II — closed, declared step-type registry; Clarifications 2026-09-21)*
- **FR-002**: The canvas MUST let the operator connect two nodes with a directed edge, and
  MUST reject an edge that would introduce a cycle at the moment it is drawn. *(UI-001,
  data-model.md §Edge)*
- **FR-003**: The edge set MUST remain acyclic at all times; cycle detection MUST run on every
  mutation, not only on save or validate. *(UI-001, data-model.md §Edge)*
- **FR-004**: A target node with two or more incoming edges MUST render as a fan-in: all
  incoming edges share one diamond junction, drawn once per target, followed by a single arrow
  into the target's diamond handle. *(UI-001)*
- **FR-005**: Sequence edges MUST render at 1.5px stroke width in the `edge.sequence` token;
  join edges MUST render at 2.5px in the `edge.join` token. *(UI-001, UI-006)*
- **FR-006**: Each node MUST render its full anatomy: hazard band (destructive steps only),
  title with `#NN` id, namespace chip, database directory (where applicable), a divider, then
  timeout and WQM category. *(UI-001)*
- **FR-007**: A node's left border MUST carry its step-type category colour, 3px, and MUST
  NEVER carry a state colour. *(UI-001, UI-006, Constitution II)*
- **FR-008**: When a step's precondition is not met, the node MUST show the warning border
  token, an inset panel with a warning triangle, the title "Precondition not met", and the
  condition stated in plain words naming what the step needs. In v1 the only live precondition
  evaluated is database-directory mount status (read-only); it is a single hard-coded check, not
  a general precondition engine. *(UI-001, Clarifications 2026-09-21)*
- **FR-009**: The status bar MUST count precondition warnings in the format
  `N precondition not met (#NN, …)`. *(UI-001)*
- **FR-010**: A precondition warning MUST NOT block scheduling. Only validation errors (cycles,
  invalid parameters, unresolvable namespaces) block scheduling. *(UI-001, openapi.yaml
  §/flows/{flowId}/validate)*
- **FR-011**: Every destructive step MUST carry all three signals together, at every zoom level
  and density mode: the hazard band, the `DESTRUCTIVE` text seal with warning triangle, and a
  typed-confirmation control in the inspector's destructive block. No signal may be dropped, and
  none may stand alone. *(UI-001, UI-006, Constitution I)*
- **FR-012**: `isDestructive` MUST be derived from the step type registry; it MUST NOT be an
  operator-editable field. *(data-model.md §Step, Constitution I)*
- **FR-013**: Dispatch of a flow containing a destructive step MUST require the typed
  confirmation for that step (the database or namespace name) before the run starts, and the
  confirming user MUST be recorded and shown in the run log. *(UI-002, openapi.yaml
  §/flows/{flowId}/dispatch, Constitution I)*
- **FR-014**: Clicking a node MUST open the inspector with sections in this exact order:
  `SELECTED STEP`, `IDENTIFICATION` (TaskName, Namespace, Run as user), `PARAMETERS`
  (type-specific fields, then Timeout (min), then WQM category), destructive block (if
  applicable), `OUTPUT`. *(UI-001)*
- **FR-015**: The inspector's `OUTPUT` section MUST show where the step's GUID lands, in the
  form `stepNN.guid → ^SentaiRun(runId,"NN")`. *(UI-001, data-model.md §GUID registry,
  Constitution III)*
- **FR-016**: Every inspector field MUST be a real `<input>` with a real `<label>`; no `div`
  with a `role` attribute may substitute for a form control. *(UI-001, UI-006 §Accessibility)*
- **FR-017**: The canvas MUST support zoom in, zoom out, fit view and lock, as icon-only
  buttons in the bottom-left, each carrying an `aria-label` and no emoji glyph. *(UI-001,
  UI-006)*
- **FR-018**: The canvas MUST render a minimap, bottom-right, 168×104, showing nodes as blocks
  in their step-type category colour and the viewport as an outlined rectangle. *(UI-001)*
- **FR-019**: *Validate flow* MUST run cycle detection, parameter-schema validation, and the
  database-directory mount-status precondition check, and MUST report the result as a
  `ValidationReport` with separate `errors` (block scheduling) and `warnings` (do not block
  scheduling). *(UI-001, openapi.yaml §ValidationReport, Clarifications 2026-09-21)*
- **FR-020**: *Schedule in Task Manager* MUST compile the flow's steps into native
  `%SYS.Task.Definition` entries via the `SENTAI.*` ObjectScript backend and MUST NOT start a
  private, in-process scheduler. *(UI-001, openapi.yaml §/flows/{flowId}/schedule, Constitution
  I)*
- **FR-021**: Dispatch MUST return the run GUID synchronously, and every step MUST already have
  a `StepRun` row with a GUID and `TimeQueued` populated before dispatch responds. *(UI-002,
  openapi.yaml §/flows/{flowId}/dispatch, data-model.md §StepRun, Constitution III)*
- **FR-022**: Every node on the live-run screen MUST carry a state chip — shape glyph plus
  uppercase monospace state name — for one of the six closed states: `queued`, `running`,
  `paused`, `completed`, `failed`, `cancelled`. The shape is normative per UI-006 and MUST NOT
  vary; only its colour token may. *(UI-002, UI-006, Constitution II)*
- **FR-023**: The wave progress bar MUST render one segment per step in flow order, equal
  width, with the running segment filling proportionally to progress and the failed segment
  using the hazard stripe pattern. *(UI-002)*
- **FR-024**: The wave progress count line MUST render verbatim as
  `N completed · N failed · N running · N queued`, alongside `ELAPSED` and `START` in tabular
  monospace figures. *(UI-002)*
- **FR-025**: A running node MUST show its elapsed time in the largest monospace on the node,
  and its progress as a bar plus literal counts where the step type reports progress; where the
  type reports none, no fake indeterminate animation may be shown. *(UI-002)*
- **FR-026**: A failed node's `FAILURE REASON` panel MUST show the string exactly as IRIS
  produced it — not summarised, sentence-cased, or truncated — and MUST offer *Re-run step*.
  The `failureReason` field MUST be stored and displayed byte-for-byte. *(UI-002, data-model.md
  §StepRun, openapi.yaml §StepRun, Constitution IV)*
- **FR-027**: The edge leaving a failed node MUST render dashed in the failure token so the
  break in the wave is visible at zoom-out. *(UI-002)*
- **FR-028**: Whenever any join input has failed, the `JOIN POLICY` panel MUST appear near the
  join, stating the policy in force (`ALL_MUST_SUCCEED`) and which required input(s) did not
  complete. *(UI-002, data-model.md §Join, openapi.yaml §JoinPolicy)*
- **FR-029**: The join policy in force for this spec MUST be `ALL_MUST_SUCCEED`; per-join
  policy configuration is deferred. When any required input fails, the join step itself MUST
  transition to `failed`, with `failureReason` naming the input step that failed — no new state
  is introduced. *(data-model.md §Join, §StepRun, Clarifications 2026-09-21)*
- **FR-030**: Pause and cancel MUST be offered per step, inside the node, and MUST act on that
  step alone without affecting sibling steps in the same wave. *(UI-002, openapi.yaml
  §/runs/{runGuid}/steps/{stepGuid}/{cancel,pause})*
- **FR-031**: *Pause wave* and *Cancel wave* MUST act on the whole run: pause suspends dispatch
  of not-yet-started steps, and cancel — styled in the destructive token and requiring
  confirmation naming the run — stops dispatch of anything not yet started and requests
  cancellation of what is running. *(UI-002, openapi.yaml §/runs/{runGuid}/{cancel,pause})*
- **FR-032**: State changes MUST reach the client within 2 seconds of occurring on the platform
  (NFR-001), whether delivered by a live stream or by polling. *(UI-002, openapi.yaml
  §/runs/{runGuid}/events)*
- **FR-033**: The right rail MUST render, in order: `RUN GUIDS` (full, selectable, never
  truncated), the per-step list (shape glyph, `#NN` + name, duration right-aligned in tabular
  figures, bold for the running step, `—` for a queued step), the six-state key
  `STATES — SHAPE BEFORE COLOUR` as a permanent legend, and `RUN LOG` (newest first, monospace,
  timestamped, with destructive confirmations logged against the confirming user). *(UI-002,
  Constitution II)*
- **FR-034**: The access-token refresh MUST occur proactively, before the 60-second token
  expires, and MUST NOT interrupt an active polling or streaming session. The same login/refresh
  token pair from spec 001 authenticates every call, including calls to
  `SENTAI.REST.Dispatcher` (`/csp/sentai/api/v1`), not only the SysAdmin API. *(spec 001
  compatibility.md §Deviations, openapi.yaml §/runs/{runGuid}/events, Clarifications
  2026-09-21)*
- **FR-035**: The WQM screen MUST render the four-bar nesting diagram in descending order —
  `MaxTotalWorkers`, `MaxWorkers`, `MaxActiveWorkers`, `DefaultWorkers` — each proportional to
  `MaxTotalWorkers`, plus a prediction sentence that recomputes on every field change. *(UI-005)*
- **FR-036**: The WQM nesting invariant
  `defaultWorkers ≤ maxActiveWorkers ≤ maxWorkers ≤ maxTotalWorkers` MUST be enforced as a
  validation error, not a warning, blocking save. *(UI-005, data-model.md §WQM category,
  openapi.yaml §PUT /wqm/categories/{name})*
- **FR-037**: Before save, the system MUST count and display how many scheduled tasks outside
  the current flow use the category, plus the rule that a change takes effect on the next
  dispatch and never affects a run already in flight. *(UI-005, openapi.yaml
  §affectedTaskCount)*
- **FR-038**: Both the dark theme (default) and the light theme MUST be applied by setting
  `data-theme` on `:root`; no component may read the theme in script to pick a colour, and no
  light-theme token value may be computed from its dark-theme counterpart. *(UI-006, UI-007,
  Constitution VI)*

### Key Entities

Entity definitions and rules are authoritative in [`contracts/data-model.md`](contracts/data-model.md);
summarised here for traceability:

- **Flow** (`SENTAI.Model.Flow`): a named, versioned DAG of steps the operator composes. Every
  save bumps `revision`; a run pins the revision it started with.
- **Step** (`SENTAI.Model.Step`): one node — a step type plus its configuration. `isDestructive`
  is derived from the type registry, never operator input.
- **Edge** (`SENTAI.Model.Edge`): a directed dependency between two steps. The set MUST stay
  acyclic.
- **Join** (`SENTAI.Model.Join`): the incoming-edge set of a step with ≥2 inputs, plus its
  policy — fixed at `ALL_MUST_SUCCEED` in this spec.
- **Run** (`SENTAI.Model.Run`): one execution of one flow revision, identified by a GUID from
  `$SYSTEM.Util.CreateGUID()`.
- **StepRun** (`SENTAI.Model.StepRun`): one execution of one step within a run, carrying the
  six-state machine, timings, failure reason and progress.
- **WQM category** (`SENTAI.Model.Category`): the Work Queue Manager worker-ceiling
  configuration, subject to the nesting invariant.
- **GUID registry** (`^SentaiRun`): written inside the dispatch transaction; resolves a GUID
  found in `messages.log` to a run and step in one lookup.

## Acceptance Criteria

- **[Q1]** is accepted when a screenshot of the flow canvas shows the five-step canonical graph
  with a 3-into-1 fan-in rendered as a shared diamond junction, demonstrated against
  [`contracts/screens/Main.png`](contracts/screens/Main.png).
- **[Q2]** is accepted when a screenshot shows a destructive node carrying its hazard band,
  namespace chip, database directory, timeout, WQM category and category-coloured left border,
  demonstrated against [`contracts/screens/Main.png`](contracts/screens/Main.png).
- **[Q3]** is accepted when a screenshot shows the inspector open with its five sections in the
  bound order for a selected node, demonstrated against
  [`contracts/ui/UI-001-flow-canvas.md`](contracts/ui/UI-001-flow-canvas.md) §Inspector.
- **[Q4]** is accepted when a `ValidationReport` JSON capture shows at least one error and one
  warning, and the corresponding screenshot shows the status bar's counts matching that report.
- **[Q5]** is accepted when a JSON capture of `POST /flows/{flowId}/schedule` shows returned
  `taskIds` and `nextRun` for a flow with no validation errors.
- **[Q6]** is accepted when a screenshot of the live-run screen shows at least four of the six
  states simultaneously live, with the wave progress bar and count line matching
  [`contracts/screens/LiveRun.png`](contracts/screens/LiveRun.png).
- **[Q7]** is accepted when a JSON state log shows a per-step pause/cancel and a per-wave
  pause/cancel each transitioning only their intended scope, with transitions timestamped
  within 2 seconds of the triggering call.
- **[Q8]** is accepted when a JSON log shows at least two token refreshes during a live-run
  polling or streaming session exceeding 60 seconds, with zero user-visible interruption.
- **[Q9]** is accepted when a screenshot of the WQM screen shows the four-bar nesting diagram
  and recomputed prediction sentence, demonstrated against
  [`contracts/screens/WQM.png`](contracts/screens/WQM.png), plus a JSON capture of a save that
  is blocked by the nesting-invariant validation error.
- **[Q10]** is accepted when paired dark/light screenshots of the flow canvas
  ([`contracts/screens/Main.png`](contracts/screens/Main.png) and
  [`contracts/screens/FlowLight.png`](contracts/screens/FlowLight.png)) pass the structural,
  string and contrast assertions in both themes, and a token audit shows no light value equal
  to the computed inverse of its dark value.

## Evidence Contract

Evidence files MUST be committed to `specs/002-canvas-ui/evidence/`. Screenshots MUST be
captured at the contract viewport and scale for the screen under test — 1440×900 dark
(deviceScaleFactor 2) for canvas and live-run captures, 1440×900 light for the UI-007 pair, and
1100×1000 light for the WQM capture — per [`contracts/README.md`](contracts/README.md)
§How they are tested.

| Evidence ID | Type | Description |
|---|---|---|
| `q1-flow-composition.png` | Screenshot (1440×900 dark) | Canonical graph with fan-in rendered |
| `q2-node-anatomy.png` | Screenshot (1440×900 dark) | Destructive node showing all anatomy elements |
| `q3-inspector.png` | Screenshot (1440×900 dark) | Inspector open, sections in bound order |
| `q4-validation-report.json` | JSON | `ValidationReport` with ≥1 error and ≥1 warning |
| `q4-status-bar.png` | Screenshot (1440×900 dark) | Status bar counts matching the report |
| `q5-schedule.json` | JSON | `POST /flows/{flowId}/schedule` request + response |
| `q6-live-run.png` | Screenshot (1440×900 dark) | Wave progress bar + ≥4 live states |
| `q7-step-control.json` | JSON | State log: per-step pause/cancel, per-wave pause/cancel, timestamps |
| `q8-token-lifecycle.json` | JSON | ≥2 token refreshes during a >60s live-run session |
| `q9-wqm-diagram.png` | Screenshot (1100×1000 light) | Nesting diagram + prediction sentence |
| `q9-wqm-invariant-block.json` | JSON | Save attempt blocked by the nesting invariant |
| `q10-theming-dark.png` | Screenshot (1440×900 dark) | Flow canvas, dark |
| `q10-theming-light.png` | Screenshot (1440×900 light) | Flow canvas, light — [`contracts/screens/FlowLight.png`](contracts/screens/FlowLight.png) |
| `q10-token-audit.json` | JSON | Per-token dark/light value pairs with an inverse check |

JSON evidence follows the spec 001 envelope (`call_id`, `captured_at`, `platform`, `request`,
`response`, `notes`) where the capture is an API call, or the simplified UI-log schema from the
prior spec 002 for state logs:

```json
{
  "evidence_id": "string",
  "captured_at": "ISO-8601",
  "entries": [{ "timestamp": "ISO-8601", "event": "string", "detail": {} }]
}
```

## Constraints

### From the Constitution

- **Principle I (Layered Architecture)**: Canvas, inspector and run-rail components (presentation)
  MUST NOT reach into `SENTAI.*` persistence directly; they cross the layer boundary only
  through the REST surface in [`contracts/openapi.yaml`](contracts/openapi.yaml).
- **Principle II (Closed Capability Set)**: The step-type registry (data-model.md §Step types)
  is the only source of what a step can be. No user-supplied code, expression field, or
  dynamically dispatched class name may extend it at runtime.
- **Principle III (Delegated Authorization)**: Every REST call carries the operator's IRIS
  credentials; the front end MUST NOT cache or infer permission outcomes across requests.
- **Principle IV (Errors as Values)**: Validation errors, dispatch failures (HTTP 428), and
  `failureReason` strings are surfaced verbatim, never paraphrased or swallowed.
- **Principle V (Verifiable Increments)**: Each user story above is independently demonstrable
  with its own evidence set, per the Evidence Contract.
- **Principle VI (Technology Agnosticism)**: This spec names SvelteKit, Svelte Flow and
  ObjectScript only as the problem domain the Plan already committed to; no new technology
  choice is introduced here.

### From Spec 001

- **Token TTL = 60s**: refresh MUST be proactive, not a reaction to a 401 (FR-034). This applies
  to every call the front end makes, including calls to the product's own
  `SENTAI.REST.Dispatcher`, which authenticates with the same token pair rather than a separate
  CSP session (Clarifications 2026-09-21).
- **`POST /v2/task` requires all 31 fields, returns no identifier, and no read endpoint exposes
  a task's own GUID**: the SysAdmin REST API's task-creation surface is not used for flow
  dispatch. The `SENTAI.*` ObjectScript backend bypasses this gap by generating GUIDs via
  `$SYSTEM.Util.CreateGUID()` and registering them in `^SentaiRun` before a step leaves
  `queued` (FR-021, data-model.md §GUID registry).
- **Decision (delegate parallel execution to platform)**: wave dispatch relies on the
  platform's own async-job and Work Queue Manager mechanisms; this product does not build its
  own execution engine.

### From Design (binding)

- [`contracts/tokens.json`](contracts/tokens.json) is the machine-readable source of truth for
  every colour, size, radius, spacing and typography value. Where any screen image and
  `tokens.json` disagree, `tokens.json` is correct and the image is regenerated.
- [UI-006](contracts/ui/UI-006-design-system.md) is normative for state shapes, edge treatment
  and handle geometry. Where any other screen contract disagrees with UI-006 about a shape or a
  token, UI-006 wins and the other screen is the defect.
- The six job-state shapes are a closed set (`queued`, `running`, `paused`, `completed`,
  `failed`, `cancelled`); a seventh state requires a constitutional amendment, not a spec
  change.

### Explicit Exclusions

- AI/LLM features of any kind.
- Log analysis, telemetry-based remediation, semantic search.
- The prohibited reactive loop: telemetry → LLM hypothesis → action.
- Mobile or responsive layout (desktop operations console only, per
  [`contracts/README.md`](contracts/README.md) §What it does not bind).
- Multi-user concurrency.
- Task catalog (UI-003) and run history/timeline (UI-004) — deferred to spec 003.
- Per-join policy configuration (fixed at `ALL_MUST_SUCCEED`), a general `SENTAI.Precondition`
  evaluation engine (v1 ships one hard-coded check only — see Clarifications), and a working
  `custom` step (declared and placeable in v1, but never passes validation without a real
  `%SYS.Task.Definition` subclass — see Clarifications).

## Dependencies

- **[Spec 001 compatibility.md](../001-validate-async-job-contract/compatibility.md)** and
  **[decision.md](../001-validate-async-job-contract/decision.md)**: ground truth for the token
  TTL, the API deviations, and the delegate-to-platform execution decision. Not re-validated
  here.
- **Design contracts**: [`contracts/README.md`](contracts/README.md),
  [`contracts/tokens.json`](contracts/tokens.json), the five screen images under
  `contracts/screens/`, and the five UI contracts under `contracts/ui/` — binding per the rules
  in `contracts/README.md` §Why the PNGs are contracts and not mockups.
- **[`contracts/data-model.md`](contracts/data-model.md)**: entity definitions, the StepRun
  state machine, and validation rules referenced throughout the Requirements section.
- **[`contracts/openapi.yaml`](contracts/openapi.yaml)**: the REST surface between the front
  end and the `SENTAI.*` ObjectScript dispatcher; every endpoint cited above exists in this
  file.
- **ObjectScript backend via iris-agentic-dev**: `SENTAI.Model.Flow`, `Step`, `Edge`,
  `SENTAI.Model.Run`, `StepRun`, `SENTAI.Dispatch.WaveDispatcher`,
  `SENTAI.REST.Dispatcher`, `SENTAI.Model.Category`, and the `^SentaiRun` global.
- **Running IRIS 2026.2 Community instance**: all evidence requires a live platform, reachable
  through both the SysAdmin REST API (reads, async ops, WQM) and the product's own
  `SENTAI.REST.Dispatcher`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: An operator can compose the five-step canonical flow (three parallel checks
  feeding one fan-in, then a sequence step) from an empty canvas in under 2 minutes.
- **SC-002**: An operator can locate a validation error or warning and identify the affected
  step without leaving the canvas.
- **SC-003**: An operator can dispatch a flow and identify every step's current state from the
  live-run screen alone, without opening a separate log.
- **SC-004**: A state change on the platform is visible to the operator within 2 seconds, for
  the full duration of a run, including across at least one token refresh.
- **SC-005**: An operator can cancel one misbehaving step without affecting any sibling step in
  the same wave.
- **SC-006**: An operator can predict, from the WQM screen alone, how many workers a given
  parallel wave will actually use at once, before dispatching it.
- **SC-007**: Switching between dark and light theme changes no structural region, string, or
  state shape — only colour, elevation and selection treatment change.

## Assumptions

- The operator authenticates via IRIS platform credentials; the canvas does not manage its own
  user accounts.
- The IRIS 2026.2 Community instance used for evidence capture has the `SENTAI.*` ObjectScript
  classes installed and the `SENTAI.REST.Dispatcher` web application configured.
- A single operator uses the canvas at a time; multi-user concurrency is out of scope for this
  spec.
- The five step types with real backing classes (`integrity-check`, `compact-globals`,
  `defragment-globals`, `switch-journal`, `purge-audit-records`, `purge-task-history`) are
  sufficient to demonstrate the composition, validation, dispatch and monitoring flows; the
  `custom` type is placeable on the canvas but is expected to always fail validation in this
  spec's evidence (Clarifications 2026-09-21), since no real subclass is provided.
- The canvas targets modern desktop browsers (Chrome, Firefox, Safari latest); no legacy or
  mobile browser support is required.
- The v1 mount-status precondition check (Clarifications 2026-09-21) reads the target
  database directory's read-only flag directly; it does not require a general rule engine and
  is implemented as a fixed check in the validation path, not a `SENTAI.Precondition` class.
