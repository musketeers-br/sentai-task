# Tasks: In-Process Embeddings for Step-Type Search

**Input**: Design documents from `specs/017-in-process-embeddings/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api-delta.md, quickstart.md

**Tests**: Required. The Constitution (V, TDD) and AGENTS.md make the failing test the first task of
every story. Backend tests sit flat under `tests/sentai/unittest/search/`; frontend tests beside
their module (`frontend/src/**/*.test.ts`).

**Organization**: By user story. Order follows the contract first: US2 (the operator's search,
including `warming`) → US3 (provider identity) → US1 (the image and compose) → US4 (demo) → US5
(existing stacks). US1 is P1 but needs US2's provider to exist.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1–US5 from spec.md
- **[external]**: needs an action outside the repository

## How to run things (every task that says "load" or "suite")

- **Load** (a class change counts only once the instance has it):
  `docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP` then `zpm "load /home/irisowner/dev"`.
- **Suite**: in the same session `zpm "test sentai-task -only"`; green ends with `All PASSED`. No
  single-class runs exist.
- **Frontend**: `cd frontend && npm test && npm run check` (`npm run generate:tokens` first on a
  fresh clone).
- ObjectScript edits follow the `objectscript-guardrails` / `objectscript-review` skills. Never
  hand-edit a `Storage` block.

---

## Phase 1: Setup

**Purpose**: Freeze the "before" state that SC-001, SC-003 and US5 are measured against.

- [X] T001 Create `specs/017-in-process-embeddings/evidence/README.md` with a table of evidence files and a "Before" section: `docker images` sizes (`ollama/ollama:latest` 9.28 GB, `sentai-task-iris:latest` 3.99 GB, `sentai-task-iris-target:latest` 3.74 GB), backend suite count (375 methods), and the R-5 baseline table from `specs/017-in-process-embeddings/research.md` (ollama scores per query). No credentials in the file.
- [X] T002 Tag the current primary image for the US5 check before any rebuild: `docker tag sentai-task-iris:latest sentai-task-iris:pre-017`, and record the tag in `specs/017-in-process-embeddings/evidence/README.md`.
- [X] T003 Run the backend suite and `npm test` on branch `017-in-process-embeddings` before any change and record both counts in `specs/017-in-process-embeddings/evidence/README.md` (baseline must be green).

---

## Phase 2: Foundational

No shared prerequisite beyond Setup: each story below brings its own test doubles.

---

## Phase 3: User Story 2 — The operator sees exactly spec 011's search, `warming` included (Priority: P1) 🎯 contract

**Goal**: An in-process provider that holds the model in one worker process and answers every
condition as a value — `warming` while loading, a vector when ready, `slow` on timeout, `error`
otherwise — with `warming` kept by name all the way to the canvas.

**Independent Test**: With the test-only worker installed under `sentai-steps`, the first search
answers `{"available":false,"reason":"warming"}` and a search after the worker is ready ranks; the
canvas keeps today's palette on `warming`.

### Tests for User Story 2 (write first, see them fail)

- [X] T004 [P] [US2] In `tests/sentai/unittest/search/SearchOutcomeTest.cls` add `TestWarmingIsAKnownReason`: `Unavailable("warming")` yields `reason = "warming"` (not `error`), and `NormalizeReason("WARMING")` is `warming`.
- [X] T005 [P] [US2] In `frontend/src/lib/api/wire.test.ts` add a case: a search response `{"available":false,"reason":"warming"}` is decoded with `reason: 'warming'`, and an unknown reason still decodes as `'error'`.
- [X] T006 [P] [US2] In `frontend/src/lib/palette/search.test.ts` add a case: an outcome `{ available: false, reason: 'warming' }` produces exactly the sections today's local filter produces (no `suggested` section).
- [X] T007 [US2] Create the test-only worker `tests/sentai/unittest/search/FakeEmbeddingWorker.cls` extending `sentai.search.EmbeddingWorker`: overrides the model hooks with the deterministic 256-wide vector of `FakeEmbeddingService` (a test double's width; the real model is 384), overrides the event-name and registry parameters so it can never collide with a real worker, and reads an optional load delay and encode delay from `^IRIS.Temp.sentai.embedtest` so tests can hold it in `warming` or force `slow`.
- [X] T008 [US2] Create `tests/sentai/unittest/search/FakeLocalEmbedding.cls` extending `sentai.search.LocalEmbedding` with its worker-class parameter set to `sentai.unittest.search.FakeEmbeddingWorker` (a compile-time parameter, never a name taken from input — Constitution II).
- [X] T009 [US2] Create `tests/sentai/unittest/search/EmbeddingWorkerTest.cls` (uses `FakeEmbeddingWorker`, stops it in `OnAfterOneTest`): `Start()` twice leaves exactly one live worker; registration goes `warming` → `ready` with pid and identity (data-model §4); `Stop()` removes the event and the registration; a registration whose pid is dead reads as absent.
- [X] T010 [US2] Create `tests/sentai/unittest/search/LocalEmbeddingTest.cls` (uses `FakeLocalEmbedding`): `IsValidConfig` rejects a configuration without `modelName` or `cachePath` with a message; with no worker, `Embedding` starts one and throws a status whose text carries `warming:`; once ready it returns the double's 256-wide vector; an encode delay above 0.8 s throws `slow:`; a dead registered pid is restarted and answers `warming:`; a row whose model differs from the worker's identity restarts the worker and answers `warming:`; a load failure answers `error:`.
- [X] T011 [US2] In `tests/sentai/unittest/search/StepSearchServiceTest.cls` add `TestWarmingProviderAnswersWarming` and `TestReadyProviderRanks`: install `sentai.unittest.search.FakeLocalEmbedding` under `sentai-steps` through `SearchFixtures.WriteProvider` (capture and restore the real row as the existing tests do); `Search()` first answers `{"available":false,"reason":"warming"}` with no `matches`, then — after the fake worker reports `ready` — ranks the catalog.

### Implementation for User Story 2

- [X] T012 [P] [US2] Add `warming` to `Parameter REASONS` in `src/sentai/search/SearchOutcome.cls` (order: `not-configured,unreachable,slow,incompatible,warming,error`) and to the class comment's reason list.
- [X] T013 [P] [US2] Add `'warming'` to the `REASONS` set in `frontend/src/lib/api/wire.ts` and to the `UnavailableReason` union in `frontend/src/lib/palette/search.ts`; no other frontend change (the palette already falls back on every unavailable reason).
- [X] T014 [US2] Create `src/sentai/search/EmbeddingWorker.cls` per plan.md design notes 1, 3 and data-model §4: parameters for the event name (`sentai.embed`) and registry global (`^IRIS.Temp.sentai.embed`); `Start(configName)` — lock-guarded, idempotent, `JOB`s `Serve`; `Serve` — registers `warming` with pid and identity, loads the model, registers `ready`, loops on `$SYSTEM.Event.WaitMsg`, encodes, replies with `$SYSTEM.Event.Signal(callerPid, vectorText)`, stops on a stop message, and cleans up the event and registration on exit (including after a failed load, recording `error`); `Stop()`; `IsAlive()` from the registered pid; the model hooks as `[ Language = python ]` class methods holding the model in a module-level object, constructed with `device="cpu"`, `cache_folder` from `cachePath`, `trust_remote_code=False`, `local_files_only=True`, and `pythonPath` appended to `sys.path` when given.
- [X] T015 [US2] Create `src/sentai/search/LocalEmbedding.cls` extending `%Embedding.Interface`, per data-model §1 and plan.md design note 2: worker-class parameter (default `sentai.search.EmbeddingWorker`); `IsValidConfig` requires `modelName` and `cachePath` and asks the worker class whether the packages import and the model is present, never downloading; `Embedding(input, configuration)` computes the identity, checks the registration and pid, asks the worker with a 0.8 s wait, and otherwise starts/restarts it — every failure thrown as `$$$ERROR($$$EmbeddingGeneralError, "<token>: <detail>")` with token `warming`, `slow` or `error`, so `StepSearchService.ReasonFromMessage` reads it unchanged.
- [X] T016 [US2] Load, run the backend suite and `npm test` / `npm run check`; T004–T011 now pass and the 375 earlier methods still pass. Record the new counts in `specs/017-in-process-embeddings/evidence/README.md`.

### Docs for User Story 2

- [X] T017 [P] [US2] README "🔎 Semantic step-type search" (≈L481–547 of `README.md`): add `warming` to the answers that fall back to today's palette, with one sentence on when it appears (plan.md "README changes").
- [X] T018 [P] [US2] README "🐍 Where SentaiTask uses Embedded Python" (≈L549 of `README.md`): add the search worker — the model runs in Embedded Python; ObjectScript owns the process, the event protocol, the timeouts and every failure as a value.
- [X] T019 [P] [US2] README "⚠️ Known limitations" (≈L681 of `README.md`) and `docs/limitations.md`: the first searches after the instance starts may answer `warming` (measured window, from evidence), and one worker serves every search (≈12 ms each, serialized).

**Checkpoint**: The provider exists and the operator contract holds under test; nothing in the image
uses it yet.

---

## Phase 4: User Story 3 — A provider change never mixes two models' vectors (Priority: P2)

**Goal**: The stored corpus is valid only for the provider identity that produced it (FR-007).

**Independent Test**: Switch the `sentai-steps` row between two fake configurations of equal length
and see a full rebuild; search again with nothing changed and see none.

### Tests for User Story 3 (write first)

- [X] T020 [P] [US3] In `tests/sentai/unittest/search/StepSearchServiceTest.cls` add `TestModelChangeRebuildsCorpus`: install `sentai.unittest.search.RecordingEmbeddingService` (or `FakeEmbeddingService`) with `{"model":"a"}`, search, switch the row to `{"model":"b"}` with the same class and length, search: every `sentai_search.StepCorpus.providerIdentity` ends with `|b|256` and every catalog description was embedded again.
- [X] T021 [P] [US3] In the same file add `TestUnchangedProviderDoesNotRebuild` (a second search embeds only the query) and `TestIdentityCarriesNoSecret` (a configuration with `"apiKey":"k-123"` yields an identity and stored rows that do not contain `k-123`).
- [X] T022 [P] [US3] In `tests/sentai/unittest/search/StepCorpusTest.cls` add a case that a row written with `providerIdentity` reads back with it, and that rows written by spec 011 (empty identity) are treated as not current.

### Implementation for User Story 3

- [X] T023 [US3] Add `Property providerIdentity As %String(MAXLEN = 512);` with its comment to `src/sentai/search/StepCorpus.cls`; let the compiler extend the storage map on load (do not edit `Storage Default` by hand).
- [X] T024 [US3] In `src/sentai/search/StepSearchService.cls` add `ProviderIdentity()` (data-model §2: `Name|EmbeddingClass|model-or-modelName|VectorLength` read from the row, no other key); write it with every row in `EnsureCorpus` (extend `InsertSQL`); make `CorpusIsCurrent` also require every stored row's identity to equal the current one; make `CorpusVersion` return `v2-…` including the identity; update the class comments that cite R-005.
- [X] T025 [US3] Load and run the backend suite; T020–T022 pass with everything else. Record in `specs/017-in-process-embeddings/evidence/README.md`.

**Checkpoint**: Any provider change — including the one US1 makes — rebuilds the corpus before
ranking.

---

## Phase 5: User Story 1 — Semantic search works from a plain bring-up, with no sidecar (Priority: P1)

**Goal**: `docker compose up -d --build` yields two containers and ranked intent search, offline,
with the worker warmed at start.

**Independent Test**: quickstart.md §1–§3.

### Verification first

- [X] T026 [US1] Add a check script `scripts/check-search-image.sh` that fails unless: `docker compose config --services` lists no `ollama`; inside `sentai-task-iris-1`, no `nvidia-*` package is importable/installed; `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` are set in the container environment; the `sentai-steps` row names `sentai.search.LocalEmbedding`. Run it now and see it fail.

### Implementation for User Story 1

- [X] T027 [US1] In `Dockerfile` (IRIS stage, before the `RUN` that loads the module): one command `pip install --index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple torch sentence-transformers` into the directory Embedded Python imports from (verify with `irispython -c "import sys; print(sys.path)"`; `/usr/irissys/mgr/python` expected — if not on `sys.path`, install with `--target` and put `pythonPath` in the row instead). Never split into two commands (research R-3: 5.4 GB).
- [X] T028 [US1] In `Dockerfile`: download `sentence-transformers/all-MiniLM-L6-v2` into `/usr/irissys/mgr/sentai-models` at build time (one `irispython -c` line), owned by `irisowner`; then `ENV HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1` (in `Dockerfile`, not compose — the demo override resets compose `environment`).
- [X] T029 [US1] In `Dockerfile`: `CMD ["--after", "iris session iris -U IRISAPP '##class(sentai.search.EmbeddingWorker).Start()'"]` so `iris-main` starts the worker after `iris start` (research R-2); confirm with `docker inspect` that the running container got it.
- [X] T030 [US1] In `iris-provider.script`: the row written when no `sentai-steps` row exists becomes `sentai.search.LocalEmbedding` with `{"modelName":"sentence-transformers/all-MiniLM-L6-v2","cachePath":"/usr/irissys/mgr/sentai-models"}`, length 384, description `Step-type search, in-process (installed by the dev build)`; keep the insert-only-when-absent rule and update the header comment (no replace rule — research R-6).
- [X] T031 [US1] In `docker-compose.yml`: remove the `ollama` service with its comment block and the `ollama-models` volume (and the now-empty `volumes:` key).
- [X] T032 [US1] Build and bring up: `docker compose up -d --build`; time the build; run `scripts/check-search-image.sh` (now passes); record in `specs/017-in-process-embeddings/evidence/README.md` the build time, `docker images` sizes (SC-001: at least 5 GB less than T001), `docker compose ps` services (SC-002) and the time from container healthy to worker `ready`.
- [X] T033 [US1] Run quickstart.md §1 and save `specs/017-in-process-embeddings/evidence/api-us1-search.txt`: the seven R-5 queries through the REST API with status, time and matches; top results equal T001's baseline (SC-003).
- [X] T034 [US1] SC-004: five fresh starts (`docker restart sentai-task-iris-1`), each time the first search made once the worker reports `ready` — ranked within one second; plus 20 consecutive searches, at most one above one second. Save `specs/017-in-process-embeddings/evidence/timing-us1.txt`.
- [X] T035 [US1] Run quickstart.md §2 (a search right after restart answers `warming`, HTTP 200, then ranks) and §3 (network cut: worker ready in seconds; restore with `--alias iris`). Save `specs/017-in-process-embeddings/evidence/api-us1-warming-offline.txt`.

### Docs for User Story 1

- [X] T036 [P] [US1] README "🚀 Try it" (≈L28–36 of `README.md`): the first build also installs the in-instance search once (≈1.4 GB, from T032), and intent search ranks about ten seconds after the container is up.
- [X] T037 [P] [US1] README "📋 Prerequisites" (≈L137 of `README.md`): disk for the two images (from T032, was ≈17 GB with `ollama`), ≈500 MB RAM for the search worker, no GPU.
- [X] T038 [P] [US1] README "🔎 Semantic step-type search" (≈L481–547 of `README.md`): scores caption says `all-MiniLM-L6-v2`, in-process; the "one row" example becomes the `LocalEmbedding` row and its keys (`modelName`, `cachePath`, optional `pythonPath`); remove "the dev stack serves `all-minilm` on the compose network's `ollama` service"; privacy note says the default keeps the query inside the instance; add the one-row recipe for `sentai.search.EmbeddingService` pointed at an `ollama` the operator runs.
- [X] T039 [P] [US1] README "🛠️ Installation → IPM" (≈L170–199 of `README.md`): replace the `%Embedding.SentenceTransformers` recipe with the CPU-only single pip command (and why the index order matters), the model download into a writable `cachePath`, `HF_HUB_OFFLINE=1`, and the `LocalEmbedding` row; the first search answers `warming` and starts the worker; keep `EmbeddingService` and `%Embedding.OpenAI` as alternatives and say why `%Embedding.SentenceTransformers` is not recommended (reloads the model on every call, research R-1). The module itself installs nothing (FR-003a).
- [X] T040 [P] [US1] `dev.md`: replace the `sentai-steps → EmbeddingService → ollama` line and the `ollama-models` volume note with the in-process provider, its model location and the worker.
- [X] T041 [P] [US1] README "🗂️ Project Structure" (≈L752 of `README.md`): add `LocalEmbedding` and `EmbeddingWorker` only if the tree lists `src/sentai/search` files; otherwise record "no change" in the task note. — **No change**: the tree lists packages, not files, and has no `search/` line.

**Checkpoint**: MVP — a fresh clone brings up two containers with ranked search.

---

## Phase 6: User Story 4 — The public demo offers semantic search (Priority: P2)

**Goal**: The demo, built from the same `Dockerfile`, ranks intents with no similarity container.

**Independent Test**: quickstart.md §7.

- [X] T042 [US4] Locally, with a throwaway `.env` (`SENTAI_DEMO_SECRET` only, not committed), run `scripts/demo/up.sh`; confirm `docker compose -f docker-compose.yml -f docker-compose.demo.yml ps` lists no `ollama`, the container environment has `HF_HUB_OFFLINE=1` despite `environment: !reset []`, and a demo-user search for *rotate the journal* ranks `switch-journal`. Save `specs/017-in-process-embeddings/evidence/demo-us4.txt` (no secret, no token); tear the demo stack down and bring the dev stack back. — **Done without `up.sh`** (it would replace the dev containers and bind :80/:443): the demo account step, `scripts/demo/demo-account.script`, was applied to the dev primary with the published account and resources, then removed. The spec 011 grants answered `error`; a grant on `sentai_search` and `SELECT` on `%EMBEDDING.Config` was added and the demo user's search then rebuilt the corpus and ranked (`evidence/demo-us4.txt`). The full `up.sh` run remains part of T043/T048.
- [ ] T043 [US4] [external] On the demo VM: check free disk against the image sizes from T032, deploy with `scripts/demo/up.sh`, search once, and record the result in `specs/017-in-process-embeddings/evidence/README.md`.

---

## Phase 7: User Story 5 — Existing installs move over without losing an operator's choice (Priority: P3)

**Goal**: The migration is the rebuild; without it, search degrades as a value.

**Independent Test**: quickstart.md §5.

- [X] T044 [US5] Run the `sentai-task-iris:pre-017` image from T002 as the `iris` service without the `ollama` service; search answers `{"available":false,"reason":"unreachable"}` (HTTP 200); then `docker compose up -d --build` and the same search ranks. Save `specs/017-in-process-embeddings/evidence/migration-us5.txt`.
- [X] T045 [US5] README "🛠️ Installation → Docker" (≈L147 of `README.md`) and `dev.md`: what the build now adds, and that an existing stack moves over with `docker compose up -d --build` — without `--build` search answers `unreachable` until rebuilt.

---

## Phase 8: Polish & Cross-Cutting

- [X] T046 Run `/speckit-agent-context-update` so the AGENTS.md SPECKIT block describes this plan (it replaces "The dev stack serves `all-minilm` on the `ollama` compose service"); never hand-edit the block. — Both extension scripts failed on Windows and were fixed (PowerShell 5.1 lost the quotes of `python -c`; bash kept the CR of CRLF Python output); both now write the same block.
- [X] T047 `objectscript-review` pass over `src/sentai/search/LocalEmbedding.cls`, `src/sentai/search/EmbeddingWorker.cls`, `src/sentai/search/StepSearchService.cls`, `src/sentai/search/StepCorpus.cls`, `src/sentai/search/SearchOutcome.cls` and the new test classes; fix findings, load, suite green. — Done as a manual review (the `objectscript-review` skill is not installed in this environment); suite green, 395/395.
- [ ] T048 [external] Full quickstart.md run (§1–§8) on a fresh `docker compose up -d --build`; complete the evidence table in `specs/017-in-process-embeddings/evidence/README.md` (file, task, what it proves; before/after sizes; counts; no credentials). — §1–§6 and §8 were run on the dev stack (evidence/); §7 (the demo through a real `scripts/demo/up.sh`) is done on the demo VM together with T043.
- [X] T049 Final gates: backend suite `All PASSED` with the new count, `npm test`, `npm run check`, `bash scripts/check-spec-status.sh`; then set `**Status**` in `specs/017-in-process-embeddings/spec.md` to `Implemented` (open tasks only if marked `[external]`, e.g. T043) with the counts in `**Status note**`.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T003)** first; T002 must happen before any image rebuild (T032).
- **US2 (T004–T019)** after Setup. Inside: T004–T011 before T012–T015; T007–T008 need
  `EmbeddingWorker`/`LocalEmbedding` to compile, so they fail first and pass after T014–T015.
- **US3 (T020–T025)** after Setup; independent of US2 (it uses the existing fake providers). Can run
  in parallel with US2 by another developer, but both edit `StepSearchServiceTest.cls` — merge there.
- **US1 (T026–T041)** after US2 (it installs `LocalEmbedding`) and after US3 (so the image's provider
  switch rebuilds the corpus).
- **US4 (T042–T043)** after US1. **US5 (T044–T045)** after US1 (needs T002's tag).
- **Polish (T046–T049)** last.

### Parallel opportunities

- US2 tests T004, T005, T006 (three different files); implementation T012 and T013.
- US2 docs T017–T019 (different README sections / files — edit sequentially if one person holds
  `README.md`).
- US3 tests T020–T022.
- US1 docs T036–T041 once T032 has produced the numbers.

## Parallel Example: User Story 2

```text
T004 SearchOutcomeTest warming     T005 wire.test.ts warming     T006 search.test.ts warming
then
T012 SearchOutcome.REASONS          T013 wire.ts + search.ts
```

## Implementation Strategy

- **MVP**: Setup → US2 → US3 → US1. At the US1 checkpoint the stack has no sidecar and ranks.
- **Then**: US4 (demo), US5 (migration evidence), Polish.
- Every checkpoint ends with the suite green and its evidence file written; nothing is committed by
  the agent — the developer commits (AGENTS.md workflow for this repository).
