# Evidence — 010 Canvas Onboarding and Flow Management Usability

Rule: no token, password or refresh token ever goes into an evidence file. JSON records hold ids,
names, revisions, states, timings and key *names* only.

## Files this feature produces

| File | Task | What it shows |
|---|---|---|
| `us17-save-as.json`, `us17-rename-note.png` | T004/T016 | Save as: two flows, the original untouched; the rename note |
| `us18-open-flow.json`, `us18-perf.json` | T017/T019 | Open flow… order/filter/actions ≤ 3; 5,000-flow timings |
| `us19-storage-keys.json` | T029 | Kept sign-in: storage key names only (FR-011) |
| `us20-example.json` | T038 | Example validation report, per-step states, elapsed time |
| `us21-guide.json`, `us21-guide-step1.png` | T046 | Guide steps, keyboard, SC-006 |
| `theming-*.png` | T054 | New dialogs in dark and light |
| `sc001-usability.md`, `sc003-sc007-manual.md`, `sc004-sc005.json`, `sc006-manual.md` | T057–T060 | Manual quickstart runs |
| `constitution-review.md` | T063 | Review against the Constitution |

## Baseline (T001, 2026-09-27)

- Unit (vitest): **89/89 passed**.
- E2e (Playwright, `sentai-task-iris-1`, published build of `master`): **26 passed, 3 failed,
  2 did not run** (31). The 3 failures (`us15-targets` ×2, `us16-remote-run` place) and the 2 that
  did not run are spec 009 tests that need the compose service `iris-target`. That container does
  not exist on this machine (`docker ps -a` lists only `sentai-task-iris-1`), so
  `POST /targets` → `iris-target` fails. This is the environment, not code; this feature does not
  touch targets. Start it with `docker-compose up -d iris-target` before the full regression
  (T056) to get 31/31.

## No-backend check (T002, re-run in T062)

```bash
git diff --stat master -- src/ specs/002-canvas-ui/contracts/openapi.yaml
```

Must print nothing. 2026-09-27 (before implementation): empty.

## Top bar at 1440 px (T025 — applied during US1)

The plan's fallback alone did not fit. Measured at 1440×900: the bar was 109 px over with *New flow*
and *Save as…* as buttons, and *Open flow…* (SC-002: one click) and *Help ▾* still had to come.
The existing theming tests require *Schedule in Task Manager*, *Dark* and *Light* to stay visible
text. The layout that shipped:

- *Open flow…* and *Save flow* are visible buttons; *New flow* and *Save as…* are in a **More ▾**
  menu (WAI-ARIA menu button, `lib/shell/MenuButton.svelte`) — the plan's D-7 fallback;
- the `%SYS` chip and the `rev n · saved hh:mm` line are stacked **under** the flow name instead of
  beside it; the bar's gap went from 10 to 8 px; the name field's minimum is 112 px.

Result: no clipping, 0 px overflow, with room left for *Help ▾* (checked again in US5).

## Open flow… with 5,000 flows (T019/T024)

`us18-perf.json`: real `GET /flows` (5,046 flows) 44 ms + client render 34 ms = **79 ms** to the
first rows; filter **73 ms**; longest main-thread task **73 ms**. No windowed rendering was needed
(the list uses `content-visibility: auto`). The first attempt measured 3.5 s, all of it in
Playwright's own locator engine walking 20k nodes (CPU profile: `visitNode`), not the app — so the
timings are taken in the page.

## Refresh-token expiry, opt-in (T030, run once for T036)

`SENTAI_SLOW=1 npx playwright test tests/us19-kept-sign-in.spec.ts -g expired` — **passed** in
15.1 min on 2026-09-27: a kept token left unused for 905 s was refused on load; the canvas said
"Your session ended — sign in again." and, after signing in, reopened the flow in the address.

## Focus trap (found by us21)

A native modal `<dialog>` lets Tab leave the page for the browser's chrome after its last control.
`lib/shell/Modal.svelte` now wraps Tab / Shift+Tab inside the dialog (FR-025), for all four new
dialogs.

## Theming and wording (T054, T055)

- `us21` "theming" opens the invitation, *Open flow…*, the guide, *Save as…* and the unsaved-changes
  dialog in both themes: 0 contrast failures; screenshots `theming-*-{dark,light}.png`.
- No raw colour in the new components or `dialog.css` (grep for hex / `rgb(` / `hsl(` is empty);
  `audit.test.ts` unchanged (no token added).
- English wording as the spec gives it: "Renames this flow — use Save as… to keep a copy",
  "Your session ended — sign in again.", "Sign in to continue in this tab.",
  "Use Save as… to keep your version.", "Don't show this again", "Getting started",
  "Example: storage health check", "Start from scratch", "No saved flows yet.",
  "Save as a new flow", "Signing you back in…".

## Full regression (T053, T056 — 2026-09-27)

- Unit: **145/145** (18 files; baseline 89).
- E2e: **59 passed, 1 skipped, 3 failed, 2 did not run** (65). Skipped = the opt-in 905 s expiry
  test (run separately, passed). The 3 failures and 2 not run are the same spec 009 tests as the
  baseline — they need the compose service `iris-target`, which is not running on this machine
  (`docker-compose up -d iris-target` to include them). No other failure.
- The suite rewrites spec 002/007 evidence files on every run; those were restored with
  `git checkout` (spec 009 convention), so this change carries only spec 010 evidence.

## Cleanup (T061 — approved by the user, 2026-09-27)

Deleted **134** flows with `deleteFlowWithRuns` (guarded: localhost, `sentai-task-iris-1`,
namespace IRISAPP, exact name, test prefix): every `us17-`…`us21-` flow, the e2e
`Example: storage health check`, and `plan010-probe-1790544431` (id 5126, with its run). The count
was 114 when approved; the final regression run added 20 more of the same kind before the delete.
Afterwards: `GET /flows/5126` → 404; 0 flows left in scope; 0 orphan runs.

## No-backend check (T062)

`git diff --stat master -- src/ specs/002-canvas-ui/contracts/openapi.yaml` → empty. No
ObjectScript changed, so no IRIS `%UnitTest` run was needed.

## Spec 009 target tests (T064, 2026-09-27)

**Environment.** `POST /targets` answered `400` with, verbatim:
`INSECURE_TARGET: http is allowed only for loopback targets unless the development allowance is set`.
The `iris` image was built 2026-09-25, before `iris.script` gained
`set ^sentai("config","allowInsecureTargets")=1` (commit `6d8a992`, 2026-09-27); the IRIS journal
(all 9 files, the container's whole life) shows that node written only by spec 008's
`TargetServiceTest` (SET then restore-KILL at 16:14:37 UTC). Not a regression: the T001 baseline on
`master`'s build failed at the same assertion. The user set the allowance on the dev instance by
hand (`iris session iris -U IRISAPP`); rebuilding the `iris` image would make it permanent.

**One real conflict, test-only fix.** us15 "theming and secrets" rejected any JWT in browser storage;
it then found this tab's own kept refresh token (`sessionStorage["sentai.signin"]`), which spec 010
keeps by design (**FR-011**: only the credential needed to renew the sign-in). Spec 009 **SC-004**
forbids *target* passwords and tokens only. The check now asserts the target's real tokens (from the
page's own sign-in to the target) are absent everywhere, allows exactly one JWT —
`sentai.signin.refreshToken` — and keeps the password check. us15 also registers `iris-target`
itself (idempotent `beforeAll`), removing its dependence on us16 running first.

Results: us15 alone (target deleted first) 2/2; us16 alone 3/3; us15 again 2/2.

Full suite after T064 (with `iris-target` up and the allowance set): **64 passed, 1 skipped, 0 failed**
(8.6 min). The skipped test is the opt-in 905 s expiry test (passed on its own run). Spec 002/007/009
evidence files rewritten by the run were restored with `git checkout`.
