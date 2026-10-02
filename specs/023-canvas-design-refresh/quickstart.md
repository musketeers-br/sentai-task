# Quickstart: validating the Canvas Design Refresh

Prerequisites: the compose stack up (`docker compose up -d`), dev credentials `_SYSTEM` / `SYS`,
`frontend/node_modules` installed (`npm ci`), the branch based on `master` with specs 018 and 019
(both merged). Contracts: [contracts/api-delta.md](contracts/api-delta.md); shapes:
[data-model.md](data-model.md).

## 0. Load and test

```sh
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
zpm "load /home/irisowner/dev"
zpm "test sentai-task -only"
EOF
cd frontend && npm run check && npm test
bash scripts/publish-canvas.sh
```

Expected: `All PASSED`; svelte-check 0 errors; vitest green.

## 1. Catalog counts (API, US2)

```sh
TOKEN=$(curl -s -X POST -u _SYSTEM:SYS http://localhost:52773/api/admin/login | jq -r .access_token)
curl -s "http://localhost:52773/csp/sentai/api/v1/catalog/tasks?filter=suspended" \
  -H "Authorization: Bearer $TOKEN" | jq '{total, matched, counts}'
curl -s "http://localhost:52773/csp/sentai/api/v1/catalog/tasks?unclassifiedOnly=1" \
  -H "Authorization: Bearer $TOKEN" | jq '.matched, ([.items[].destructiveUnknown] | all)'
curl -s -o /dev/null -w '%{http_code}\n' \
  "http://localhost:52773/csp/sentai/api/v1/catalog/tasks?unclassifiedOnly=maybe" -H "Authorization: Bearer $TOKEN"
```

Expected on the dev instance: `total 16, matched 2, counts {2, 2, 12}` — counts unchanged by the
filter; `12` and `true`; `400`.

## 2. Flow editor (US1) — http://localhost:52773/csp/sentai/?view=flows

1. Global bar: mark, Overview/Flows/Task catalog/Targets/Runs, Dark/Light, Help ▾, user, Sign out.
   Same bar on every tab.
2. Flow bar under it: name, "unsaved", Open…, Save, Validate, Run now, Schedule, ⋯ (New flow,
   Save as…, Run history). "add a step to enable running" visible next to the disabled buttons.
3. Empty canvas: explanation, sequence/join legend, "Start from a template", "Import from the task
   catalog". Inspector: flow name, WQM category, "Nothing selected…".
4. Drag two steps and a join: status bar "2 steps · 1 join · 0 destructive · snap 8 px · zoom 100%".
5. Palette: per-category counts, "Show N more", "N types not supported in v1 · Show" at the end;
   typing "purge" finds a collapsed entry.

## 3. Catalog (US2) — `?view=catalog`

1. Header "16 of 16 tasks · updated N s ago"; Suspended 2, Destructive 2, "12 unclassified".
2. "12 unclassified" lists 12 rows; footer "sorted by next run · 2 destructive · 2 suspended · 12 unclassified".
3. *Purge Tasks*: DESTRUCTIVE, the consequence text, "classified from the step-type registry · not
   editable here", "created outside SentaiTask".
4. A never-run task: "No run recorded. This task has never executed on this instance."
5. *Integrity Check* → Add to a flow → Flows opens with an Integrity check step, flow "unsaved".
   A task whose class is not declared (e.g. *Inventory Scan*): Add to a flow disabled, reason shown.
6. Suspend toggle on a task the test created → confirmation → confirm → SUSPENDED and Suspended 3;
   toggle back → resumed. Cancel sends nothing. As an operator without `%Admin_Task:USE`: the
   platform's refusal shown verbatim, toggle unchanged.

## 4. Overview attention (US3) — `/csp/sentai/`

1. Signing in on the bare address lands on Overview (spec 019, unchanged).
2. Above 019's cards: Needs attention — backup (if never backed up, with last backup and uptime),
   "2 scheduled tasks are suspended" → Show in catalog opens the suspended filter; "12 of 16 tasks
   have no destructiveness classification" → Show them opens the unclassified filter.
3. Next 24 hours: slots with counts, destructive marked, "2 suspended", next time after the strip.
4. Unread summary: with `/catalog/tasks` route-mocked to 403 it names the task catalog with the
   platform's status and message, Next 24 hours says it could not be read, and the 11 cards render;
   with one `/overview` area mocked `refused` it names that area. Hidden when everything was read.
5. 019's cards, Open and Run report behave as `us29-overview.spec.ts` verifies — that spec passes
   unchanged.

## 5. e2e and evidence

```sh
cd frontend && npx playwright test tests/us30-flow-chrome.spec.ts tests/us31-catalog-attention.spec.ts tests/us32-overview-attention.spec.ts tests/us29-overview.spec.ts
npx playwright test     # full suite, ~6 min
```

Each new spec runs the axe check (serious/critical = 0) in dark and light and writes PNG/JSON into
`specs/023-canvas-design-refresh/evidence/`, listed in its README next to the design board each
screenshot follows.

## 6. Spec status

```sh
bash scripts/check-spec-status.sh
```
