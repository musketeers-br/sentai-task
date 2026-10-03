# Feature Specification: First-Time Canvas Tour — Three Coach Marks

**Feature Branch**: `first-time-tour`

**Created**: 2026-10-01

**Status**: Implemented <!-- Draft | Planned | In Progress | Implemented | Merged | Superseded by NNN — see "Spec status" in AGENTS.md -->

**Status note**: T001–T017 done 2026-10-01 on `feat/spec021`: vitest 265 green, svelte-check clean, `us30` 9/9, us21 (spec 010 guard) green and unedited, and the full e2e shows zero failures beyond the pre-existing shared-stack set (see evidence/README.md). The Tour button sits pinned to the canvas' top-right corner, not the top bar — the bar already fits exactly at 1440 px (plan risk R-4) and FR-001 asks only for a visible one-action control on the canvas screen. Open: T018 (SC-004 usability spot-check with 3 operators) is [external], owned by the team, due before voting ends 2026-10-04.

**Input**: User description (2026-10-01, Portuguese, verbatim): "Tour de primeira vez (3 passos). Coach marks na primeira abertura: 'Esta é a paleta — arraste um step' → 'Ligue dois steps para criar dependência' → 'Valide e rode'. Com Pular. Por que ganha: ataca direto Clarity of Instructions. Custo: 3 horas. O que eu não faria agora: tela de categorias WQM (está nas limitações, mas é pouco visível para votante); provar os step types faltantes (compact-globals, defragment-globals) — risco alto, retorno baixo; prevenir runs sobrepostos — é correto, mas invisível numa demo; qualquer coisa que toque no dispatcher a 3 dias do fim."

In English: a three-step first-time tour, shown as coach marks — the palette (drag a step), connecting two steps (creates a dependency), validate and run — with a *Skip* control. It is chosen because it attacks the clarity-of-instructions problem directly, for about three hours of work; the four items listed at the end are explicitly rejected for now, with the reasons given. How the tour is reached was clarified (Q1): the *Getting started* dialog stays as it is, and the tour gets its own button.

## Context and Problem

The canvas (specs 002, 007, 009, 010) is where an operator composes a flow. A first-time operator — an evaluator on the public demo during the voting week (spec 011), or a new operator on any installation — must today learn the core loop unaided, or from the six-step *Getting started* dialog (spec 010 US5), which states facts but does not point at the controls:

1. **Where steps come from.** Nothing on the screen says that the palette is the source of steps and that dragging is the gesture.
2. **How dependency is expressed.** The connection between two steps is what makes one depend on the other; an empty canvas gives no hint that drawing a line is the gesture.
3. **How to check and start.** *Validate flow* and *Run now* sit in the top bar; their meaning, and their order (check, then start), is unexplained.

The result is a first screen that requires instructions the product does not give at the place they are needed — a clarity-of-instructions failure that coach marks (a message anchored to the control it explains) attack directly. The team has roughly three hours of budget and three days of voting week left, so the tour is deliberately small: three marks, one skip control, one button to start it, no backend work, nothing that touches the dispatcher. The *Getting started* dialog remains the automatic guide that tells; the tour is the opt-in way to be shown, on the real canvas, at the moment the operator chooses.

## Objective

An operator on the canvas can start a three-step tour of coach marks from a visible button. The marks point at the real controls and teach the core loop — drag a step from the palette, connect two steps to create a dependency, validate and run — and the tour can be skipped at any point and taken again at any time. The *Getting started* dialog and every other first-use behavior are untouched, as is everything deadline-sensitive (dispatcher, run engine, demo setup).

## Clarifications

### 2026-10-01

- Q1: What happens to the *Getting started* dialog's automatic opening (spec 010 FR-020) when the tour arrives? → A: Nothing changes about the dialog — it keeps opening automatically after the first sign-in exactly as spec 010 defines, and stays in *Help → Getting started*. The tour never opens automatically: it is launched by its own button, added for that purpose, and can be taken at any time, any number of times.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Take the tour from a button (Priority: P1)

An operator on the canvas — often a first-time evaluator who has just closed the *Getting started* dialog — chooses a visible **Tour** control. A tour of three coach marks starts, one at a time, each anchored to the region it explains, in this order:

1. **The palette** — conveys that this is where steps come from and that the gesture is dragging one onto the canvas (suggested copy: "This is the palette — drag a step onto the canvas.").
2. **Connections** — conveys that connecting two steps is what creates a dependency between them (suggested copy: "Connect two steps to create a dependency.").
3. **Validate and run** — conveys that the flow can be checked against the instance and then started (suggested copy: "Validate the flow, then run it.").

Each mark shows its position ("1 of 3"), a *Next* control (the last mark a finishing control), and *Skip*. The marks anchor to regions that exist on the canvas screen regardless of which flow is open, so the tour works on an empty canvas, on the example flow, and on the showcase flow.

**Why this priority**: These three messages are the entire value — they turn an unexplained screen into an instructed one. The button is how they are reached; everything else exists to serve them.

**Independent Test**: On the canvas with any flow open (or none), activate the Tour control: the three marks appear in this order, each anchored to its region and conveying its message. Reproducible with an automated end-to-end test.

**Acceptance Scenarios**:

1. **Given** the canvas screen in its editing state, **Then** a Tour control is visible and starts the tour in one action.
2. **Given** the tour starts, **Then** the marks appear one at a time in the order palette → connections → validate-and-run, each anchored to and highlighting its target region: the step palette, the surface where connections between steps are drawn, and the *Validate flow* / *Run now* controls.
3. **Given** the first or second mark is showing, **When** the operator chooses *Next*, **Then** the next mark appears and the position indicator advances ("1 of 3" → "2 of 3" → "3 of 3").
4. **Given** the third mark is showing, **Then** the tour offers a finishing control, and choosing it ends the tour.
5. **Given** any mark is showing, **Then** the region it explains stays visible and is never covered by the mark's own box or controls.
6. **Given** the tour is started with a flow already open (the operator's own, the example flow, or the showcase flow), **Then** every mark still anchors correctly.
7. **Given** the tour is open, **Then** it is operable by keyboard alone: focus starts inside the tour, its controls are reachable by *Tab*, and it is announced as a dialog with its title.
8. **Given** the tour was finished or skipped, **When** the operator activates the Tour control again, **Then** the tour starts from the first mark, identically.

---

### User Story 2 - Skip ends it, with no consequence (Priority: P1)

At any mark the operator can choose *Skip* (or press *Escape*) and the tour ends immediately: nothing is blocked, the canvas is exactly what it would have been without the tour, and focus returns to where it was. Nothing is remembered against the operator: taking or skipping the tour changes no state, and the operator can take it again later from the same control whenever they want.

**Why this priority**: A tour that cannot be dismissed is worse than no tour; the input names *Skip* explicitly, and without it the tour cannot ship. It shares P1 with Story 1 because together they are the minimum viable tour.

**Independent Test**: Start the tour and choose *Skip* on the first mark: the canvas is fully usable immediately. Start it again from the control: it runs identically from the first mark.

**Acceptance Scenarios**:

1. **Given** any mark of the tour is showing, **When** the operator chooses *Skip* or presses *Escape*, **Then** the tour ends immediately, the canvas is fully usable, and focus returns to where it was before the tour started.
2. **Given** the tour was skipped or finished, **When** the operator starts it again from the same control, at any later time, **Then** it starts from the first mark and behaves identically — nothing was remembered, and nothing needs clearing.

---

### User Story 3 - The tour fits in without displacing anything (Priority: P2)

Everything that greets a first-time operator behaves exactly as before: the *Getting started* dialog still opens automatically after the first sign-in with the password, with its paging, *Don't show this again* checkbox and *Help* entry unchanged (spec 010); the empty-canvas invitation remains visible beneath the tour and after it; the demo sign-in hint is unaffected. The tour adds one control to the canvas screen and changes nothing else about the first experience.

**Why this priority**: It is cheap and it protects the merged spec 010 behavior from regression. It ranks below the marks themselves because the tour is useful even if the rest of the first experience merely stays as it is.

**Independent Test**: In a fresh browser, sign in with the password for the first time: the *Getting started* dialog opens automatically exactly as before the tour existed. Close it; the empty-canvas invitation is there; the Tour control is visible; start the tour and the invitation remains beneath it and after it ends; *Help → Getting started* still opens the dialog at step 1.

**Acceptance Scenarios**:

1. **Given** a browser where the guide was never dismissed, **When** the operator signs in with the password, **Then** the *Getting started* dialog opens automatically, exactly as spec 010 FR-020 defines it, unchanged by the tour.
2. **Given** a first canvas-ready on an instance with no saved flows, **Then** the empty-canvas invitation is visible; the tour, when started, opens on top of it, and the invitation remains after the tour ends.
3. **Given** the tour is open, **Then** no other guide, dialog or hint opens automatically on the same screen.
4. **Given** the operator chooses *Help → Getting started* at any time, **Then** the six-step dialog (spec 010) opens at step 1, unchanged, regardless of the tour.
5. **Given** a demo instance, **Then** the sign-in hint (spec 011 FR-009) and the published demo account are unaffected by the tour.

### Edge Cases

- The tour is open when the sign-in ends or the canvas leaves its editing state (a refusal, an unreachable instance): the tour closes by itself and the platform's own state or reason is shown as today; the tour never masks a refusal or error (Constitution IV).
- The canvas screen is in a non-editing state (refused, unreachable) or the operator is on another screen via a deep link: no Tour control is offered — the tour exists only on the editable canvas, where its targets exist.
- The operator takes the tour while the *Getting started* dialog is open: not possible — the dialog is modal; the Tour control is reached after closing it.
- The viewport is the smallest the product supports: each mark still shows its target region and its controls without scrolling, and no anchor points outside the visible area.
- The demo's daily reset (spec 011) runs while a visitor is mid-tour: the reset clears server-side data, never the visitor's browser; the tour (button-launched, storing nothing) behaves identically before and after a reset.

## Requirements *(mandatory)*

### Functional Requirements

**Tour entry and content**

- **FR-001**: The canvas screen MUST offer a clearly visible Tour control that starts the tour in one action, available whenever the canvas is in its editing state, regardless of which flow is open, including none.
- **FR-002**: The tour MUST present exactly three coach marks, in this order, each conveying at least: (1) steps come from the palette and are added by dragging one onto the canvas; (2) a connection between two steps is what creates a dependency between them; (3) the flow can be checked against the instance with *Validate flow* and then started with *Run now*.
- **FR-003**: Each coach mark MUST be anchored to, and highlight, the region it explains — the step palette, the surface where connections between steps are drawn, and the *Validate flow* / *Run now* controls — and MUST anchor correctly regardless of which flow is open, including none.
- **FR-004**: Each mark MUST show its position in the tour ("1 of 3").

**Navigation and dismissal**

- **FR-005**: Every mark MUST offer *Skip*; every mark except the last MUST offer *Next*; the last MUST offer a finishing control.
- **FR-006**: The tour MUST be keyboard-operable: focus starts inside the tour when it opens, its controls are reachable by *Tab*, *Escape* has the same effect as *Skip*, and on finish or skip focus returns to where it was. It MUST be announced as a dialog with its title.
- **FR-007**: While the tour is open, the product MUST NOT open any other guide, dialog or hint automatically on the same screen; the empty-canvas invitation remains visible beneath it and after it ends.

**Coexistence and state**

- **FR-008**: The *Getting started* dialog MUST remain exactly as spec 010 defines it — automatic opening after a password sign-in (010 FR-020), the *Don't show this again* preference (010 FR-022), and *Help → Getting started* (010 FR-023). The tour MUST NOT change any of it.
- **FR-009**: The tour MUST NOT open automatically at canvas-ready or at any other moment; its only entry is the Tour control of FR-001.
- **FR-010**: The tour MUST NOT persist any state — no preference, no "seen" memory — and MUST behave identically on every launch.
- **FR-011**: If the canvas leaves its editing state while the tour is open (the sign-in ends, the platform becomes unreachable, a refusal is shown), the tour MUST close and MUST NOT mask the platform's own state or message.
- **FR-012**: On a demo instance, the sign-in hint (spec 011 FR-009) and the published demo account MUST be unaffected by the tour.

**Language and scope**

- **FR-013**: All tour text MUST be in English, matching the canvas (specs 010 FR-026, 011 FR-019).
- **FR-014**: The tour MUST NOT add any server-side operation and MUST NOT change flow validation, dispatch, the run engine or the scheduler.

### Key Entities

- **Coach mark**: one step of the tour — the region it anchors to, the message it conveys, and its position in the order. Exactly three exist, fixed in the codebase; none comes from user input. The tour stores no state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From the canvas in its editing state, the tour starts from its control in one action in 100% of attempts, presenting exactly the three marks in the specified order, each anchored to a visible target region.
- **SC-002**: With the tour present, the *Getting started* dialog shows 0 regressions against spec 010 — it still opens automatically after the first password sign-in, honors *Don't show this again*, and opens from *Help → Getting started*.
- **SC-003**: A keyboard-only operator can start, traverse and finish the tour, and can skip from any mark with *Escape* alone.
- **SC-004**: In a usability spot-check, at least 3 of 3 first-time operators who take the tour complete the core loop — add a step from the palette, connect two steps, validate, run — with no instructions other than the tour's marks.

## Assumptions

- The tour is aimed at first-time operators but available to everyone, at any time: "first opening" is served by the unchanged *Getting started* dialog (which tells) plus the always-present button (which shows). No automatic opening of the tour exists, so no first-use detection and no per-browser preference are needed — a deliberate simplification that keeps the feature inside its budget.
- The Tour control sits in the top bar of the canvas screen, near *Help*; exact placement and label ("Tour", "Take a tour", "Canvas tour") are design decisions for the Plan, provided it is visible and one action.
- The coach-mark texts will be in English; the input is in Portuguese and user-facing text is English by house convention (specs 010 FR-026, 011 FR-019). The copy in Story 1 is suggested; final wording is a design decision for the Plan.
- The tour does not wait for the operator to perform the real actions: *Next* always advances. Advancing on the real action, translated tours, and tour analytics are out of scope for v1; the six-step *Getting started* dialog remains the in-depth guide.
- The tour needs no backend work, no new platform operation, and no change to the demo setup (spec 011). The roughly 3 hours named in the input is the budget; the Plan should slice the tasks so the tour can land within it.
- Explicitly rejected for now, from the input, with its reasons: a WQM categories screen (a documented limitation — the canvas has no category screen yet — but little visible to a voter); proving the missing step types compact-globals and defragment-globals (high risk, low return this close to the deadline); preventing overlapping runs (correct, but invisible in a demo); anything that touches the dispatcher three days before the voting week ends.
