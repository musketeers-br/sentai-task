# Implementation contract — REST mapping

Feature: `003-backend-objectscript` · Date: 2026-09-22

This file does not change `specs/002-canvas-ui/contracts/openapi.yaml` — it maps each already
contracted endpoint to the class/method that implements it, and to the spec 003 requirement(s) it
satisfies. It serves as the index that `tasks.md` will decompose.

| Endpoint (openapi.yaml) | Class/service | Requirement(s) |
|---|---|---|
| `GET /flows` | `sentai.rest.Dispatcher` → `sentai.model.Flow` (query) | FR-002 |
| `POST /flows` | `sentai.rest.Dispatcher` → `sentai.validation.FlowValidator` (structural) → `sentai.model.Flow` (save) | FR-001, FR-005, FR-007 |
| `GET /flows/{flowId}` | `sentai.rest.Dispatcher` → `sentai.model.Flow` (read) | FR-003 |
| `PUT /flows/{flowId}` | `sentai.rest.Dispatcher` → `sentai.validation.FlowValidator` (structural) → `sentai.model.Flow` (save, revision) | FR-004, FR-005, FR-006, FR-007 |
| `POST /flows/{flowId}/validate` | `sentai.rest.Dispatcher` → `sentai.validation.FlowValidator.Validate` | FR-012, FR-013, FR-014, FR-015 |
| `POST /flows/{flowId}/schedule` | `sentai.rest.Dispatcher` → `sentai.validation.FlowValidator` (blocks on error) → call to the native administrative API (`%SYS.Task.Definition` creation per step) | FR-031, FR-032 |
| `POST /flows/{flowId}/dispatch` | `sentai.rest.Dispatcher` → `sentai.validation.FlowValidator` (structural) → destructive-confirmation check → `sentai.model.Run`/`StepRun` (transaction) → `JOB` of `sentai.dispatch.WaveDispatcher` | FR-016, FR-017, FR-018 |
| `GET /runs` | `sentai.rest.Dispatcher` → `sentai.model.Run` (query) | FR-024 |
| `GET /runs/{runGuid}` | `sentai.rest.Dispatcher` → `sentai.model.Run/StepRun/LogEntry` (read) | FR-024 |
| `GET /runs/{runGuid}/events` | `sentai.rest.Dispatcher` (dedicated SSE method) — see `sse-protocol.md` | FR-025, FR-026 |
| `POST /runs/{runGuid}/cancel` | `sentai.rest.Dispatcher` → `sentai.dispatch.WaveDispatcher.CancelRun` | FR-027 |
| `POST /runs/{runGuid}/pause` | `sentai.rest.Dispatcher` → `sentai.dispatch.WaveDispatcher.PauseRun` | FR-027 |
| `POST /runs/{runGuid}/steps/{stepGuid}/cancel` | `sentai.rest.Dispatcher` → `sentai.dispatch.WaveDispatcher.CancelStep` | FR-028 |
| `POST /runs/{runGuid}/steps/{stepGuid}/pause` | `sentai.rest.Dispatcher` → `sentai.dispatch.WaveDispatcher.PauseStep` (409 if the type is not pausable — `sentai.registry.StepType`) | FR-029 |
| `POST /runs/{runGuid}/steps/{stepGuid}/rerun` | `sentai.rest.Dispatcher` → `sentai.dispatch.WaveDispatcher.RerunStep` | FR-030 |
| `GET /catalog/tasks` | `sentai.rest.Dispatcher` → `sentai.catalog.TaskService` (P3, reducible) | FR-038 |
| `GET /catalog/tasks/{taskId}` | `sentai.rest.Dispatcher` → `sentai.catalog.TaskService` (P3, reducible) | FR-038 |
| `POST /catalog/tasks/{taskId}/suspend` | `sentai.rest.Dispatcher` → `sentai.catalog.TaskService` (P3, reducible) | FR-039 |
| `GET /wqm/categories` | `sentai.rest.Dispatcher` → `sentai.wqm.CategoryService` (passthrough to the administrative API) | FR-033 |
| `GET /wqm/categories/{name}` | `sentai.rest.Dispatcher` → `sentai.wqm.CategoryService` (+ `affectedTaskCount`) | FR-033, FR-035 |
| `PUT /wqm/categories/{name}` | `sentai.rest.Dispatcher` → `sentai.wqm.CategoryService` (invariant, then passthrough) | FR-033, FR-034, FR-036 |
| Step-type catalog (consumed by the canvas; no explicit dedicated endpoint in `openapi.yaml` — served as part of the payload the frontend already consumes, or as a read extension over `sentai.registry.StepType`) | `sentai.registry.StepType` | FR-037 |

## Errors — unified shape

Every error response uses the `Problem` schema already defined in `openapi.yaml` (`status`,
`title`, `detail`) except where the contract already specifies a more specific body
(`ValidationReport` for a 422 validation error; no body beyond `202`/`409` for the others).
`sentai.rest.Dispatcher` centralizes this translation — no service class writes to the HTTP
response directly.

| Situation | Status | Body |
|---|---|---|
| Missing/invalid authentication (FR-040, NFR-006) | 401 | `Problem` |
| Flow not found | 404 | `Problem` |
| Duplicate flow name / stale revision | 409 | `Problem` |
| Structural validation error (create/save/schedule/dispatch) | 422 | `ValidationReport` |
| Missing/incorrect destructive confirmation on dispatch | 428 | `Problem` (naming the step) |
| Pause requested for a non-pausable type | 409 | `Problem` |
