# Research: In-Process Embeddings for Step-Type Search

Every decision below was measured on the running dev stack on 2026-09-29: container
`sentai-task-iris-1` (image `sentai-task-iris:latest`, IRIS 2026.2 Build 221U, Ubuntu 24.04.4,
Python 3.12.3, pip 24.0, 16 CPUs, 15.6 GB RAM, no GPU), namespace `IRISAPP`, with the spec 011
provider (`sentai.search.EmbeddingService` → compose `ollama`, `all-minilm`) still configured.

**Probe hygiene.** The probes created: packages under `/tmp/st`, a model cache under `/tmp/hf`, a
`%Embedding.Config` row `probe017-st`, classes `sentaiprobe.CachedST` and `sentaiprobe.Daemon`
(loaded from `/tmp`, never in the repository), a global `^sentaiprobe017` and a named event
`sentaiprobe017`. All were deleted and re-queried afterwards: zero probe rows, zero probe classes,
no global, no event, no process above 200 MB RSS, `/tmp` clean, and `sentai-steps` still the only
row. One side effect was repaired: the network-cut test (R-3) dropped the container's `iris` alias
on the compose network; it was reconnected with `--alias iris` and `iris-target` resolves it again.

## Baseline — the spec 011 provider (ollama), through the REST API

`GET /csp/sentai/api/v1/catalog/step-types/search` with a bearer token, corpus empty at start:

| Query | HTTP | Time | Matches (score ≥ 0.20) |
|---|---|---|---|
| free up disk space | 200 | **0.772 s** (builds the 13-row corpus) | storage-headroom-check 0.594, compact-globals 0.487, db-size-report 0.451, purge-audit-records 0.400, purge-task-history 0.292, defragment-globals 0.289 |
| check my globals are sound | 200 | 0.038 s | integrity-check 0.474, system-alerts-check 0.229, defragment-globals 0.202 |
| get rid of old audit records | 200 | 0.033 s | purge-audit-records 0.705, purge-task-history 0.332, switch-journal 0.291, compact-globals 0.289, db-size-report 0.279, storage-headroom-check 0.229 |
| rotate the journal | 200 | 0.036 s | switch-journal 0.555, db-size-report 0.320, purge-audit-records 0.217 |
| order me a pizza | 200 | 0.032 s | none |
| send an email to my manager | 200 | 0.034 s | none |
| banana | 200 | 0.032 s | none |

## R-1 — The provider is the product's own, and one process holds the model

**Decision.** A new provider class `sentai.search.LocalEmbedding` (extends `%Embedding.Interface`)
is what the `sentai-steps` row names. It does not load the model in the calling process. It hands
the text to **one** long-lived IRIS process, `sentai.search.EmbeddingWorker`, which loads
`sentence-transformers` once, keeps the model for the life of the process, and answers each request
over a named `$SYSTEM.Event` resource. The caller waits with a timeout and turns every failure into
the reason token the search service already reads (`warming:`, `slow:`, `error:`).

**Measured.**

| Candidate | First call in a fresh process | Every later call | Memory |
|---|---|---|---|
| `%Embedding.SentenceTransformers` (platform) | 13 981 ms | **4 016, 3 359, 3 360, 3 350 ms** | — |
| Per-process cache (model held in each calling process) | 11 022 ms (import 6.42 s + load 4.58 s); a second fresh process 10 410 ms | 10.2–11.8 ms | **515 MB per process** (45 MB before) |
| One worker process, callers ask over `$SYSTEM.Event` | worker warm 10.4 s once | **11.5–14.7 ms** per round trip | 500 MB, once |
| Worker under load: 3 concurrent callers × 10 asks | — | 320–344 ms per 10 asks (~33 ms each), 0 errors | 500 MB, once |

The platform class misses FR-004 on **every** call, not only the first: `EmbeddingPy` constructs
`SentenceTransformer(modelName, cache_folder=…, trust_remote_code=True)` inside the method, so each
call reloads the model (read from the class's own implementation on this build).

The REST API is served by **3** CSP gateway processes (`CSPa24.so`, user `CSPSystem`, counted in
`%SYS.ProcessQuery`); the gateway grows and recycles them on its own. A per-process cache therefore
costs ~500 MB **per worker** (1.5 GB at the observed three) and a ~10 s cold load that lands on an
operator's request every time the gateway starts a new worker — which nothing outside the gateway
can target or pre-warm. One worker process pays both once.

**Rationale.** FR-004 (one second, first search included) and FR-004a (warm before any operator)
can only both hold if the load happens once, ahead of time, somewhere the gateway's pool does not
own. The event round trip adds ~1–4 ms to an ~11 ms encode.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| `%Embedding.SentenceTransformers` as the row's class | ~3.35 s per call, measured. Also `trust_remote_code=True`: a model name in configuration could execute code downloaded with it — in tension with Constitution II. |
| Per-process cache in each CSP worker | 515 MB × workers; 10 s cold load per new worker, untargetable by warm-up (above). |
| Python thread inside each CSP worker that loads in the background and answers `warming` meanwhile | Removes the blocking load but keeps the ×N memory and a `warming` answer every time the gateway recycles a worker. |
| Work Queue Manager workers | The worker pool is managed and recycled by WQM — the same "who is warm" problem, one layer down. |
| ONNX runtime / a smaller runtime | Out of this feature's scope (the input names sentence-transformers); recorded as a later image-size option. |

**Constitution II.** The worker constructs the model with `trust_remote_code=False` and
`local_files_only=True`: it loads only files already in the cache, and never executes code that
arrives with a model. The model name comes only from the operator's row.

## R-2 — Warm-up: the image starts the worker right after IRIS; any caller can start it too

**Decision.** Two paths start the worker, and both are idempotent (the worker holds a lock and
registers itself; a second start exits at once):

1. **At container start (dev and demo images).** The image's default command is
   `iris-main --after "iris session iris -U IRISAPP '##class(sentai.search.EmbeddingWorker).Start()'"`.
   `iris-main -a/--after` runs shell commands after `iris start` (read from `/iris-main --help` on
   this image). It lives in the `Dockerfile` (`CMD`), so the demo's `environment: !reset []` does not
   remove it, and it is not part of the IPM module (R-7).
2. **Lazily, from any caller.** `LocalEmbedding.Embedding` that finds no live worker `JOB`s one and
   answers `warming`. This covers an IPM install (no image), an `iris restart` inside a container,
   and a worker that died.

`warming` is returned while the worker is loading; `slow` when a live, ready worker does not answer
within the caller's timeout (0.8 s, so the whole request stays under FR-004's one second);
`error` for anything else.

**Measured.** Worker start → ready: **10.5 s** with network access, **6.6 s** from a fresh process
with `HF_HUB_OFFLINE=1` (R-3). No task-manager option runs at system start on this build
(`%SYS.Task` `TimePeriod`: Daily, Weekly, Monthly, Monthly Special, Run After, On Demand), and
`^%ZSTART` does not exist; the container hook is the least invasive way to run at start.

**State.** The worker's registration (pid, `warming`/`ready`) lives in a temporary global
(`^IRIS.Temp.sentai.embed`, mapped to IRISTEMP), so it cannot survive a restart and claim a worker
that is gone; liveness is confirmed with the pid, not trusted from the global.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| `^%ZSTART` `SYSTEM` label | A system-wide routine in `%SYS`, shared by everything on the instance; heavier than a container hook for an image-only need (FR-003a). |
| Warm by firing HTTP requests at start | Cannot target which gateway worker answers; irrelevant once one worker holds the model. |
| Block the first search until warm | Explicitly rejected in Clarifications (option C). |

## R-3 — Install: one CPU-only pip command, the model baked in, offline at run time

**Decision.** In the `Dockerfile` IRIS stage, one command installs both packages with the CPU index
as primary: `--index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple
torch sentence-transformers`, into the directory Embedded Python reads (`/usr/irissys/mgr/python`;
the implementation verifies the path in the image — the probe used `--target` plus `sys.path`). The
model is downloaded once at build time into `/usr/irissys/mgr/sentai-models` (outside the read-only
dev mount). The image sets `ENV HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1`.

**Measured (in the running container).**

| Item | Value |
|---|---|
| Install time | **87 s** (pip exit 0) |
| Installed size | **1.3 GB**: torch 769 MB (`2.14.0+cpu`), transformers 115 MB (`5.17.0`), scipy 109 MB, sympy 74 MB, sklearn 49 MB, numpy 43 MB; `sentence_transformers 6.1.0` |
| `nvidia-*` packages | **0** |
| Same install from PyPI only, or split into two commands | **5.4 GB** (CUDA torch pulled again) — measured on 2026-09-29 in a throwaway container |
| Model `sentence-transformers/all-MiniLM-L6-v2` | 88 MB; row insert that validates and downloads it: 7.4 s |
| First load, **network cut**, no offline variables | **146.0 s** (retries against the model hub) |
| First load, network cut, `HF_HUB_OFFLINE=1` + `TRANSFORMERS_OFFLINE=1` | **6.6 s**, 384 dimensions |

The offline variables are therefore required, not cosmetic: without them a demo VM with restricted
egress would wait minutes on the first search. They go in `ENV` (not compose `environment`, which
the demo override resets).

## R-4 — Corpus identity: currency is decided on catalog text *and* provider identity

**Decision.** `StepCorpus` gains `providerIdentity`. It is
`<config name>|<EmbeddingClass>|<model>|<VectorLength>`, where `<model>` is the row's
`Configuration.model`, else `Configuration.modelName`, else empty. `StepSearchService.CorpusIsCurrent`
— which is what actually decides a rebuild (spec 011 compares the stored rows with the catalog; the
`corpusVersion` stamp is informational) — also requires every row's `providerIdentity` to equal the
current one. `CorpusVersion` includes it in the stamp.

**Rationale.** Changing the provider with an equal vector length is exactly the case the width
check (`WidthsAgree`) cannot see; the corpus must be rebuilt by the new provider before ranking
(FR-007, SC-005). The identity deliberately excludes the rest of the `Configuration`: it may carry
an `apiKey`, and the corpus table must not hold a secret (Constitution III).

**Test (written first).** Install the fake provider under `sentai-steps` with model `a`, search,
switch the row to model `b` (same class, same length), search again: every stored row carries
identity `…|b|…`, and the fake provider recorded a full rebuild. A second search with nothing changed
records no embedding of catalog text.

## R-5 — The relevance floor stays at 0.20

Same queries, new model (`all-MiniLM-L6-v2` through the worker), cosine computed with the
platform's own `VECTOR_COSINE` over the 13 catalog descriptions:

| Query | Top (new) | Top (ollama baseline) | Best score of a no-match query |
|---|---|---|---|
| free up disk space | storage-headroom-check 0.594 | storage-headroom-check 0.594 | |
| check my globals are sound | integrity-check 0.474 | integrity-check 0.474 | |
| get rid of old audit records | purge-audit-records 0.705 | purge-audit-records 0.705 | |
| rotate the journal | switch-journal 0.555 | switch-journal 0.555 | |
| order me a pizza | — | — | 0.073 |
| send an email to my manager | — | — | 0.104 |
| banana | — | — | 0.049 |

Every score agrees with the baseline to three decimals (the same model, served differently). The
weakest true top result is 0.474 and the strongest nonsense 0.104, so **0.20 is kept** (FR-008) and
`StepSearchService.MinScore` does not change.

## R-6 — Migration is the image rebuild; the provider script stays "insert when absent"

**Decision.** `iris-provider.script` keeps its rule: write `sentai-steps` only when no row of that
name exists; it now writes the `sentai.search.LocalEmbedding` row. No "replace the old dev row" rule
is added.

**Rationale.** The dev and demo containers keep no instance data outside the image (no data volume
in either compose file), so every image build starts from a fresh instance that has no row: the
next build *is* the migration (FR-011 holds by construction), and an operator's row can never be
touched by it (FR-010). A developer who pulls the change but runs `docker compose up -d` without
`--build` keeps the old container: its row still names `ollama`, the service is gone, and search
answers `unreachable` — the spec 011 degradation — until `docker compose up -d --build`. `dev.md`
says so.

**Alternative rejected.** A replace rule keyed on class + host `ollama` + description: it would only
ever run against a fresh instance where it can match nothing — dead code (YAGNI).

## R-7 — IPM stays untouched

`module.xml` gains nothing. `LocalEmbedding` and `EmbeddingWorker` are ordinary classes in the
module, so an IPM install has them but installs no package, downloads no model, writes no row and
starts no worker (FR-003a). Search there answers `not-configured` exactly as today. The README's IPM
section changes from recommending `%Embedding.SentenceTransformers` (3.35 s per call, R-1) to: the
same CPU-only pip command, a model download, and one `LocalEmbedding` row; the first search after
that answers `warming` and starts the worker lazily (R-2).

## R-8 — Compose and demo

**Decision.** `docker-compose.yml` loses the `ollama` service and the `ollama-models` volume. The
demo needs no compose change: it builds the same `Dockerfile`, so it gets the packages, the model,
the `ENV` and the `CMD` warm-up.

**Sizes.**

| Image | Before | After (estimate from R-3) |
|---|---|---|
| `ollama/ollama:latest` | 9.28 GB on disk (~3.7 GB download) | removed |
| `sentai-task-iris` | 3.99 GB | ≈ 5.4 GB (+1.3 GB packages, +88 MB model) |
| `sentai-task-iris-target` | 3.74 GB | unchanged (`Dockerfile_target`) |

Dev stack on disk: 17.0 GB → ≈ 9.1 GB (SC-001: ≥ 5 GB less). The demo never ran `ollama`, so its
disk need grows by ≈ 1.4 GB, to ≈ 9.1 GB for the two images; the VM needs that plus IRIS data and
build cache. Build time grows by ≈ 87 s (pip) + ≈ 7 s (model). Memory: the worker holds ≈ 500 MB
once, where the `ollama` container used to run beside IRIS.

The final numbers are re-measured on the real image build and recorded in `evidence/`.

## R-9 — `warming` joins the closed list of reasons

**Decision.** `SearchOutcome.REASONS` gains `warming`; the frontend's closed list in
`frontend/src/lib/api/wire.ts` and the `UnavailableReason` type in
`frontend/src/lib/palette/search.ts` gain it too. The palette's behaviour is unchanged — every
unavailable reason already falls back to today's palette — but without the addition the wire would
normalize `warming` to `error`, and the evidence could not show FR-004a's outcome by name. The
response shape does not change (FR-015); one value is added to an existing enumeration
([contracts/api-delta.md](contracts/api-delta.md)).
