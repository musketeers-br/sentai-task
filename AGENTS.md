<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
at specs/011-semantic-step-search/plan.md

Current feature: semantic step-type search over the closed catalog. The design decisions, with the
measurements behind them, are in `specs/011-semantic-step-search/research.md`; the shapes are in
`data-model.md` and `contracts/`. Three things a coding agent must not re-derive:

- `src/sentai` is **flat** — 26 classes, no nested package. New classes are `sentai.<domain>.<Class>`
  and new tests sit flat under `tests/sentai/unittest/<domain>/`.
- The step-type catalog (`src/sentai/registry/StepType.cls`) is the **only** place a capability is
  declared. Search reads its `type`, `label` and `description` through `GetCatalog()` and never a
  class name. New prose goes in the catalog's XData entry, reviewed in a pull request.
- An embedding provider is a row in the platform's `%Embedding.Config` naming
  `sentai.search.EmbeddingService`; the endpoint, model and key live in that row's `Configuration`
  JSON, never in code. The dev stack serves `all-minilm` on the `ollama` compose service.
<!-- SPECKIT END -->

# SentaiTask — notes for coding agents

ObjectScript app on IRIS 2026.2 that orchestrates platform maintenance tasks, plus a SvelteKit
canvas that IRIS itself serves at `/csp/sentai/`. **Two codebases, two verification loops.**
Product/API docs: `README.md`. Dev ops and the public tunnel: `dev.md`. `docs/limitations.md`
lists what v1 deliberately does not do.

## The environment is the compose stack

- `docker compose up -d` brings `iris` (primary, `127.0.0.1:52773`) and `iris-target` (compose
  network only — remote-step behaviour and its e2e tests need it up).
- `docker-compose.override.yml` applies automatically: it rebinds 1972/52773/53773 to loopback and
  mounts the repo **read-only** at `/home/irisowner/dev`. LAN access needs the base file spelled out:
  `docker compose -f docker-compose.yml up -d`.
- Dev credentials `_SYSTEM` / `SYS`. The module's globals live in `IRISAPP`.

## ObjectScript — editing the file is not enough

`src/` is bind-mounted, so the container compiles what you write, but only after a load:

```sh
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
zpm "load /home/irisowner/dev"
zpm "test sentai-task -only"
EOF
```

- Suite: 268 methods, ~15 s. Green ends with `All PASSED` / `268 total, 268 passed, 0 failed`.
  REST tests print raw JSON into the terminal — that noise is expected, not a failure.
- **There is no single-class run.** `##class(%UnitTest.Manager).RunTest("…")` dies with `ERROR #5007`
  (`^UnitTestRoot` points at a directory that does not exist) and `zpm "test"` accepts only the
  package. Run the whole suite; it is cheap.
- `iris_*` MCP tools omit the namespace → they answer for `USER`; the module is in `IRISAPP`, so
  pass `namespace: "IRISAPP"`. `iris_test` reports `NO_TESTS_FOUND` here — use `zpm "test"`.
- The `<CSPApplication> is deprecated` warning on every load comes from `module.xml`; known, harmless.
- Before editing `.cls`, follow the `objectscript-guardrails` / `objectscript-review` skills; never
  hand-edit a `Storage` block. A change is only saved when the **instance** has it (`zpm load` or
  `iris_doc mode=put`) — `iris_compile` alone never sees your local file.
- `module.xml`'s `<Version>` is bumped by CI on push to master. Don't hand-edit it.

## Frontend

```sh
cd frontend
npm ci                          # node_modules is gitignored; absent in a fresh clone
npm run check                   # svelte-check — the typecheck
npm test                        # vitest, pure modules only (src/**/*.test.ts)
bash scripts/publish-canvas.sh  # build + docker cp into /opt/sentai-web of the running container
npx playwright test             # e2e: needs the stack up, ~6 min, real runs
```

- **e2e drives the container's baked bundle on :52773, not a dev server** — publish first, or
  redirect: `PLAYWRIGHT_BASE_URL=http://localhost:5173/csp/sentai/ APP_ENTRY=''` with `npm run dev`
  (Vite proxies `/api/admin` and `/csp/sentai/api` to the container).
- e2e creates and deletes IRIS users and flows through `docker exec` (override the container with
  `SENTAI_CONTAINER`) and writes evidence PNG/JSON into `specs/00*/evidence/`.
- `src/lib/design/tokens.{css,ts}` are **generated and gitignored** — edit
  `specs/002-canvas-ui/contracts/tokens.json`, then `npm run generate:tokens` (runs automatically
  on `predev`/`prebuild`).
- Layering the current plan holds to: components → `lib/<domain>/*.ts` (pure view models) →
  `lib/api/client.ts` / `wire.ts`. Components never call `fetch`; screen state is a tagged union
  (`list` | `refused` | `status` | `unreachable`), because errors are values.

## How work gets specified (spec-kit SDD)

- The process is normative: `.specify/memory/constitution.md` (six principles), then
  **spec → plan → tasks → implement** through `/speckit.specify`, `/speckit.plan`, `/speckit.tasks`,
  `/speckit.implement` (plus `/speckit.analyze`, `.checklist`, `.clarify`, `.constitution`,
  `.agent-context.update`, `.taskstoissues`).
- Current feature: `.specify/feature.json` → `specs/<NNN>-<slug>/` holding `spec.md`, `plan.md`,
  `tasks.md`, `checklists/`, `evidence/`. One numbered directory per feature, branch per feature.
- The block at the top of this file is machine-managed: the `agent-context` extension's
  `after_specify`/`after_plan` hook rewrites everything between the SPECKIT markers. Keep your notes
  outside them.
- Tasks are sliced by user-observable behaviour with the test written first (Principle V), never by
  technical layer. Each feature's `evidence/` gets a README table; no credentials in it.

## Constitution rules that change what you may write

- **II — closed capability set**: no code, method or class name ever comes from input. Step types
  resolve through the catalog in `sentai.registry.StepType` (`XData Catalog`); a legacy `custom`
  step's `customClass` is never read on any execution path. New capability = a compiled class plus
  one catalog entry, reviewed in a pull request.
- **III — delegated authorization**: call the platform with the operator's own credential and pass
  its refusal through verbatim (HTTP status + `status` object). Never reinterpret, never cache a
  permission outcome.
- **IV — errors as values**: predictable failures cross layers as tagged results; exceptions stay at
  the infrastructure edge and are never control flow across the core; a partially failed run is
  never reported as success.
- One gate: `sentai.validation.FlowValidator` is shared by validate, dispatch and schedule, so a
  flow that fails `/validate` can never run.
