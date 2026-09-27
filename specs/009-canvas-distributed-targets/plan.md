# Implementation Plan: Canvas Screens for Distributed Targets (frontend)

**Branch**: `009-canvas-distributed-targets` | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

**Input**: spec.md (Q1 = A: existing visual system, screenshots as review). Frontend only, over the
spec 008 API ([contract](../008-distributed-targets/contracts/api-delta.md)); no backend change.

## Summary

A *Targets* screen (third top-bar tab, `?view=targets`) lists, edits and switches targets, and
reads a target's live state after an in-memory sign-in. The inspector gains *Run on* for
remote-capable types; a node on a target shows a badge; the dispatch dialog asks one password per
target the flow uses and sends `targetCredentials`; the live run shows `executedOn`. Target findings
already arrive as ordinary findings and are shown by the existing node/status-bar code.

## Technical Context

**Language/Version**: TypeScript 5.9, Svelte 5 (runes), SvelteKit 2 (static, one prerendered page)
— as spec 007.
**Primary Dependencies**: none new.
**Storage**: none. Target sign-ins live in component state and are dropped after use or expiry.
**Testing**: vitest (pure modules), Playwright against the compose stack with `iris-target`.
**Constraints**: no backend change; no credential in storage/cookies/URL; the API decides every
rule; the spec 002 theming test's inspector section list stays unchanged (so *Run on* is a field in
IDENTIFICATION, not a new section).
**Scale/Scope**: 1 new pure module, 1 new screen, 6 touched files; unit 73 → ~85; e2e 22 → 25.

## Constitution Check

| Principle | Compliance | Status |
|---|---|---|
| I Layered | Components → `lib/targets/targets.ts` (pure view models) → `lib/api/client.ts`/`wire.ts` (only HTTP/wire) | ✅ |
| II Closed set | A target is only chosen from the API's list, for types the API marks `remoteCapable`; nothing is typed that names code | ✅ |
| III Delegated authz | Every target call is the operator's own sign-in; refusals verbatim; nothing about permission cached; passwords used once | ✅ |
| IV Errors as values | Every screen state a tagged union (`list`, `refused`, `signedOut`, `status`, `unreachable`); `ApiError` reused | ✅ |
| V Verifiable increments | One e2e per story group; unit tests on pure modules | ✅ |
| VI Tech agnostic | Technology only here | ✅ |

## Decisions

- **D-1 Navigation.** `Screen` gains `'targets'`; `TopBar` a third tab; `+page.svelte` mounts
  `TargetsScreen` (same pattern as the catalog, spec 007 D-1).
- **D-2 API client.** `listTargets`, `createTarget`, `updateTarget`, `deleteTarget`,
  `setTargetOnline`, `signInTarget(name, password)` (user = the signed-in operator),
  `targetStatus(name, accessToken)` (header `X-Sentai-Target-Authorization`).
- **D-3 View models** (`lib/targets/targets.ts`): `fromWireTarget`, `fromWireTargetStatus`
  (reachable / unreachable / refused), `targetsUsedBy(steps)` (distinct `target`s in step-id
  order), `targetChoices(targets, info)` (online targets, or none when `remoteCapable` is false).
- **D-4 Flow model.** `FlowStep.target?: string`; `wire.ts` maps `target` both ways (absent when
  local); `StepTypeInfo.remoteCapable`. `editor.targets` loaded at boot and after the Targets
  screen changes; `editor.setTarget(id, name | null)`.
- **D-5 Dispatch.** `DispatchDialog` shows one password per `targetsUsedBy(steps)`; `editor.dispatch`
  signs in to each target (`signInTarget`) after the run's own sign-in, and sends
  `targetCredentials`; any refusal stops before dispatch, verbatim.
- **D-6 Run view.** `StepRunView.executedOn`; `RunNode` shows it next to `executedAs`.
- **D-7 Targets screen.** Table (name, address, description, online) + side pane: edit form,
  online toggle, delete, sign-in field and status block. Tokens are held only in the pane's state
  and discarded after ~55 s (the server's 60 s); the password field is cleared after each call.

## Project Structure

```text
frontend/src/lib/
├── targets/targets.ts, targets.test.ts   # NEW pure view models
├── targets/TargetsScreen.svelte          # NEW
├── api/client.ts, api/wire.ts            # TOUCH
├── shell/screen.ts, shell/TopBar.svelte  # TOUCH (tab)
├── flow/document.ts, flow/editor.svelte.ts  # TOUCH (target, remoteCapable, dispatch)
├── inspector/Inspector.svelte            # TOUCH (Run on, in IDENTIFICATION)
├── canvas/StepNode.svelte                # TOUCH (badge)
├── shell/DispatchDialog.svelte           # TOUCH (target passwords)
└── run/run.ts, run/RunNode.svelte        # TOUCH (executedOn)
frontend/src/routes/+page.svelte          # TOUCH
frontend/tests/us15-targets.spec.ts       # NEW US1 + theming pair
frontend/tests/us16-remote-run.spec.ts    # NEW US2–US5
```

## Risks

| Risk | Mitigation |
|---|---|
| e2e depends on `iris-target` running | the compose stack is the declared environment; tests skip with a stated reason if `/targets/…/sign-in` cannot reach it |
| Target token expires between sign-in and status | status read right after sign-in; the pane asks to sign in again after ~55 s |
| Theming test for the inspector | *Run on* inside IDENTIFICATION keeps the section list unchanged |
