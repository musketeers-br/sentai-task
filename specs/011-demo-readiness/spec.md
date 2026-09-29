# Feature Specification: Demo Readiness — A Public Demo That Stays Up and a README That Sells in One Screen

**Feature Branch**: `011-demo-readiness`

**Created**: 2026-09-28

**Status**: Draft

**Input**: Competitor analysis of the contest (2026-09-28, "Analise_concorrentes.pdf", 37 approved
apps, voting 2026-09-28 → 2026-10-04). Its top risk: the application's demo link is a free
tunnel that changes or disappears, so an expert who clicks it during the voting week may find
nothing. Its second risk: an evaluator decides in the first screen of the README whether the
application covers the contest's areas. The team chose to host a stable demo on a virtual machine
with the compose stack (clarification Q1). Also in scope: the warning the operator gets before
cancelling a running platform job, which makes the instance report "unhealthy"
(`docs/limitations.md`).

## Context and Problem

SentaiTask is complete and verified from a clean checkout (specs 001–010). Three things still
hurt the first impression of an expert or community voter:

1. **The demo is not dependable.** The public link points at a tunnel to a developer machine. It
   dies when that machine sleeps, and anyone who reaches it signs in with the platform's
   well-known default administrator password, which also opens the platform's own management
   portal on the same address.
2. **The README makes the evaluator scroll.** The contest-area table sits below the motivation,
   there is no picture of the product at the top, no "try it now" block, and the roadmap does not
   list spec 010 as done.
3. **Cancelling looks like breaking the instance.** Cancelling a running platform job makes IRIS
   record a severity-2 alert, so the container reports "unhealthy". This is documented, but the
   operator is not told at the moment they cancel, and the step's *Cancel* tooltip still says the
   platform job is not cancelled, which stopped being true with spec 008.

## Objective

During the whole voting week, an evaluator can open a stable public address, sign in with a
published demo account that cannot harm the instance, run a ready-made flow that shows
orchestration (parallel steps, a fan-in join, one step on a second server), and come back later
to find the demo clean. The README's first screen says what the product is, shows it, lists the
contest areas it covers and tells the reader how to try it. An operator who cancels a running
platform job knows beforehand what the instance will report.

## Clarifications

### Session 2026-09-28

- Q: Where does the public demo run? → A: On a virtual machine the team controls, with the
  repository's compose stack (both IRIS services). The tunnel link is replaced by the machine's
  address. When the team has a host name for it, the demo is served over HTTPS.
- Q: Which account do visitors use? → A: A dedicated demo operator account whose name and password
  are published in the README and on the sign-in screen of the demo only. It holds only the
  privileges needed to use SentaiTask's non-destructive features. The platform's built-in
  privileged accounts get passwords that only the host knows.
- Q: What does the demo account do when a step needs more privilege than it holds (for example a
  security report)? → A: The platform refuses and the refusal is shown verbatim, like for any
  operator (Constitution III). The demo documents this as intended behavior, not a defect.
- Q: How is the demo kept clean for a week of visitors? → A: A reset returns it to its initial
  state once a day and on demand: visitor flows and runs are removed, the example and showcase
  flows and the target registration are recreated, and the platform alert state is cleared. The
  reset is an explicit host action, never automatic masking inside the product.
- Q: Is the cancel warning shown for every cancel? → A: Only when what is being cancelled includes
  a running step executed through the platform's management API, which is the only case where
  the platform records the alert. Cancelling queued or in-process steps shows today's dialog
  unchanged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The README's first screen answers "what, does it cover the areas, how do I try it" (Priority: P1)

An expert opens the repository or the Open Exchange page. Without scrolling past one screen they
read a one-line pitch, see a picture of a flow running, see the table of contest areas SentaiTask
covers, and find a "Try it" block with the demo address, the demo account, and the three
commands to run it locally.

**Why this priority**: The README is read by every voter, including the ones who never open the
demo. It costs hours and is effective immediately.

**Independent Test**: Render the README on the repository host at 1440×900. The pitch, the
picture, the contest-area table and the "Try it" block are all above the first scroll position
or start within it, in that order. Every link in the "Try it" block resolves.

**Acceptance Scenarios**:

1. **Given** the README, **When** it is rendered, **Then** its order from the top is: badges,
   title and one-line pitch, a picture of the product, "Try it" (public demo address, demo
   account, local quickstart), the contest-area table, and then Motivation and the rest.
2. **Given** the "Try it" block, **Then** the local quickstart is at most three commands, from a
   clean machine with Docker, to the canvas sign-in screen, and states the default local account.
3. **Given** the contest-area table, **Then** each row names the area, what SentaiTask offers there,
   and links to the section or spec that proves it. No row claims a capability that is not merged.
4. **Given** the roadmap, **Then** spec 010 is listed as done and the next items name specs 012 to
   015 by their titles.
5. **Given** the demo is unavailable (host down), **Then** the README still shows the product
   through its picture, and the "Try it" block says the local quickstart works without the demo.

---

### User Story 2 - A host brings up the public demo safely with one documented command (Priority: P1)

A team member with a fresh virtual machine and Docker follows one README section: set a host
name (optional) and a secret for the privileged accounts, run one command, and the demo is up.
Visitors sign in with the demo account. The platform's privileged accounts no longer accept the
default password, on the primary and on the target server.

**Why this priority**: It removes the first-ranked risk of the analysis. A public instance that
accepts the default administrator password can be taken over by any visitor, which would end the
demo and could embarrass the team.

**Independent Test**: On a clean machine, run the documented command with a secret. Confirm that
the canvas answers on the public port (HTTPS when a host name was given), that the demo account
signs in and can open and run the example flow, and that signing in with the default privileged
password fails on the canvas, on the platform's management portal and on the management API of
both instances.

**Acceptance Scenarios**:

1. **Given** a clean machine with Docker and the repository, **When** the host runs the documented
   demo command with a privileged secret, **Then** both instances start healthy and the canvas
   answers on the public port.
2. **Given** a host name was configured and resolves to the machine, **Then** the canvas is served
   over HTTPS with a valid certificate on that name, and plain HTTP redirects to it.
3. **Given** the demo is up, **When** anyone signs in with the platform's default privileged
   password, **Then** the sign-in is refused on the canvas and the management API of the primary,
   and on the target server's management API. The platform's management portal and every other
   web application except the canvas and the sign-in it needs are not reachable from outside the
   machine.
4. **Given** the demo is up, **When** a visitor signs in with the published demo account, **Then**
   they reach the canvas, can open, validate and run the example and showcase flows, can read the
   Task catalog and the Targets screen, and see the platform's verbatim refusal for anything their
   account may not do.
5. **Given** the demo account, **Then** it cannot create, change or delete platform users, roles,
   services or web applications, and cannot change the privileged accounts. The platform refuses,
   and the refusal is shown verbatim. Destructive steps still need their typed confirmation; the
   platform may allow the task-history purge to the demo account (the privileges the integrity
   check needs also allow it, T001), which is accepted on a disposable demo and documented.
6. **Given** the demo command is run without a privileged secret, **Then** it stops before starting
   anything and says which secret is missing.
7. **Given** the machine reboots, **Then** the demo comes back on its own with the same settings.

---

### User Story 3 - A visitor sees orchestration within a minute (Priority: P2)

A visitor who signed in to the demo opens *Open flow…* and finds, next to the spec 010 example, a
**showcase flow**: integrity checks of two databases on the primary and one on the target server
run in parallel and converge on a join that gates a final report step. They choose *Run now* and
watch it finish.

**Why this priority**: The spec 010 example shows two parallel steps. The product's differentiator,
which no competitor has, is orchestration: waves, a fan-in join and distributed steps. The demo
must show that without the visitor building anything.

**Independent Test**: On a freshly started demo, sign in as the demo account, open the showcase
flow, run it with the demo account's password for the primary and the target, and confirm every
step completes and the target step reports that it ran on the target.

**Acceptance Scenarios**:

1. **Given** a freshly started or reset demo, **Then** the showcase flow exists under a well-known
   name, validates with no errors, and contains only non-destructive, available step types.
2. **Given** the showcase flow, **Then** it has at least three parallel steps, one of which runs on
   the registered target server, and a join with the "all must succeed" policy before a final
   step.
3. **Given** the visitor runs it as the demo account, **Then** the run completes, each step shows
   where it ran, and no destructive confirmation is requested.
4. **Given** the sign-in screen of the demo, **Then** it shows the demo account and a one-line
   hint to open the showcase flow. This hint appears only on a demo instance, never on a normal
   installation.

---

### User Story 4 - The demo stays clean and the host can check it (Priority: P2)

A team member runs a reset command, or lets the daily reset run, and the demo returns to its
initial state. A status command tells them, in a few lines, whether both instances are healthy,
whether the platform is in its alert state, and how many flows and runs visitors created.

**Why this priority**: A week of anonymous visitors fills the instance with flows, runs and
cancelled jobs, and each cancel leaves the instance "unhealthy". An expert who arrives on day
five must see the same demo as one who arrives on day one.

**Independent Test**: On a running demo, create a visitor flow, run and cancel it, then run the
status command (it reports the extra flow, the run and the alert state), run the reset, and run
status again (initial counts, no alert, both healthy).

**Acceptance Scenarios**:

1. **Given** visitors created flows and runs, **When** the reset runs, **Then** every flow except
   the example and showcase flows is removed with its runs, the example and showcase flows are
   recreated if they were changed or deleted, and the target server is registered and online.
2. **Given** the platform is in its alert state, **When** the reset runs, **Then** the alert state
   is cleared on both instances and the reset reports that it did so.
3. **Given** the reset is scheduled daily by the host, **Then** it runs at the configured hour
   without anyone signed in, and its output is kept where the status command can show the last
   reset time.
4. **Given** the status command, **Then** it prints each instance's health, alert state, the count
   of flows and runs beyond the initial ones, and the time of the last reset, and exits non-zero
   when an instance is unhealthy.
5. **Given** the reset, **Then** it never changes the privileged accounts, the demo account or any
   platform setting other than those listed above.

---

### User Story 5 - The operator is warned before a cancel that raises a platform alert (Priority: P2)

An operator cancels a run, or one step, while a step executed through the platform's management
API is running. The confirmation tells them that IRIS will record the ended job as an alert and
that the instance may report "unhealthy" until the alert is cleared, and that the run and the
instance are fine. The step's *Cancel* tooltip describes what cancel really does.

**Why this priority**: It turns a confusing "the product broke my container" moment into an
expected outcome, on every installation, not only in the demo.

**Independent Test**: Start a flow whose integrity check runs for more than a few seconds; open
*Cancel wave*: the notice is present. Start a flow with only in-process steps; open *Cancel
wave*: the notice is absent. Hover a running integrity-check step's *Cancel*: the tooltip says the
job is asked to stop on the instance running it.

**Acceptance Scenarios**:

1. **Given** a run with at least one running step executed through the management API, **When**
   the operator opens *Cancel wave*, **Then** the dialog shows the alert notice in addition to
   today's text.
2. **Given** a run whose running steps are all in-process or still queued, **When** the operator
   opens *Cancel wave*, **Then** the dialog is today's dialog, without the notice.
3. **Given** a running step executed through the management API, **When** the operator chooses its
   *Cancel*, **Then** a confirmation with the same notice is shown before the cancel is sent;
   **When** the step is in-process or queued, **Then** cancel behaves as today.
4. **Given** any step's *Cancel* control, **Then** its tooltip states what happens: the job is
   asked to stop on the instance running it, and the step is marked cancelled.
5. **Given** the notice, **Then** it links to the limitations section that explains the alert and
   how to clear it.

### Edge Cases

- The host name does not resolve yet when the demo starts: the demo still starts and answers on
  plain HTTP; HTTPS starts working once the name resolves, without a restart.
- A visitor changes the demo account's own password through the platform: the platform decides
  whether that is allowed. The reset restores the published password, so the demo account works
  again after the next reset.
- A visitor cancels the showcase run while the target step is running: the target records its own
  alert; the reset clears alert state on both instances.
- The target server is down when the reset runs: the reset reports it, still cleans the primary,
  and exits non-zero so the host notices.
- Two resets overlap (manual during the daily one): the second waits or refuses; flows are never
  half-recreated.
- A visitor runs a step their demo account may not run (for example a destructive purge, or a
  security report): validation or dispatch shows the platform's refusal verbatim; nothing is
  hidden from the palette.
- The demo is reset while a visitor watches a run: their live view reports the run is gone, like
  for any deleted run; they can open the showcase flow again.

## Requirements *(mandatory)*

### Functional Requirements

**README**

- **FR-001**: The README MUST start, after the badges, with the title, a one-line pitch, a picture
  of the product in use, a "Try it" block, and the contest-area table, in that order, before the
  Motivation section.
- **FR-002**: The "Try it" block MUST give the public demo address, the demo account's name and
  password, and a local quickstart of at most three commands with the local default account.
- **FR-003**: Each contest-area row MUST link to the README section or spec that proves it, and MUST
  NOT claim anything that is not merged on the default branch.
- **FR-004**: The roadmap MUST list every merged spec as done (including 010) and name the planned
  specs 012–015.

**Public demo**

- **FR-005**: The repository MUST provide one documented command that starts the public demo on a
  machine with Docker: both instances, the canvas on a public port, and HTTPS when a host name is
  given.
- **FR-005a**: From outside the machine, the demo MUST expose only the canvas and the management API
  calls the canvas makes; the platform's management portal and other web applications MUST NOT be
  reachable.
- **FR-006**: The demo command MUST refuse to start without a host-provided secret for the
  platform's privileged accounts, and MUST set every privileged account that accepts a password,
  on both instances, to that secret before the instance accepts visitors.
- **FR-007**: The demo MUST create a demo operator account, with the same name on both instances,
  with a published password and only the privileges needed to sign in, read and save flows,
  validate and run non-destructive steps, read the Task catalog and the WQM categories, and sign
  in to the target server. It MUST NOT hold security administration privileges. Whatever else
  the platform allows with those privileges (T001: the task-history purge) MUST be documented in
  the demo section of the README.
- **FR-008**: The demo MUST contain the spec 010 example flow and a showcase flow composed only of
  non-destructive, available step types, with at least three parallel steps (one on the target
  server) converging on an "all must succeed" join before a final step.
- **FR-009**: On a demo instance only, the sign-in screen MUST show the demo account and a hint to
  open the showcase flow. A normal installation MUST NOT show it.
- **FR-010**: The demo MUST come back after a machine reboot without manual steps.

**Reset and status**

- **FR-011**: The repository MUST provide a reset command that removes every flow except the example
  and showcase flows, with their runs; recreates those two flows as shipped; registers the target
  server and sets it online; restores the demo account's published password; and clears the
  platform's alert state on both instances.
- **FR-012**: The reset MUST NOT change the privileged accounts or any platform setting other than
  those in FR-011, and MUST refuse to run on an instance that is not marked as a demo.
- **FR-013**: The host MUST be able to schedule the reset daily at a configured hour, and the time
  and outcome of the last reset MUST be kept.
- **FR-014**: The repository MUST provide a status command that reports, for both instances, health,
  alert state, flows and runs beyond the initial ones, and the last reset, and exits non-zero
  when an instance is unhealthy.

**Cancel warning**

- **FR-015**: *Cancel wave* MUST show an alert notice when, and only when, at least one step of the
  run executed through the management API is running.
- **FR-016**: Cancelling a single running step executed through the management API MUST ask for
  confirmation with the same notice; other steps keep today's one-click cancel.
- **FR-017**: The notice MUST say that IRIS records the ended job as an alert, that the instance
  may report "unhealthy" until the alert is cleared, that the run and the instance are fine, and
  MUST link to the limitations section.
- **FR-018**: The step *Cancel* tooltip MUST describe the current behavior: the job is asked to stop
  on the instance running it and the step is marked cancelled.

**Language and honesty**

- **FR-019**: All new user-facing text MUST be in English, matching the canvas.
- **FR-020**: The product MUST NOT hide, clear or reinterpret the platform's alert state on its own
  (Constitution III). Clearing it is only ever an explicit host action (FR-011).

### Key Entities

- **Demo instance**: an installation started by the demo command. Marked as a demo so that the
  sign-in hint (FR-009) and the reset (FR-012) can tell it apart from a normal installation.
- **Demo account**: an operator account with a published password and least privilege, present on
  both instances with the same name.
- **Privileged secret**: the host-provided password for the platform's privileged accounts. Never
  committed, never shown, never logged.
- **Showcase flow**: an ordinary saved flow with a well-known name and a fixed composition, created
  by the demo setup and by the reset.
- **Reset record**: the time and outcome of the last reset, readable by the status command.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: At 1440×900, the README's pitch, product picture, "Try it" block and the start of the
  contest-area table are visible without scrolling past the first screen and a half.
- **SC-002**: From a clean machine with Docker, a team member brings the public demo up in under 15
  minutes of wall time by following one README section, typing one start command.
- **SC-003**: On the running demo, 0 of the platform's privileged accounts accept the default
  password, on either instance, and 0 web applications other than the canvas and the management
  API's sign-in and product calls answer from outside the machine.
- **SC-004**: A first-time visitor goes from the demo address to watching the showcase flow finish
  in under 2 minutes.
- **SC-005**: After a reset, the status command reports 0 visitor flows, 0 visitor runs, no alert
  state and both instances healthy.
- **SC-006**: The demo stays reachable for the whole voting week (2026-09-28 → 2026-10-04), checked
  at least twice a day by the status command; any outage is detected within 12 hours.
- **SC-007**: In a cancel test, the alert notice appears in 100% of cancels that include a running
  management-API step and in 0% of the others.

## Assumptions

- The team has a virtual machine with Docker, a public IP and, optionally, a DNS name. Choosing
  and paying for it is outside this spec.
- The competition's Open Exchange page can be edited during voting to change the demo link. If it
  cannot, the README (linked from that page) still carries the stable address.
- IRIS 2026.2 lets the setup set the passwords of the built-in privileged accounts and create a
  role with the privileges FR-007 needs; the Plan proves the least-privilege set by running the
  example and showcase flows as the demo account (Constitution V).
- The platform's alert state can be cleared by an explicit administrative action, as documented in
  `docs/limitations.md`.
- The product picture for FR-001 is a still image until spec 014 delivers the animated one; spec
  014 replaces it in place.
- Deleting flows is not a product feature (spec 010 out of scope); the reset deletes them as a host
  action on the demo instance only.
- Monitoring beyond the status command (alerts to a phone, uptime services) is out of scope.
