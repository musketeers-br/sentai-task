# Quickstart — 022 Runbook Gallery (acceptance)

Runs against the compose stack (`sentai-task-iris-1`, `http://localhost:52773/csp/sentai/`).
Evidence goes to `specs/022-runbook-gallery/evidence/`; no credential ever goes into an evidence
file. Behaviour: [spec.md](spec.md); design: [plan.md](plan.md); entities:
[data-model.md](data-model.md); the UI surface the tests enforce:
[contracts/runbook-gallery.md](contracts/runbook-gallery.md). No API changes.

## Prerequisites

```bash
docker compose up -d          # iris-target included; the cross-server card needs it registered
cd frontend && npm ci && npm test && npm run check && npm run build
bash scripts/publish-canvas.sh
```

## Automated validation

```bash
cd frontend
npx playwright test tests/us31*          # the gallery: SC-001…SC-003
npx playwright test                     # full suite — us21/us30 adapted, us20 retired (SC-004)
```

```sh
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
zpm "load /home/irisowner/dev"
zpm "test sentai-task -only"            # includes the new DemoTest fixture comparison
EOF
```

Expected: all suites green (`All PASSED`, `269 total` after the one new method), zero failures in
the full e2e beyond the pre-existing shared-stack set.

## Manual script (the SCs a human must see)

**SC-001 — the gallery is the empty canvas (≈2 min).** Sign in fresh → Overview → **Flows**, no
flow open: the gallery is there immediately — seven cards, each with its name, purpose, mini-graph
and **Use**; *Start from scratch* visible. Time it: gallery visible within ~5 s of the click into
Flows. On the demo (which has saved flows) the gallery still shows — that is the point.

**SC-002 — click to a running flow (≈3 min).** On *Weekly maintenance window*, press **Use**: the
flow opens on the canvas, its graph matching the card's mini-graph. *Validate flow* → 0 errors;
*Run now* → steps complete (journal switch and purge are real, on this dev instance). Press **Use**
on the same card again: the same flow opens — no duplicate.

**Honesty checks (FR-005/FR-007).** A card that includes *Switch journal* / *Purge task history*
marks those steps as destructive on the card. With `iris-target` down, *Cross-server nightly*'s
Use is disabled and its reason is shown; nothing looks clickable-into-a-dead-end.

**Guard (FR-008).** Drag a step onto the canvas (dirty), then press **Use** on any card: the
Save / Discard / Cancel guard appears first, exactly as for *New flow*.

**Entry points (FR-013).** From *Help → Getting started*, step 2's **Browse runbooks** lands on
the gallery; same from *Open flow…*. No path offers a lone example anymore.

**Tour coexistence (FR-015).** With the gallery on screen, press **Tour**: all three marks anchor
exactly as before; the gallery sits beneath and remains after *Done*.

**SC-004 — regression sweep.** Fresh profile: the *Getting started* dialog still auto-opens once;
theming flips cleanly over the gallery; keyboard-only (Tab + Enter) reaches every card's Use and
*Start from scratch*.

**SC-005 — the 3-of-3 spot-check (people, ~15 min).** Three colleagues who have never used
SentaiTask, the public demo address, no instructions: "find a runbook and run it". Count hands-off
completions — 3 of 3 is the bar (record only counts/notes in evidence, no personal data).
