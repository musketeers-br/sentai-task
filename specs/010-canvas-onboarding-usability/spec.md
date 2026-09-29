# Feature Specification: Canvas Onboarding and Flow Management Usability

**Feature Branch**: `010-canvas-onboarding-usability`

**Created**: 2026-09-27

**Status**: Implemented

**Status note**: US1–US5 and T064 merged in PR #15. T057–T060 are manual sessions with real operators and browsers, marked [external]; record their results in evidence/ when done.

**Input**: Operator feedback (2026-09-27) after updating and restarting the product: "Every F5
sends me back to the login page, even though I am signed in." / "I don't understand how to get
back to a saved task. I named it and saved; then typed another name and saved again. When I tried
to go back to the first one, nothing happened." / "Hardly anyone will build a task by hand on day
one — a ready-made task where you just click a button and see it working would do much more."
Plus a product request: a getting-started guide shown as a step-by-step dialog, with a
"Don't show this again" option. All user-facing text is in English.

## Context and Problem

The canvas (spec 002, extended by specs 007 and 009) lets an operator compose, save, validate,
dispatch and schedule flows. Four gaps make it hard to use for anyone who is not already familiar
with it:

1. **Saved flows cannot be reopened.** A flow is saved on the server, but the canvas has no place
   that lists saved flows. The only ways back to a flow are a link carrying its identifier or the
   origin link on a Catalog entry.
2. **A page reload signs the operator out.** The sign-in exists only for the lifetime of the page,
   so a reload (F5) always returns to the sign-in screen. Operators read this as the product
   losing their session.
3. **Renaming looks like "save as".** After the first save, the name field renames the open flow.
   Typing a new name and saving again replaces the name of the same flow instead of creating a
   second one. The first name disappears, and the operator concludes their first flow was lost.
   There is also no way to start a new, empty flow except reloading the page, which runs into
   gap 2.
4. **The first experience is an empty canvas.** A first-time operator must learn the palette, the
   inspector, validation and dispatch before seeing anything run. There is no ready-made flow and
   no explanation of the steps.

## Objective

An operator who opens the product for the first time is guided through it, can run a ready-made
flow with one action, and can reliably return to, create, duplicate and switch between saved
flows. A page reload never costs them their sign-in or their place.

## Clarifications

### Session 2026-09-27

- Q: Should the example flow run against the live instance? → A: Yes. It is a real flow made only
  of steps the step-type registry declares **non-destructive** and **available**, so running it
  cannot change or remove data. The operator sees the tool working against their own instance,
  not a simulation.
- Q: Where is "don't show the guide again" remembered? → A: Per browser, on the operator's
  device. It is a display preference, not a permission, so it does not involve the platform.
  Clearing browser data shows the guide again, which is acceptable.
- Q: Does keeping the sign-in across a reload conflict with Constitution III (no cached
  permission outcomes)? → A: No. Only the credential that proves the sign-in survives the reload,
  and only for the current browser tab. Every request is still authorized by the platform at the
  moment it is made; nothing about what the operator may do is stored.
- Q: What is a "visit" for the getting-started guide, and does a reload count as a sign-in? → A: A
  visit runs from a sign-in with the password to sign-out (or to the tab closing). A reload that
  keeps the sign-in (Story 3) is the same visit and is not a new sign-in, so it never opens the
  guide automatically. Signing in again after "Your session ended" is a new sign-in.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Save as a new flow, never overwrite by accident (Priority: P1)

An operator has a saved flow open. They want a second flow based on it. They choose **Save as…**,
give it a new name, and get a second flow; the original is untouched. They can also choose
**New flow** to start from an empty canvas. The top bar makes clear that editing the name of a
saved flow renames that flow.

**Why this priority**: This is the only gap that causes the operator to lose work (or believe they
lost it). It must be fixed before anything else is encouraged.

**Independent Test**: Save flow "A"; choose *Save as…* and name it "B"; confirm both "A" and "B"
exist on the server with their own contents, and the canvas now shows "B".

**Acceptance Scenarios**:

1. **Given** a saved flow "A" is open, **When** the operator chooses *Save as…* and enters "B",
   **Then** a new flow "B" is created with the current steps, edges and layout, the canvas shows
   "B", and flow "A" keeps its name, revision and contents.
2. **Given** a saved flow "A" is open, **When** the operator edits the name field, **Then** the top
   bar states that saving will rename "A" (for example "Renames this flow — use Save as… to keep a
   copy"), before they save.
3. **Given** a flow with unsaved edits is open, **When** the operator chooses *New flow*,
   **Then** they are asked to save, discard, or cancel before the canvas is cleared.
4. **Given** the operator chooses *New flow* with no unsaved edits, **Then** the canvas is empty,
   the flow has a fresh default name, and the address no longer names the previous flow.
5. **Given** *Save as…* is given a name that another flow already uses, **Then** the dialog shows
   the platform's refusal and keeps the dialog open so the operator can choose another name.

---

### User Story 2 - Open a saved flow (Priority: P1)

An operator chooses **Open flow…** in the top bar and sees every saved flow on the instance, with
its name, revision and when it was last saved. They pick one and it opens on the canvas.

**Why this priority**: Without it, saved work is effectively unreachable. Together with Story 1 it
makes saving meaningful.

**Independent Test**: Save two flows; reload the canvas without a flow in the address; open
*Open flow…*, pick the first flow and confirm the canvas shows it and the address names it.

**Acceptance Scenarios**:

1. **Given** saved flows exist, **When** the operator opens *Open flow…*, **Then** a list shows each
   flow's name, revision and last-saved time, most recently saved first, with the open flow marked.
2. **Given** the list is open, **When** the operator types in its filter field, **Then** the list
   narrows to flows whose name contains the text, ignoring case.
3. **Given** the operator picks a flow and the open flow has no unsaved edits, **Then** the chosen
   flow opens and the address names it, so reload, back and forward all agree.
4. **Given** the open flow has unsaved edits, **When** the operator picks another flow, **Then**
   they are asked to save, discard, or cancel before switching.
5. **Given** there are no saved flows, **Then** the list says so and offers the example flow
   (Story 4) and *New flow*.
6. **Given** the list cannot be read (for example, the platform denies it), **Then** the platform's
   reason is shown as-is in the dialog.

---

### User Story 3 - A reload keeps the operator signed in (Priority: P2)

An operator reloads the page (F5) or the browser restores the tab. They stay signed in and return
to the same screen and the same open flow, without typing their password again. Closing the tab or
signing out ends the sign-in.

**Why this priority**: It removes the most visible annoyance and makes the address (flow, run,
screen) useful after a reload. It is not data loss, so it ranks after Stories 1 and 2.

**Independent Test**: Sign in, open a flow, reload the page; confirm the canvas shows the same flow
with no sign-in screen. Sign out, reload; confirm the sign-in screen is shown.

**Acceptance Scenarios**:

1. **Given** a signed-in operator with flow "A" open, **When** they reload the page, **Then** they
   are still signed in and flow "A" is open again, without seeing the sign-in form.
2. **Given** a signed-in operator watching a live run, **When** they reload, **Then** they return to
   that run's live view.
3. **Given** the operator signed out, **When** they reload, **Then** the sign-in screen is shown.
4. **Given** the operator closes the tab and opens the product in a new tab, **Then** the sign-in
   screen is shown (the sign-in does not outlive the tab).
5. **Given** the kept sign-in can no longer be renewed (expired, revoked, or the instance
   restarted), **When** the page loads, **Then** the sign-in screen is shown with a short
   explanation ("Your session ended — sign in again"), and after signing in the operator returns
   to the flow and screen named in the address.
6. **Given** a second tab is opened by duplicating the first, **Then** each tab keeps its own
   sign-in and renewing one never signs the other out.

---

### User Story 4 - Run a ready-made example flow (Priority: P2)

A first-time operator, with no flows of their own, is offered **Open example flow**. It opens a
small ready-made flow of safe, read-only checks. They can choose *Run now* and watch it execute on
their instance without building anything.

**Why this priority**: It is the fastest path from "just installed" to "seen it work", which the
feedback identifies as what engages new operators. It depends on Story 2's list as one of its
entry points.

**Independent Test**: On an instance with no flows, open the example flow and dispatch it; confirm
the live-run view shows every step reaching a finished state and no step asks for a destructive
confirmation.

**Acceptance Scenarios**:

1. **Given** no saved flows exist, **When** the operator is on the canvas, **Then** the empty canvas
   shows an invitation with *Open example flow* and *Start from scratch*.
2. **Given** the operator chooses *Open example flow*, **Then** a flow named "Example: storage
   health check" opens, containing only steps the registry declares non-destructive and available,
   at least two of which run in parallel, each with its parameters already filled in and valid.
3. **Given** the example flow is open, **When** the operator validates it, **Then** it reports no
   errors on a default installation.
4. **Given** the example flow is open, **When** the operator chooses *Run now*, **Then** the run
   starts after the normal run sign-in, no destructive confirmation is requested, and the live-run
   view follows it to the end.
5. **Given** the example flow already exists on the instance, **When** the operator chooses *Open
   example flow* again, **Then** the existing example opens; no duplicate is created.
6. **Given** the operator changed the example, **Then** their changes are kept like any other flow;
   the example is offered from *Open flow…* like any other saved flow.

---

### User Story 5 - Getting-started guide (Priority: P3)

After signing in for the first time in a browser, the operator sees a **Getting started** dialog
that walks them through the product step by step. They can page through it, close it at any time,
and tick **Don't show this again**. They can reopen it later from **Help** in the top bar.

**Why this priority**: It amplifies Stories 1–4 by pointing at them, but the product is usable
without it.

**Independent Test**: Sign in in a fresh browser profile; confirm the guide appears. Tick *Don't
show this again*, close, reload and sign in again; confirm it does not appear. Open *Help →
Getting started*; confirm it appears.

**Acceptance Scenarios**:

1. **Given** an operator signs in on a browser where the guide was never dismissed, **When** the
   canvas is ready, **Then** the *Getting started* dialog opens once for that visit.
2. **Given** the dialog is open, **Then** it presents these steps in order, one at a time, with
   *Back*, *Next* and a step indicator ("Step 2 of 6"):
   1. **Welcome** — what SentaiTask does: compose maintenance flows, run them now or on a schedule.
   2. **Open the example** — *Open example flow* runs safe, read-only checks; includes an action
      that opens it directly.
   3. **Build a flow** — drag steps from the palette, connect them to order them, edit parameters
      in the inspector.
   4. **Validate and run** — *Validate flow* checks the flow against the instance; *Run now* starts
      it and shows each step live.
   5. **Save, Save as, Open** — *Save flow* keeps changes to this flow, editing the name renames
      it, *Save as…* makes a copy, *Open flow…* returns to any saved flow, *New flow* starts empty.
   6. **Schedule and explore** — *Schedule* hands the flow to the platform scheduler; *Catalog* and
      *Targets* show tasks and remote servers.
3. **Given** the dialog is open, **Then** it shows a *Don't show this again* checkbox, unticked by
   default, and a *Close* action on every step (and *Get started* on the last step).
4. **Given** the operator ticks *Don't show this again* and closes the dialog, **Then** the guide
   does not open automatically again in this browser, including after reload and sign-out/sign-in.
5. **Given** the operator closes the dialog without ticking the checkbox, **Then** it does not open
   again during this visit, but does open on the next sign-in.
6. **Given** the guide was dismissed, **When** the operator chooses *Help → Getting started*,
   **Then** it opens at step 1 with the checkbox reflecting the saved choice; unticking it and
   closing restores automatic display.
7. **Given** the browser refuses to store preferences (private mode, blocked site data), **Then**
   the guide still works; it simply opens again on the next sign-in.
8. **Given** the dialog is open, **Then** it can be operated by keyboard alone (focus starts in the
   dialog, *Escape* closes it, focus returns to where it was) and is announced as a dialog with its
   title.

### Edge Cases

- A reload happens while a save is in flight: after the reload the flow shows the last revision the
  server confirmed; any edit not yet confirmed is lost, as with any closed page.
- The address names a flow that was deleted or that the operator may not read: the canvas shows the
  platform's reason and offers *Open flow…* and *New flow* instead of a blank failure.
- *Save as…* on a flow that was never saved behaves like the first *Save flow*, with the name the
  operator enters.
- *Save as…* on a flow with unsaved edits saves the edits into the new flow only; the original keeps
  its last saved revision.
- Another operator saved the open flow meanwhile (revision conflict): *Save flow* shows the conflict
  as today; the notice suggests *Save as…* to keep the operator's version.
- A step type used by the example flow is no longer declared or available on the instance: the
  example is not offered, and the invitation offers only *Start from scratch*.
- The guide and the empty-canvas invitation appear together on first use: the guide is on top; the
  invitation remains once the guide is closed.
- The sign-in is kept, but the instance restarted and no longer recognises it: this is the
  "session ended" path (Story 3, scenario 5), never an error page.

## Requirements *(mandatory)*

### Functional Requirements

**Flow management**

- **FR-001**: The top bar on the Flows screen MUST offer *New flow*, *Open flow…*, *Save flow* and
  *Save as…*.
- **FR-002**: *Open flow…* MUST list every flow the platform returns for the operator, showing name,
  revision and last-saved time, ordered most recently saved first, with the currently open flow
  marked, and MUST filter by a case-insensitive name substring.
- **FR-003**: Opening a flow from the list MUST load it on the canvas and put it in the address, so
  reload, back, forward and shared links open the same flow (consistent with spec 002 FR-002).
- **FR-004**: *Save as…* MUST ask for a name, create a **new** flow from the current canvas
  (steps, edges, layout, default category), open the new flow, and leave the original flow
  unchanged.
- **FR-005**: While a saved flow is open and its name field differs from its saved name, the top bar
  MUST state that saving will rename this flow and point to *Save as…* for a copy.
- **FR-006**: *New flow*, opening another flow, and opening the example MUST, when the open flow has
  unsaved edits, ask the operator to *Save*, *Discard* or *Cancel* before proceeding.
- **FR-007**: *New flow* MUST produce an empty canvas with a fresh unique default name and remove
  the previous flow from the address.
- **FR-008**: Any platform refusal while listing, opening, creating or saving flows (name clash,
  denial, revision conflict, missing flow) MUST be shown with the platform's own reason
  (Constitution III, IV).

**Sign-in across reloads**

- **FR-009**: A page reload in the same browser tab MUST keep the operator signed in without asking
  for credentials, as long as the platform still accepts the kept sign-in.
- **FR-010**: The kept sign-in MUST be scoped to the browser tab: it MUST end when the tab is
  closed, and MUST be erased on sign-out and whenever the platform rejects it.
- **FR-011**: Only the credential needed to renew the sign-in MAY be kept. The password MUST never
  be kept, and no permission outcome, role or capability MUST be stored (Constitution III).
- **FR-012**: When the kept sign-in cannot be renewed on load, the product MUST show the sign-in
  screen with the message "Your session ended — sign in again." and, after sign-in, restore the
  screen, flow and run named in the address.
- **FR-013**: Two tabs MUST NOT share one kept sign-in; renewing in one tab MUST NOT sign the other
  out.
- **FR-014**: The existing rules for proactive renewal (spec 002 FR-034) and for the separate run
  sign-in at dispatch continue to apply unchanged.

**Example flow**

- **FR-015**: The product MUST offer an example flow named "Example: storage health check",
  composed only of step types the registry declares non-destructive and available, with at least
  two parallel steps and all parameters pre-filled with valid values.
- **FR-016**: The example MUST be offered (a) on the empty canvas when the instance has no saved
  flows, (b) in *Open flow…* when no flows exist, and (c) from the getting-started guide.
- **FR-017**: Opening the example MUST open the existing example flow if one exists on the
  instance, and create it otherwise; it MUST never create a duplicate.
- **FR-018**: Once created, the example MUST behave as an ordinary flow (edit, save, save as,
  validate, dispatch, schedule).
- **FR-019**: If any step type the example needs is not declared or not available on the instance,
  the example MUST NOT be offered.

**Getting-started guide**

- **FR-020**: After a sign-in with the password (not a reload that keeps the sign-in), when the guide has not been dismissed in this browser and has not
  already been shown in this visit, the product MUST open the *Getting started* dialog once the
  canvas is ready.
- **FR-021**: The dialog MUST present the six steps listed in Story 5 in that order, one at a time,
  with *Back*, *Next*, a step indicator, and a way to close it from any step.
- **FR-022**: The dialog MUST include a *Don't show this again* checkbox, unticked by default. Its
  state at the moment the dialog closes MUST be remembered in this browser and MUST govern whether
  the guide opens automatically on later sign-ins.
- **FR-023**: The top bar MUST offer *Help → Getting started*, which opens the guide at step 1 at
  any time, regardless of the remembered choice.
- **FR-024**: When the browser cannot store the choice, the guide MUST still open and close
  normally; failing to remember MUST NOT produce an error.
- **FR-025**: The dialog MUST be keyboard-operable and announced as a modal dialog with its title,
  trap focus while open, close on *Escape*, and return focus on close.

**Language**

- **FR-026**: All new user-facing text (labels, dialogs, notices, the guide, the example flow's name
  and step labels) MUST be in English, matching the rest of the canvas.

### Key Entities

- **Flow summary**: what the flow list shows for a saved flow — identifier, name, revision,
  last-saved time. Read from the platform; never cached across sign-ins.
- **Example flow**: an ordinary saved flow with a well-known name and a fixed, non-destructive
  composition. Identified by its name, so it is created at most once per instance.
- **Kept sign-in**: the renewal credential for the current tab's sign-in. Tab-scoped, erased on
  sign-out, rejection, or tab close. Holds no permissions.
- **Guide preference**: a per-browser yes/no — whether the operator asked not to see the guide
  again. A display preference only.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a usability run, 100% of operators who save a flow under a second name end with
  **two** flows on the instance (via *Save as…*), and none report losing their first flow.
- **SC-002**: An operator can reopen any previously saved flow in at most 3 actions from the canvas
  (open list, optionally filter, pick).
- **SC-003**: Reloading the page 10 times in a row during a signed-in session shows the sign-in
  screen 0 times, and the same flow is open after each reload.
- **SC-004**: A first-time operator on a fresh installation goes from signing in to watching the
  example flow finish in under 2 minutes, without building or configuring any step.
- **SC-005**: The example flow validates with 0 errors and completes with every step finished on a
  default installation, requesting 0 destructive confirmations.
- **SC-006**: After ticking *Don't show this again*, the guide opens automatically 0 times over the
  next 5 sign-ins in the same browser, and remains reachable from *Help* every time.
- **SC-007**: Signing out, or closing the tab, leaves no credential that lets a later page load in
  that browser enter the product without signing in.

## Assumptions

- The flow-list, flow-read and flow-create operations that the backend already exposes (spec 002
  contract) are sufficient for Stories 1, 2 and 4; if a gap is found, the Plan adds it to the API
  as a declared operation (Constitution II), not a client workaround.
- The example uses in-process, read-only step types available today (storage headroom check and
  database size report), running in parallel. The Plan confirms the final composition against the
  registry.
- Flow names are unique per instance (existing platform rule); the example's name relies on it to
  avoid duplicates.
- The platform's refresh operation revokes the previous access credential (spec 002 notes); the
  Plan must keep renewal on load compatible with that and with the run's separate sign-in.
- "First use" is per browser, not per operator account; showing the guide once more on a new
  browser is acceptable.
- Deleting flows, sharing flows between operators, and localising the UI into other languages are
  out of scope.
- This is a frontend-first change; the only backend work considered is what the example flow may
  need, to be decided in the Plan.
- When the kept sign-in cannot be renewed on load because the instance cannot be reached (a network
  failure, not a platform rejection), it is also erased and the "session ended" path is shown.
  Keeping a credential that may no longer be valid gains nothing, because signing in works again as
  soon as the instance is reachable.
