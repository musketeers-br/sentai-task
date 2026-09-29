# Implementation Plan: Area Report Steps — Security, Web Applications, System Alerts and Secrets as Flow Steps

**Branch**: `feat/spec013` (feature dir `013-area-report-steps`) | **Date**: 2026-09-28 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (5 clarifications, 13 FRs, 6 SCs). A third executor kind,
**`platform-read`**: a WQM worker makes a fixed set of `GET`s on the management API of the
instance the step runs on (local or target) with the run's credential, and a declared report
class turns the answers into a report with findings. Four report classes, registry entries,
palette groups, and a result panel in the run view, which also serves every existing step that
stores a result. The product API changes only by values: a new `executor` value and two new
categories in `GET /catalog/step-types`, plus `result` already present in step runs
([contracts/api-delta.md](contracts/api-delta.md)).

## Summary

1. **Executor `platform-read` (all stories).** `WaveDispatcher.StartStep` sends a
   `platform-read` step to `sentai.dispatch.ReadExecutor.Run` on a detached WorkMgr worker of the
   step's category, after `TransitionLocked(running)`, exactly like in-process steps (spec 005).
   The worker builds a `sentai.steps.reports.Reader` bound to the step's instance (base URL and
   token from the run: `^sentaiRun(run,"%token")` locally, `TargetToken` on a target), calls the
   type's report class, fits the result with findings protected from truncation, and ends the
   step through `TransitionLocked` with the result, `executedAs` = the token's subject.
2. **Four report classes** under `sentai.steps.reports`, each a pure function of the reader's
   answers and the parameters, so each is unit-tested with `AdminApiDouble` scripts:
   `SecurityPosture`, `WebAppInventory`, `SystemAlerts`, `SecretsInventory`. They share one
   abstract `Report` (`Build(reader, parameters, .report) As %Status`, finding helpers, field
   allow-lists).
3. **Registry.** Four entries (`executor: "platform-read"`, categories `security` and
   `monitoring`). `remoteCapable` is derived for `platform-api` **and** `platform-read`.
   `IsInstalled` accepts a `platform-read` class that extends `sentai.steps.reports.Report`.
   Timeouts, cancel and re-run reuse the in-process paths (`SweepTimeouts` covers every
   worker-run step, local or remote).
4. **Canvas.** `executor: 'platform-read'` and categories `security`/`monitoring` in the wire and
   palette (groups *Security* and *Monitoring*). `StepRunView` gains `result`. A **Result** action
   on finished steps opens a side panel: `ReportView` for reports (summary, findings by severity,
   then details); `CatalogValue`'s tree for any other result.

## Technical Context

**Language/Version**: ObjectScript (IRIS 2026.2); TypeScript 5.9 + Svelte 5.

**Primary Dependencies**: none new. The management API endpoints used (probed 2026-09-28 on the
dev instance, [research R-1](research.md)):
`GET /api/admin/v2/security/users`, `GET …/security/user?name=`, `GET …/security/services`,
`GET …/security/audit/enabled`, `GET …/web-apps`, `GET …/monitor/dashboard/main`,
`GET …/wallet/collections`, `GET …/wallet/secrets?collection=`.

**Storage**: none new. Results go in `StepRun.result` (8,000 characters, spec 005 FitResult).

**Testing**:
- `%UnitTest`: `ReportSecurityPostureTest`, `ReportWebAppInventoryTest`, `ReportSystemAlertsTest`,
  `ReportSecretsInventoryTest` (scripted answers, including refusals, partial reads, oversize,
  and value fields that must be dropped); `ReadExecutorTest` (states, local/target token, cancel
  race, timeout sweep); registry and validator additions; `ResultSecrecyTest` (SC-004 scan).
- vitest: `palette` groups, `result.ts` (report detection, severity order, counts), wire.
- Playwright `us27-area-steps.spec.ts`: the four types locally and on `iris-target`, result panel,
  a refused operator.

**Target Platform / Project Type**: as today.

**Performance Goals**: SC-001 < 10 s per step. The security report makes 1 + N + 2 reads (N =
enabled users, capped at 200, [R-3](research.md)); about 20 ms per local read measured by the
probe, so under 5 s at the cap.

**Constraints**: read-only (only `GET`); no field outside each report's allow-list is copied from
an answer (FR-005); findings are never truncated (FR-004); platform text verbatim; UI English.

**Scale/Scope**: backend 1 executor class, 1 abstract + 4 report classes (~500 lines), ~6 test
classes (~45 tests). Frontend: 1 panel, 1 report view, 1 pure module, wire and palette changes.

## Constitution Check

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | `ReadExecutor` (application) depends on the `Reader` abstraction; the concrete reader wraps `AdminApiClient` (infrastructure) and is composed in `ReadExecutor.Run`, the edge of the worker. Report classes are pure rules over answers. | ✅ |
| **II Closed Capability Set** | Four declared types; each class's reads are fixed paths in its code; the class is chosen only from the registry by `type`. Parameters are validated against declared schemas (boolean/integer with `min`). No rule is an expression. | ✅ |
| **III Delegated Authorization** | Every read is a management-API call with the operator's own credential for that instance; the platform decides. A refusal fails the step verbatim; no privilege table is kept in the product (the README documents observed requirements only). | ✅ |
| **IV Errors as Values** | `Build` returns `%Status` plus the report; a partial read is a finding value; the executor records the outcome through `TransitionLocked`. Frontend: tagged result kinds. | ✅ |
| **V Verifiable Increments** | One increment per type (backend report + registry entry + e2e case), after a first increment that ships the executor with `system-alerts-check` end to end and the result panel. | ✅ |
| **VI Technology Agnosticism** | Only in plan/research. | ✅ |
| SOLID | Open/closed: a new report type is a new class + registry entry; the executor does not change. Interface segregation: `Reader` has one method, `Get(path)`. | ✅ |
| TDD | Each report class starts from failing scripted-answer tests. | ✅ |
| YAGNI | No policy engine, no corrective actions, no per-rule configuration. | ✅ |

## Decisions

- **D-1 Why a new executor instead of `platform-api`.** `platform-api` means "start an
  asynchronous platform job and poll it" (`ExecuteStepAsync` + `PollInFlightSteps`). These steps
  are synchronous reads plus product rules. Reusing that path would need fake job ids. The
  worker-based in-process path already provides the lifecycle they need (running at start,
  terminal state written by the worker, timeout sweep, cancel race handled by
  `TransitionLocked`).
- **D-2 Credential in the worker.** The worker reads the token when it starts. The run loop renews
  local and target credentials every `RENEWAFTERSECONDS` (well inside the 60 s lifetime), and a
  report completes in seconds, so the token cannot expire mid-report in practice. If a read gets
  401, the step fails with it verbatim, as a platform step does (E-1 behaviour).
- **D-3 Result fitting.** `InProcessExecutor.FitResult(json)` drops elements from the largest
  top-level array. `ReadExecutor` uses a new `FitResult(json, protect)` overload with
  `protect = "summary,findings"`: protected keys are never cut, and details arrays are cut first
  (largest first), adding `truncated`/`omitted` as today. If protected keys alone exceed the
  limit, findings are cut from the *info* end and `summary.findingsOmitted` says how many.
- **D-4 Report shape.**
  `{"type": "<type>", "instance": "local|<target>", "summary": {"high": n, "medium": n, "info": n,
  "itemsRead": n, "itemsOmitted": n}, "findings": [{"severity", "rule", "item", "detail"}],
  "details": {…}}`. Details per type are in [data-model §2](data-model.md).
- **D-5 Allow-lists (FR-005).** Each report copies named fields only: users `Name, FullName,
  Enabled, Roles, AccountNeverExpires, PasswordNeverExpires, ChangePassword`; services `Name,
  Enabled, AuthenticationMethods, Public`; web apps `Name, Namespace, Enabled, Type, Resource,
  AuthenticationMethods, DispatchClass, IsSystemApp`; collections `Name, UseResource,
  EditResource` (names confirmed in T001); secrets `Name, Type`. Anything else in an answer is
  never read, so a value field cannot leak.
- **D-6 Failing on findings.** `SecurityPosture` and `WebAppInventory` complete unless
  `failOnFindings` is true and `summary.high > 0`; then `Build` returns an error status whose text
  is `"<n> high finding(s): <rule> <item>; …"` (first 5), and the report is still stored.
  `SystemAlerts` fails per FR-009; `SecretsInventory` never fails on findings.
- **D-7 "Normal" status.** `SystemAlerts` treats exactly the string `Normal` as normal for
  `DatabaseSpace`, `DatabaseJournal`, `JournalSpace`, `LockTable`, `WriteDaemon` (and any other
  `SystemUsage` field whose value is a string), following the probe; unknown strings are not
  normal (spec edge case). What `SeriousAlerts` counts, and whether `$SYSTEM.Monitor.Clear()`
  resets it, is established in T001 ([R-4](research.md)) and documented in the type's
  description.
- **D-8 Palette and categories.** `StepCategory` gains `security` and `monitoring`; `GROUP_ORDER`
  places them after `verification`. `groupOf` keeps sending `in-process` types to *Custom*, and
  `platform-read` types go by their category.
- **D-9 Result panel.** `RunNode` shows **Result** when `state` is terminal and `result` is not
  empty. It opens `ResultPanel` in the run view's aside (replacing the legend while open). The
  panel has `ReportView` for `isReport(result)` (has `summary` and `findings`), and the spec 007
  `CatalogValue` tree otherwise. Findings are ordered high → medium → info, with severity as a
  text chip plus colour.
- **D-10 Namespace field.** `Step.namespace` stays required; the four types default to `%SYS`
  and their descriptions say the reads are instance-wide. No new "scope" concept (YAGNI).

## Increments

| # | Scope | First failing test | Then |
|---|---|---|---|
| 1 | Executor + `system-alerts-check` + result panel | `ReadExecutorTest`, `ReportSystemAlertsTest`, `result.test.ts`, us27 case A (alerts check completes locally and its result opens) | executor, registry entry, panel |
| 2 | `security-posture-report` | `ReportSecurityPostureTest`; us27 case B (local and on target; refused operator) | class + entry |
| 3 | `web-app-inventory` | `ReportWebAppInventoryTest`; us27 case C | class + entry |
| 4 | `secrets-inventory` | `ReportSecretsInventoryTest`, `ResultSecrecyTest`; us27 case D | class + entry |
| 5 | Gate scenario and docs | us27 case E (SC-005: alerts check fails → join blocks integrity checks) | README, limitations |

## Project Structure

```text
specs/013-area-report-steps/
├── plan.md  research.md  data-model.md  quickstart.md  analysis.md  tasks.md
├── contracts/api-delta.md
└── checklists/requirements.md

src/sentai/dispatch/ReadExecutor.cls                 # new
src/sentai/dispatch/InProcessExecutor.cls            # FitResult(json, protect)
src/sentai/dispatch/WaveDispatcher.cls               # StartStep branch; SweepTimeouts condition
src/sentai/registry/StepType.cls                     # 4 entries; remoteCapable; IsInstalled
src/sentai/steps/reports/Report.cls                  # new (abstract)
src/sentai/steps/reports/Reader.cls                  # new
src/sentai/steps/reports/SecurityPosture.cls         # new
src/sentai/steps/reports/WebAppInventory.cls         # new
src/sentai/steps/reports/SystemAlerts.cls            # new
src/sentai/steps/reports/SecretsInventory.cls        # new
tests/sentai/unittest/Report*Test.cls, ReadExecutorTest.cls, ResultSecrecyTest.cls
frontend/src/lib/api/wire.ts, flow/document.ts       # executor, categories, result
frontend/src/lib/run/result.ts (+ test)              # new
frontend/src/lib/run/ResultPanel.svelte, ReportView.svelte   # new
frontend/src/lib/run/RunNode.svelte, RunScreen.svelte
frontend/tests/us27-area-steps.spec.ts               # new
README.md, docs/limitations.md
```

## Complexity Tracking

No violations.

## Constitution re-check after Phase 1

Passing. The reports interpret platform answers with fixed rules; they never grant, deny or cache
anything. Where the platform refuses a read, the step shows that refusal.
