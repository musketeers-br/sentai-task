# Quickstart — acceptance walkthrough

Feature: `011-semantic-step-search` · Date: 2026-09-27

Run this against the dev stack. It is the four stories from [spec.md](spec.md) turned into a sequence
you can perform, and it is what "done" means for this feature. Every step names the requirement it
proves. Commands assume the repo root.

---

## Prerequisites

```bash
docker compose up -d                 # iris + the ollama embedding service, model pulled
docker compose ps                     # both healthy
```

- A row in `%Embedding.Config` naming `sentai.search.EmbeddingService` — on the dev stack the
  build installs it (`iris-provider.script`), so there is nothing to do; for installs outside the compose
  stack, see [Provider setup](#provider-setup) below, and `README.md` (### IPM) for the
  alternatives, including the sidecar-free `%Embedding.SentenceTransformers` row.
- The canvas published to the container (`bash scripts/publish-canvas.sh` from the repository
  root — or none at all: the image bakes its own build) or a dev server on `:5173` with the API
  proxied.

```bash
TOKEN=$(curl -s -X POST -u _SYSTEM:SYS http://localhost:52773/api/admin/login | jq -r .access_token)
API=http://localhost:52773/csp/sentai/api/v1
AUTH="Authorization: Bearer $TOKEN"
```

### Provider setup

One row in `%Embedding.Config`, in `IRISAPP`. The feature ships with the dev value in
[api-delta.md](contracts/api-delta.md); this is the command that installs it:

```sql
INSERT INTO %EMBEDDING.Config (Name, EmbeddingClass, Configuration, VectorLength, Description)
VALUES ('sentai-steps', 'sentai.search.EmbeddingService',
        '{"host":"ollama","port":11434,"https":0,"path":"/v1/embeddings","model":"all-minilm"}',
        384, 'Step-type search, local Ollama');
```

From an `iris session` in `IRISAPP`:

```bash
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
set cfg = ##class(%DynamicObject).%New()
do cfg.%Set("host","ollama"), cfg.%Set("port",11434), cfg.%Set("https",0), cfg.%Set("path","/v1/embeddings"), cfg.%Set("model","all-minilm")
set rs = ##class(%SQL.Statement).%ExecDirect(, "INSERT INTO %Embedding.Config (Name, EmbeddingClass, Configuration, VectorLength, Description) VALUES (?, ?, ?, ?, ?)", "sentai-steps", "sentai.search.EmbeddingService", cfg.%ToJSON(), 384, "Step-type search, local Ollama")
write "install SQLCODE=",rs.%SQLCODE," ",rs.%Message,!
halt
EOF
```

(The `INSERT` is written as bound ObjectScript SQL because the terminal session does not accept
bare SQL statements — `INSERT ...` at the `IRISAPP>` prompt is a `<SYNTAX>` error.)

`VectorLength` **must** be in the `INSERT`: the column is `SqlComputed`, and its compute method
rejects an empty value for any class that is not `%Embedding.SentenceTransformers`. The `INSERT` is
also validated by the table's own trigger, which requires the named class to exist, to extend
`%Embedding.Interface`, and to accept the JSON through its `IsValidConfig` — so a bad row fails here,
with the platform's own message, rather than at the operator's first keystroke (R-002, R-013).

To remove it:

```sql
DELETE FROM %EMBEDDING.Config WHERE Name = 'sentai-steps'
```

---

## Story 1 — search by intent · *FR-001–FR-004, all 8 acceptance scenarios*

1. Open `/flows/new`. Type **`rotate the journal`** in the palette's search box.

✅ A **SUGGESTED** group appears above the category groups with `Switch journal` in it *(FR-001)*.
✅ Within ~1 s of the last keystroke — measured warm latency is ~100 ms end to end *(SC-003)*.
✅ `Switch journal` appears **once**: in SUGGESTED, not again under JOURNAL *(FR-003)*.

2. Type **`get rid of old audit records`**.

✅ SUGGESTED offers `Purge audit records` — the entry was found by intent, with none of those words in
its label, type or description *(FR-001, story 1 scenario 3)*.

3. Type **`free up disk space`**.

✅ SUGGESTED offers `Compact globals`. The same query also matches `Defragment`, so **SUGGESTED is
ranked**, not merely non-empty *(FR-002)*.

4. Drag `Compact globals` from SUGGESTED onto the canvas.

✅ A storage step node appears. Adding is still an explicit action — the palette never builds a flow
by itself *(FR-004)*.

5. Confirm the API side, which is what the palette is reading:

```bash
curl -s -H "$AUTH" --get --data-urlencode 'q=check my globals are sound' "$API/catalog/step-types/search"
# {"available":true,"matches":[{"type":"integrity-check","score":0.5006}, …]}
```

✅ `available: true` and the top match is `integrity-check`.
✅ Scores are **descending** and every `type` is one from `GET /catalog/step-types`.
✅ Ties break on catalog order, so the palette does not reshuffle between identical rankings *(FR-002)*.

6. Type an unrelated sentence:

```bash
curl -s -H "$AUTH" --get --data-urlencode 'q=order me a pizza' "$API/catalog/step-types/search"
# {"available":true,"matches":[]}
```

✅ `matches` is **empty** — not a wrong entry. Below the 0.20 floor there is no suggestion at all
*(FR-008)*. The palette shows no SUGGESTED group and today's list is untouched.

---

## Story 2 — unavailable degrades to today · *FR-022–FR-026, all 6 acceptance scenarios*

7. Type `free up disk space` again and confirm SUGGESTED appears. Now stop the provider:

```bash
docker compose stop ollama
```

8. Clear the box and retype `free up disk space`.

✅ The palette renders **exactly as it does today** — the local filter's results, in their category
groups, with no SUGGESTED group *(FR-023, SC-004)*.
✅ **No error, no toast, no empty state.** Nothing asks the operator to dismiss anything.

9. Check why:

```bash
curl -s -H "$AUTH" --get --data-urlencode 'q=free up disk space' "$API/catalog/step-types/search"
# {"available":false,"reason":"unreachable"}
```

✅ The response is **`200`**, not a 5xx, and carries a reason *(FR-024, R-007)*.
✅ `matches` is **absent** — a partial ranking never escapes *(FR-025)*.
✅ Typing keeps working throughout, because typing never waited on the provider in the first place.

10. Exercise the other reasons, one at a time:

| Setup | `reason` |
|---|---|
| rename the config row's `EmbeddingClass` to a class that is not a provider | `not-configured` |
| `docker compose stop ollama`, then let the request time out | `slow` |
| point the row at a model with a different vector width | `incompatible` |

✅ Each is a `200` with that reason; in every case the palette is indistinguishable from today's
*(FR-022, FR-023, FR-024, FR-026)*.

11. Delete the row entirely and repeat.

```bash
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
set rs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM %Embedding.Config WHERE Name = ?", "sentai-steps")
write "delete SQLCODE=",rs.%SQLCODE," ",rs.%Message,!
halt
EOF
```

✅ `{"available":false,"reason":"not-configured"}` and the palette is still today's palette.
✅ **The application still loads and the whole test suite still passes with no provider configured** —
this is the state CI runs in, and the reason the corpus column is lengthless *(R-001)*.

12. Restore the row from [Provider setup](#provider-setup) and `docker compose start ollama`.

---

## Story 3 — only the closed catalog · *FR-013, FR-018, FR-020, FR-021, all 5 acceptance scenarios*

13. Ask for something the catalog cannot do, in words that name no entry:

```bash
curl -s -H "$AUTH" --get --data-urlencode 'q=send an email to my manager' "$API/catalog/step-types/search"
```

✅ Either a ranked set of existing types or an empty set — **never an entry that is not in the
catalog** *(FR-013)*.

14. Prove the endpoint cannot invent one. An identifier with no catalog entry is dropped by the view
model, so SUGGESTED does not appear:

```
matches: [{"type":"send-email","score":0.97}]   # not a catalog type
```

✅ The palette shows no SUGGESTED group. The view model can only reorder or drop entries it was
handed; it has no way to create one *(R-011)*.

15. Compare against the catalog itself — every suggested type appears in it:

```bash
curl -s -H "$AUTH" "$API/catalog/step-types" | jq -r '.[].type' | sort
```

✅ Each of them is in that list. The corpus is built **from** the catalog's `type`, `label` and
`description` and **never from a class name** *(FR-018)*.

16. Type `custom` in the palette.

✅ `Custom` is offered, carries its reviewed description in the entry, and renders **un-addable**:
listed, `disabled`, not draggable — exactly as when browsing *(FR-021)*.

17. Check the catalog's new field:

```bash
curl -s -H "$AUTH" "$API/catalog/step-types" | jq -r '.[] | "\(.type)\t\(.description)"'
```

✅ **Every** entry has a non-empty description, each one hand-written in the catalog, none derived
from a class name *(FR-014, SC-009)*.

---

## Story 4 — the entry alone is enough · *FR-015–FR-017, all 4 acceptance scenarios*

18. Add a new entry to `StepType.cls`'s catalog with a description that says what the capability is
for, then load and test:

```bash
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
zpm "load /home/irisowner/dev"
quit
EOF
```

19. Ask for it **by its description, using none of its label words**:

```bash
curl -s -H "$AUTH" --get --data-urlencode 'q=see which backups are due' "$API/catalog/step-types/search"
```

✅ It ranks. No manual step, no separate registration, no index build, no migration — the corpus
noticed the catalog changed and rebuilt itself *(FR-016, FR-017)*.

20. Confirm the rebuild is idempotent and the corpus matches the catalog exactly:

```bash
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS rows, COUNT(DISTINCT corpusVersion) AS versions FROM sentai_search.StepCorpus")
if rs.%Next() write "corpus rows=",rs.%Get("rows")," versions=",rs.%Get("versions"),!
halt
EOF
```

✅ Row count = catalog entry count; one `corpusVersion` across all rows.
✅ Re-running the same search does not change anything — the upsert is idempotent and needs no lock
*(R-005)*.

21. Remove the entry again and repeat step 20.

✅ Its corpus row is **gone** on the next search. The corpus is a cache of the catalog, never a
second record of capabilities *(FR-013)*.

---

## Regression gate · *FR-003, FR-005, FR-021*

22. With the provider running, and again with it stopped, for each of these queries check that the
palette's non-suggested list is byte-for-byte the same as before this feature:

`integrity` · `purge` · `journal` · `compact` · `custom` · `` (empty box)

✅ The local substring filter — including its `className` match — is unchanged, and the SUGGESTED
group is purely additive *(FR-003, FR-005)*.

23. The full gates:

```bash
docker exec -i sentai-task-iris-1 iris session iris -U IRISAPP <<'EOF'
zpm "test sentai-task -only"
EOF
# 268 total, 268 passed, 0 failed

cd frontend && npm run check && npm test
```

✅ Backend suite green, `svelte-check` clean, vitest green — including the new palette view-model
tests and the catalog's non-empty-description assertion.
