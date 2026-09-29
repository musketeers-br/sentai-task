# Evidence — spec 017 (in-process embeddings)

No credentials, tokens or secrets appear in any file here.

| File | Task | What it proves |
|---|---|---|
| this README, "Before" | T001–T003 | The state every "after" number is compared with |
| this README, "US2" | T016 | The in-process provider's contract holds under test |
| this README, "US3" | T025 | A provider change rebuilds the corpus; nothing else does |
| this README, "US1" | T032 | Build, sizes, services, worker warm-up, `scripts/check-search-image.sh` |
| `api-us1-search.txt` | T033 | The R-5 queries through the REST API: same top results and scores as the ollama baseline (SC-003) |
| `timing-us1.txt` | T034 | Five fresh starts, first search ranked in ≈0.1 s; 20 warm searches, 0 above one second (SC-004) |
| `demo-us4.txt` | T042 | The demo account's search answered `error` with spec 011's grants and ranks with spec 017's (grant on `sentai_search`, `SELECT` on `%EMBEDDING.Config`) |
| `migration-us5.txt` | T044 | The pre-017 image with no `ollama` answers `unreachable` (HTTP 200); the rebuilt stack ranks |
| `api-us1-warming-offline.txt` | T035 | `warming` right after a restart (HTTP 200), then ranked; the worker loads with no network (7.4 s) |

## Before (2026-09-29, branch `017-in-process-embeddings`, before any change)

### Images (`docker images`)

| Image | Size | Id |
|---|---|---|
| `ollama/ollama:latest` | 9.28 GB | `8262851b2846` |
| `sentai-task-iris:latest` | 3.99 GB | `5066dcaca35f` |
| `sentai-task-iris-target:latest` | 3.74 GB | `72367a17db74` |
| **Dev stack total** | **17.01 GB** | |

`sentai-task-iris:pre-017` is a tag on `5066dcaca35f`, kept for the US5 check (T002, T044).

### Suites

| Suite | Result |
|---|---|
| Backend `zpm "test sentai-task -only"` | All PASSED — 375 methods, 2619 assertions |
| Frontend `npm test` | 26 files, 215 tests passed |

### Search with the spec 011 provider (`ollama`, `all-minilm`), REST API

Measured for research.md (baseline). First request builds the 13-row corpus.

| Query | Time | Matches (≥ 0.20) |
|---|---|---|
| free up disk space | 0.772 s | storage-headroom-check 0.594, compact-globals 0.487, db-size-report 0.451, purge-audit-records 0.400, purge-task-history 0.292, defragment-globals 0.289 |
| check my globals are sound | 0.038 s | integrity-check 0.474, system-alerts-check 0.229, defragment-globals 0.202 |
| get rid of old audit records | 0.033 s | purge-audit-records 0.705, purge-task-history 0.332, switch-journal 0.291, compact-globals 0.289, db-size-report 0.279, storage-headroom-check 0.229 |
| rotate the journal | 0.036 s | switch-journal 0.555, db-size-report 0.320, purge-audit-records 0.217 |
| order me a pizza | 0.032 s | none |
| send an email to my manager | 0.034 s | none |
| banana | 0.032 s | none |

## US2 — the in-process provider under test (T016)

| Suite | Result |
|---|---|
| Backend | All PASSED — **391** methods (375 + 16 new), 2700 assertions |
| Frontend `npm test` | 26 files, 216 tests passed (1 new case) |
| Frontend `npm run check` | 0 errors, 0 warnings |

New backend tests: `EmbeddingWorkerTest` (6), `LocalEmbeddingTest` (7), `SearchOutcomeTest`
(+1, and `warming` in the documented-reasons loop), `StepSearchServiceTest` (+2). After the run:
no worker process, no registration in IRISTEMP, no event resource, and `sentai-steps` restored.

Found while making them pass: IRIS resource names take letters and digits only (`-`, `_` or `.`
fail with `<FUNCTION>`) and at most 32 characters, so the worker's event is `sentaiEmbed` + the
namespace's letters and digits, cut to 32 (data-model §4).

## US3 — provider identity (T025)

| Suite | Result |
|---|---|
| Backend | All PASSED — **395** methods, 2732 assertions |

New: `TestModelChangeRebuildsCorpus`, `TestUnchangedProviderDoesNotRebuild`,
`TestIdentityCarriesNoSecret` (StepSearchServiceTest), `TestRowsCarryProviderIdentity`
(StepCorpusTest).

Changed: spec 011's `TestIncompatibleProviderIsUnavailableIncompatible` produced its width mismatch
by re-pointing the row at a half-width double. Under FR-007 a changed row now rebuilds the corpus
(which is what the new tests assert), so the test now narrows the stored vectors with the row
unchanged; the `incompatible` answer it proves is the same. `NarrowEmbeddingService` is no longer
used by any test.

## US1 — the image and the stack (T032)

`docker compose build iris` then `docker compose up -d --remove-orphans` (the orphaned `ollama`
container was removed; the `ollama-models` volume and the `ollama/ollama` image were left on the
machine and can be removed by hand).

| Item | Value |
|---|---|
| Build of `iris` (whole image, no cache for the new layers) | 249 s — pip layer 97.2 s, model layer 22.2 s |
| `sentai-task-iris:latest` | **5.93 GB** (was 3.99 GB: +1.94 GB) |
| Inside it | `/usr/irissys/mgr/python` 1.4 GB (torch `2.14.0+cpu`), `/usr/irissys/mgr/sentai-models` 88 MB |
| Dev stack images | **9.67 GB** (5.93 + 3.74) — was 17.01 GB with `ollama`: **7.34 GB less** (SC-001 ≥ 5 GB) |
| `docker compose ps` | `iris`, `iris-target` — two containers (SC-002) |
| `up` → healthy → worker `ready` | 19 s → +7 s (26 s), with no search made |
| Worker process | 447 MB RSS, one process |
| `scripts/check-search-image.sh` | all 6 checks ok (no `ollama`; CPU-only torch; 0 `nvidia-*`; offline variables; `sentai-steps` → `LocalEmbedding`) |

Before the image change the same script failed 5 of 6 checks (T026).

## Final gates (T049)

| Gate | Result |
|---|---|
| Backend suite, on the spec 017 image with the real worker `ready` | All PASSED — 395 methods, 2732 assertions; the real worker and the `sentai-steps` row are untouched by the suite |
| Frontend `npm test` / `npm run check` | 216 passed / 0 errors |
| `scripts/check-search-image.sh` | 6 of 6 ok |
| `scripts/check-spec-status.sh` | consistent (Status `Implemented`; open tasks T043 and T048 are `[external]`) |

Observed, not changed (spec 011 behaviour): with the `ollama` host gone, the HTTP provider takes
≈5.4 s to answer `unreachable` (connection timeout), above the one-second budget.
