# Feature Specification: Runbook Gallery — Named Ready-Made Flows Instead of the Empty Canvas

**Feature Branch**: `022-runbook-gallery`

**Created**: 2026-10-01

**Status**: Implemented <!-- Draft | Planned | In Progress | Implemented | Merged | Superseded by NNN — see "Spec status" in AGENTS.md -->

**Status note**: Implemented 2026-10-02, nothing committed (the session's "não commit nada" instruction): all 022 work sits uncommitted in the worktree on top of the finished `feat/spec021` session — see evidence/README.md. T001–T022 done: vitest 35 files / 290 tests green, svelte-check clean, IRIS suite 476/476 (incl. the new fixture comparison), full e2e 116 passed with only spec 021's documented pre-existing shared-stack set failing (us9/us18/us23 — none reachable by this change). Open: T023 [external] — the SC-005 3-of-3 usability spot-check, owned by the team, due before voting ends 2026-10-04.

**Input**: User description (2026-10-01, Portuguese, verbatim): "Galeria de receitas no lugar do canvas vazio. Hoje o fluxo é: abre Overview → Flows → canvas vazio → Open example flow (um só). O canvas vazio é a maior barreira de usabilidade que um editor de grafo tem. Troque por uma galeria de 56 runbooks nomeados, cada um um card com o mini-grafo desenhado e um botão Usar: Nightly integrity sweep — integrity check em paralelo em N namespaces → join → report; Weekly maintenance window — switch journal → purge task history → db size report; Pre-upgrade checklist — security posture + web app inventory + certificate expiry → join; Certificate expiry watch — certificate-expiry-check 30 dias) + agendamento sugerido; Security review — permissions-inventory + security-posture-report + oauth-inventory; Cross-server nightly — o showcase distribuído que já existe. Por que ganha: o jurado clica, vê um grafo real em 5 segundos e roda. Hoje ele precisa entender o conceito antes de ver valor. É também a resposta direta a Usability e Developer Experience, 2 dos 5 critérios publicados. Vocês já têm os flows seedados (iris-demo.script, spec 011/014) — é embalagem, não lógica nova."

In English: replace the empty canvas with a gallery of named runbooks. Today the judge's journey is Overview → Flows → empty canvas → *Open example flow* (a single one), and the empty canvas is the biggest usability barrier a graph editor has. Replace it with a gallery of named runbooks, each a card with a small drawing of its graph and a **Use** button; six are named (nightly integrity sweep, weekly maintenance window, pre-upgrade checklist, certificate expiry watch with a suggested schedule, security review, and the existing cross-server nightly showcase). Why it wins: the judge clicks, sees a real graph in five seconds, and runs it — today they must understand the concept before seeing any value. It answers the Usability and Developer Experience criteria directly, two of the five published ones. The flows are already seeded (the demo script; specs 011/014) — this is packaging, not new logic.

## Context and Problem

The canvas is where an operator composes a flow — and, today, the first thing almost everyone sees. The judge's journey on the public demo (spec 011) is: sign in → Overview → **Flows** → an empty canvas. What meets them is a blank professional surface with a palette of step types and top-bar controls, all of which presuppose the one concept the screen never shows: what a finished flow looks like. The single ready-made path — *Open example flow* (spec 010) — has two weaknesses the input names precisely:

1. **It is one small flow** — two read-only checks, no dependencies — so it demonstrates the palette, not the product: no parallel waves, no join, no scheduled narrative.
2. **It is offered only on an instance with no saved flows** (spec 010 FR-016a) — and the demo instance seeds flows, so on the very stage that matters the invitation does not appear at all. The evaluator faces the empty canvas unaided.

Every runbook the input names is already composable from capabilities that exist in the closed catalog: integrity checks in parallel namespaces with a join, journal switch and task-history purge, the security inventories (posture, web applications, certificates, permissions, OAuth), and the distributed showcase, which already exists as a seeded flow (`Showcase: nightly checks across servers`, spec 011). The create-or-open mechanism the gallery needs already exists too: the example flow is created through the ordinary flow-creation path with the operator's own sign-in, idempotent by name (spec 010 FR-017). So the input's framing holds: this is packaging — curated content plus one new screen state — not new logic, and it attacks two of the five published criteria (Usability, Developer Experience) the same way spec 021 attacked Clarity of Instructions.

## Objective

An operator arriving at the canvas with no flow open sees a gallery of named runbooks instead of an empty surface. Each card shows the runbook's name, what it is for, a small drawing of its graph, and a **Use** control; one action puts that runbook on the canvas as a runnable flow, ready to validate and run with the controls that are already there. Nothing changes about flow validation, dispatch, the run engine, the scheduler, or the demo setup and its daily reset.

## Clarifications

### 2026-10-01

- Q1: Is the launch catalog the six runbooks the input names, a materially larger count that must be authored before voting ends, or something between? → **A (chosen 2026-10-01): the six named runbooks are the full v1 catalog**; the count grows later only through the ordinary change process. The input's "56" is a missing separator ("5, 6"): it lists exactly six, maps each to capabilities that already exist, and calls the work "packaging, not new logic" — and authoring ~50 more definitions would not fit the remaining days of the voting week. FR-002 was updated accordingly.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The empty canvas is a gallery of named runbooks (Priority: P1)

An operator on the canvas screen with no flow open — the judge's journey is sign-in → Overview → Flows — sees, in place of the empty canvas, a gallery of runbook cards. Each card shows: the runbook's **name**, a one-line statement of what it is for, a **mini-graph** of the runbook — its steps and the dependencies and joins between them, drawn from the runbook's own definition, recognizable as the same graph that will open on the canvas — and a **Use** control. The gallery presents the six runbooks named in the input:

1. **Nightly integrity sweep** — integrity checks running in parallel across namespaces, joined, then a report;
2. **Weekly maintenance window** — journal switch, task-history purge, database size report;
3. **Pre-upgrade checklist** — security posture, web application inventory, certificate expiry, joined;
4. **Certificate expiry watch** — certificate expiry check (30-day warning), with a suggested schedule shown on the card;
5. **Security review** — permissions inventory, security posture report, OAuth inventory;
6. **Cross-server nightly** — the distributed showcase that already exists as a seeded flow.

**Why this priority**: This is the feature — the barrier (an empty surface that presupposes the concept) is replaced by the value (real, named graphs a judge can read in five seconds). Everything else exists to serve it.

**Independent Test**: On the demo instance (or any instance), sign in and reach Flows without opening a flow: the gallery is there, with the cards above. Reproducible with an automated end-to-end test.

**Acceptance Scenarios**:

1. **Given** the canvas screen in its editing state with no flow open, **Then** the gallery is presented in place of the empty canvas surface.
2. **Given** the gallery, **Then** each card shows the runbook's name, its purpose line, its mini-graph, and a Use control.
3. **Given** the demo instance, which has saved flows (the seeded ones), **When** the operator reaches Flows without opening a flow, **Then** the gallery appears — the empty canvas is no longer shown on an instance just because flows exist.
4. **Given** a card, **Then** its mini-graph shows the runbook's steps and the dependencies between them — parallel branches and joins included — such that what opens from Use is the graph the card drew.
5. **Given** the gallery, **Then** a path to start from a blank canvas remains visible on the same screen, one action away.

---

### User Story 2 - Use puts a runnable flow on the canvas in one action (Priority: P1)

From a card, the operator chooses **Use**. The runbook opens on the canvas as a flow: a flow of that name that already exists is opened; when none exists, the flow is created through the ordinary flow-creation path with the operator's own sign-in, and the platform validates it exactly as it validates any operator flow. From that moment the canvas is an ordinary editing session — the flow can be inspected, changed, validated, and started with the controls that are already there. The input's promise is the measure: from the gallery to a real graph on the canvas in about five seconds, with no prior knowledge of the product.

**Why this priority**: The gallery only wins if the click lands. Use is the action that turns a showcase card into the operator's own runnable flow, and it shares P1 with Story 1 because the two together are the minimum viable gallery.

**Independent Test**: On the demo instance, choose Use on *Weekly maintenance window*: the flow opens on the canvas, *Validate flow* passes, and *Run now* starts it — no other setup.

**Acceptance Scenarios**:

1. **Given** a card whose runbook can run on this instance, **When** the operator chooses Use, **Then** a flow with the runbook's name is open on the canvas, in one action.
2. **Given** no flow of that name exists, **When** Use is chosen, **Then** the flow is created through the ordinary flow-creation path under the operator's own credential — a saved flow like any other, listed among the operator's flows and runnable at once.
3. **Given** a flow of that name already exists (for example the seeded *Cross-server nightly*), **When** Use is chosen, **Then** the existing flow opens; nothing is duplicated — the platform's unique name index decides, as it does today for the example flow.
4. **Given** the used runbook is open on the canvas, **Then** *Validate flow* and *Run now* are available and behave exactly as for any flow, with no further setup.
5. **Given** the platform refuses the creation (for instance the operator is not permitted to save a flow), **Then** the refusal — status and the platform's own reason — is surfaced as-is, never reinterpreted or retried silently.

---

### User Story 3 - Cards tell the truth about the runbook (Priority: P2)

Each card presents the runbook honestly: the steps it runs, named; the suggested cadence, where one is declared (*Certificate expiry watch* — suggested: daily); destructive steps identified the same way the product identifies them everywhere else; and whether the runbook can run on **this** instance. A runbook whose steps are not all declared and available here — or that needs a resource the instance does not have, such as the distributed target the cross-server showcase requires — keeps its card and its mini-graph, but its Use control is disabled and the card states why. The gallery never hides what a runbook does and never lets an unusable card be clicked into a dead end.

**Why this priority**: Honesty is what makes the gallery a first impression that can be trusted — and unusable cards that look clickable would trade one bad first impression for a worse one. It ranks below the two P1 stories because a truthful card of an unrunnable runbook still shows the product's shape, which is most of the value on the demo stage.

**Independent Test**: Sign in to the shared demo account and use two different runbooks: both open as flows of their own names, and each keeps its steps and joins intact.

**Acceptance Scenarios**:

1. **Given** a card, **Then** the steps the runbook runs are identifiable on the card, and a destructive step is marked as destructive, consistently with how the canvas identifies destructive steps.
2. **Given** a runbook that declares a suggested cadence, **Then** the card shows it as text (for example "suggested: daily"); choosing Use creates a flow and never a schedule.
3. **Given** a runbook with a step type not available on this instance, **Then** its card shows the mini-graph but offers no working Use control, and states the reason.
4. **Given** a runbook that needs a resource this instance does not have, **Then** the card behaves the same — shown, not clickable, with the reason.

---

### User Story 4 - The gallery fits in without displacing anything (Priority: P2)

Everything that guards an operator's work survives the gallery. The unsaved-changes guard still fires before Use replaces an edited flow. Authoring from scratch remains: from the gallery the operator can still start a blank canvas, and the gallery does not stand in the way of the palette, *New flow*, or *Open flow…*. The *Getting started* dialog still opens automatically after a first password sign-in; the tour (spec 021) still starts from its button and its marks still anchor to the palette, the connection surface and the *Validate flow* / *Run now* controls — regions that exist with the gallery on screen, so the tour works on the gallery exactly as it worked on the empty canvas and the invitation before it.

**Why this priority**: A judge who is also a voter must not lose the merged first-use behaviors; a gallery that eats the guard or the tour would cost more than it wins. It is P2 because the gallery is valuable even if some entry point still says *Open example flow*, but nothing in it may regress.

**Independent Test**: Edit a flow, then choose Use on a card: the guard asks. Dismiss it, start a blank canvas, and add a step from the palette: both work as before the gallery.

**Acceptance Scenarios**:

1. **Given** the open flow has unsaved changes, **When** the operator chooses Use on a card, **Then** the unsaved-changes guard fires first, exactly as it does today for *New flow*, opening another flow, and opening the example.
2. **Given** the gallery is shown, **Then** starting a blank canvas and authoring from the palette work unchanged.
3. **Given** a browser where the guide was never dismissed, **When** the operator signs in with the password, **Then** the *Getting started* dialog opens automatically, exactly as spec 010 FR-020 defines it.
4. **Given** the tour is started with the gallery on screen, **Then** every mark anchors to its region exactly as spec 021 requires.
5. **Given** the operator is on a shared instance (the demo's single published account), **When** they use a runbook another visitor already used and edited, **Then** the flow of that name opens — the shared instance behaves consistently; the gallery creates nothing beyond what the name index already governs.

---

### User Story 5 - One ready-made path, not two (Priority: P3)

The *Open example flow* entry points that exist today — in the *Getting started* dialog and in the *Open flow…* dialog — now lead to the gallery: their job, "show me something ready-made", is served by every card. The former example flow (the two read-only checks) is available as one more card. No path in the product offers a single example in isolation any more, and the guide's copy that references *Open example flow* is updated to the gallery while keeping its meaning.

**Why this priority**: Two parallel ready-made mechanisms (one example flow, one gallery) would be a small confusion the demo does not need; but rewiring entry points is secondary to the gallery itself and can land after it.

**Independent Test**: From the *Getting started* dialog, follow its ready-made entry: the gallery appears; choose a card; its flow opens.

**Acceptance Scenarios**:

1. **Given** the *Getting started* dialog, **When** the operator follows its ready-made entry point, **Then** the gallery is presented.
2. **Given** the *Open flow…* dialog, **When** the operator follows its ready-made entry point, **Then** the gallery is presented.
3. **Given** the gallery, **Then** the former example flow's checks are available as a card like any other.

### Edge Cases

- The instance is reachable but the sign-in ends, or the platform becomes unreachable, while the gallery is open: the screen shows the platform's own state or reason, exactly as the canvas states do today — the gallery never masks a refusal or an unreachable state (Constitution IV).
- The canvas is in a non-editing state (a refusal shown, the instance unreachable, a flow that could not be opened): the gallery is not shown; the platform's state panel is, as today.
- The demo's daily reset (spec 011) runs while a visitor is on the gallery, or after a visitor used runbooks: the gallery renders the curated runbooks, which are part of the shipped product, not saved flows — so the reset changes nothing about it. Visitor-used flows are removed by the reset exactly as visitor flows are today.
- A visitor uses a runbook on the shared demo account and edits it; a later visitor chooses Use on the same card: the same-name flow opens (the name index decides), showing the earlier visitor's edits — the same behavior the example flow has today on a shared account, consistent and predictable.
- The operator's stored flow of a runbook's name was created by an older version of the runbook definition: the existing flow opens untouched — Use never clobbers a flow the operator already has (the same idempotence the seeded demos rely on).
- A runbook's create is refused by the platform mid-Use (permissions revoked between the gallery's check and the create): the refusal is surfaced verbatim; the gallery remains usable; nothing is created partially.
- The viewport is the smallest the product supports: the gallery's cards remain readable and usable, and the path to a blank canvas stays reachable without horizontal scrolling.
- The curated set is larger than the visible area: the gallery scrolls; every card remains reachable by keyboard.

## Requirements *(mandatory)*

### Functional Requirements

**The gallery state**

- **FR-001**: Whenever the canvas screen is in its editing state with no flow open, the product MUST present the runbook gallery in place of the empty canvas surface — on every instance, including one that has saved flows. This supersedes the empty-canvas invitation (spec 010 FR-016a); the invitation's *Start from scratch* duty is carried on by FR-012.
- **FR-002**: The gallery MUST present the curated runbooks shipped with the product; the launch catalog is exactly the six runbooks named in the input (Story 1) plus the example-flow card (FR-013) — no others at launch. Additional runbooks enter only through the ordinary change process (FR-011) (Q1, answered: option A).
- **FR-003**: Each card MUST show the runbook's name, a one-line statement of what the runbook is for, and a mini-graph drawn from the runbook's definition — its steps and the dependencies and joins between them — such that the graph that opens from Use matches the graph the card drew.
- **FR-004**: A card whose runbook declares a suggested cadence MUST show it as text; the gallery MUST NOT create, change or suggest into existence any schedule (scheduling remains the operator's deliberate act, spec 015).
- **FR-005**: The gallery MUST show which steps of a runbook are destructive, consistently with how the product identifies destructive steps elsewhere. The gallery MUST NOT filter runbooks out for being destructive: what a runbook does is shown, not hidden; execution remains governed by the platform's own authorization (Constitution III).

**Use**

- **FR-006**: The Use control MUST put the chosen runbook on the canvas as a flow in one action: a flow of the runbook's name that already exists is opened; otherwise the flow is created through the ordinary flow-creation path under the operator's own credential and validated by the platform exactly like any operator flow. The platform's unique name index is the sole arbiter of "already exists" — the gallery MUST NOT keep its own record of used runbooks (Constitution III).
- **FR-007**: A card whose runbook cannot run on the current instance — a step type not declared or not available, or a required resource absent — MUST NOT offer a working Use control and MUST state the reason on the card.
- **FR-008**: When the open flow has unsaved changes, Use MUST go through the existing unsaved-changes guard (spec 010 FR-006) before anything on the canvas is replaced.
- **FR-009**: A refusal from the platform during Use MUST be surfaced verbatim — the platform's status and its own reason, unmodified — and MUST NOT be retried or recovered silently.
- **FR-010**: A flow opened or created by Use MUST be immediately operable: inspectable, editable, validatable and runnable with the controls the canvas already has, with no gallery-specific setup.

**Content and its governance**

- **FR-011**: Every runbook MUST be a named flow definition composed only of step types from the closed catalog, with each declared parameter filled in — data in the codebase, never code, never runtime-extensible (Constitution II). New runbooks enter only through the ordinary change process.
- **FR-012**: The gallery MUST offer, on the same screen, a path to start authoring from a blank canvas that behaves as today's *Start from scratch*.
- **FR-013**: The curated set MUST include the existing ready-made example flow's checks (the two read-only checks of spec 010) as a card, and the *Getting started* dialog's and the *Open flow…* dialog's ready-made entry points MUST lead to the gallery; no product path offers a lone example flow any more (supersedes spec 010 FR-016b/FR-016c in that role). The automatic opening and every other behavior of the *Getting started* dialog are unchanged (spec 010 FR-020/FR-022/FR-023).
- **FR-014**: The gallery MUST NOT change flow validation, dispatch, the run engine, the scheduler, the demo setup, or the demo reset (specs 011, 015).

**Coexistence and interaction**

- **FR-015**: The tour (spec 021) MUST work unchanged with the gallery on screen: its marks anchor to the palette, the connection surface and the *Validate flow* / *Run now* controls, all of which exist with the gallery presented. The gallery replaces the empty-canvas invitation that spec 021 US3 scenario 2 expected to remain — there, this spec supersedes; the tour itself is untouched.
- **FR-016**: The gallery MUST be operable by keyboard alone: its cards and controls are reachable by *Tab*, Use is activatable from the keyboard, and the gallery is announced to assistive technology with an accessible name.
- **FR-017**: All gallery text MUST be in English, matching the canvas (specs 010 FR-026, 011 FR-019). The *Use* label is the English for the input's *Usar*; exact wording is a design decision for the Plan.

### Key Entities

- **Runbook**: a named, curated ready-made flow definition shipped with the product — its name, its purpose line, its steps and the dependencies and joins between them, and an optional suggested cadence. It is data in the codebase (Constitution II): composed only of catalog step types, extendable only through the ordinary change process. It is not a saved flow; using it may create one.
- **Runbook card**: the gallery's presentation of one runbook — the name, the purpose line, the mini-graph drawn from the definition, the runnability verdict on this instance with its reason when negative, and the Use control.
- **Gallery**: the screen state that replaces the empty canvas — the set of cards, the path to a blank canvas, and nothing else; it owns no state of its own.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On 100% of arrivals at the canvas in its editing state with no flow open — including the demo instance, which has saved flows — the operator sees the gallery, not an empty surface.
- **SC-002**: From the gallery, an operator reaches a real, runnable flow open on the canvas in at most 2 actions and about 5 seconds, with no prior knowledge of the product.
- **SC-003**: Every flow the gallery creates passes the same validation as an operator-built flow, and every platform refusal during Use is surfaced verbatim — 0 silent recoveries, 0 reinterpretations.
- **SC-004**: 0 regressions against the merged behavior: the unsaved-changes guard, the *Getting started* dialog's automatic opening, the tour's anchoring, and the demo sign-in hint all behave as their specs define (spec 021's empty-canvas-invitation expectation excepted, superseded here).
- **SC-005**: In a usability spot-check on the public demo, at least 3 of 3 first-time evaluators open a runbook from the gallery and start a run with no instructions other than what the gallery and the canvas show.

## Assumptions

- "56 runbooks" is read — confirmed by Q1 (option A) — as the six the input names (a missing separator: "5, 6"): the input lists exactly six, maps each to capabilities that already exist, and calls the work "packaging, not new logic". The launch catalog is those six (plus the example-flow card, FR-013); more may be added later through the ordinary change process.
- The judge is the primary actor for this feature (the public demo, the voting week), and the operator of any installation benefits identically; no demo-only behavior is added — the gallery is a product state, not a demo artifact.
- The runbook definitions ship with the product as curated data reviewed in a pull request. Where the definitions live (frontend-bundled data like today's example flow, or a server-side catalog) is deliberately not decided here; the Plan resolves it against Principle I.
- The mini-graph is drawn from the runbook definition (steps, dependencies, joins) — not a picture maintained by hand; exact rendering is a design decision for the Plan.
- The *Use* semantic follows today's example-flow pattern (create-or-open by name, under the operator's credential), which the input's "packaging, not new logic" supports; a copy-for-me semantic with renamed duplicates is rejected because the platform's unique name index makes same-name identity the only consistent rule (Constitution III).
- Cross-server nightly's card relies on the distributed target existing (the demo registers it); on an instance without it, the card is shown with its Use disabled and the reason — the same honest treatment as any unrunnable runbook.
- The failure-demo flows (*failing-check*, *security-posture*) are teaching artifacts for the run-log story, not runbooks; they are not gallery cards.
- Voting-week constraint: the Plan should slice the work so the minimal gallery (the empty-canvas replacement, the six runbooks, Use with the guard) lands first and everything else (entry-point rewiring, polish) follows; authoring a materially larger catalog would not fit the remaining days (Q1, option A).
- The demo's daily reset and the seeded flows are untouched: seeded flows keep working as they do (used by Use when a card's name matches, left alone otherwise).
