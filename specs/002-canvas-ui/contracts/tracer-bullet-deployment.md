# Tracer-bullet deployment contract

Plan slice: **Tracer Bullet** · Date: 2026-09-21

This is the interface this plan's slice exposes: the HTTP surface of the container once built
and started. It is not an addition to `openapi.yaml` (no REST endpoint is implemented this
phase) and it does not touch the screen contracts (`ui/UI-00*.md`) — the tracer bullet is not
required to pass their visual tests. It exists so `/speckit-tasks` has a concrete, checkable
target for this phase's one verifiable increment.

## What the container MUST do

| # | Requirement |
|---|---|
| 1 | `docker build .` succeeds using the multi-stage `Dockerfile`, with the Node build stage discarded from the final image. |
| 2 | The final image is built `FROM` the IRIS Community base image already pinned in `Dockerfile` (no second base image, no sidecar container). |
| 3 | `docker-compose up -d` starts the container and IRIS's private web server serves a page at `http://localhost:52773/<tracer-app-path>/` returning HTTP 200. |
| 4 | The served page's DOM contains exactly 3 elements matching Svelte Flow's node selector and exactly 1 element matching its edge selector, once the client-side bundle has hydrated. |
| 5 | The single edge renders with the `edge.sequence` token's stroke width (1.5px) and an arrowhead terminator — the sequence treatment from [UI-006](ui/UI-006-design-system.md), not the join treatment. |
| 6 | No network request in the browser's request log targets any IRIS management API (`/api/admin/*`) or the product's own API (`/csp/sentai/api/v1/*`) — the page is fully static, per this plan's exclusions. |

## What the container is NOT required to do (this phase)

- Serve any route other than the one tracer-bullet page.
- Respond to a drag, an edge draw, a click-to-inspect, or any interaction beyond Svelte Flow's
  built-in pan/zoom.
- Authenticate, refresh a token, or make any REST call.
- Persist, load, import, or export anything.
- Render the light theme or expose a theme switch.

## Evidence

- `tracer-build.log` — full output of `docker build .`, showing the multi-stage build
  succeeding and the final image's `FROM` line.
- `tracer-render.png` — a screenshot of the served page showing 3 nodes and 1 edge.
- `tracer-network.json` — the browser's request log for the page load, showing no call to
  `/api/admin/*` or `/csp/sentai/api/v1/*`.
