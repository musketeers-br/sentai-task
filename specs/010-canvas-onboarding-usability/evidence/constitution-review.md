# Constitution review — 010 Canvas Onboarding and Flow Management Usability (T063)

Reviewed on 2026-09-27 against `.specify/memory/constitution.md` v1.0.0 and plan.md's Constitution
Check, over the uncommitted working tree (nothing is committed on this project's behalf).

| Principle | Verdict | Evidence |
|---|---|---|
| **I Layered Architecture** | ✅ | Components → state classes (`lib/flow/editor.svelte.ts`, `lib/guide/guide.svelte.ts`, `lib/api/session.svelte.ts`) → pure modules (`lib/flows/list.ts`, `guard.ts`, `example.ts`, `lib/guide/preference.ts`, `lib/api/kept-sign-in.ts`). `grep -rnE "fetch\(\|sessionStorage\|localStorage" --include='*.svelte' src/lib src/routes` prints nothing: no component performs HTTP or touches storage. Storage is injected into the pure modules and wired only in the `session` and `guide` singletons. |
| **II Closed Capability Set** | ✅ | No new operation: `git diff --stat master -- src/ specs/002-canvas-ui/contracts/openapi.yaml` is empty. The example flow is typed data (`lib/flows/example.ts`) made only of registry-declared types, created through the existing `POST /flows` and validated server-side like any flow. Nothing typed by the operator is evaluated. |
| **III Delegated Authorization** | ✅ | The kept sign-in is one refresh token plus a `live` flag; `kept-sign-in.test.ts` pins the key set to `live, refreshToken, v`, and `us19` "storage audit" asserts no password, access token, user, role or permission in any storage (`evidence/us19-storage-keys.json`). Redeeming grants nothing — every request is still judged by the platform. The example is created with the operator's own credential; a refused list shows no invitation rather than guessing. Refusals are verbatim: `us17` (409 name clash, 409 revision), `us18` (403 list, 404 address), `us20` (`openExample` returns the platform's error). The conflict hint is a separate line, never a rewrite. |
| **IV Errors as Values** | ✅ | `editor.saveAs` → `ApiResult<FlowDocument>`; `openExample` → `ApiResult<string>`; `api.listFlows` → `ApiResult<FlowSummaryView[]>`; `OpenFlowDialog` state is a tagged union (`loading / list / empty / refused`); the guard's failed save is `afterSave(false) → stay`. Storage exceptions are caught at the storage edge (`kept-sign-in.ts`, `preference.ts`) and become `none` / not dismissed. `session.restore()` turns every redeem failure into the "session ended" state, never a thrown error. |
| **V Verifiable Increments** | ✅ | Five observable increments, each with a failing e2e first (`us17`…`us21`) plus unit tests on its pure modules. The unsaved-changes guard was built inside US1 with `us17` scenario 4 as its failing test (analysis finding C1). Every unit test file and e2e spec was run and seen failing for the missing behaviour before the code (recorded in this session's runs); no commits exist to link. |
| **VI Technology Agnosticism** | ✅ | spec.md and the constitution name no technology; technology appears only in plan.md / research.md. |

## Engineering Standards

- **SOLID / SoC**: one reason to change per module (listing, guarding, example data, token keeping,
  guide preference, guide state). Two small shared UI primitives were introduced because each has
  several users: `lib/shell/Modal.svelte` (4 dialogs: modal shell, focus wrap, focus return) and
  `lib/shell/MenuButton.svelte` (*More ▾*, *Help ▾*), plus `lib/design/dialog.css` (the 4 dialogs'
  shared look, tokens only).
- **TDD**: see V.
- **YAGNI**: no new endpoint, no server-side filter or paging, no windowed list (5,000 rows render in
  34 ms), no cross-tab session sharing, no i18n layer. The *More ▾* menu exists because the 1440 px
  fit check required it (`evidence/README.md`).
- **Reproducibility**: no new toolchain or dependency (`package.json` unchanged); the quickstart uses
  the existing `docker-compose up`, `npm ci`, `npm run build`, `scripts/publish-canvas.sh`.

## Deviations recorded

- **Top bar layout** (plan D-7): the plan's fallback alone did not fit 1440 px; in addition the
  `%SYS` chip and the revision line were stacked under the flow name and the bar's gap reduced.
  *Open flow…* stays one click (SC-002). Recorded in `evidence/README.md`.
- **us18 refused list** is exercised with a routed 403 (the shared stack cannot deny the list on
  demand); the assertion is that the platform's words reach the dialog unchanged.
- **Example layout**: the first positions (0,0)/(320,0) put step 01 under the canvas's edge legend;
  moved to (40,160)/(360,160) — found by `us20`.
