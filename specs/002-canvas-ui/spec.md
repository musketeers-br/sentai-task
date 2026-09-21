# Feature Specification: Canvas UI

**Feature**: 002-canvas-ui

**Created**: 2026-09-21

**Status**: Draft

**Deadline**: 2026-09-27 (InterSystems Programming Contest)

## Scope

SentaiTask Canvas UI delivers a visual orchestration surface where an IRIS administrator views every scheduled task as a node on an interactive canvas, inspects any task's full configuration in a detail sidebar, triggers and monitors asynchronous maintenance operations with real-time state feedback, and manages worker-capacity ceilings from a dedicated panel. Edges between nodes display the existing `RunAfterGUID` relationships as visual documentation only — they do not represent execution dependencies and cannot be created or modified through the canvas (spec 001, path 3: the create→read→GUID cycle cannot close via the API). This spec explicitly excludes: task chaining execution, AI/LLM features, log analysis, telemetry-based remediation, semantic search, and task creation or editing through the canvas.

## Questions to Answer

Each question is a capability the canvas must demonstrate with committed evidence, following the same pattern as spec 001. Every question must close with a reproducible artifact, not a verbal report.

### Q1 — Node rendering

Can the canvas render a custom node that displays a task's Name, Type, Status (derived from `Suspended` + runtime state), NextScheduled, and Suspended flag, matching the prototype layout?

**Evidence required**: Screenshot of at least three rendered nodes showing all five data fields, matching the layout in [contracts/prototype/canvas-overview.png](contracts/prototype/canvas-overview.png).

### Q2 — Data binding

Can the canvas load the task list from `GET /api/admin/v2/tasks` (response shape documented in [spec 001 evidence/03-tasks-list.json](../001-validate-async-job-contract/evidence/03-tasks-list.json)) and create one node per task, positioned by an automatic layout algorithm?

**Evidence required**: Screenshot of the canvas after initial load showing nodes corresponding to the platform's scheduled tasks, plus a JSON capture of the API response consumed.

### Q3 — Node interaction

Can clicking a node open a detail sidebar showing the full task configuration from `GET /api/admin/v2/task?id=` (all fields documented in [spec 001 evidence/04-task-single.json](../001-validate-async-job-contract/evidence/04-task-single.json)), matching the layout in [contracts/prototype/node-task-detail.png](contracts/prototype/node-task-detail.png)?

**Evidence required**: Screenshot of the detail sidebar for a selected node showing scheduling fields (`TimePeriod*`, `DailyFrequency*`, `StartDate`), `TaskClass`, `RunAsUser`, and `RunAfterGUID`.

### Q4 — Edge rendering

Can edges be drawn between nodes where `RunAfterGUID` is populated (e.g., task 7 → task 1 on a default IRIS Community instance), with a clear visual indicator that these are documentation-only — not execution dependencies?

**Evidence required**: Screenshot showing at least one edge with its visual-only indicator (e.g., dashed line, label, or distinct color). The indicator must be unambiguous to an operator who did not read this spec.

**Constraint**: Edges are read-only. The canvas MUST NOT offer any affordance to create, delete, or modify edges. This is a consequence of the spec 001 finding that the task's own GUID is not exposed by any API read endpoint, making programmatic chaining impossible.

### Q5 — Async job trigger

Can the canvas trigger an async maintenance operation (e.g., integrity-check via `POST /api/admin/v2/database-dir/integrity-check`, which returns HTTP 202 with a Location header per [spec 001 evidence/06-integrity-check-start.json](../001-validate-async-job-contract/evidence/06-integrity-check-start.json)) and show job state transitions (Running → Paused → Running → Finished or Canceled) in real-time via polling?

**Evidence required**: A sequence of screenshots or a JSON log capturing: (a) the trigger action, (b) the Running state displayed on the node or in a job panel, (c) at least one transition (pause or cancel), and (d) the settled state.

**Constraint**: Polling interval MUST NOT exceed 2 seconds. Token refresh MUST be transparent (see Q6).

### Q6 — Token lifecycle

Does the authentication layer transparently refresh the 60-second access token (spec 001 deviation: `exp - iat = 60`) without interrupting canvas operations — including mid-poll during a long-running async job?

**Evidence required**: A JSON log showing at least two successful token refreshes during a single async-job polling session that exceeds 60 seconds, with no user-visible interruption or error.

### Q7 — WQM sidebar

Can the canvas display worker-capacity categories from `GET /api/admin/v2/wqm-categories` (response shape documented in [spec 001 evidence/09-wqm-categories.json](../001-validate-async-job-contract/evidence/09-wqm-categories.json)) and allow editing `MaxActiveWorkers` via `PUT /api/admin/v2/wqm-category?name=` (query parameter, not body field — spec 001 deviation), with a read-back confirming the write took effect?

**Evidence required**: Screenshot of the WQM panel showing categories with their current values, plus a JSON capture of the write request and read-back verification.

## User Scenarios & Testing

### User Story 1 — Task Canvas Overview (Priority: P1)

An IRIS administrator opens SentaiTask and sees every scheduled task on the platform rendered as a node on an interactive canvas. Each node shows the task's name, type, status, next scheduled run, and whether it is suspended. The canvas arranges nodes automatically so the operator does not need to position them manually.

**Why this priority**: Without the canvas, there is no product. This is the minimum demonstrable artifact: a visual representation of the platform's task state, sourced from live API data.

**Independent Test**: Load the canvas against a running IRIS Community instance. Verify nodes appear for each scheduled task and display correct data. Covers Q1 + Q2.

**Acceptance Scenarios**:

1. **Given** a running IRIS instance with at least 5 scheduled tasks, **When** the operator opens the canvas, **Then** one node per task is rendered with Name, Type, Status, NextScheduled, and Suspended visible on each node.
2. **Given** the canvas is loaded, **When** the operator pans and zooms, **Then** the canvas responds without lag and all nodes remain readable.
3. **Given** a task whose `Suspended` field is `true`, **When** the canvas renders it, **Then** the node displays a visually distinct suspended indicator.

---

### User Story 2 — Task Detail Inspection (Priority: P1)

An operator clicks a node on the canvas and a detail sidebar opens showing the task's full configuration: all scheduling fields, the task class, the run-as user, and the `RunAfterGUID` (if populated). The sidebar reflects the data from the single-task read endpoint.

**Why this priority**: Inspection is the primary interaction model. Without it, the canvas is a picture, not a tool.

**Independent Test**: Click any node and verify the sidebar shows all fields from the `GET /api/admin/v2/task?id=` response. Covers Q3.

**Acceptance Scenarios**:

1. **Given** the canvas is loaded, **When** the operator clicks a task node, **Then** a detail sidebar opens within 1 second showing the task's full configuration.
2. **Given** the sidebar is open for a task with a populated `RunAfterGUID`, **When** the operator reads the sidebar, **Then** the GUID value and the predecessor task's name (if resolvable) are displayed.
3. **Given** the sidebar is open, **When** the operator clicks a different node, **Then** the sidebar updates to show the newly selected task's details.

---

### User Story 3 — Async Job Trigger and Monitor (Priority: P1)

An operator selects a task node and triggers an asynchronous maintenance operation (e.g., integrity check). The canvas shows the job's state in real-time (Running, Paused, Finished, Canceled) and supports pause, resume, and cancel actions on the running job.

**Why this priority**: Job triggering and monitoring is the core value proposition — the operator acts on the platform through the canvas, not just reads from it.

**Independent Test**: Trigger an integrity check, observe Running state, pause it, resume it, cancel it, and verify each state transition is reflected in the UI. Covers Q5 + Q6.

**Acceptance Scenarios**:

1. **Given** a task node is selected, **When** the operator triggers an async operation, **Then** the UI shows the job as Running within 2 seconds.
2. **Given** a job is Running, **When** the operator clicks Pause, **Then** the UI shows the job as Paused and a subsequent GET confirms `State=Paused`.
3. **Given** a job is Running for more than 60 seconds, **When** the access token expires, **Then** the auth layer refreshes it transparently and polling continues without interruption.

---

### User Story 4 — Relationship Visualization (Priority: P2)

The canvas draws edges between tasks where `RunAfterGUID` indicates a predecessor relationship. Edges are visually marked as documentation-only (not execution dependencies) so the operator understands the limitation.

**Why this priority**: Adds context to the canvas but does not enable new actions. Depends on Q1+Q2 being complete.

**Independent Test**: Load a canvas against an IRIS instance where at least one task has a populated `RunAfterGUID` (e.g., task 7 with GUID `511A7F43-7187-11F1-AD1F-000000000000`). Verify the edge renders with the visual-only indicator. Covers Q4.

**Acceptance Scenarios**:

1. **Given** task 7 has `RunAfterGUID` pointing to task 1's GUID, **When** the canvas renders, **Then** a dashed edge (or equivalent visual-only indicator) connects the two nodes.
2. **Given** edges are rendered, **When** the operator attempts to drag or create an edge, **Then** no affordance exists — edges are not interactive.

---

### User Story 5 — Resource Ceiling Management (Priority: P2)

The operator opens a WQM panel, sees all worker-capacity categories with their current `MaxActiveWorkers`, edits a value, and receives confirmation that the write took effect via a read-back.

**Why this priority**: Resource management is a secondary canvas function. Depends on the auth layer (Q6) being stable.

**Independent Test**: Open WQM panel, change a MaxActiveWorkers value, verify read-back shows the new value. Covers Q7.

**Acceptance Scenarios**:

1. **Given** the WQM panel is open, **When** the operator views it, **Then** all categories and their MaxActiveWorkers, DefaultWorkers, MaxWorkers, and MaxTotalWorkers values are displayed.
2. **Given** the operator changes MaxActiveWorkers for a category, **When** the write completes, **Then** a read-back confirms the new value and the original is restorable.
3. **Given** the operator enters an invalid value, **When** the write is attempted, **Then** the platform's error (carried as a value per Principle IV) is displayed to the operator.

---

### Edge Cases

- What happens when the IRIS instance has zero scheduled tasks? The canvas MUST show an empty state with guidance, not a blank screen or an error.
- What happens when `GET /api/admin/v2/tasks` returns a task whose `Id` is not found by `GET /api/admin/v2/task?id=`? The node renders with the list data; the sidebar shows the error the platform returned.
- What happens when a token refresh fails (IRIS container restarted mid-session)? The canvas MUST show a re-authentication prompt, not silently fail.
- What happens when an async job's `FailureReason` is populated? The UI MUST display the value. (Note: spec 001 open risk — populated FailureReason was not observed; UI should render whatever the field contains.)
- What happens when `RunAfterGUID` references a GUID that does not match any task's `Id`? The edge is omitted (the predecessor is not on this canvas), and the sidebar notes the unresolved reference.

## Requirements

### Functional Requirements

- **FR-001**: The canvas MUST render one custom node per scheduled task returned by the task list endpoint, displaying Name, Type, Status, NextScheduled, and Suspended.
- **FR-002**: Nodes MUST be positioned by an automatic layout algorithm on initial load. The operator MAY reposition nodes manually after layout.
- **FR-003**: Clicking a node MUST open a detail sidebar showing all fields from the single-task read endpoint within 1 second.
- **FR-004**: The sidebar MUST display `RunAfterGUID` and, when populated, resolve and display the predecessor task's Name.
- **FR-005**: The canvas MUST draw edges between nodes where the source task's `RunAfterGUID` matches a target task's GUID. The GUID-to-task resolution requires reading each task's single-task endpoint to find the match.
- **FR-006**: Edges MUST carry a visual indicator (dashed line, label, color, or combination) that unambiguously communicates they are documentation-only, not execution dependencies.
- **FR-007**: The canvas MUST NOT provide any affordance to create, delete, or modify edges.
- **FR-008**: The canvas MUST offer a trigger action on a selected node that starts an async maintenance operation and displays the job's real-time state.
- **FR-009**: The canvas MUST support pause, resume, and cancel actions on a running async job, reflecting each state transition within 2 seconds.
- **FR-010**: The authentication layer MUST refresh the access token before it expires (60-second TTL) without interrupting any active polling or user interaction.
- **FR-011**: The canvas MUST provide a WQM panel that displays all worker-capacity categories and allows editing `MaxActiveWorkers`.
- **FR-012**: After a WQM write, the system MUST read back the value and confirm the write took effect before reporting success to the operator.
- **FR-013**: Platform errors (denied operations, failed writes, expired sessions) MUST be surfaced to the operator with the platform's original error message, per Principle IV.
- **FR-014**: The canvas MUST NOT execute code supplied at runtime, construct executable code from input, or offer any extension mechanism beyond the declared capability set, per Principle II.
- **FR-015**: Authorization for every API call MUST be delegated to the platform. The canvas MUST NOT cache, infer, or predict permission outcomes, per Principle III.

### Key Entities

- **Task Node**: Visual representation of a scheduled task. Carries display fields (Name, Type, Status, NextScheduled, Suspended) from the list read, and full configuration from the single-task read. Keyed by `Id` (small integer from the platform).
- **Edge**: Visual-only connection between two Task Nodes. Read from `RunAfterGUID` on the source node. Not interactive. Not persisted by the application.
- **Async Job**: Transient entity created when the operator triggers a maintenance operation. Identified by the `Location` header's `id` parameter. Carries State, TimeQueued, TimeStarted, TimeFinished, FailureReason.
- **WQM Category**: Worker-capacity configuration. Carries Name, MaxActiveWorkers, DefaultWorkers, MaxWorkers, MaxTotalWorkers, AlwaysQueue. Readable and writable via the platform API.
- **Auth Session**: Access token + refresh token pair. Access token TTL = 60 seconds. Refresh must be proactive (before expiry), not reactive.

## Acceptance Criteria

- **[Q1]** is accepted when a screenshot shows at least three task nodes rendered with Name, Type, Status, NextScheduled, and Suspended visible, matching the prototype layout in [contracts/prototype/canvas-overview.png](contracts/prototype/canvas-overview.png).
- **[Q2]** is accepted when the canvas loads and renders one node per task from a live `GET /api/admin/v2/tasks` response, with nodes positioned by an automatic layout algorithm, demonstrated by a screenshot and a captured API response.
- **[Q3]** is accepted when clicking a node opens a detail sidebar within 1 second showing all fields from `GET /api/admin/v2/task?id=`, demonstrated by a screenshot matching [contracts/prototype/node-task-detail.png](contracts/prototype/node-task-detail.png).
- **[Q4]** is accepted when at least one edge renders between nodes with a populated `RunAfterGUID` relationship, carrying an unambiguous visual-only indicator, demonstrated by a screenshot.
- **[Q5]** is accepted when triggering an async operation shows real-time state transitions (Running → at least one transition → settled state) on the canvas, demonstrated by sequential screenshots or a JSON state log.
- **[Q6]** is accepted when a JSON log shows at least two token refreshes during a polling session exceeding 60 seconds with zero user-visible errors.
- **[Q7]** is accepted when the WQM panel displays categories, an edit to MaxActiveWorkers is written and confirmed by read-back, demonstrated by a screenshot and a JSON capture of the write+verify cycle.

## Success Criteria

- **SC-001**: An operator viewing the canvas for the first time can identify every scheduled task on the platform within 10 seconds of page load.
- **SC-002**: An operator can locate and read any task's full configuration in under 3 clicks (canvas load → click node → read sidebar).
- **SC-003**: An operator can trigger, observe, and control an async maintenance operation without leaving the canvas.
- **SC-004**: The canvas sustains uninterrupted operation for at least 5 minutes of active use, including multiple async job cycles, without token-related failures.
- **SC-005**: An operator unfamiliar with the spec 001 chaining limitation can tell from the edge visual alone that edges are not execution dependencies.
- **SC-006**: Resource ceiling changes via the WQM panel take effect on the platform within one write-read cycle, with confirmation visible to the operator.

## Constraints

### From the Constitution

- **Principle II (Closed Capability Set)**: No `Xecute` on request parameters, no dynamic code construction, no runtime-extensible operations. The canvas exposes a fixed set of actions: view, inspect, trigger, pause, resume, cancel, and edit WQM values.
- **Principle III (Delegated Authorization)**: No `MatchRoles:"%All"`. No unauthenticated web applications. Every API call carries the operator's credentials; the platform decides what is permitted.
- **Principle IV (Errors as Values)**: Platform denials and partial failures are surfaced verbatim — never swallowed, retried silently, or paraphrased.
- **Principle V (Verifiable Increments)**: Each user story is independently demonstrable with its own evidence.

### From Spec 001

- **Token TTL = 60s**: The auth layer must refresh proactively (before expiry), not reactively (after a 401).
- **POST /v2/task requires all 31 fields and returns no identifier**: Task creation is out of scope for this spec.
- **Task's own GUID not exposed**: Chaining via API is impossible for app-created tasks. Edges are visual-only.
- **`name` is a query parameter on PUT wqm-category**: Not a body field (spec 001 deviation).
- **WQM type asymmetry**: Numeric properties require explicit coercion between reads and writes.

### From Contest Rules

- No DevExtreme UI library.
- The application MUST run as a Docker container built from the IRIS Community base image.

### Explicit Exclusions

- Task creation or editing through the canvas.
- Task chaining execution (edges do not drive scheduling).
- AI/LLM features of any kind.
- Log analysis, telemetry-based remediation, semantic search.
- Mobile or responsive layout (desktop only for contest).

## Evidence Contract

Evidence files MUST be committed to `specs/002-canvas-ui/evidence/` following these naming conventions:

| Evidence ID | Type | Description |
|-------------|------|-------------|
| `q1-node-rendering.png` | Screenshot | Three or more rendered task nodes showing all five fields |
| `q2-data-binding.png` | Screenshot | Full canvas after initial load with auto-layout |
| `q2-api-response.json` | JSON | Captured `GET /api/admin/v2/tasks` response consumed during load |
| `q3-node-interaction.png` | Screenshot | Detail sidebar open for a selected node |
| `q4-edge-rendering.png` | Screenshot | At least one edge with visual-only indicator |
| `q5-async-trigger.json` | JSON | State log: trigger HTTP 202, polling snapshots, transition results |
| `q5-async-states.png` | Screenshot | Job state displayed on canvas (Running, Paused, or Canceled) |
| `q6-token-lifecycle.json` | JSON | Log of token refresh events during a >60s polling session |
| `q7-wqm-panel.png` | Screenshot | WQM panel with categories and values |
| `q7-wqm-write-verify.json` | JSON | Write request + read-back confirmation |

Screenshots MUST be captured at desktop resolution (minimum 1280x720). JSON files MUST follow the evidence envelope schema from spec 001 (`call_id`, `captured_at`, `platform`, `request`, `response`, `notes`) where applicable, or a simplified schema for UI-generated logs:

```json
{
  "evidence_id": "string",
  "captured_at": "ISO-8601",
  "entries": [{ "timestamp": "ISO-8601", "event": "string", "detail": {} }]
}
```

## Dependencies

- **[spec 001 compatibility.md](../001-validate-async-job-contract/compatibility.md)**: Ground truth for all API response shapes, deviations, and field names.
- **[spec 001 decision.md](../001-validate-async-job-contract/decision.md)**: Execution model decision (delegate to platform).
- **Prototype screenshots**: [contracts/prototype/canvas-overview.png](contracts/prototype/canvas-overview.png) and [contracts/prototype/node-task-detail.png](contracts/prototype/node-task-detail.png) define the target layout. Every deviation from the prototype MUST be called out in the evidence.
- **Running IRIS Community instance**: All evidence requires a live platform. Container setup is documented in the project's `docker-compose.yml`.

## Assumptions

- The operator has network access to the IRIS instance's management API port.
- The IRIS Community instance has at least 5 pre-existing scheduled tasks (default system tasks are sufficient).
- At least one task has a populated `RunAfterGUID` (task 7 on a default instance, per spec 001 curl verification).
- The canvas targets modern desktop browsers (Chrome, Firefox, Safari latest). No IE or mobile support.
- A single operator uses the canvas at a time; multi-user concurrency is out of scope.
- The operator authenticates via IRIS platform credentials (`_SYSTEM` or equivalent); the canvas does not manage its own user accounts.
