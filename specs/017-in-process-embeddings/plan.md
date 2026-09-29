# Implementation Plan: In-Process Embeddings for Step-Type Search

**Branch**: `017-in-process-embeddings` | **Date**: 2026-09-29 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/017-in-process-embeddings/spec.md`

## Summary

Replace the `ollama` sidecar with sentence-transformers running inside the primary IRIS instance,
without changing what the operator sees. Measured on the running stack (research.md): the
platform's own `%Embedding.SentenceTransformers` reloads the model on every call (≈3.35 s), and a
per-process cache costs ≈500 MB and a ≈10 s cold load in every CSP gateway worker. So the model lives
in **one** IRIS process, `sentai.search.EmbeddingWorker`, started right after IRIS by the image and
lazily by any caller; the row's provider class, `sentai.search.LocalEmbedding`, asks it over a named
`$SYSTEM.Event` (≈12 ms round trip) and answers `warming` while it loads. The stored corpus becomes
valid only for the provider identity that produced it. Packages are installed CPU-only in one pip
command (1.3 GB, zero GPU packages), the model is baked into the image, and the image runs offline.
The ranking scores are identical to spec 011's, so the 0.20 floor stays.

## Technical Context

**Language/Version**: ObjectScript on InterSystems IRIS 2026.2 (Build 221U); Embedded Python 3.12.3
for the worker's model code; TypeScript (SvelteKit) for the one frontend value added.

**Primary Dependencies**: `torch 2.14.0+cpu` and `sentence-transformers 6.1.0` (with
`transformers 5.17.0`), from the PyTorch CPU index with PyPI as the extra index; model
`sentence-transformers/all-MiniLM-L6-v2` (384 dimensions, 88 MB). Platform: `%Embedding.Interface`,
`%Embedding.Config`, `VECTOR_COSINE`, `$SYSTEM.Event`, `iris-main --after`.

**Storage**: `sentai.search.StepCorpus` (one new property, `providerIdentity`); worker registration
in `^IRIS.Temp.sentai.embed` (IRISTEMP). No new persistent class.

**Testing**: `%UnitTest` through `zpm "test sentai-task -only"` (375 methods today, flat under
`tests/sentai/unittest/search/`), tests written first; `vitest` and `svelte-check` for the frontend
value; quickstart.md for the end-to-end, image and demo checks.

**Target Platform**: The project's Linux container images (Ubuntu 24.04, x86-64, CPU only). IPM
installs on other instances receive the classes but not the packages, model or row.

**Project Type**: Web service (ObjectScript REST API) plus the SvelteKit canvas IRIS serves.

**Performance Goals**: Search answer within 1 s of the last keystroke, first search after start
included (FR-004, FR-004a). Measured: ≈12 ms per embed through the worker; 3 concurrent callers ≈33 ms
per ask.

**Constraints**: No network at run time (`HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`,
`local_files_only=True` — without them a network-cut first load took 146 s); model cache outside the
read-only dev mount; no GPU runtime; caller timeout 0.8 s.

**Scale/Scope**: 13 catalog entries; one worker process (≈500 MB); 3 gateway workers observed.

## Constitution Check

*GATE: checked before Phase 0 and re-checked after Phase 1 design.*

| Principle | How this plan satisfies it | Pre | Post |
|---|---|---|---|
| I. Layered architecture | `StepSearchService` (core) still reaches the provider only through the `%Embedding.Config` row and `$CLASSMETHOD(EmbeddingClass, "Embedding", …)`; it never names `LocalEmbedding` or the worker. The worker is infrastructure behind the provider class. The image hook and pip install are edge concerns in the `Dockerfile`. | ✅ | ✅ |
| II. Closed capability set | The corpus is still read only through `StepType.GetCatalog()`. The model name comes from the operator's row, and the worker loads with `trust_remote_code=False` and `local_files_only=True`, so no code arrives with a model (the platform class uses `trust_remote_code=True` — one reason it was rejected, R-1). The worker executes nothing it receives: it embeds text. | ✅ | ✅ |
| III. Delegated authorization | No permission logic is added. The provider identity stored with the corpus excludes every `Configuration` key but the model, so a key such as `apiKey` is never copied into the product's storage. | ✅ | ✅ |
| IV. Errors as values | Every worker condition reaches the core as a reason token the existing `ReasonFromMessage` reads (`warming`, `slow`, `error`); `Search` still answers HTTP 200 with `{"available":false,"reason":…}`. `warming` is added to the closed list (R-9). | ✅ | ✅ |
| V. Verifiable increments | Tasks are sliced by the spec's user stories (bring-up with no sidecar; same search incl. `warming`; provider change rebuilds; demo), each with its test first. | ✅ | ✅ |
| VI. Technology agnosticism | The technology is chosen here, not in the Constitution or the spec. The product core stays provider-neutral: a different provider is still one row. | ✅ | ✅ |

**Engineering standards.** *SOLID / SoC*: `LocalEmbedding` (the platform-facing provider: validate a
row, ask for a vector, map failures to reasons) and `EmbeddingWorker` (own the model process: start,
serve, stop, register) change for different reasons and are separate classes. *YAGNI*: no replace
rule for old rows (R-6), no worker pool, no ANN index. *Reproducibility*: `docker compose up -d`
still gives working search with no manual step. *TDD*: see Testing.

No violations; Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/017-in-process-embeddings/
├── spec.md
├── plan.md              # this file
├── research.md          # R-1..R-9, with measurements
├── data-model.md        # provider identity, corpus currency, worker registration, reasons
├── quickstart.md        # end-to-end validation
├── contracts/
│   └── api-delta.md     # `reason` gains `warming`
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
src/sentai/search/
├── LocalEmbedding.cls        # NEW  %Embedding.Interface provider named by the row; asks the worker
├── EmbeddingWorker.cls       # NEW  the one process holding the model (Start, Serve, Stop, state)
├── StepSearchService.cls     # CHANGED  provider identity in CorpusIsCurrent / CorpusVersion
├── StepCorpus.cls            # CHANGED  + providerIdentity
├── SearchOutcome.cls         # CHANGED  REASONS + warming
└── EmbeddingService.cls      # unchanged (HTTP provider stays, FR-013)

tests/sentai/unittest/search/
├── LocalEmbeddingTest.cls    # NEW  config validation, reason mapping, lazy start → warming
├── EmbeddingWorkerTest.cls   # NEW  registration, liveness, identity change, stop
├── StepSearchServiceTest.cls # CHANGED  identity rebuild (R-4), warming passes through
└── SearchOutcomeTest.cls     # CHANGED  warming is a known reason

frontend/src/lib/api/wire.ts          # CHANGED  REASONS + 'warming'
frontend/src/lib/palette/search.ts    # CHANGED  UnavailableReason + 'warming'
frontend/src/lib/api/*.test.ts        # CHANGED  warming kept by name

Dockerfile                    # pip (CPU index), model download, ENV offline, CMD --after warm-up
iris-provider.script          # default row → sentai.search.LocalEmbedding
docker-compose.yml            # − ollama service, − ollama-models volume
README.md                     # FR-014 — section by section, see "README changes" below
dev.md, AGENTS.md, docs/limitations.md   # FR-014
specs/017-in-process-embeddings/evidence/   # sizes, timings, API transcripts
```

**Structure Decision**: The existing flat `src/sentai/search` package and its flat test directory,
per AGENTS.md. `iris-target` (`Dockerfile_target`) and `docker-compose.demo.yml` are not touched.

## Design notes the tasks must respect

1. **The worker's Python** is one class method in `EmbeddingWorker` with `[ Language = python ]` that
   loads the model once per process (module-level holder) and returns the vector's display form;
   ObjectScript owns the loop, the event, the registration and every failure.
2. **Caller path** (`LocalEmbedding.Embedding`): read registration → pid alive? → `state = ready`
   and identity equal → `Signal` + `WaitMsg` with 0.8 s → vector; else start or restart the worker
   (lock-guarded `JOB`) and throw `warming:`; timeout throws `slow:`; anything else `error:`.
3. **Start is idempotent**: a lock on `^IRIS.Temp.sentai.embed` decides who starts; a second
   `Start()` returns at once.
4. **Offline**: `ENV HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1` in the `Dockerfile` (not compose,
   which the demo resets) and `local_files_only=True` in the load.
5. **Tests cannot load the real model** (the suite must stay fast and must pass on a stack without
   the packages): worker tests use a test-only worker body behind the same registration and event
   protocol, the way spec 011 used `FakeEmbeddingService`. The real model is exercised by the
   quickstart and recorded in `evidence/`.
6. **Evidence**: image sizes before/after, build time, worker ready time after start, the R-5 query
   table through the REST API, a `warming` transcript, an offline transcript.

## README changes (FR-014)

The README is part of this feature's deliverable, not a follow-up: today it tells IPM users to
configure `%Embedding.SentenceTransformers` (≈3.35 s per search, R-1) and tells everyone the dev
stack serves `all-minilm` on an `ollama` service that this feature removes. Each change lands in the
same task as the behaviour it describes, and the numbers come from `evidence/`, not from this plan.

| README section (current line) | Change |
|---|---|
| **🚀 Try it** (≈L28–36) | Say the first `docker compose up -d --build` also installs the in-instance search (CPU-only Python packages and the model, ≈1.4 GB, once, at build time), and that intent search ranks about ten seconds after the container is up. No second service to wait for. |
| **📋 Prerequisites** (≈L137) | Disk: ≈9 GB for the two images (was ≈17 GB with `ollama`). Memory: the search worker holds ≈500 MB. No GPU. |
| **🛠️ Installation → Docker** (≈L147) | What the build now adds (packages, model, offline run time), and that an existing stack moves over with `docker compose up -d --build` — without `--build`, search answers `unreachable` until rebuilt (R-6). |
| **🛠️ Installation → IPM** (≈L170–199) | Replace the `%Embedding.SentenceTransformers` recipe. New recipe: the one CPU-only pip command (index order matters: split commands pull 5.4 GB of GPU packages), download the model into a writable `cachePath`, set `HF_HUB_OFFLINE=1`, insert one `sentai.search.LocalEmbedding` row; the first search answers `warming` and starts the worker. Keep the alternatives — `sentai.search.EmbeddingService` pointed at an `ollama` or any `/v1/embeddings` server the operator runs, and `%Embedding.OpenAI` with its privacy note — and say why `%Embedding.SentenceTransformers` is not recommended (reloads the model on every call). |
| **🔎 Semantic step-type search** (≈L481–547) | Scores caption: measured with `all-MiniLM-L6-v2` in-process (values unchanged, R-5). The "one row" example becomes the `LocalEmbedding` row and its keys (`modelName`, `cachePath`, optional `pythonPath`). Drop "the dev stack serves `all-minilm` on the compose network's `ollama` service". Add `warming` to the list of answers that fall back to today's palette. Privacy note: the default keeps the query text inside the instance (was "on the compose network"). Add the one-row recipe for an `ollama` the operator runs. |
| **🐍 Where SentaiTask uses Embedded Python** (≈L549) | Add the search worker: the model runs in Embedded Python because that is where the model library lives; ObjectScript owns the process, the event protocol, the timeouts and every failure as a value. |
| **⚠️ Known limitations** (≈L681) | The first searches after the instance starts may answer `warming` for ≈7–11 s; one worker process serves every search (≈12 ms each, serialized). |
| **🗂️ Project Structure** (≈L752) | Only if the tree lists `src/sentai/search` files: add `LocalEmbedding` and `EmbeddingWorker`. |

`dev.md` (the `ollama-models` volume and the `sentai-steps → ollama` line) changes the same way.
In `AGENTS.md` the sentence "The dev stack serves `all-minilm` on the `ollama` compose service" sits
**inside** the SPECKIT block, so it is replaced by running `/speckit-agent-context-update` for this
plan, never by hand. `docs/limitations.md` gets the `warming` point with its measured window.
