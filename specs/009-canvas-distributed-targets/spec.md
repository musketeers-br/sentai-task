# Feature Specification: Canvas Screens for Distributed Targets (frontend)

**Feature Branch**: `009-canvas-distributed-targets`

**Created**: 2026-09-27

**Status**: Draft

**Input**: Frontend only: canvas screens for spec 008 (distributed targets, implements InterSystems
Ideas DPI-I-588). Every value comes from the product's API; no business rule is re-implemented in
the browser (same rule as spec 007). Depends on spec 008 merged (contract in
`specs/008-distributed-targets/contracts/api-delta.md`) — merged 2026-09-27.

## Context and Problem

Spec 008 lets a flow step run on another IRIS instance, a **target server**, and proved it end to
end over the API: register a target, sign in to it through the primary, read its status, place a
step on it, dispatch with one credential per target, and follow the run with `executedOn` per step.
None of that is reachable from the canvas yet: an operator who never leaves the canvas cannot
register a target, cannot place a step on one, and — because a flow with a remote step needs a
credential for its target at dispatch — cannot even run a flow that someone else placed on a
target.

## Objective

An operator can, from the canvas:

1. manage target servers and see each one's live state as the target reports it;
2. place a step on a target;
3. run a flow that uses targets, signing in to each target once at *Run now*;
4. see, while the run goes, where each step runs and why a remote one failed;
5. see target problems on the affected node, like any other validation finding.

## Clarifications

### Session 2026-09-27

- Q: Is a design prototype required before the target screens are built, as spec 007 Part B
  required one for custom steps? → **No (A).** The screens are built in the existing visual system
  (the catalog screen's layout, the node's chips, the dispatch dialog's fields); paired dark/light
  screenshots are the review (SC-006). The same decision unblocks spec 007 Part B.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Manage targets and see their state (Priority: P1) 🎯 MVP

From the top bar the operator opens a *Targets* screen. It lists every registered target (name,
address, description, online or offline). They add one, edit its address or description, delete
it, and switch it online or offline. To see a target's live state they sign in to it (their user
name and password for that target); the screen then shows what the target reported: reachable or
not, its IRIS version, and its Work Queue Manager categories with their worker settings. A target
that does not answer shows the transport error as the API returned it.

**Why this priority**: without a registered, observable target nothing else in this spec can be
used; it is also the "manage targets" half of DPI-I-588 on its own.

**Independent Test**: on the compose stack, register `iris-target` from the screen, sign in, and
compare the version and categories shown with `GET /targets/iris-target/status`; stop the target
and check the screen shows it unreachable with the transport error.

**Acceptance Scenarios**:

1. **Given** the Targets screen, **When** the operator adds a target with a valid name and address,
   **Then** it appears in the list exactly as the API returned it, online.
2. **Given** an address the API refuses (for example plain `http` to a non-loopback host), **When**
   the operator saves, **Then** the API's refusal is shown verbatim and nothing is added.
3. **Given** a registered target, **When** the operator signs in to it and asks for its state,
   **Then** reachable, version and categories are shown as the API returned them, with the time of
   the read.
4. **Given** a target that does not answer, **Then** the screen shows "unreachable" and the
   transport error verbatim; nothing is filled in.
5. **Given** a wrong password, **Then** the target's refusal is shown (for example
   `HTTP 401 — no reason given`) and no state is shown.
6. **Given** an online target, **When** the operator switches it offline, **Then** the list shows it
   offline after the API confirms it.
7. **Given** the operator deletes a target used by a flow, **Then** the flow still opens, and its
   validation reports the step's target as not found.

### User Story 2 — Place a step on a target (Priority: P1)

In the inspector, a step has a *Run on* choice: *Local* or any online target. The choice is offered
only for step types the API marks remote-capable; for the others the inspector says the step runs
locally and why. A step placed on a target shows a target badge with the target's name on its node,
in both themes.

**Why this priority**: this is how a flow uses a target at all.

**Independent Test**: place a step on `iris-target`, save, reload the flow: the step reads back
with `target: iris-target` from the API and the node shows the badge.

**Acceptance Scenarios**:

1. **Given** an integrity-check step, **Then** *Run on* offers *Local* and every online target.
2. **Given** a declared in-process step, **Then** *Run on* is not offered, and the inspector says
   it can only run locally (the API's `remoteCapable: false`).
3. **Given** a step placed on a target that is later set offline or deleted, **Then** the inspector
   still shows the stored name, marked as offline or not registered, and validation reports it.
4. **Given** a step on a target, **Then** its node carries the target badge; a local step has none.

### User Story 3 — Run a flow that uses targets (Priority: P1)

At *Run now*, the dispatch dialog asks for the operator's password once for the run (as today) and
once per target the flow uses, each labelled with the target's name. It signs in to each target,
dispatches with those credentials, and opens the live run. Every refusal comes back verbatim in the
dialog, which stays open.

**Why this priority**: without it, a flow with a remote step cannot be run from the canvas.

**Independent Test**: the demo flow (two local integrity checks and one on `iris-target`, fanning
in) is run from the canvas and completes.

**Acceptance Scenarios**:

1. **Given** a flow with steps on one target, **When** the operator opens *Run now*, **Then** the
   dialog shows one password field for the run and one for that target, and none for targets the
   flow does not use.
2. **Given** a wrong password for the target, **Then** the target's refusal is shown in the dialog
   and nothing is dispatched.
3. **Given** a target that does not answer, **Then** the dialog shows it unreachable with the
   transport error, and nothing is dispatched.
4. **Given** correct passwords, **Then** the run is dispatched and the live run opens.
5. **Given** a flow with no target, **Then** the dialog is exactly today's.

### User Story 4 — Watch where each step runs (Priority: P2)

The live-run view shows, for each step, where it runs (*local* or the target's name) next to who
it runs as. A remote failure shows the target's reason or the transport error verbatim, as for any
failed step.

**Why this priority**: the run already completes without it; this makes remote execution visible.

**Independent Test**: during the demo run, each node shows `executedOn` equal to the run read; after
stopping the target mid-run, the remote step shows the timeout with the transport error.

**Acceptance Scenarios**:

1. **Given** a running flow with a remote step, **Then** that node shows the target's name as where
   it runs, and local nodes show *local*.
2. **Given** a remote step that failed because its target stopped answering, **Then** its failure
   reason is shown verbatim (`timed out after N min; last transport error: …`).

### User Story 5 — Target problems on the node (Priority: P2)

Validation findings about targets (`TARGET_NOT_FOUND`, `TARGET_OFFLINE`, `TARGET_UNREACHABLE`,
`TARGET_REFUSED`, `STEP_TYPE_NOT_REMOTE_CAPABLE`, and the warning `TARGET_NOT_VERIFIED`) appear on
the affected node and in the status bar like any other finding; dispatch refusals
(`TARGET_CREDENTIAL_MISSING`, `TARGET_CREDENTIAL_USER_MISMATCH`) appear in the dispatch dialog.

**Why this priority**: the findings already reach the canvas as ordinary findings; this story makes
sure they read well and are tested.

**Independent Test**: a flow with a step on an unknown target shows `TARGET_NOT_FOUND` on that node
after *Validate flow*.

**Acceptance Scenarios**:

1. **Given** a step on an unregistered target, **When** the operator validates, **Then** that node
   shows the finding verbatim and the status bar counts it.
2. **Given** a step on a target and no target credential at validation, **Then** the node shows the
   warning `TARGET_NOT_VERIFIED` and it does not block *Run now*.

### Edge Cases

- A target renamed is impossible (the name is the key); an address edited while a run uses the
  target does not affect that run (spec 008 FR-018) — the screen shows the new address only.
- A target's sign-in answer expires after about 60 s: the Targets screen then asks to sign in again
  before reading the state; it never keeps the password.
- A flow using two targets asks two target passwords; the dialog lists them in the order of the
  steps' ids.
- The operator's user name is the same on the primary and the targets (spec 008 assumption); the
  dialog shows that user name next to each password field and does not let it be changed.
- Unknown values in a status answer are shown as returned; nothing is computed from categories (no
  load percentage, no queue length — the platform reports none).

## Requirements *(mandatory)*

### Functional Requirements

**Navigation**

- **FR-001**: The top bar MUST offer *Targets* next to *Flows* and *Task catalog*, addressable as
  `?view=targets`, with back/forward working as for the catalog (spec 007 FR-001/FR-002).

**Targets screen (spec 008 US1)**

- **FR-002**: The screen MUST list the targets `GET /targets` returns, with name, address,
  description and online state, and nothing else computed.
- **FR-003**: The operator MUST be able to add, edit (address, description), delete, and switch
  online/offline, each through its API call; every refusal MUST be shown verbatim
  (`HTTP <status> — <detail | "no reason given">`, spec 007 rule).
- **FR-004**: Reading a target's state MUST go through a sign-in to that target (user name fixed to
  the signed-in operator, password typed) followed by the status read. The screen MUST show exactly
  the status fields the API returned (reachable, version, user, categories as returned, read time),
  or the unreachable / refused answer verbatim.
- **FR-005**: The target password and the target's tokens MUST be kept in memory only, never in
  storage, cookies or the address; the password MUST be cleared right after the sign-in call, and
  the tokens dropped when they expire or the screen closes.

**Placing a step (spec 008 US2)**

- **FR-006**: The inspector MUST offer *Run on* (*Local* + online targets) only for step types whose
  catalog entry has `remoteCapable: true`; for the others it MUST say the step runs locally. The
  API remains the gate (validation reports misuse).
- **FR-007**: The chosen target MUST be saved as the step's `target` and read back from the API;
  *Local* removes it.
- **FR-008**: A node with a target MUST show a badge with the target's name, in both themes, without
  displacing the existing destructive signals.

**Running (spec 008 FR-010, FR-011)**

- **FR-009**: The dispatch dialog MUST ask one password per distinct target the flow's steps use, in
  addition to the run's own sign-in, sign in to each through `POST /targets/{name}/sign-in`, and
  send `targetCredentials: [{target, refreshToken}]` with the dispatch. Target refusals, unreachable
  targets and dispatch refusals MUST be shown verbatim and keep the dialog open.
- **FR-010**: A flow without targets MUST dispatch exactly as today (no extra field, no extra call).

**Watching (spec 008 FR-013, FR-015)**

- **FR-011**: The live-run view MUST show each step's `executedOn` as returned by the run read,
  next to `executedAs`.

**Findings**

- **FR-012**: Target findings MUST be shown on their node and counted like other findings; the
  frontend MUST NOT decide any of them itself.

**No business logic in the browser**

- **FR-013**: The frontend MUST NOT decide reachability, remote capability, availability, load or
  permissions; it shows the API's answers. Filtering *Run on* by `remoteCapable` and online is a
  convenience; the API validates.

### Key Entities

- **Target (view)**: name, base address, description, online — as `GET /targets` returns.
- **Target session (in memory)**: the target, the access and refresh tokens from a sign-in, and when
  they were issued; never persisted.
- **Target status (view)**: reachable, version, user, categories, read time, or unreachable /
  refused, as returned.
- **Step (existing view)**: gains the optional `target`.
- **Step run (existing view)**: gains `executedOn`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From the canvas alone, an operator registers `iris-target`, places a step on it and
  runs the demo flow to completion; every node shows `executedOn` equal to the run read.
- **SC-002**: Every value on the Targets screen equals the API's answer for it (list and status),
  checked field by field by an end-to-end test.
- **SC-003**: Every refusal tested (bad address, wrong target password, unreachable target, missing
  credential) is shown with the API's HTTP status and text, 100%.
- **SC-004**: After a full end-to-end run, no target password or token is found in local storage,
  session storage, cookies or the address bar.
- **SC-005**: Existing frontend tests stay green (unit 73, end-to-end 22) and none is removed; each
  user story adds at least one end-to-end test against the compose stack.
- **SC-006**: Paired dark/light screenshots of the Targets screen and of a node with a target badge
  pass the spec 002 theming checks (same structure, text contrast ≥ 4.5:1).

## Assumptions

- Spec 008's API is the only source; no backend change is part of this spec. In particular there is
  no call to renew a target sign-in, so the Targets screen signs in again when a status read needs a
  fresh credential (after about 60 s).
- The operator's user name is the same on the primary and on every target (spec 008 assumption).
- Validation from the canvas is sent without target credentials, so remote steps show the warning
  `TARGET_NOT_VERIFIED` until dispatch, which always checks them (spec 008 D-2).
- The compose stack's `iris-target` and the demo allowance for `http` are the end-to-end
  environment.
- The visual language is spec 002's (tokens, themes); the target badge and the Targets screen reuse
  the catalog screen's patterns (spec 007) (Clarifications Q1).
