# Evidence — 008 Distributed Targets (DPI-I-588)

Captured on 2026-09-27 on the compose stack: `iris` (SentaiTask) and `iris-target` (plain IRIS
2026.2, nothing installed). No password, token or refresh token appears in any file here.

| File | What it shows |
|---|---|
| `t0-summary.md`, `t0-target-calls.json`, `t0-transport-errors.json` | T001: the management-API calls a remote step needs, proven from inside the primary against the target; transport error texts; no queue-length read exists; IRISTEMP mapping; refresh without a bearer (addendum) |
| `t008-demo-run.json` | The first real remote run: 01, 02 on the primary, 03 on `iris-target`, fan-in to 04 — completed; step 03's report names the target machine |
| `quickstart-http-2026-09-27.json` | The quickstart (a)–(f), every call with status, time and body (secrets redacted), produced by `scripts/targets-evidence/quickstart.py` |

## Success criteria

| SC | Result |
|---|---|
| SC-001 demo flow, `executedOn` correct | **Met.** Quickstart (d): completed; `local`, `local`, `iris-target`, `local` |
| SC-002 remote `result` = the target's job read | **Met by construction:** the stored result is the `result` object of the target's own async-result read (step 03's report names the target's system, `t008-demo-run.json`). It was not compared with a second, independent read |
| SC-003 target stopped mid-run fails exactly one step | **Met after a fix.** The first quickstart run found a stopped target stalling the run loop, so the local run credential expired and a local step failed with 401. Fixed (30 s back-off per target; local credential renewed right before each local poll). Rerun (e): 01 local `completed`, 03 `failed` with `timed out after 1 min; last transport error: ERROR #6059 …`. **Limitation:** while the target is down each attempt still waits up to ~15 s, so that failure — and local progress — lagged by about 2.5 minutes |
| SC-004 every new code by a test and a recorded call | **Partly met.** Unit tests cover all of them. Recorded calls: `TARGET_NOT_FOUND`, `TARGET_OFFLINE`, `STEP_TYPE_NOT_REMOTE_CAPABLE`, `TARGET_NOT_VERIFIED`, `NAMESPACE_NOT_FOUND` (from the target), `TARGET_CREDENTIAL_MISSING`, `TARGET_CREDENTIAL_USER_MISMATCH`, and the unreachable target in the status read and in (e). `TARGET_REFUSED` and dispatch-time `TARGET_UNREACHABLE` are unit-tested only |
| SC-005 no secret stored or logged | **Met.** 153 passwords and tokens used during the quickstart were searched in `^sentai`, `^sentaiRun`, the target registry, `^IRIS.Temp.sentaiTargetCred` and `messages.log`: 0 hits; the run credentials of both runs were erased |
| SC-006 status read < 3 s when reachable | **Met.** 0.07 s (unreachable: 7.96 s, the connection timeout) |
| SC-007 existing suites green, none removed | **Met.** Backend 268/268 (225 before 008); frontend unit 73/73, e2e green except `us14`, skipped until spec 005 T016 reaches `master` |
| SC-008 a clean checkout brings both up with one command | **Not verified** from a clean checkout: `iris-target` was built with `docker compose up -d --build iris-target`; the main image was not rebuilt in this session |

## Deviations recorded during implementation

- T006: `STEP_TYPE_NOT_REMOTE_CAPABLE` is checked before reachability, so no call is made for a
  step that could not run there anyway.
- T009: a refused cancel/pause leaves the step running and returns `CONTROL_REFUSED` verbatim
  (502) instead of recording it as a failure reason — the job is still running there.
