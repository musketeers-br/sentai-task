# Research — 004 Backend Hardening

All items below were resolved by reading the existing code (spec 003 as implemented) and the
spec 001/003 evidence. No external research was needed; no NEEDS CLARIFICATION remains.

## R-001 — Where availability lives

- **Decision**: add `"available": true|false` to each entry of `sentai.registry.StepType`'s
  `XData Catalog`, plus `ClassMethod IsAvailable(type) As %Boolean` next to
  `IsDestructive`/`IsPausable`.
- **Rationale**: the XData block is already the sole declared catalog (Constitution II: data, not
  code branches). `GetCatalog()` returns the XData as-is, so `GET /catalog/step-types` gains the
  field with **no REST change** — PROMPTS T007 collapses into T001.
- **Alternatives**: a separate "support set" list in the validator (two sources of truth —
  rejected); a runtime platform probe (not proven stable, adds a credential dependency to the
  catalog read — rejected, spec Assumptions).

## R-002 — Where the availability rule runs, and rerun

- **Decision**: new rule in `FlowValidator.Validate()` inside the existing per-step loop, in the
  `ElseIf` chain after `IsKnownType` (so unknown types report only `UNKNOWN_STEP_TYPE`). It is
  additive to every other rule. Rerun gets a guard at the top of `WaveDispatcher.RerunStep`:
  look up the step's type from the run's flow and return
  `$$$ERROR(…"STEP_TYPE_NOT_SUPPORTED_ON_TARGET: …")`, which the REST layer already maps to 409.
- **Rationale**: validate, dispatch (`WaveDispatcher.Dispatch` → `Validate`) and schedule
  (`ValidateForSchedule` → `Validate`) share one gate, so one rule covers three paths. Rerun
  bypasses validation today (`RerunStep` only checks `state = failed`).
- **Order vs. confirmation**: `Dispatch` validates before checking confirmations, so an
  unsupported destructive step yields `VALIDATION_FAILED` (422), never 428. Matches the spec edge
  case with no code change.
- **Alternatives**: a dispatch-only check (misses validate/schedule — rejected); re-validating the
  whole flow on rerun (wider behavior change than needed — rejected).

## R-003 — How category existence is checked (F-3)

- **Decision**: `Validate(flowId, bearerToken As %String = "")`. When `bearerToken '= ""`, the
  validator calls `sentai.wqm.CategoryService.List(bearerToken)` **once per validation**, builds a
  name set, and emits `CATEGORY_NOT_FOUND` for every step whose effective category
  (`step.wqmCategory`, else `flow.defaultCategory` — same resolution as
  `WaveDispatcher` line 253) is not in the set. When the list call fails, the set is empty, so every
  step reports the error (fail closed). When `bearerToken = ""`, the rule is skipped.
- **Callers**: `Dispatcher.ValidateFlow` and `ScheduleFlow` pass `..CurrentToken()`;
  `ValidateForSchedule(flowId, bearerToken)` forwards it; `WaveDispatcher.Dispatch` gains a
  trailing `bearerToken As %String = ""` that `Dispatcher.DispatchFlow` fills.
  `ScheduledFlowTask.OnTask` keeps calling `Dispatch` without a token → the rule is skipped at fire
  time, which keeps D-2's documented behavior (run created, steps fail with verbatim 401) instead
  of silently creating no run at all.
- **`List` hardening**: `CategoryService.List` today calls `body."result".%GetIterator()`
  unguarded; a non-2xx or empty body would throw. Guard it: non-2xx or missing `result` → return
  `[]`. This is what makes "fail closed" a value, not an exception (Constitution IV).
- **Rationale**: the platform's own category list, read with the operator's credential, is the
  source of truth (Constitution III; `CategoryService` doc comment). The local
  `sentai.model.Category` mirror is only refreshed by reads, so it can be stale or empty.
- **Alternatives considered**:
  - Local mirror lookup — stale/empty on a fresh instance; would reject `Default` until someone
    opened the WQM screen. Rejected.
  - In-process probe `$SYSTEM.WorkMgr.%New(,,category)` (same check the enqueue does; needs no
    token) — allocates a work queue per validation with unmeasured side effects, and tests would
    need real categories on the test instance. Rejected for v1; noted as an option if the admin
    API read ever becomes a bottleneck.
  - Fail-open when the lookup fails — reintroduces F-3 silently. Rejected.

## R-004 — Default category for new flows (spec Clarifications, Q1)

- **Decision**: keep `SENTAI.DEFAULT` (`sentai.model.Flow.defaultCategory` InitialExpression and
  spec 002 `flow-definition.schema.json` `default`). No change.
- **Rationale**: the user constraint "no change to the flow JSON schema" is explicit; the schema
  carries the default. R-003 turns the non-existent default into a visible validation error.
- **Consequence**: the quickstart sets `defaultCategory: "Default"` explicitly; the README states
  that flows must name an existing category.

## R-005 — Zero means unbounded (D-3, F-4)

- **Decision**: change only `sentai.model.Category.SatisfiesInvariant`: map `maxWorkers = 0` and
  `maxTotalWorkers = 0` to a sentinel "infinite" before comparing. ObjectScript has no +∞;
  compare with an explicit rule: `a ≤ b` holds when `b` is unbounded; `a` unbounded ≤ `b` holds
  only when `b` is also unbounded.
- **Rationale**: it is the single invariant implementation, called by both
  `CategoryService.Write` and `FlowValidator` rule 5 — one fix covers every evaluation (FR-005).
  `NormalizeWorkerCount` already turns `"Dynamic (N)"` into N before the invariant runs.
- **Note**: `maxWorkers = 0` with `maxTotalWorkers = 5` becomes ∞ ≤ 5 → **fails**. This is
  intended: evidence shows built-ins report both as 0; a finite total with an unbounded per-queue
  max is not observed and would be a real inconsistency.
- **Alternatives**: a large number (e.g. 999999) as ∞ — hides the semantics and can collide with
  a real value. Rejected.

## R-006 — WQM write contract (F-1)

- **Decision**:
  - add `AdminApiClient.Put(urlPath, bearerToken, body, .httpStatus, .location)` mirroring `Post`
    (`req.Put(urlPath)`), with the same test-double dispatch;
  - add `AdminApiDouble.Put` that records `^sentaiTestDouble("put", basePath) = $LB(urlPath, json)`
    and responds from `^sentaiTestDouble("response", basePath, "PUT")`;
  - `CategoryService.Write` calls
    `Put("/api/admin/v2/wqm-category?name="_$ZCONVERT(name,"O","URL"), …)` with body **without
    `Name`** (evidence 10a: name is a query parameter; body-only `Name` → `ERROR #40300`);
    numeric fields set with `%Set(key, value, "number")` and `AlwaysQueue` with `"boolean"`
    (compatibility.md: WQM type asymmetry).
- **Regression guard (FR-004)**: the new test asserts `^sentaiTestDouble("put", "/api/admin/v2/wqm-category")`
  holds the expected URL/body, **and** that nothing was recorded under `"posted"` for any
  `wqm-categories/<name>` path. `CategoryTest` and `WqmCategoryEndpointTest` switch their scripted
  response from `POST …/wqm-categories/<name>` to `PUT /api/admin/v2/wqm-category`.
- **Alternatives**: overloading `Post` with a method argument — muddles an API used by every
  dispatch call. Rejected.

## R-007 — Keeping destructive/pausable behavior tested after D-1

- **Problem**: the canonical fixture (`SentaiTestCase`) has step 04 `purge-audit-records` and 05
  `switch-journal`, both unavailable, and every step on `SENTAI.NIGHT`. After R-002/R-003 it no
  longer validates, so tests that expect `errors: []`, 202, or 428 on it break.
- **Decision**:
  1. Keep the canonical fixture unchanged — it is the only vehicle for destructive and pausable
     behavior, which the spec says stays implemented and tested.
  2. Add `SupportedGraph()` to `SentaiTestCase`: 01, 02 `integrity-check` roots → 03
     `integrity-check` join, all on `Default` (D-1 amended: `integrity-check` only). Tests whose point is "a valid flow validates /
     dispatches / schedules" move to it.
  3. Tests whose point is typed confirmation move from `Dispatch` to a new extracted
     `WaveDispatcher.CheckConfirmations(flowId, confirmations, .pendingStepId) As %Boolean`
     (the existing loop, lifted out verbatim; `Dispatch` calls it). This keeps FR-017 coverage
     without a test-only availability override in production code.
  4. `SentaiTestCase` setup scripts `GET /api/admin/v2/wqm-categories` on the double with
     `Default`, `SQL`, `Utility` (values from evidence 09: `MaxTotalWorkers = 0`) and
     `SENTAI.NIGHT` (test fixture), so validation tests keep passing the category rule.
  5. `DestructiveSchedulingRuleTest` keeps asserting `DESTRUCTIVE_NOT_SCHEDULABLE` is **present**;
     it now also sees `STEP_TYPE_NOT_SUPPORTED_ON_TARGET` (additive — spec edge case).
- **Rationale**: FR-008 allows adjusting tests that encoded a now-false promise; no test is
  deleted. Extracting `CheckConfirmations` is the smallest refactor that avoids a production
  test seam.
- **Alternatives**: a `^sentaiTestDouble("available", type)` override in `IsAvailable` —
  production code reading test globals for a domain rule. Rejected.

## R-008 — Documentation targets

- **Decision**: README gets a `## Known limitations (v1)` section (the README is still the IRIS
  dev template; the section is added after "What does it do"). Spec 003 `quickstart.md` gets a
  "Superseded by spec 004" banner pointing to `specs/004-backend-hardening/quickstart.md`; its
  canonical-flow steps are not edited in place (they are the T070 evidence record). Spec 003
  `HANDOFF.md` gets a "Resolution by spec 004" section.
- **Rationale**: preserves 003's evidence trail; the runnable path lives in 004.
