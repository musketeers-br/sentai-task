# Data Model — 022 Runbook Gallery

**Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md) · **Research**: [research.md](research.md)

Everything here is frontend state and pure data. No server entity is added, changed or removed;
the only server-side artifact this feature touches is one **test** ([research R-2](research.md)).

## 1. Runbook (curated data, shipped in the codebase)

A named ready-made flow definition the product ships (Constitution II: data, never code —
composed only of catalog step types, extendable only through the ordinary change process).

```ts
interface Runbook {
	/** Card heading — what the spec names (English, FR-017). */
	title: string;
	/** One line: what this runbook is for (card copy, FR-003). */
	purpose: string;
	/** Suggested cadence, shown as text only (FR-004); absent = no suggestion. */
	suggestedCadence?: string;
	/**
	 * Identity: the flow name the platform's unique (case-insensitive) name index arbitrates.
	 * Use opens a flow of this name if one exists, otherwise creates one (FR-006).
	 * For the cross-server card this is the seeded showcase's name, so the demo's
	 * existing distributed flow is what opens.
	 */
	flowName: string;
	/** The flow definition, exactly what a create sends to POST /flows (FR-011). */
	definition: FlowDefinition; // name = flowName; steps/edges/joins/canvasGeometry
}
```

**Invariants** (vitest-enforced, [research R-10](research.md)):

- Exactly **seven** runbooks (the six the spec names + the example card, FR-002/FR-013); the set
  is a fixed, code-reviewed array.
- `flowName`s are unique and non-empty; `definition.name === flowName`.
- Every step's `type` is declared **and** available in the catalog; every declared parameter of
  that type is filled (its default or better).
- Every definition ships `canvasGeometry` for its nodes (the mini-graph is drawn from it, FR-003).
- The three definitions that also live server-side equal the shared fixtures byte-for-byte in
  name, fingerprint-equivalent content and geometry ([research R-2](research.md)):
  `tests/fixtures/example-flow.json`, `weekly-window-flow.json`, `showcase-flow.json`.

## 2. RunbookCard (pure view model)

Computed per gallery render from (runbook, registry, targets) — never stored:

```ts
type Availability =
	| { kind: 'runnable' }
	| { kind: 'unavailable'; reason: string }; // names the missing thing, e.g. "iris-target is not registered"

interface RunbookCard {
	runbook: Runbook;
	/** Registry label per step, plus the destructive flag (FR-005). */
	steps: Array<{ id: string; label: string; destructive: boolean; onTarget: string | null }>;
	availability: Availability; // FR-007: unavailable ⇒ Use disabled, reason shown
}
```

Rules (FR-007, [research R-4](research.md)): unavailable iff some step type is not declared or
not available, or some step's `target` is not in the targets list. The verdict is derived from
catalog and target data — it is not a permission decision; the platform decides permission at
create/run time and its refusal passes through verbatim (FR-009).

## 3. MiniGraph (pure geometry)

```ts
interface MiniNode { id: string; x: number; y: number; width: number; label: string; destructive: boolean }
interface MiniEdge { from: Point; to: Point } // segment between node border anchors
interface MiniGraph { nodes: MiniNode[]; edges: MiniEdge[]; viewBox: { w: number; h: number } }
```

`miniGraph(definition, registry): MiniGraph` — reads `canvasGeometry.nodes` (all shipped
definitions have it), scales positions into a fixed card viewBox preserving relative layout,
computes edge segments between source/target border anchors. No layout algorithm, no DOM. Every
node and edge is addressable by data-testid so the e2e can count them per card (FR-003's "the
graph that opens matches the graph the card drew" is enforced by comparing card counts to the
definition's steps/edges).

## 4. Use — the create-or-open outcome (value semantics)

`useRunbook(api, runbook): Promise<ApiResult<string>>` — same state machine `openExample` proves
today (spec 010 FR-017), generalized ([research R-3](research.md)):

```text
list flows ──ok──> found by flowName? ──yes──> { ok: true, value: id }   (open, never a duplicate)
   │                    │no
   │                    └─ create (POST /flows, operator's credential) ──201──> { ok, value: id }
   │                                                                    └─409──> re-list → id
   └─refused──> { ok: false, error }        └─refused──> { ok: false, error }   (verbatim, FR-009)
```

- The returned id navigates to the flow (the existing `flowHref` path); a refused outcome
  becomes the editor's error notice — the platform's status and reason, unmodified.
- In the page, the switch to the used runbook goes through the unsaved-changes guard as
  `{ kind: 'runbook'; runbook }` (FR-008, [research R-7](research.md)); the `'example'` kind
  retires (the example is a runbook now).
- A successful Use sets `galleryDismissed` (a flow is open — FR-001 no longer applies).

## 5. Gallery screen state

No new store: the gallery is a derived region of the Flows screen, replacing the invitation at
the same mount ([research R-6](research.md)).

```ts
showGallery = unreadable === null && editor.id === null && editor.steps.length === 0 && !galleryDismissed
```

- `galleryDismissed`: session state (not persisted), set by *Start from scratch* (FR-012) and by
  a successful Use; **reset** by the ready-made entry points (guide step 2, *Open flow…*)
  so they land on the gallery (FR-013).
- Precedence is unchanged: the unreadable-flow panel, refusal, unreachable and sign-in states
  win over the gallery (the gallery is never shown over a platform state, Constitution IV).
- The gallery owns no other state; the targets it read for verdicts are refetched each time it
  is shown (never cached across requests, Constitution III).

## 6. Superseded entities (so no later check flags a contradiction)

| Superseded | By | Where recorded |
|---|---|---|
| `EmptyCanvasInvitation` (spec 010 FR-016a) + the `noFlows` boot fact | the gallery region, FR-001 | spec FR-001, plan D-6, us21/us30 edits |
| `PendingSwitch { kind: 'example' }`, `openExample`, `showExample`/`onexample` props | `{ kind: 'runbook' }`, `useRunbook`, `onrunbooks` | spec FR-013, plan D-7/D-8 |
| `us20-example-flow.spec.ts` (all 7 scenarios) | `us31-runbook-gallery.spec.ts`, 1:1 guarantee mapping | plan *Testing Strategy*, [research R-9](research.md) |

## 7. Fixture contract

| Fixture | Bundled data (vitest) | ObjectScript definition (IRIS test) |
|---|---|---|
| `tests/fixtures/example-flow.json` | example card's definition | `Demo.ExampleDefinition()` — exists (`DemoTest.cls:60`) |
| `tests/fixtures/weekly-window-flow.json` | weekly-window runbook's definition | `DemoFlows.Payload()` — **new** `TestWeeklyWindowMatchesFixture` |
| `tests/fixtures/showcase-flow.json` | cross-server runbook's definition | `Demo.ShowcaseDefinition()` — exists (`DemoTest.cls:69`) |

Comparison is name + fingerprint-equivalent content + geometry, the way `DemoTest.Fixture`
(`DemoTest.cls:41-45`) and `example.test.ts:74-76` already do it.
