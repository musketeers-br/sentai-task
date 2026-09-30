# Quickstart: validate the Canvas Instance Overview

**Needs**: spec 018 merged into this branch and loaded in the container (`zpm "load
/home/irisowner/dev"`), the stack up. Contract: [contracts/ui-contract.md](contracts/ui-contract.md).

```sh
cd frontend
npm ci
npm run check
npm test
bash scripts/publish-canvas.sh
npx playwright test tests/us29-overview.spec.ts
npx playwright test          # full e2e (SC-007), ~6 min
```

| # | Story / SC | Do | Expect |
|---|---|---|---|
| 1 | US1, SC-001 | open `http://127.0.0.1:52773/csp/sentai/index.html`, sign in as `_SYSTEM` | *Overview* shows 11 cards within 3 s, all `data-state="ok"` |
| 2 | US1, SC-003 | sign in as a temporary `SentaiDemo` account | *Security posture* refused with the platform's text; every card the API marked ok shows its headline |
| 3 | US2 | *Processes* → sort by *Commands*, filter a namespace | rows equal the API reading; "N rows / M shown" |
| 4 | US2, SC-006 | auto-refresh on, hide the tab 60 s | 0 reading requests while hidden |
| 5 | US3, SC-005 | *Web applications* → *Run report*; close; compare with a one-step run | same findings and order; card shows counts, time, *Open report* |
| 6 | US4, SC-004 | *Secrets* → *Schedule this check* → schedule a minute ahead | ≤ 4 actions; scheduled run produces the secrets report |
| 7 | SC-007 | `?flow=<id>`, `?run=<guid>`, `?view=catalog` | each opens what it names, never *Overview* |
| 8 | SC-008 | both themes | paired screenshots in `evidence/` |
