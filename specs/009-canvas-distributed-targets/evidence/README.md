# Evidence — 009 Canvas Screens for Distributed Targets

Captured on 2026-09-27 on the compose stack (`iris` + `iris-target`), canvas published with
`scripts/publish-canvas.sh`. No password or token appears in any file here.

| File | What it shows |
|---|---|
| `us1-targets.json` | The Targets screen's values compared with `GET /targets` and `GET /targets/{name}/status` (us15) |
| `us3-remote-run.json`, `us3-remote-run.png` | The demo flow dispatched from the canvas with one target password; every node's `executedOn` equals the run read (us16) |
| `sc006-targets-dark.png`, `sc006-targets-light.png` | The Targets screen with a target's live state open, both themes (us15) |

## Success criteria

| SC | Result |
|---|---|
| SC-001 register, place, run from the canvas | **Met.** us15 registers from the screen; us16 places a step with *Run on* (saved and read back) and runs the demo flow to completion with `executedOn` per node |
| SC-002 every Targets value equals the API | **Met.** List and live state compared field by field (us15) |
| SC-003 refusals verbatim | **Met.** `INVALID_TARGET` (400), wrong target password (`HTTP 401 — no reason given`, on the screen and at *Run now*), unknown host (`HTTP 502 — TARGET_UNREACHABLE …`) |
| SC-004 no credential left in the browser | **Met** for tokens (no JWT in storage, cookies or URL after a sign-in). The password check is skipped with the dev default password `SYS` (too short to search meaningfully) |
| SC-005 existing tests green, none removed | **Met.** Unit 73 → 80; e2e 22 → 27 (us15 ×2, us16 ×3) |
| SC-006 theming pair | **Met.** Same text in both themes, every text ≥ 4.5:1 |

## Findings while building

- A wrong **target** password came back as the target's 401, which the client took as the
  operator's own session expiring and signed them out. A 401 whose body carries `httpStatus` (spec
  008 marks every passed-through target answer that way) is now a refusal, not an expiry.
- The spec 008 backend tests left every target they registered in the instance (486 of them). The
  shared test base now removes the targets a test created; the residue was deleted.
- Reading a target's state keeps nothing (the plan's ~55 s token cache was dropped as useless: the
  tokens expire in 60 s).
