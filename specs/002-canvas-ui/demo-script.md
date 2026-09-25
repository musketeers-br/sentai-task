# Demo video script — 4 minutes (v1)

Replaces the dossiê §10 script, whose flow (checks → purge → switch journal) cannot run in v1
(spec 004: only `integrity-check` is executable). Every beat below was exercised against the dev
container on 2026-09-25; times are what the platform actually takes there.

**Before recording**: `docker-compose up -d --build`, open
`http://localhost:52773/csp/sentai/`, answer the browser's IRIS prompt, sign in, window at 1440×900, dark theme. Have a
second, pre-saved flow containing a *Purge audit records* step for beat 3.

| Time | Beat | On screen |
|---|---|---|
| 0:00–0:20 | **The problem.** Heavy maintenance on IRIS is a list of Task Manager entries; order, parallelism and "what if one fails" live in someone's head. | Management Portal Task Manager list, then cut to the SentaiTask canvas. |
| 0:20–1:10 | **Compose.** Drag three *Integrity check* steps, a fourth, a fifth. Connect #01 #02 #03 → #04 (one diamond appears: a join), #04 → #05. Try #05 → #01: refused, "would create a cycle". Click #01, set namespace/directory in the inspector. Point at the greyed *not supported in v1* palette entries: the product only offers what the platform proved. | Canvas, palette, inspector, status bar `5 steps · 1 join · 0 destructive`. |
| 1:10–1:40 | **Validate.** Save, *Validate flow* on the clean flow ("Flow is valid"). Open the pre-saved flow with *Purge audit records*: validation names #04 as unsupported on the node and in the status bar; *Run now* is disabled. | Error panel on the node, `N errors block scheduling (#04…)`. |
| 1:40–3:20 | **Run.** Back to the clean flow, *Run now*, password once ("the run gets its own sign-in and renews it"). Live view: three steps run in parallel, #04 waits for #01 #02 #03, #05 waits for #04. Cancel nothing; let it go. ~50 s per check: the wave completes at ~2:30 of run time — speed through the middle with a cut, keep the clock visible. End on `RUN COMPLETED · 5 completed`. | Wave strip, count line, clocks, rail with GUIDs and the six-state key. |
| 3:20–3:40 | **Control.** Start a second run, cancel one running step: its siblings keep running; *Cancel wave* asks for confirmation naming the run; the run ends `RUN CANCELLED` — never reported as success. | Cancelled chip, confirmation dialog, final pill. |
| 3:40–4:00 | **Honest and installable.** Toggle Light (designed, not inverted). Show README "Known limitations (v1)" and the one-command install. | Light theme, README. |

**Do not show**: scheduling as a working feature (spec 004 D-2 — it registers native tasks that
cannot run in v1); pause (no v1 type is pausable); the SSE stream (the canvas polls).
