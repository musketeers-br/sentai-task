# Quickstart — Tracer Bullet validation

Feature: `002-canvas-ui` · Plan slice: **Tracer Bullet** · Date: 2026-09-21

Validates the one increment this plan slice delivers: a multi-stage Docker build that compiles
a SvelteKit + Svelte Flow app and serves it, as static assets, from a container built FROM the
IRIS Community base image, rendering 3 fixed nodes and 1 fixed edge. See
[`contracts/tracer-bullet-deployment.md`](contracts/tracer-bullet-deployment.md) for the full
contract this validates against.

## Prerequisites

- Docker and `docker-compose` installed.
- Repository root checked out; `frontend/` present with `package.json`,
  `svelte.config.js` (adapter: `@sveltejs/adapter-static`), and the tracer-bullet fixture from
  [`data-model.md`](data-model.md).
- `Dockerfile` updated with the Node builder stage ahead of the existing IRIS stage (see
  `research.md` R-001–R-004 for the decisions this build follows).

## Build

```
docker-compose build --no-cache
```

**Expected**: the build log shows a `node` stage running `npm ci && npm run build`, then the
final stage copying the resulting `frontend/build/` output into the IRIS image, with the base
`FROM` line unchanged from the current `Dockerfile`. Save this log as `tracer-build.log`
(evidence item 1 in the deployment contract).

## Run

```
docker-compose up -d
```

**Expected**: the `iris` service starts as it does today (ports 1972, 52773, 53773 published);
no new service is added to `docker-compose.yml`.

## Verify

1. Open `http://localhost:52773/<tracer-app-path>/` in a browser (or headless via Playwright).
   **Expected**: HTTP 200, page loads.
2. Inspect the rendered canvas.
   **Expected**: exactly 3 nodes, each with a title, an `#NN` id, and a left-border colour from
   `tokens.json`'s `category.*` tokens; exactly 1 edge, rendered as a sequence edge (1.5px,
   arrowhead) — not a join.
3. Open the browser's network log for the page load.
   **Expected**: no request to `/api/admin/*` or `/csp/sentai/api/v1/*`. The page is fully
   static.
4. Capture a screenshot of the rendered canvas as `tracer-render.png`, and the network log as
   `tracer-network.json` — evidence items 2 and 3 in the deployment contract.

## Teardown

```
docker-compose down
```

## What this quickstart does NOT cover

Composition, validation, scheduling, live run, WQM, and theming (spec 002's full scope,
Q1–Q10) are not exercised here — see `research.md` §Deferred to a later phase. This quickstart
proves the deployment pipeline only.
