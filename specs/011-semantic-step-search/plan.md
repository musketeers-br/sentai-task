# Implementation Plan: Semantic Step-Type Search over the Closed Catalog

**Branch**: `011-semantic-step-search` | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-semantic-step-search/spec.md`

## Summary

Give the palette's existing search box semantic ranking over the closed step-type catalog. An operator
types what they mean; the product embeds that sentence, compares it against a stored vector per
catalog entry, and shows the closest entries first. Insertion stays an explicit operator action, a
result can only ever be a catalog entry, and the reviewed prose an engineer writes when they add a
capability is the only searchable text. The similarity service is configuration — a locally served
embedding model by default — and when it is unconfigured, unreachable, slow or incompatible the
palette behaves exactly as today, because every one of those crosses every layer as a typed value.

Technical approach, all decisions verified against the running instance and recorded in
[research.md](research.md): a `%Embedding.Interface` provider subclass named by a row in the
platform's `%Embedding.Config` table; a class-projected side table whose `VECTOR` column holds one
stored vector per entry; one SQL statement (`VECTOR_COSINE(EMBEDDING(...), TO_VECTOR(Vector))`) for
the whole 9-row ranking; a lazily rebuilt corpus keyed by a hash of the catalog's
`(type, description)` pairs; and a pure frontend view model that re-orders entries it already holds.

## Technical Context

**Language/Version**: ObjectScript on InterSystems IRIS 2026.2; TypeScript + SvelteKit (Svelte 5
runes) for the canvas

**Primary Dependencies**: `%Embedding.Interface` (the two-method provider contract the product
owns), `EMBEDDING()`, `TO_VECTOR()`, `VECTOR_COSINE()`, `%Library.Vector`, `%Net.HttpRequest`;
frontend: `vitest`, `svelte-check`, `playwright`

**Storage**: IRIS persistent class side table (one row per catalog entry, 9 today); provider
configuration in the platform's `%Embedding.Config` table

**Testing**: `zpm "test sentai-task -only` (the whole 268-method suite — there is no single-class run);
`npm run check`; `npm test` (vitest, pure modules); `npx playwright test` (e2e against the published
bundle on :52773)

**Target Platform**: Linux containers (IRIS 2026.2 primary + a compose-network embedding service);
browsers for the canvas

**Project Type**: two codebases — an ObjectScript REST API and a SvelteKit SPA that the same
instance serves at `/csp/sentai/`

**Performance Goals**: the ranked palette lands within 1 s of the last keystroke (FR-009, SC-003).
Measured baseline: one embed call is ~75 ms from inside `iris` (71/87/79/75/74 over five runs), so a
warm request is on the order of 100 ms — roughly 10× headroom.

**Constraints**: corpus is 9 rows, so the ranking is an exact scan with no ANN index (FR-027, R-006);
one embed call per keystroke against a stored corpus (R-004); query text must not leave the host in
the default configuration (FR-010); the relevance floor is an absolute 0.20 (FR-008, R-008)

**Scale/Scope**: 1 new REST route, 1 provider class, 1 class-projected side table (9 rows), 1 search
service, 1 pure frontend view model + tests, 1 description field per catalog entry, palette changes.
The corpus is expected to stay well under 100 entries; the index re-evaluation threshold is 10,000
(R-006).

## Constitution Check

*GATE: evaluated before Phase 0 research and re-evaluated after Phase 1 design.*

### I. Layered Architecture — PASS

`sentai.search` is an application service that depends on two things: `sentai.registry.StepType`
(the declared catalog, through its own accessor) and the `%Embedding.Interface` contract. Neither is
concrete infrastructure the core reaches around — the provider is bound by a table row at the edge.
`Dispatcher` gains one delegating route and keeps its "no business logic" contract (R-010): it reads
`q`, hands off, and writes the outcome it is given. On the frontend, the component calls a pure
`lib/palette/search.ts`, which calls `client.ts`; no `fetch` in a component (R-012). The provider
class is the one place that knows HTTP exists, and it knows nothing about the palette.

### II. Closed Capability Set — PASS, and structurally enforced

The corpus is the catalog, read only through `StepType.GetCatalog()` (R-009). The class-name field is
never read, so the legacy `custom` entry has nothing to leak. A result is a re-ordering of
`registry` the browser already holds: the view model receives identifiers and maps them onto entries
it has, so it is not able to introduce one even by mistake (R-011). The provider class is a compiled
class in the source tree, not a name taken from input. Adding a capability remains "a catalog entry
plus what it names" — the corpus rebuild is lazy and automatic (R-005), so no second registration
point exists. `StepTypeTest` gains the non-empty-description assertion so an entry without prose
cannot land (R-009, FR-015).

### III. Delegated Authorization — PASS

Untouched by construction. This feature reads a catalog and calls a similarity service; it
authorises nothing, and no platform call is made on any path. `Dispatcher.OnPreDispatch` still
validates the token per request with no caching. The one delegation the feature does make — the
HTTP call to the embedding service — is to a service the operator configured, with a key the operator
supplied, and it asks for nothing privileged. FR-028 states the guarantee in the spec.

### IV. Errors as Values — PASS, and this is the feature's second subject

Every degradation of the similarity service is a typed reason crossing the API as a value
(`available: false`), never an exception through the layers and never a behaviour change
(R-007, FR-022–FR-026). The request is bounded by an explicit timeout so "slow" is an answer and not
a hang (R-013). A comparison that cannot be made is treated as unavailability, never as a poor match
(FR-025). No partially ranked set ever escapes as a success. The HTTP status for unavailability is
200 deliberately, and R-007 records why: the operator's experience is a working palette, and an error
status would manufacture the error state SC-004 forbids.

### V. Verifiable Increments — PASS

Each user story in the spec is one increment carrying its own test, and the slicing is by observable
behaviour: story 1 (search by intent), story 2 (degrades to today's behaviour), story 3 (only ever
offers the closed catalog), story 4 (a capability is findable with the entry alone). Story 2 is
genuinely shippable before story 1's full value and is worth sequencing early — it is what makes
story 1 safe. The deliverable is never "the model layer for search"; each unit ends at a behaviour an
operator or a test can see. Tasks will be sliced this way in `/speckit-tasks`, test first.

### VI. Technology Agnosticism — PASS

The spec mandates no technology; this plan is where the choices live, and each is justified above.
Within the design, the search domain names no platform, vendor, model or endpoint: it depends on a
two-method abstraction it owns and on configuration (R-002). Swapping providers — to
`%Embedding.SentenceTransformers`, to `%Embedding.OpenAI`, to a hosted service — is a row in a
table and a documentation change, not a code change. The relevance floor is a constant with its
measurement recorded beside it (R-008), not a consequence of one model's geometry.

### Engineering Standards

- **SOLID / Clean Architecture** — one reason to change per module: the provider knows HTTP and
  nothing else; the search service knows the catalog and the ranking; the view model knows how a
  ranking becomes a palette; the component knows how to render.
- **TDD** — every task in `/speckit-tasks` writes its test first, against the story's behaviour.
- **Error as Value** — see IV.
- **YAGNI** — no index (R-006), no lock around an idempotent rebuild (R-005), no description
  rendering in the palette (R-011), no second provider abstraction before a second provider exists.
- **Reproducibility** — one `docker compose up -d` brings up the embedding service with its model
  pulled; a stranger needs no other toolchain.

### Complexity Tracking

> No violations. No entry required.

## Project Structure

### Documentation (this feature)

```text
specs/011-semantic-step-search/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output — 13 verified decisions
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── api-delta.md     # the one new route, the one new field, the provider row
│   └── palette-search.md # the frontend view-model contract + wire shapes
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
src/sentai/
├── registry/
│   └── StepType.cls             # MODIFIED: description field per catalog entry (FR-014)
├── search/                      # NEW: the search package, beside the registry it reads
│   ├── StepCorpus.cls           #   the stored corpus — one row per catalog entry
│   ├── StepSearchService.cls    #   the application service: corpus currency + ranking
│   ├── SearchOutcome.cls        #   the typed outcome that crosses every layer
│   └── EmbeddingService.cls     #   the provider: host/port/path/model from configuration
├── rest/
│   └── Dispatcher.cls           # MODIFIED: one route, one delegating method
└── ...

tests/sentai/
├── unittest/
│   ├── registry/StepTypeTest.cls        # MODIFIED: every entry has a description
│   └── search/                          # NEW: flat per domain, as the suite already is
│       ├── StepSearchServiceTest.cls
│       ├── StepCorpusTest.cls
│       ├── SearchOutcomeTest.cls
│       └── EmbeddingServiceTest.cls
└── ...

frontend/src/lib/
├── palette/
│   ├── search.ts               # NEW: pure view model — ranking becomes a palette
│   ├── search.test.ts          # NEW: vitest
│   └── Palette.svelte          # MODIFIED: suggestion group, debounce, latest-wins
├── api/
│   ├── client.ts               # MODIFIED: searchStepTypes(q)
│   └── wire.ts                 # MODIFIED: fromWireStepSearch
└── ...

docker-compose.yml              # MODIFIED: the ollama service with all-minilm pulled
README.md                       # MODIFIED: the provider section (FR-012)
```

**Structure Decision**: keep the existing two-codebase layout (Option 2 in the template's terms,
already in place and described in `AGENTS.md`). The new backend code is a new `sentai.search` package
placed *beside* `sentai.registry` rather than inside it, because it depends on the registry and must
not be able to modify it — the closed catalog's accessor stays the only way in, and that boundary is
what makes Principle II checkable by reading the imports. `src/sentai` is flat today — 26 classes, no
nested package — so the provider is `sentai.search.EmbeddingService` rather than a deeper name that
would be the only 3-level class in the codebase, and the tests sit flat under
`tests/sentai/unittest/search/` as every other suite does. The frontend view model is a new file in
the existing `lib/palette/` domain directory, matching `lib/flows/list.ts` (pure module plus
colocated test). No new top-level directory, no new build step, no new test runner.

## Phase 1 Design Summary

The full design is in [data-model.md](data-model.md) and [contracts/](contracts/). In brief:

- **Corpus** — `sentai_search.StepCorpus`: `type` (id, 9 rows), `description`, `vector`
  (`%Library.Vector`), `corpusVersion`, `embeddedAt`. Derived from the catalog, never the other way
  round.
- **Currency** — `corpusVersion` is a hash over the catalog's `(type, description)` pairs. A search
  computes the current version, rebuilds if it differs, then ranks. The rebuild is an idempotent
  upsert, so a duplicate concurrent rebuild is harmless and no lock is needed (R-005).
- **Outcome** — one tagged value crosses the layers: `matches` (ranked identifiers above the floor)
  or `unavailable` (a typed reason). It is the single thing the Dispatcher writes and the single
  thing `client.ts` maps.
- **Route** — `GET /catalog/step-types/search?q=…`. 400 on a missing or empty `q`; 200 with
  `available: false` and a reason for every degradation; never an error status for a degraded
  provider (R-007).
- **Ranking** — one SQL statement, exact scan, absolute floor 0.20 (R-001, R-008).
- **Palette** — the view model maps ranked identifiers onto `registry` entries it already holds,
  producing a leading suggestion group plus the remainder from the existing `paletteGroups()`,
  unchanged (R-012).

### Constitution Check — re-evaluated after Phase 1

No gate changed status. Two design details survived Phase 1 that are worth stating because they are
where a weaker design would have bent:

1. **The view model cannot introduce a capability.** It receives ranked *identifiers* and maps them
   onto entries it already holds; an identifier with no matching entry is dropped, not rendered. The
   closed set is therefore a property of the type, not of a filter someone could forget (R-011).
2. **Unavailability is a 200 with a reason, and the reason never becomes a toast.** The reason is
   carried in the response and visible in the network/response, while the palette renders its normal
   grouped list. Nothing in the component's render path can surface it as an error, because the
   component's only search state is the ranked list and its absence (R-007, R-012).

No `NEEDS CLARIFICATION` remains; all thirteen are resolved in [research.md](research.md).
