# Research: Runbook Gallery — Named Ready-Made Flows Instead of the Empty Canvas

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Date**: 2026-10-01

Frontend-only in product terms: every mechanism this feature needs already exists (the
create-or-open example pattern, the registry, the targets list, the guard). The findings below
are read from the current tree (with `file:line`), and each decision names its rejected
alternative. One IRIS-side **test** is added (R-2); no ObjectScript product code changes.

---

## R-1 Where the runbook definitions live

**Decision**: bundled curated data in `frontend/src/lib/flows/runbooks.ts`, following `example.ts`
— the spec 010 precedent of "data, not code (Constitution II)".

**Findings**: The example flow already ships exactly this way (`example.ts:1-11`): a definition
composed only of registry types, created at use time through the ordinary flow API with the
operator's own sign-in. The canvas already loads the registry (`editor.registry`, used by
`exampleAvailable`, `+page.svelte:234`), and the API client already exposes everything Use needs:
`listFlows()` (`client.ts:216`), `createFlow(def)` (`client.ts:224`), `listTargets()`
(`client.ts:332`). The seeded flows are seeded by the demo script for the demo's sake
(`iris-demo.script:12-16`); the gallery must be a **product** state that works on any
installation, so it cannot depend on seeding having run.

**Alternatives rejected**:
- *A server-side runbook catalog + a new read endpoint* — a new API surface, new wire contract
  and backend work against the voting-week budget, for zero user-visible gain (Constitution VI
  keeps the door open; nothing in the spec asks for server-side runbooks).
- *Runbooks as seeded saved flows only* — a non-demo installation would show an empty gallery,
  and the daily demo reset (`scripts/demo/reset.sh` → `Demo.Reset()`, `Demo.cls:172`) deletes
  everything but the two `IsSeeded` names (`Demo.cls:214-218`), so even the demo would lose
  cards between resets.

## R-2 Keeping the three fixture-backed definitions in sync

**Decision**: the house two-sided fixture pattern, completed. The three runbooks whose
definitions also exist server-side — the example (`Demo.cls:77-88`), *Weekly maintenance window*
(`DemoFlows.cls:13-51`) and *Cross-server nightly* (= the showcase, `Demo.cls:93-107`) — are
compared to `tests/fixtures/{example-flow,weekly-window-flow,showcase-flow}.json` from **both**
sides: vitest for the bundled data, `DemoTest` for the ObjectScript definitions. Two of the three
IRIS comparisons already exist (`DemoTest.cls:60-75`, `TestExampleMatchesFixture`,
`TestShowcaseMatchesFixture`); this plan adds the missing one, `TestWeeklyWindowMatchesFixture`
— a test-only change. `weekly-window-flow.json` already exists in the tree but is referenced by
no test today; this plan puts it to work.

**Findings**: `Demo.cls:75-76` states the rule: "identical to
`frontend/src/lib/flows/example.ts` (both are compared with `tests/fixtures/example-flow.json`)".
`DemoTest.Fixture` reads the fixtures through the read-only mount
(`/home/irisowner/dev/tests/fixtures/`, `DemoTest.cls:41-45`), so no data has to be duplicated
into the IRIS instance. The e2e-facing shape is the same: `us20` proves the example's idempotence
today, `media/showcase.media.ts:13` reads the showcase fixture directly.

**Why it matters**: on the demo, a card whose bundled definition drifted from the seeded flow
would draw one graph and open another — the exact "five seconds, then betrayal" this feature
exists to prevent.

**Alternatives rejected**:
- *Let the seed read the fixture as its source* — changes the demo setup; FR-014 forbids it.
- *Accept drift, fix by review* — no failing test means the drift ships silently.

## R-3 Use semantics: create-or-open by the runbook's flow name

**Decision**: generalize `openExample`'s create-or-open (`example.ts:61-75`) into
`useRunbook(api, runbook)`: list flows → find by `flowName` case-insensitively → open that id;
otherwise create through the ordinary `POST /flows`; a 409 re-lists (someone else created it
meanwhile). The runbook carries its own `flowName` — the identity the platform's name index
arbitrates. For *Cross-server nightly* the flowName is the seeded showcase's name
(`"Showcase: nightly checks across servers"`, `Demo.cls:15`), so on the demo the existing
distributed flow is what opens; for *Weekly maintenance window* it is the `DemoFlows` XData name.

**Findings**: the name index is the platform's uniqueness arbiter (spec 010 FR-017, proven by
`us20`'s idempotence scenario); `findExample` (`example.ts:46-49`) is the case-insensitive lookup
precedent. The demo's daily reset keeps the showcase but deletes a used *Weekly maintenance
window* (`IsSeeded` covers only two names, `Demo.cls:214-218`) — and the card does not care:
open if it exists, create from the definition if it does not.

**Alternatives rejected**:
- *Copy with a suffixed name ("Weekly maintenance window (2)")* — the spec's Assumptions reject
  it: same-name identity is the only consistent rule, duplicates litter the shared demo account,
  and the reset would delete the copies as visitor flows.
- *Run without saving* — a dispatch needs a saved flow; the run contract does not change here
  (FR-006 requires "a saved flow like any other").

## R-4 What a card's availability verdict knows — and what it must not

**Decision**: a card is runnable iff every step type in the definition is declared **and**
available in the loaded registry, and every step that names a `target` finds that target in the
targets list (fetched once, when the gallery is shown, through the existing `listTargets()`).
Otherwise the Use control is disabled and the card names the missing thing. Everything else — a
namespace that does not exist, a permission — is **not** pre-guessed: the create/run path
surfaces the platform's refusal verbatim (FR-009).

**Findings**: `StepTypeInfo` carries `available` and `destructive` (`document.ts:6-14`; the
catalog at `StepType.cls:14-87` marks `compact-globals`, `defragment-globals`,
`purge-audit-records`, `custom` unavailable). A remote step is a step with a `target` field
(`document.ts:49-50`; showcase step 03, `Demo.cls:100`). The demo registers `iris-target`
(`Demo.cls:17`, `EnsureTarget`, `Demo.cls:151`). The verdict is derived from catalog and target
**data** — it is never a cached permission outcome (Constitution III): permission is decided by
the platform at create and run time, as today.

**Alternatives rejected**:
- *Also gate on namespaces* — the Flows screen has no namespace list and the platform's
  validator is the authority; a refused create is a value (FR-009), not a card state.
- *Gate on target online-ness* — offline is a run-time fact; existence is the resource fact
  FR-007 names.

## R-5 The mini-graph: pure SVG from the definition's geometry

**Decision**: a pure module `miniGraph.ts` computes a scaled layout from the runbook's
`canvasGeometry.nodes` plus edge segments between node anchors; `MiniGraph.svelte` renders a
small SVG — rounded node rects labelled with the registry's step-type labels (short; `taskName`
is too long), edges with direction, destructive steps carrying the palette's destructive accent.
vitest covers the pure math; the e2e asserts node/edge counts per card through data-testids.

**Findings**: every definition in play already ships authored geometry (`DemoFlows.cls:39-49`,
`Demo.cls:105`, `example.ts:34`), so no layout algorithm is needed — only scale-to-fit. The
editable canvas uses `@xyflow/svelte`; embedding seven read-only editor instances would drag the
whole editor stack into cards with no headless-testability.

**Alternatives rejected**:
- *SvelteFlow per card* — heavy, provider-wrapped, and untestable headlessly for what is a
  static picture.
- *Hand-drawn static images* — they lie when a definition changes and double the drift surface
  R-2 exists to close.

## R-6 The gallery's mount, derivation and dismissal

**Decision**: the gallery replaces the invitation at its mount (`+page.svelte:556-561`) with a
widened derivation: `showGallery = unreadable === null && editor.id === null && editor.steps.length
=== 0 && !galleryDismissed`, rendered in the Flows editing screen as today. The `noFlows` term is
dropped (FR-001: also on instances with saved flows — the demo's exact case);
`invitationDismissed` renames to `galleryDismissed`, set by *Start from scratch* and by a
successful Use. The unreadable-flow panel (`+page.svelte:563-573`) and every non-editing state
(refused, unreachable, sign-in overlay) keep precedence, exactly as today. The top bar is not
touched — the gallery is in-canvas, so the 1440 px fit (spec 021's R-4) is not at risk.

**Findings**: today's derivation `+page.svelte:236`; the boot-time `noFlows` fact
(`+page.svelte:77`, `:232`) retires with the invitation. The palette and the top-bar controls
remain around the gallery (as they do around the invitation today — `us30`'s first tour anchor
proves the palette exists there), which is what keeps spec 021's anchors valid (FR-015).

**Alternatives rejected**:
- *A modal gallery* — the spec makes it the empty-canvas state, not a dialog; a modal adds
  dialog semantics and a close rule for no gain.
- *Keep the invitation for no-flows instances, gallery otherwise* — two empty states to build,
  maintain and test; FR-001 says one.

## R-7 The guard: one ready-made switch kind

**Decision**: `PendingSwitch`'s `{ kind: 'example' }` (`guard.ts:8`) generalizes to
`{ kind: 'runbook'; runbook: Runbook }`; `perform()` gains the open-by-runbook case; the example
becomes just a runbook. The dialog copy is unchanged (it speaks of the open flow and Save /
Discard / Cancel, not of the target).

**Findings**: the guard kinds live in `guard.ts:5-10`, the `perform` switch in
`+page.svelte:302-310`, and `openExampleNow` (`+page.svelte:318-330`) is the exact shape of the
new `openRunbookNow`. `guard.test.ts` enumerates the kinds today.

**Alternatives rejected**:
- *Keep `'example'` and special-case the gallery through it* — two paths through the guard for
  one semantics, and the pending switch could not name which runbook was chosen.
- *Bypass the guard* — FR-008 forbids it; `us20`'s guard scenario moves to `us31` unchanged in
  spirit.

## R-8 Entry points: one ready-made path, the lone example retires into a card

**Decision**: the *Getting started* dialog's and the *Open flow…* dialog's ready-made buttons
become **Browse runbooks** and call a page handler that (through the guard, when the canvas is
dirty) lands on the empty-canvas state with `galleryDismissed` reset — i.e. they lead to the
gallery (FR-013). The guide's step 2 copy (`steps.ts:17-20`, action `'open-example'`) is
rewritten for the gallery. The example flow becomes the seventh card, reusing
`exampleDefinition()`; its fixture tests stay. `openExample`'s create-or-open folds into
`useRunbook` (`example.ts` keeps the name constant and the definition).

**Findings**: the two buttons live at `GettingStartedDialog.svelte:22` and
`OpenFlowDialog.svelte:81`; both take `showExample` + `onexample` props from the page. The old
"hidden when the example is unavailable" gating (`us21:150-168`, spec 010 FR-019's button rule)
is superseded: the entry is always offered and the honesty moves to the per-card verdicts
(FR-005, FR-007 of this spec).

**Alternatives rejected**:
- *Keep both buttons pointing at the single example* — FR-013 forbids a lone-example path.
- *Hide the guide entry when no card is runnable* — the gallery with its reasons is the honest
  screen; verdicts are per card.

## R-9 Existing-suite impact, owned

**Decision**: `us20-example-flow.spec.ts` is retired; its guarantees move 1:1 into the new
`us31-runbook-gallery.spec.ts` (offered → a card is present; idempotent → Use twice, one flow;
guard → Use over unsaved edits asks; unavailable → disabled card with reason).
`us21-getting-started.spec.ts` adapts its step-2 scenario, its "on first use" scenario and its
invitation theming shot to the gallery; `us30-first-time-tour.spec.ts`'s single
invitation-under-tour scenario asserts the gallery instead (FR-015).

**Findings**: `us20` (7 scenarios, all around `example-invitation` and the example buttons);
`us21:150-168`, `:171-180`, `:202-218`; `us30:181-191`. `example.test.ts`'s fixture equality
stays, now serving the card's reuse of the definition.

**Alternatives rejected**:
- *Keep `us20` driving the example card directly* — it would duplicate `us31`'s surface
  click-for-click; the guarantees mapping is 1:1 and is documented in the plan and tasks.

## R-10 The seven cards' content (authoring rules)

**Decision**: six runbooks plus the example card, exactly (Q1 answer A). Rules: only declared
**and available** types (the catalog's available twelve, `StepType.cls:14-84`); every declared
parameter filled with its default or better (FR-011); every definition ships `canvasGeometry`;
titles and copy in English (FR-017); a suggested cadence where the input names one.

| Card (title) | flowName (identity) | Steps (→ join) | Cadence |
|---|---|---|---|
| Nightly integrity sweep | Nightly integrity sweep | integrity-check USER ∥ IRISAPP → ALL_MUST_SUCCEED → db-size-report %SYS | nightly |
| Weekly maintenance window | Weekly maintenance window | the `DemoFlows`/fixture definition verbatim (storage-headroom ∥ db-size → switch-journal → integrity USER ∥ %SYS → purge) | weekly |
| Pre-upgrade checklist | Pre-upgrade checklist | security-posture ∥ web-app-inventory ∥ certificate-expiry (warnDays 30) → ALL_MUST_SUCCEED → db-size-report | — (run before an upgrade) |
| Certificate expiry watch | Certificate expiry watch | certificate-expiry-check (warnDays 30) | daily |
| Security review | Security review | permissions-inventory ∥ security-posture ∥ oauth-inventory (three reads, wave 1) | — |
| Cross-server nightly | Showcase: nightly checks across servers | the showcase/fixture definition verbatim (3× integrity across servers → join → db-size-report) | nightly |
| Example: storage health check | Example: storage health check | `exampleDefinition()` (storage-headroom ∥ db-size) | — |

**Findings**: the showcase minus its remote step is the sweep's shape; the security reads are
three independent `platform-read` steps, so no join is needed for them to run as one wave (the
example flow's two edges-less steps prove the pattern, `example.ts:13`). `warnDays` default is 30
(`StepType.cls:69-72`) — the input's "30 dias".

**Alternatives rejected**:
- *Per-namespace variants to pad the count* — Q1 answer A is normative: exactly six plus the
  example card; more enter later through the ordinary change process.
