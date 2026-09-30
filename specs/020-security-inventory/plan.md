# Implementation Plan: Security Inventory — Roles, Resources, Certificates and OAuth (read-only)

**Branch**: `specs/020-security-inventory` (implementation on `feat/spec020`, based on
`feat/spec015`) | **Date**: 2026-09-29 | **Spec**: [spec.md](spec.md)

**Input**: [spec.md](spec.md) (4 user stories, 12 FRs, 6 SCs), the live probe of
[research.md](research.md), and spec 013's `platform-read` executor, which this plan reuses
unchanged.

## Summary

Three new report classes on spec 013's `platform-read` executor, three registry entries, and
nothing else in the architecture:

1. **`sentai.steps.reports.CertificateExpiry`** (`certificate-expiry-check`, P1): reads x509
   credentials and each one's certificate (`ValidityNotAfter`), and the SSL/TLS configurations;
   raises `CERT_EXPIRED` / `CERT_EXPIRING` against `warnDays`, and **fails the step** when any
   certificate crosses it — so a flow scheduled with spec 015 fails *before* expiry.
2. **`sentai.steps.reports.PermissionsInventory`** (`permissions-inventory`, P1): roles (one read
   per role for its resources and granted roles) and resources with their public permission;
   fixed rules for public write/use and roles granting `%All`.
3. **`sentai.steps.reports.OAuthInventory`** (`oauth-inventory`, P2): server, server clients,
   server definitions, client configurations per definition, resource servers; `ERROR #8864`
   (`OAuth2NoConfiguration`) is the *not configured* state, not a failure.
4. **Canvas**: no new component. The palette already groups `security`; the inspector already
   renders integer/boolean parameters with field errors; the result panel already shows reports.
   The only frontend change is none unless T001 shows a field the result panel should format
   (dates are strings, shown as-is).

The platform reads go through the existing `Reader` (one `Get(path)`), with the run's credential
for the instance the step runs on — local, a target, or the run-as account in a scheduled run
(spec 015). Nothing is written.

## Technical Context

**Language/Version**: ObjectScript (IRIS 2026.2); TypeScript 5.9 + Svelte 5 (no change expected).

**Primary Dependencies**: none new. Management API v2 routes in
[contracts/api-delta.md](contracts/api-delta.md), all probed live except the OAuth item fields
(no OAuth object on the dev instance — T001).

**Storage**: none new; `StepRun.result` via `ReadExecutor.FitResult(json, "summary,findings")`.

**Testing**:
- `%UnitTest` with `AdminApiDouble` scripted answers: `ReportCertificateExpiryTest` (expired,
  expiring, valid, unknown validity, threshold edge `daysLeft = warnDays`, configurations with and
  without file, empty instance, partial refusal, full refusal, private-key fields never copied),
  `ReportPermissionsInventoryTest` (counts, the three rules, `failOnFindings`, cap at 200),
  `ReportOAuthInventoryTest` (not configured → completes; per-definition client reads; the two
  rules; `ClientSecret` never copied); registry test (16 types); `ResultSecrecyTest` extended.
- Playwright `us29-security-inventory.spec.ts`: the three types in the palette; the certificate
  check fails with a fixture certificate and completes with a small `warnDays`; OAuth completes
  "not configured"; permissions on `iris-target`; field error for `warnDays: 0`.
- Acceptance `scripts/security-evidence/acceptance.py`: the scheduled firing (SC-001) on the real
  platform, reusing spec 015's acceptance helpers.

**Target Platform / Project Type**: as today (IRIS backend + SvelteKit canvas, dev compose stack
with `iris-target`).

**Performance Goals**: SC-005 (answer in under a minute) — each step under 5 s on the dev
instance (≈ 50 reads at ≈ 20 ms, research R-5).

**Constraints**: GET only; allow-listed fields only (never `PrivateKey*`, `ClientSecret`, key
material); platform text verbatim; `daysLeft` from the instance's own date; UI in English.

**Scale/Scope**: 3 report classes (~350 lines), 3 test classes (~35 tests), 3 registry entries,
README section, one e2e spec, one acceptance script.

## Constitution Check

| Principle / Standard | How this plan complies | Status |
|---|---|---|
| **I Layered Architecture** | Report classes are pure rules over the `Reader`'s answers (domain/application); `Reader` wraps `AdminApiClient` (infrastructure), composed by `ReadExecutor` as in spec 013. | ✅ |
| **II Closed Capability Set** | Three declared types with fixed read paths and fixed rules; parameters validated by declared schemas (`warnDays` 1–365, booleans). No expression, no configurable rule. | ✅ |
| **III Delegated Authorization** | Every read is a management-API call with the run's credential for that instance; refusals are the step's failure reason verbatim. Validity is taken only from the platform's answer (R-2): the product never opens certificate files, which would bypass the platform. | ✅ |
| **IV Errors as Values** | `Build` returns `%Status` + report; partial refusal and "not configured" are values in the report. | ✅ |
| **V Verifiable Increments** | Increment 1 ships `certificate-expiry-check` end to end (unit, e2e, scheduled acceptance); 2 and 3 add one type each. | ✅ |
| **VI Technology Agnosticism** | Only in plan/research/data-model. | ✅ |
| Stored-credential rule (1.1.0) | Not touched: no secret is stored or read; spec 015 scheduling is reused as is. | ✅ |
| TDD / YAGNI | Scripted-answer tests first; no new executor, screen, or policy engine. | ✅ |

## Decisions

- **D-1 Reuse `platform-read`.** The three steps are synchronous reads plus rules, exactly spec
  013's executor; no change to `ReadExecutor`, `WaveDispatcher` or the result panel.
- **D-2 Validity only from x509 credentials** (R-2). SSL/TLS configurations are listed (path,
  TLS versions, peer verification) with `CONFIG_VALIDITY_NOT_REPORTED` (*info*) when they name a
  certificate file. Documented in the README and limitations as a platform deviation.
- **D-3 Failing.** `certificate-expiry-check` fails when `CERT_EXPIRED + CERT_EXPIRING > 0`
  (the check's purpose; no `failOnFindings`). The two inventories fail only with
  `failOnFindings` and a *high* finding (spec 013 D-6). All three fail on reads only when every
  read was refused.
- **D-4 Days left.** `asOf` = the instance's `$ZDATETIME($HOROLOG,3)` at build time; `daysLeft` =
  `$ZDATEH(notAfter date) - +$HOROLOG` (whole days), `CERT_EXPIRED` when `notAfter` is before
  `asOf` (time included).
- **D-5 OAuth not configured.** Server read → 404 with status error id `OAuth2NoConfiguration`
  (code 8864) ⇒ `configured: false`, `serverMessage` verbatim, continue with the other lists.
  Any other 4xx/5xx ⇒ `INCOMPLETE_READ` (or step failure if every read was refused). The `Reader`
  already returns the problem text; T001 checks it exposes the status error id or code so the
  distinction is exact (otherwise match `#8864` in the text).
- **D-6 Caps.** 200 items per per-item loop (roles, credentials, configurations, definitions),
  `NOT_ALL_READ` (*info*) beyond — findings stay protected by `FitResult`.
- **D-7 Resource families** as research R-6 (`%DB_`, `%Admin_`, `%Development`).
- **D-8 Fixtures.** e2e/acceptance create throw-away x509 credentials (public certificate only)
  on the dev stack through `iris session` (helpers in `frontend/tests/iris.ts` and the acceptance
  script, guarded to the dev container and the `sentai-e2e-020-` alias prefix), deleted in
  `finally`.

## T001 spike (stop conditions)

1. On the primary and on `iris-target`: each route of the contract answers as in research R-1
   (record counts and field names; no value of a secret field).
2. Create an OAuth server definition and a client configuration on the dev stack (then delete
   them) to confirm item field names and the `serverId` value. **Stop and flag** if client
   configurations cannot be read per definition → they are reported as "not read" and documented.
3. The demo account's answer on each route (expected 403).
4. The `Reader` exposes the status error `id`/`code` of a 404 (for D-5).

## Increments

| # | Scope | First failing test | Then |
|---|---|---|---|
| 0 | T001 spike | evidence `t001-security-reads.md` | research updated |
| 1 | `certificate-expiry-check` | `ReportCertificateExpiryTest`; us29 case A (fixture → fails; warnDays 5 → completes); acceptance (scheduled failure) | class, registry entry, README example |
| 2 | `permissions-inventory` | `ReportPermissionsInventoryTest`; us29 case B (local counts, on iris-target) | class, entry |
| 3 | `oauth-inventory` | `ReportOAuthInventoryTest`; us29 case C (not configured completes) | class, entry |
| 4 | Docs and regression | `ResultSecrecyTest`; full suites | README, limitations, contest table |

## Project Structure

### Documentation (this feature)

```text
specs/020-security-inventory/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md
├── contracts/api-delta.md
├── checklists/requirements.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
src/sentai/steps/reports/CertificateExpiry.cls        # new
src/sentai/steps/reports/PermissionsInventory.cls     # new
src/sentai/steps/reports/OAuthInventory.cls           # new
src/sentai/registry/StepType.cls                      # 3 entries
tests/sentai/unittest/steps/ReportCertificateExpiryTest.cls      # new
tests/sentai/unittest/steps/ReportPermissionsInventoryTest.cls   # new
tests/sentai/unittest/steps/ReportOAuthInventoryTest.cls         # new
tests/sentai/unittest/…/StepTypeCatalogTest, ResultSecrecyTest   # counts, secrecy
frontend/tests/us29-security-inventory.spec.ts        # new
frontend/tests/iris.ts                                # x509 fixture helpers (guarded)
scripts/security-evidence/acceptance.py               # new
README.md, docs/limitations.md
```

**Structure Decision**: the existing single backend (`src/sentai`) plus the SvelteKit canvas
(`frontend/`); report classes live beside spec 013's in `sentai.steps.reports`.

## Complexity Tracking

No violations.

## Constitution re-check after Phase 1

Passing. The design adds rules over platform answers only; the deviation (no validity for SSL/TLS
configuration files) is the platform's, reported rather than worked around.
