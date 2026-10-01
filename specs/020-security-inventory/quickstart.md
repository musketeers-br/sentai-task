# Quickstart / validation guide: Security Inventory (spec 020)

Dev stack running (`docker compose up -d`, primary on `localhost:52773`, `iris-target` in the
compose network), code loaded (`LoadDir` of `src` and `tests`), canvas published
(`bash scripts/publish-canvas.sh`).

## 1. Backend tests

`zpm "test sentai-task -only"` in IRISAPP (never `DebugRunTestCase`; `git status` afterwards).
Expected: `ReportCertificateExpiryTest`, `ReportPermissionsInventoryTest`,
`ReportOAuthInventoryTest` pass together with the whole suite; the registry test counts 16 types.

## 2. An expiring certificate fails the check (US1, SC-001 local)

1. Create the fixture on the primary (key discarded, public certificate only):
   `openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/k -out /tmp/c.crt -days 10 -subj "/CN=sentai-e2e-020"`
   inside the container, delete `/tmp/k`, then in `%SYS`:
   `set x=##class(%SYS.X509Credentials).%New(),x.Alias="sentai-e2e-020" do x.LoadCertificate("/tmp/c.crt"),x.%Save()`.
2. In the canvas, a flow with *Certificate expiry check* (*Warn days* 30) → *Run now*.
   Expected: the step fails; its Result shows `CERT_EXPIRING` for `sentai-e2e-020` with
   `daysLeft` 9 or 10 first.
3. Set *Warn days* to 5, run again: the step completes; the credential is listed as `valid`.
4. Delete the credential: `do ##class(%SYS.X509Credentials).%DeleteId("sentai-e2e-020")`.

## 3. Scheduled (SC-001 scheduled)

`python scripts/security-evidence/acceptance.py` creates the fixture, schedules a flow with the
check two minutes ahead (spec 015), waits for the firing, asserts a failed scheduled run whose
reason names the certificate, then removes the schedule, the flow and the fixture.

## 4. Permissions (US2, SC-002)

Run *Permissions inventory*: `summary.itemsRead` covers every role and resource; the role and
resource counts equal `GET /api/admin/v2/security/roles` and `…/resources`.

## 5. OAuth not configured (US3, SC-003)

Run *OAuth inventory* on the dev instance: the step completes; `details.configured` is false and
`serverMessage` is the platform's `ERROR #8864` text.

## 6. Remote and refused (SC-006, FR-002)

Place the three steps on `iris-target` (one password per target at *Run now*): each reports
`instance: "iris-target"`. As the demo account (no `%Admin_Secure`), each step fails with the
platform's 403, verbatim.

## 7. Secrecy (SC-004)

`ResultSecrecyTest` extended to the three types; scan exported runs and evidence for
`PRIVATE KEY`, `PrivateKey`, `ClientSecret`: no match.
