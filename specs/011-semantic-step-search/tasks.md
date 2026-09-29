---
description: "Task list for semantic step-type search over the closed catalog"
---

# Tasks: Semantic Step-Type Search over the Closed Catalog

**Input**: Design documents from `/specs/011-semantic-step-search/`

**Prerequisites**: plan.md, research.md, data-model.md, contracts/api-delta.md,
contracts/palette-search.md, quickstart.md

**Tests**: Included, test-first. The constitution requires automated tests before merge covering the
observable behavior each task delivers, and Principle V requires slicing by user-observable behavior
with the test written first.

**Organization**: Tasks are grouped by user story so each story can be implemented, tested and
delivered independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)
- Include exact file paths in descriptions

## Conventions this list assumes

Read `AGENTS.md` first. The things a task below depends on that are easy to get wrong:

- **Two codebases, two loops.** Backend changes need a load, not just a file write:
  `docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP` then `zpm "load /home/irisowner/dev"`.
  There is **no single-class test run**; the gate is `zpm "test sentai-task -only"` (268 methods).
- **`src/sentai` is flat.** New classes are `sentai.<domain>.<Class>`; there is no nested package
  anywhere in the tree today. New tests sit flat in `tests/sentai/unittest/<domain>/`.
- **Backend test class shape**: `Class sentai.unittest.<domain>.<Name>Test Extends sentai.unittest.SentaiTestCase`,
  4-space indent, assertions via `$$$AssertEquals`, `$$$AssertTrue`, `$$$AssertNotTrue`, `$$$AssertStatusOK`.
  Route tests set `Set %request = ##class(%CSP.Request).%New()`, call the `Dispatcher` class method
  directly, then assert on `%response` (see `tests/sentai/unittest/rest/StepTypeCatalogTest.cls`).
- **Frontend test shape**: `import { describe, expect, it } from 'vitest';`, colocated
  `*.test.ts`, tabs for indentation, single quotes.
- **Never hand-edit a `Storage` block**; the compiler generates it.
- The backend suite must stay green with **no embedding provider configured at all** — that is the
  state CI runs in (research R-001).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the embedding service the dev stack provides

- [X] T001 Add an `ollama` service to `docker-compose.yml`: image `ollama/ollama`, a named volume for
      downloaded models, and a first-boot step that pulls `all-minilm`. Publish **no** host port — the
      primary reaches it on the compose network as `http://ollama:11434`. Note in a comment that the
      dev `iris` and the unrelated `ollama` on the `triageaide_fhir-net` network are separate
      containers and the service name must resolve inside this stack (research R-003).
- [X] T002 Verify the stack and the model (`docker-compose.yml`, via `docker compose`): `docker
      compose up -d`, `docker compose ps` shows both services up, and
      `docker compose exec ollama ollama list` shows `all-minilm`. Confirm from the IRIS container
      that `http://ollama:11434/v1/embeddings` answers with a 384-dimension vector.

**Checkpoint**: the provider is reachable from `iris`; nothing in the application is wired to it yet

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the substrate every story needs — the reviewed prose, the value type, the provider, the
storage, and the test double that keeps the suite hermetic

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Descriptions for all nine entries in `src/sentai/registry/StepType.cls` — one
      hand-written sentence each in the `XData Catalog` block, saying what the capability is **for**
      in the operator's terms, in the same style as the existing `parameters` entries' own
      `description` fields. Never a restatement of the label, and never derived from the entry's
      `class`. Cover `integrity-check`, `compact-globals`, `defragment-globals`, `switch-journal`,
      `purge-audit-records`, `purge-task-history`, `storage-headroom-check`, `db-size-report`, and
      `custom` (whose sentence must say it is a placeholder for an operator-declared class, because it
      is the sharpest test of FR-013/FR-018). `GetCatalog()` in the same class needs no change — it
      returns the block as is.
- [X] T004 [P] Create `src/sentai/search/SearchOutcome.cls`: the tagged value every layer crosses
      (Constitution IV). Two shapes — `matches` carrying a ranked array of `{type, score}`, and
      `unavailable` carrying one reason from `not-configured` · `unreachable` · `slow` ·
      `incompatible` · `error`. An `unavailable` outcome must not be constructible with matches
      alongside it, and must serialize to `{"available":true,"matches":[…]}` or
      `{"available":false,"reason":"…"}` per contracts/api-delta.md. Exceptions are never the failure
      channel; give the class a `%ToJSON`-shaped projection, not a `throw`.
- [X] T005 [P] Create `src/sentai/search/EmbeddingService.cls`, extending the platform's
      `%Embedding.Interface`. Implement its two abstract class methods: `Embedding(input, configuration)`
      returning a `%Vector`, and `IsValidConfig(config, ByRef errorMsg)` returning false with a
      readable message when `host`, `path` or `model` is missing. Read **everything** — host, port,
      `https`, `path`, `model`, optional `apiKey` — from the `configuration` argument; hardcode
      nothing (FR-011). Build the request body with a `%DynamicObject`: an interpolated JSON object
      literal is a compile-time error in ObjectScript (research R-001a). Set explicit connect and
      read timeouts so a slow provider is an answer rather than a hang (R-013). Do **not** call
      `api.openai.com` or any hardcoded host.
- [x] T006 Create `src/sentai/search/StepCorpus.cls`, the persistent corpus: `type` (IdKey),
      `description` (`%String` MAXLEN), `vector` (`%Library.Vector` **with no length** — a lengthless
      `VECTOR_COSINE` on the column fails with `SQLCODE=-260`, and `TO_VECTOR(vector)` in the query
      is what satisfies it, research R-001), `corpusVersion` (`%String(64)`), `embeddedAt`
      (`%TimeStamp`). No index beyond the id key. Do not hand-write or hand-edit the `Storage` block.
- [x] T007 [P] Create `tests/sentai/unittest/search/FakeEmbeddingService.cls`: a test double extending
      `%Embedding.Interface` that returns a **deterministic** vector derived from its input, so tests
      can assert a specific ranking without a network. It must be a test-only class; nothing in
      `src/` may reference it. Tests point a `%EMBEDDING.Config` row at it and remove the row
      afterwards, which is also how the `not-configured` case is exercised.
- [x] T008 [P] A `suggested` category color in `specs/002-canvas-ui/contracts/tokens.json`, then
      `cd frontend && npm run generate:tokens` to regenerate them. The generated
      `frontend/src/lib/design/tokens.{css,ts}` are gitignored and must never be hand-edited
      (AGENTS.md). The palette's heading markup interpolates
      `var(--category-${group.category})`, so this token is what the SUGGESTED group reads.

**Checkpoint**: Foundation ready — the substrate exists and compiles with no provider configured

---

## Phase 3: User Story 1 - Find the right step type by describing the job (Priority: P1) 🎯 MVP

**Goal**: the operator types a sentence and the closest catalog entries are offered first, ahead of
today's list, with everything today's list showed still reachable.

**Independent Test**: with the provider usable, type "free up disk space", "check my globals are
sound", "get rid of old audit records" and "rotate the journal" — each intended entry is among the
first shown; nothing is inserted into the canvas without an explicit action; the rest of the palette
is unchanged.

### Tests for User Story 1 ⚠️ write these FIRST and watch them fail

- [x] T009 [P] [US1] Create `tests/sentai/unittest/search/StepSearchServiceTest.cls` asserting, with
      the `FakeEmbeddingService` row installed: a ranking returns `matches` ordered by descending
      `score`; a below-floor query returns `available: true` with an **empty** `matches`; ties keep
      catalog order; and no returned `type` is absent from
      `##class(sentai.registry.StepType).GetCatalog()`.
- [x] T010 [P] [US1] Create `tests/sentai/unittest/rest/StepTypeSearchTest.cls` asserting
      `##class(sentai.rest.Dispatcher).SearchStepTypes()` returns `200` with the ranked body, and
      `400` with the `Problem` shape when `q` is absent, empty, or whitespace-only — and makes no
      provider call in that case.
- [x] T011 [P] [US1] Create `frontend/src/lib/palette/search.test.ts` asserting the behaviour table in
      contracts/palette-search.md: `filterLocally` reproduces today's substring rule **including its
      `className` match**; `paletteSections` with an empty query or a `null` outcome equals today's
      `paletteGroups()`; a ranking prepends a `suggested` section and removes those entries from their
      category groups; an entry never appears twice.

### Implementation for User Story 1

- [x] T012 [US1] Create `src/sentai/search/StepSearchService.cls` with class parameters
      `EmbeddingConfigName = "sentai-steps"` and `MinScore = 0.2` (the **absolute** floor, measured —
      research R-008), and methods `Search(q)` and a corpus builder. The builder embeds each catalog
      entry's `description` when the corpus is empty; `Search` ranks with exactly one statement —
      `SELECT Type, VECTOR_COSINE(EMBEDDING(?, :config), TO_VECTOR(Vector)) AS score FROM sentai_search.StepCorpus ORDER BY score DESC` —
      then filters at the floor and returns a `SearchOutcome`. `$VOP` has no arithmetic, so SQL is the
      only way to compare (R-001). Read the catalog through
      `##class(sentai.registry.StepType).GetCatalog()`.
- [x] T013 [US1] Add the `SearchStepTypes` route and method to `src/sentai/rest/Dispatcher.cls`,
      beside `ListStepTypes`:
      `<Route Url="/catalog/step-types/search" Method="GET" Call="SearchStepTypes"/>`. The method reads
      `q` from `%request.Get("q")`, answers `400` via `..WriteProblem` when it is blank, otherwise
      delegates to `##class(sentai.search.StepSearchService).Search(q)` and writes the result with
      `..WriteJSON(200, …)`. No SQL, no embedding call, no business logic in the Dispatcher
      (R-010).
- [x] T014 [US1] Create `frontend/src/lib/palette/search.ts` with the three pure functions from
      contracts/palette-search.md — `filterLocally` (extracted verbatim from today's inline filter in
      `Palette.svelte`, `className` match included), `suggestionsFor`, and `paletteSections` — plus
      the `StepSearchOutcome`, `UnavailableReason` and `PaletteSection` types. No `fetch`, no DOM, no
      state. `paletteGroups()` in `frontend/src/lib/flow/document.ts` is reused unchanged.
- [x] T015 [US1] Add `fromWireStepSearch` to `frontend/src/lib/api/wire.ts` (validating, in the
      style of the other `fromWire*` functions: an unrecognised `reason` and a malformed body both
      become `{available: false, reason: 'error'}`) and `searchStepTypes` to
      `frontend/src/lib/api/client.ts` through the existing `request()`/`map()` helpers, returning
      `ApiResult<StepSearchOutcome>`. `wire.ts` gains **no** `description` field on `StepTypeInfo`
      (R-011).
- [x] T016 [US1] Rework `frontend/src/lib/palette/Palette.svelte`: keep the local filter reacting on
      every keystroke, add a 150 ms debounce that calls the client, track the outcome in `$state`,
      and discard a stale response with `createSequence()` from `frontend/src/lib/catalog/catalog.ts`
      so a ranking never re-orders behind the operator (FR-002). Render a leading `suggested` section
      when there are suggestions, and mark those entries `data-suggested="true"`. `data-step-type`,
      `disabled`, `draggable` and the unavailable styling stay exactly as they are (FR-021).

**Checkpoint**: User Story 1 is fully functional and independently testable — the MVP

---

## Phase 4: User Story 2 - The search box keeps working when the similarity service is not usable
(Priority: P2)

**Goal**: unconfigured, unreachable, slow and incompatible providers are typed answers, and the
palette is indistinguishable from today's in every one of them.

**Independent Test**: with no provider row at all, then with the service stopped, type a known
identifier and an intent sentence. The palette narrows by entry text exactly as today, shows today's
no-match message when nothing matches, and shows no new error.

### Tests for User Story 2 ⚠️ write these FIRST

- [x] T017 [P] [US2] Create `tests/sentai/unittest/search/EmbeddingServiceTest.cls` asserting
      `IsValidConfig` rejects a configuration missing `host`, `path` or `model` with a non-empty
      `errorMsg`; accepts a full one; and that the request the class issues is built from the
      configuration's host, port, `https`, `path` and `model` rather than from a constant. Follow the
      HTTP-double pattern in `tests/sentai/unittest/AdminApiDouble.cls` for the transport case.
- [x] T018 [P] [US2] Extend `tests/sentai/unittest/search/StepSearchServiceTest.cls` with one case per
      reason: no row installed → `not-configured`; a row pointing at an unreachable host → `unreachable`;
      a provider past the timeout → `slow`; a provider returning a different width than the stored
      corpus → `incompatible`. Every case asserts `available: false`, the exact `reason`, and that
      **no** `matches` key is present (FR-025).
- [x] T019 [P] [US2] Extend `frontend/src/lib/palette/search.test.ts`: an `unavailable` outcome and a
      `null` outcome both produce today's sections with no `suggested` section, and the reason never
      becomes a separate render value.

### Implementation for User Story 2

- [x] T020 [US2] Complete `src/sentai/search/StepSearchService.cls`: map every failure onto exactly
      one `SearchOutcome` reason, apply the timeouts from T005, and return a bare `unavailable` rather
      than a partial ranking on any path (Constitution IV). No exception crosses this method.
- [x] T021 [US2] Complete `frontend/src/lib/palette/Palette.svelte`: collapse a non-`ok` `ApiResult`
      into `{available: false, reason: 'unreachable'}` at the point of assignment, so a transport
      failure, a 5xx and an unparseable body are the same degraded state and none of them can look
      like "no results" (FR-023, FR-025). Confirm typing stays responsive while a request is in
      flight, and that a response for a superseded keystroke is discarded (FR-002, US2 scenario 4).

**Checkpoint**: User Stories 1 AND 2 both work independently — the feature is now safe to ship

---

## Phase 5: User Story 3 - Search can only ever offer what the catalog already declares (Priority: P3)

**Goal**: the closed set holds structurally — the corpus is built from the catalog, the answer is a
re-ordering of it, and no entry can enter from either end.

**Independent Test**: search for a capability that does not exist, for an implementation class name
from inside the product, and for a legacy class name. Nothing outside the declared catalog appears,
nothing is inserted into a canvas, and the legacy `custom` entry stays unavailable and unexecutable.

### Tests for User Story 3 ⚠️ write these FIRST

- [x] T022 [P] [US3] Extend `tests/sentai/unittest/search/StepSearchServiceTest.cls`: the corpus holds
      exactly one row per catalog entry and no other type; the builder never reads an entry's `class`
      field (assert the corpus row for `custom` is derived from its `description`, and that searching
      for a `%SYS.Task.*` class name yields no entry outside the catalog); a query for an undeclared
      capability yields no undeclared entry.
- [x] T023 [P] [US3] Extend `frontend/src/lib/palette/search.test.ts`: an identifier in `matches` with
      no matching entry in the passed `registry` is **dropped** and produces no `suggested` section;
      no entry appears twice across sections; a suggested entry that is `available: false` stays
      `available: false` and the view model never alters availability.

### Implementation for User Story 3

- [x] T024 [US3] Review `src/sentai/search/StepSearchService.cls` so the builder reads only `type`,
      `label` and `description` from each catalog entry and never `class` — the legacy `custom` entry
      carries an empty `class`, and reading it anywhere on the search path is the failure this story
      exists to prevent (FR-018, R-009). Make the constraint visible in the code.
- [x] T025 [US3] Review `frontend/src/lib/palette/search.ts` so `suggestionsFor` can only reorder or
      drop entries it was handed, never create one, and never re-score or re-apply the floor
      (R-011).

**Checkpoint**: all three user stories are independently functional

---

## Phase 6: User Story 4 - A capability's description is written and reviewed with the capability
(Priority: P4)

**Goal**: a catalog change reaches search with no manual step, and a capability with no reviewed
description cannot be merged.

**Independent Test**: reword an entry's description and reword a second one — both become findable by
their new wording with no other action. Add a new entry with a description and confirm it is findable
by intent. Add an entry with an empty description and confirm the change is rejected.

### Tests for User Story 4 ⚠️ write these FIRST

- [x] T026 [P] [US4] Add a method to `tests/sentai/unittest/registry/StepTypeTest.cls` asserting every
      catalog entry's `description` is defined and non-empty — beside the existing
      `TestEveryEntryHasLabelAndExecutor`, following its shape. This is the rejection the story's third
      scenario requires (FR-015, SC-009).
- [x] T027 [P] [US4] Create `tests/sentai/unittest/search/StepCorpusTest.cls` asserting the catalog
      version changes when a `description` is reworded and does **not** change when only a `label`
      changes; that rebuilding twice yields the same rows and the same version; and that a type removed
      from the catalog is deleted from the corpus on the next build (FR-017, R-005).

### Implementation for User Story 4

- [x] T028 [US4] Compute the catalog version in `src/sentai/search/StepSearchService.cls` as a hash
      over the catalog's `(type, description)` pairs in catalog order — **excluding** label, category,
      executor, availability and destructiveness, so rewording a label does not invalidate the corpus
      (data-model §2).
- [x] T029 [US4] Make the corpus self-maintaining in `src/sentai/search/StepSearchService.cls`: before
      ranking, compare the current version against the rows' `corpusVersion` and rebuild when it
      differs or the row count differs. The rebuild is an idempotent per-entry upsert plus a delete of
      types no longer in the catalog, so a duplicated concurrent rebuild converges and **no lock is
      needed** (R-005). Replaces the build-if-empty behavior added in T012.

**Checkpoint**: the corpus cannot drift from the catalog, and the feature is complete

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T030 [P] Add the provider section to `README.md`: the `%EMBEDDING.Config` row and what
      `Configuration` accepts, how to point it at a different provider
      (`%Embedding.SentenceTransformers`, `%Embedding.OpenAI`) as a row rather than a code change, and
      the explicit warning that a hosted provider sends the operator's query text off the machine
      (FR-012, FR-010). State plainly that the app runs with no row at all.
- [x] T031 [P] Add `frontend/tests/us22-semantic-search.spec.ts` (the numbering continues the existing
      `us1`–`us21` series) asserting the SUGGESTED group appears for an intent sentence, that a
      suggested entry is not duplicated in its category group, and that dragging one adds the step
      exactly as a substring-found entry would. Needs the published bundle first:
      `bash scripts/publish-canvas.sh` from the repository root (AGENTS.md).
- [x] T032 [P] Add `frontend/tests/us23-search-degradation.spec.ts` asserting that with
      `docker compose stop ollama` the palette shows today's local filter results, today's no-match
      message, and no SUGGESTED group, toast or error — that degraded and working runs look identical.
- [x] T033 Run the full walkthrough in `specs/011-semantic-step-search/quickstart.md` end to end
      against the dev stack and record the evidence table in
      `specs/011-semantic-step-search/evidence/README.md`. No credentials in it.
- [x] T034 Run the gates — `zpm "load /home/irisowner/dev"` then `zpm "test sentai-task -only"`
      (268 methods, expect `268 total, 268 passed, 0 failed` plus the new search methods); and in
      `frontend/`, `npm run check`, `npm test`, then `npx playwright test`. Confirm the backend suite
      is green **with no `%Embedding.Config` row installed** — that is the CI state, and
      `SELECT COUNT(*) FROM %EMBEDDING.Config` must be `0` afterwards.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — **BLOCKS all user stories**
- **User Stories (Phases 3–6)**: All depend on Foundational completion
  - They can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3 → P4)
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: starts after Foundational — no dependency on other stories
- **User Story 2 (P2)**: starts after Foundational — extends the service and component from US1, so
  schedule it after US1 in a single-developer flow, but its **tests** are written against the
  contract and can be written in parallel with US1
- **User Story 3 (P3)**: starts after Foundational — its work is mostly assertions over US1's service
  and view model; the code changes are small and may land without US1 complete
- **User Story 4 (P4)**: starts after Foundational — replaces US1's build-if-empty with the version
  check, so it lands after US1 in a single-developer flow

### Critical Path

`T001` → `T002` → `T003`/`T004`/`T005`/`T006`/`T007`/`T008` → `T009`–`T011` → `T012` → `T013` →
`T014`–`T016` → `T020`/`T021` → `T028`/`T029` → `T034`

### Within Each User Story

- Tests are written and **fail** before implementation
- Values and storage before services; services before endpoints; endpoint before integration
- Story complete before moving to the next priority

### Parallel Opportunities

- T003, T004, T005, T007, T008 in Foundational — five different files, no interdependencies
- T009, T010, T011 in US1 — the three test files
- T014, T015 in US1 — two different frontend modules
- T017, T018, T019 in US2 — three different test files
- T022, T023 in US3; T026, T027 in US4
- T030, T031, T032 in Polish — docs and two e2e specs
- 18 of 34 tasks carry `[P]`
- US1 and US2 can be worked in parallel by two developers once Foundational is done

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together (they must fail first):
Task: "T009 Create tests/sentai/unittest/search/StepSearchServiceTest.cls"
Task: "T010 Create tests/sentai/unittest/rest/StepTypeSearchTest.cls"
Task: "T011 Create frontend/src/lib/palette/search.test.ts"

# Then the frontend modules together, while the backend service is written:
Task: "T014 Create frontend/src/lib/palette/search.ts"
Task: "T015 Add fromWireStepSearch to wire.ts and searchStepTypes to client.ts"
```

## Parallel Example: User Story 2

```bash
Task: "T017 Create tests/sentai/unittest/search/EmbeddingServiceTest.cls"
Task: "T018 Extend StepSearchServiceTest.cls with the four degradation reasons"
Task: "T019 Extend frontend/src/lib/palette/search.test.ts with the unavailable cases"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T002`)
2. Complete Phase 2: Foundational (`T003`–`T008`) — **CRITICAL, blocks all stories**
3. Complete Phase 3: User Story 1 (`T009`–`T016`)
4. **STOP and VALIDATE**: run the US1 independent test — the four intent sentences
5. Do **not** ship here. T029 is not done, so a catalog change will not yet reach search.

### Recommended: MVP plus safety (US1 + US2)

US2 is what makes shipping US1 safe on a deployment with no provider — the constitution requires the
failure to be a value, and this is where that is proved. Add it before any release:

1. Setup + Foundational
2. US1 → validate independently (MVP)
3. US2 → validate independently → **shippable**
4. US3 → the constitutional floor under the first two
5. US4 → the feature stops rotting

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add US1 → test independently → demo (MVP)
3. Add US2 → test independently → **deployable**
4. Add US3 → test independently
5. Add US4 → test independently
6. Polish: docs, e2e, quickstart evidence, full gates

Each story adds value without breaking the previous ones, and each leaves the palette working.

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: US1 backend (`T012`, `T013`)
   - Developer B: US1 frontend (`T014`, `T015`, `T016`)
   - Developer C: US2 tests (`T017`, `T018`, `T019`)
3. US3 and US4 are mostly assertions — one developer, after US1 lands
4. US1 and US2 code paths touch different concerns and merge cleanly; the one shared file
   (`StepSearchService.cls`) is split by role: US2/T020 owns failure mapping, US4/T028–T029 own
   versioning. **Sequence those two on that file.**

---

## Notes

- `[P]` tasks = different files, no dependencies
- `[Story]` label maps each task to a user story for traceability
- Each user story is independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate the story independently
- Avoid: vague tasks, same-file conflicts, cross-story dependencies that break independence

## Format Validation

Every task above follows `- [ ] [TaskID] [P?] [Story?] Description with file path`:
checkbox present, sequential `T001`–`T034`, `[P]` only on different-file independent work,
story labels only inside the user-story phases, and a concrete file path or an exact command in
every description.
