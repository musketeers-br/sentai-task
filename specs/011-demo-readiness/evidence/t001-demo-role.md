# T001 — Demo role and securing spike (2026-09-29)

Isolated compose project `sentai-demo-check` (`docker-compose.yml` + `docker-compose.demo.yml`,
Caddy on host port 8080), built from branch `feat/spec011`. The dev stack was not touched. The
privileged secret was random, kept in the session scratchpad only, and sent to IRIS on stdin.

## (a) Securing the privileged accounts

`scripts/demo/secure-accounts.script` on both instances secured `_Ensemble`, `_SYSTEM`, `Admin`,
`irisowner`, `SuperUser` (rule of research R-2; `CSPSystem` and `UnknownUser` left alone).

| Check | Result |
|---|---|
| `POST /api/admin/login` `_SYSTEM:SYS` through the proxy | **401** |
| same with the secret | 200 |
| `iris-target:52773/api/admin/login` `_SYSTEM:SYS` (from inside the compose network) | **401** |
| canvas `GET /csp/sentai/` | 200 (the web gateway still works) |
| `iris session iris -U %SYS` from the host (`docker exec`) | works (OS authentication) |
| `/` | 302 → `/csp/sentai/` |
| `/csp/sys/UtilHome.csp`, `/api/atelier/`, `/api/mgmnt/`, `/_vscode/` | **404** (not forwarded) |

The IRIS services also ran healthy **without** the bind mount of the checkout and without
`ISC_CPF_MERGE_FILE` (`merge.cpf` is applied at build time), so the public machine never exposes
the repository or a local `.env` inside the container.

## (b) Least privilege, found one refusal at a time

Every refusal below is the platform's, shown verbatim by the product (except where noted as a
product defect).

| Round | Role content (primary) | What failed, verbatim |
|---|---|---|
| 1 | `%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW` | validation passed with **no** findings and dispatch created runs with **no steps that never end**; catalog 403 → product defect D1 (below): the SQL refusal was swallowed |
| 2 | + SQL `SELECT, INSERT, UPDATE, DELETE ON SCHEMA sentai_model` | `CATEGORY_NOT_FOUND` for `Default` (the WQM read is refused); target step `TARGET_REFUSED: HTTP 403`; catalog 403 |
| 3 | + `%Admin_Manage:U, %DB_IRISSYS:R` | in-process steps `ERROR #5540: SQLCODE: -99 … not privileged`; integrity checks `returned HTTP 403` |
| 4 | + `%Admin_Operate:U` | catalog 200; integrity checks "Administrative job reported Failed" → the platform's real reason, read directly from the async result: `ERROR #5002: ObjectScript error: <PROTECT>%SaveData+4^SYS.BackgroundIntegrity.1 ^%SYS.BackgroundTaskD,/usr/irissys/mgr/` (product defect D2: not shown by the product) |
| 5 | `%DB_IRISSYS:RW` | integrity checks complete (local and target); in-process steps still -99 |
| 6 | + SQL `GRANT EXECUTE ON %SYS.DatabaseQuery_FreeSpace` (IRISAPP) | **example and showcase complete** |
| 7 | − `%DB_USER:R` on the primary | still completes → removed |
| 8 | − `%DB_USER:R` on the target | `NAMESPACE_NOT_FOUND: Namespace 'USER' does not exist on target` → kept on the target |

**Final role `SentaiDemo`**
- Primary: `%DB_IRISAPP_CODE:R, %DB_IRISAPP_DATA:RW, %Admin_Manage:U, %DB_IRISSYS:RW, %Admin_Operate:U`
  plus SQL on IRISAPP: `SELECT, INSERT, UPDATE, DELETE ON SCHEMA sentai_model` and
  `EXECUTE ON %SYS.DatabaseQuery_FreeSpace`.
- Target: `%DB_USER:R, %Admin_Manage:U, %DB_IRISSYS:RW, %Admin_Operate:U`.

Neither holds `%Admin_Secure` or `%All` (the stop condition was not reached).

## (c) What the demo account cannot do, and what it can

- `GET /api/admin/v2/security/users` → **403** (no security administration). ✅
- `purge-task-history` (typed confirmation given) → **the platform allows it**: the run completed.
  The same resources that the integrity check needs (`%Admin_Manage`, write on IRISSYS) let the
  platform run the task-history purge (already noted in `docs/limitations.md`). The product
  cannot separate them without deciding for the platform (Constitution III).
  **Decision** (2026-09-29, autonomous mode granted by the user): accepted for the public demo.
  The worst case is that a visitor deletes task history on a disposable instance, which harms
  nothing the demo shows; the typed confirmation still applies. Spec FR-007 and US2-5 were
  amended to say this honestly.
- Risk accepted with `%DB_IRISSYS:RW` + `%Admin_Manage:U`: a visitor could change platform
  configuration reachable through `/api/admin` (for example WQM categories). The proxy exposes no
  code-execution surface (`/api/atelier`, terminal and portal are not reachable), the privileged
  accounts use the secret, and the reset (US4) returns the product data. A changed category is
  not restored by the reset; this is documented.

## (d) Restart

`docker compose restart` of the project → both instances healthy; `_SYSTEM:SYS` → 401;
`sentai-demo` → 200; example and showcase complete again as `sentai-demo`. ✅

## Product defects found (fixed in T025)

- **D1** A platform SQL refusal (`SQLCODE -99`) while reading a flow's steps is treated as "no
  steps": validation reports no errors, and dispatch creates a run with no step runs whose loop
  dies, so it stays `running` forever. The refusal must be returned verbatim (Constitution III,
  IV).
- **D2** When a platform job ends `Failed`, the product records "Administrative job reported
  Failed" and drops the platform's `result.FailureReason`, which carries the actual reason
  (spec 003 FR-023 requires the reason verbatim).
