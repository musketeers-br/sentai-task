# T0 — Proofs on a real second instance (2026-09-27)

Target: `iris-target`, built from `Dockerfile_target` (`intersystems/iris-community:latest-cd`,
IRIS 2026.2 Build 221U, passwords unexpired, **nothing of SentaiTask installed**), on the compose
network. Every call was made from **inside the primary container** with `%Net.HttpRequest`, the
way the product calls. Tokens and passwords are redacted in the evidence files.

| Research item | Result | Evidence |
|---|---|---|
| **R-1** remote job calls | **Proven.** Login (Basic) → 200 pair + `sub`; refresh → 200; integrity-check start `{}` → 202 + `Location: /api/admin/v1/async-result?id=…`; polled to `State: Finished` in about 34 s with the full `Console`; a second job cancelled with `async-result/cancel?id=` → 200, then read as `State: Canceled`. Wrong password → 401 | `t0-target-calls.json` |
| **R-2** queue length | **Not provided by the platform.** `wqm-categories` returns worker configuration only; the single read `wqm-category?name=Default` returns zeros and no queue length. Plan deviation D-1 stands: no `queueLength` | `t0-target-calls.json` (09, 09b) |
| **R-3** identity and namespaces | **Proven.** `info` returns `serverVersion`, `username` and `namespaces` (`%SYS`, `USER` on the target — no `IRISAPP`, so a remote step naming `IRISAPP` must get `NAMESPACE_NOT_FOUND`). Without a token → 401 | `t0-target-calls.json` (00, 00b) |
| **R-4** transport errors | **Proven, with a timing finding.** Unknown host, closed port and stopped target all give `ERROR #6059: Unable to open TCP/IP socket to server <host>:<port>`, verbatim from `%SYSTEM.Status`. The attempt takes 14–18 s although `Timeout = 10`: the open timeout is separate, so T003 also sets `OpenTimeout`. On failure `HttpResponse` is not an object — the client must not read it | `t0-transport-errors.json` |
| **R-5** non-persistent storage | **Proven.** `^IRIS.Temp.sentaiT0` from IRISAPP resolves to `/usr/irissys/mgr/iristemp/` | `t0-target-calls.json` notes (below) |
| **R-13** demo target | **Proven.** `Dockerfile_target` builds, becomes healthy, and accepts `/api/admin/login` straight away | this run |

R-5 detail: `##class(%SYS.Namespace).GetGlobalDest("IRISAPP","IRIS.Temp.sentaiT0")` returned
`^/usr/irissys/mgr/iristemp/`; the probe global was killed afterwards.

**Also observed:** a cancelled job reports `State: "Canceled"`, a state the current poller does not
handle (it knows `Finished`, `Error`, `Failed`). Harmless today, because a cancelled step is not
polled again, but T009 must not rely on polling to see a cancel.

**Conclusion:** the feature is feasible as planned. Tasks T005 and T008 may proceed.

## Addendum (T007, 2026-09-27)

`POST /api/admin/refresh` on the target **without any Authorization header**, body
`{"refresh_token": …}`, returns 200 with a new `access_token`, `refresh_token`, `sub`, `iat`,
`exp`; the old refresh token is then refused (401, rotated). So dispatch can redeem a target
refresh token on its own, as research R-7 assumed.

## Addendum (2026-09-27, alert after cancel)

The cancel in `08c-cancel` (09:57:50 on `iris-target`, a plain IRIS) is followed in its
`messages.log`, at the same second, by `WorkMgr appendError … ERROR #7802: Worker job/s '725:28'
unexpectedly shut down in group '#Default:(…)'` at severity 2: the platform's own cancel ends the
worker and logs it as an alert. The same message appears on the primary each time a running step is
cancelled (reproduced with e2e us4 "Cancel wave" and "cancelling one step"); it puts the instance in
the *alert* state, which the image's healthcheck reports as `unhealthy`.

