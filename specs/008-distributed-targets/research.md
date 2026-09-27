# Research — 008 Distributed Targets

Sources: the current code (`sentai.dispatch.*`, `sentai.validation.FlowValidator`,
`sentai.rest.Dispatcher`), spec 001 evidence (the IRIS 2026.2 management API contract), spec 005
(run credential E-1). Items marked **To prove** are verified on a real second instance by plan task
T0 before the code that depends on them is merged; until then the plan states the fallback.

## R-1 — Which calls a remote step makes

**Finding.** A platform-executed step is three management-API calls, all proven locally in spec 001:
start `POST /api/admin/v2/database-dir/integrity-check` with `{}` → `202` + `Location:
/api/admin/v1/async-result?id=<id>` (evidence 06); poll `GET <Location>` until `result.State` is
`Finished` / `Error` / `Failed` (07a–c); pause/resume/cancel `POST
/api/admin/v2/async-result/{pause|resume|cancel}?id=<id>` (08a–c). `Location` is a path, so it is
relative to whichever instance answered.

**Decision.** A remote step makes the same calls against the target's base address. The poll
target is `target base + Location`. **To prove (T0):** the same three calls against a second
2026.2 instance reached over the container network, with a token issued by that instance.

## R-2 — Load: what the platform reports

**Finding.** `GET /api/admin/v2/wqm-categories` (evidence 09) returns, per category, `Name`,
`MaxActiveWorkers`, `DefaultWorkers`, `MaxWorkers`, `MaxTotalWorkers`, `AlwaysQueue` — worker
configuration, **not** a queue length. No proven read returns queue length.

**Decision.** The status read returns the categories exactly as the target reports them. A
`queueLength` value is added **only if** T0 proves a management-API read that returns it (for
example the single-category read `GET /api/admin/v2/wqm-category?name=`); otherwise the status
carries no queue length and the spec's "load via queue length" is recorded as not provided by the
platform (spec deviation D-1). Nothing is estimated.

## R-3 — Target identity and version

**Finding.** `GET /api/admin/info` (evidence 00) returns `serverVersion`, `username` and
`namespaces[]` with the caller's token.

**Decision.** The status read uses it for `version`; validation uses its `namespaces[]` for a
remote step's namespace check (the local check calls `%SYS.Namespace.Exists`, which only knows the
primary). `username` is kept to report which user the target saw.

## R-4 — Transport errors are lost today

**Finding.** `AdminApiClient` ignores the `%Status` returned by `%Net.HttpRequest.Get/Post/…`. On a
connection failure the caller sees `httpStatus = 0` and no text; `PollInFlightSteps` then retries
forever ("5xx/network: retry").

**Decision.** Each client call also returns, by reference, the transport error text
(`$SYSTEM.Status.GetErrorText` of the request's status) when no HTTP answer arrived. Existing
callers ignore the new argument, so their behaviour is unchanged (FR-019). `%Net.HttpRequest.Timeout`
is set to 10 s for target calls (the reachability bound of the spec's assumption); local calls keep
the default.

## R-5 — Where target credentials live

**Finding.** The local run credential (E-1) is kept in `^sentaiRun(runGuid, "%token"/"%refresh")`, a
database global, and erased at run end.

**Decision.** Target credentials go to `^IRIS.Temp.sentaiTargetCred(runGuid, targetName)` =
`$lb(access, refresh, issuedAt, sub)`. `^IRIS.Temp*` globals live in IRISTEMP: never journaled,
never persisted across a restart, readable by the run's worker processes. This is the closest the
platform offers to "in memory only" for a multi-process run (FR-011). They are erased with the local
credential in `FinalizeRun`. **To prove (T0):** `^IRIS.Temp.*` maps to IRISTEMP on the product
image (it is the platform default). Moving the local credential there too is out of scope (YAGNI).

## R-6 — Sign-in to a target (Clarifications Q1 = A)

**Decision.** `POST /targets/{name}/sign-in` with `{"user", "password"}` → the primary calls the
target's `POST /api/admin/login` once with `Authorization: Basic` (evidence 01), and returns the
target's `access_token`, `refresh_token`, `sub` (and nothing else). The body is read into a local
variable and never written to a global, a log or `^ISCLOG`. A refusal returns the target's status
and body `status.errors[].error` verbatim; a transport failure → `502 TARGET_UNREACHABLE` with the
transport error.

## R-7 — How a request carries a target credential

The product API's own `Authorization` header carries the primary token and is validated on every
request. So:
- **status read:** header `X-Sentai-Target-Authorization: Bearer <target access token>`;
- **validate:** optional body `{"targetCredentials": [{"target", "accessToken"}]}`;
- **dispatch:** body `targetCredentials: [{"target", "refreshToken"}]` (spec). The primary redeems
  each refresh token on its target (`POST /api/admin/refresh`, evidence 02) before any run exists,
  as E-1 does locally; the returned `sub` must equal the dispatching user, case-insensitively
  (`TARGET_CREDENTIAL_USER_MISMATCH`), otherwise nothing is created.

## R-8 — Validation without target credentials

**Finding.** `/flows/{id}/validate` today needs only the primary token. The spec's FR-009 checks
"reachable" and "by the target's answers", which need a target credential.

**Decision (spec deviation D-2).** Validate always runs the checks that need no target credential
(exists, online, remote-capable). With a credential for the target in the body it also runs
reachable + the target-answer checks. Without one it adds the **warning** `TARGET_NOT_VERIFIED`
(target named), never an error, so a flow can be saved and validated before signing in. Dispatch
always runs every check with the redeemed credentials (FR-018, authoritative).

## R-9 — Which category governs a remote step

**Finding.** A step is started from a Work Queue Manager worker **on the primary**
(`WaveDispatcher.StartStep` → `ExecuteStepAsync`); the target runs the job through its own
management API, which takes no category.

**Decision (spec deviation D-3).** The step's category is still a primary category (existing
`CATEGORY_NOT_FOUND` check, unchanged). It bounds how many start calls the primary makes at once.
The spec assumption "the category must exist on the target" is dropped: the target is never asked
for it. The target's categories appear only in its status read.

## R-10 — Results of platform-executed steps

**Finding.** `PollInFlightSteps` sets `completed` on `State = Finished` but stores nothing in
`StepRun.result`; only in-process steps (spec 005) fill it.

**Decision.** On `Finished`, the poll stores the async-result's `result` object (`State`,
`TaskName`, `Console[]`), fitted with `InProcessExecutor.FitResult`, for local and remote steps
alike. This is additive for local runs: no existing assertion reads `result` of a platform step.
SC-002 compares it with the target's own read of the job.

## R-11 — HTTPS and the development allowance

**Decision.** A target's base address is `scheme://host:port`. `https` uses the SSL/TLS client
configuration `SentaiTargets` (created by the installer, peer verification on). `http` is accepted
only for loopback hosts, or when `^sentai("config", "allowInsecureTargets") = 1`. The demo
container sets it in `iris.script` with a comment; the README states it is for the demo network
only.

## R-12 — A target that disappears mid-run

**Decision.** Poll transport errors on a remote step are recorded per step
(`^IRIS.Temp.sentaiTargetCred(runGuid, "lastError", stepRunGuid)`) and the step keeps polling.
`SweepTimeouts` extends to remote steps: past the step's timeout (or the in-process default,
60 min, when 0) it fails with `timed out after N min; last transport error: <text verbatim>`. Other
steps are untouched (FR-016). A 4xx from the target stays permanent, as today, with its text.

## R-13 — The demo's second instance

**Decision.** `docker-compose.yml` gains `iris-target`, built from `Dockerfile_target`: the same
`intersystems/iris-community` base, passwords unexpired as in the main image, nothing of SentaiTask
installed (proves the "no install on the target" assumption). Port 52773 is not published; the
primary reaches it as `http://iris-target:52773`. **To prove (T0):** login and integrity check on
it, from the primary container.
