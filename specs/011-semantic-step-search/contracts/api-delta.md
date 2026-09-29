# API Contract Delta — 011 Semantic Step-Type Search

Base: `/csp/sentai/api/v1`, same authentication as today (the primary bearer token, validated on
every call, never cached). Errors use the existing Problem shape `{status, title, detail}`.
Decisions and their measurements: [research.md](../research.md). Shapes: [data-model.md](../data-model.md).

This is a **delta**. It adds one route and one field. Every existing route, including
`GET /catalog/step-types`, is unchanged.

---

## The provider configuration (not an endpoint)

The similarity service is chosen by a row in the platform's `%Embedding.Config` table, which names
`EmbeddingClass = sentai.search.EmbeddingService` — a class this feature adds, implementing the
platform's two-method `%Embedding.Interface` contract. The endpoint, model and optional key live in
that row's `Configuration` JSON, never in code (FR-011). There is no HTTP surface for reading or
writing this: it is platform configuration, documented in `README.md` (FR-012), and the product
exposes no way to change a provider at runtime (Constitution II).

Default dev-stack row:

```json
{
  "Name": "sentai-steps",
  "EmbeddingClass": "sentai.search.EmbeddingService",
  "Configuration": "{\"host\":\"ollama\",\"port\":11434,\"https\":0,\"path\":\"/v1/embeddings\",\"model\":\"all-minilm\"}",
  "VectorLength": 384
}
```

---

## `GET /catalog/step-types/search`

**Purpose**: rank the closed catalog against a sentence, and say so honestly when it cannot.

`q` (query, **required**) — the operator's text. Sent to the configured provider, never stored
(FR-010). A missing or blank `q` is a `400`: the palette never asks (FR-005).

### 200 — ranked

```json
{
  "available": true,
  "matches": [ { "type": "compact-globals", "score": 0.5294 },
               { "type": "storage-headroom-check", "score": 0.4967 } ]
}
```

- `matches` is **already filtered** to entries above the absolute floor of `0.20`, ordered by `score`
  descending, ties broken on catalog order. An empty array is a valid answer meaning "nothing in the
  catalog is close" (FR-008).
- Every `type` is a `type` from the closed catalog. The endpoint cannot introduce one, because it
  reads the catalog and nothing else (FR-013, Constitution II).
- `score` is cosine similarity. The frontend does not apply a floor, does not re-score, and does not
  invent an entry; it uses `type` to order entries it already holds (R-011).

### 200 — unavailable, and this is deliberate

```json
{ "available": false, "reason": "not-configured" }
```

`reason` ∈ `not-configured` · `unreachable` · `slow` · `incompatible` · `error`.

**This is a 200, not a 5xx** (R-007). The product's answer when search is unavailable is *today's
working palette*, so an error status would manufacture the error state the specification forbids
(SC-004). The reason is carried so it is diagnosable (FR-024) without ever becoming a message the
operator has to dismiss. An `unavailable` response never carries `matches`, and a partial ranking is
never returned (FR-025).

### 400

`{status, title, detail}` — `q` absent or blank. No provider call is made.

### Errors that are *not* specific to this route

`401` missing or invalid bearer token (unchanged, per request). A `5xx` here means a defect in the
search path, not a degraded provider — a degraded provider is always a 200.

---

## `GET /catalog/step-types` — one new field

Each entry gains **`description`**: the reviewed prose describing what the capability is for, held in
the entry itself and returned with it.

```json
{ "type": "compact-globals", "label": "Compact globals",
  "class": "%SYS.Task.CompactGlobals", "category": "storage",
  "description": "Reclaims unused space in the database by compacting globals",
  "executor": "platform-api", "destructive": false, "pausable": false, "available": false }
```

- **Every** entry has one; an entry without prose is rejected by the change process and by the catalog
  test (FR-014, FR-015, SC-009).
- It is never derived from the class name, or from anything outside the entry's own reviewed text
  (FR-014).
- This is the only text the corpus embeds. Nothing else in the entry is searchable.
- `wire.ts` does **not** gain a `description` field on `StepTypeInfo`, and the palette does not
  display it in this feature (R-011). The field rides along because it is part of the entry; the
  Dispatcher does not project it away, because that would put a projection in the class whose
  contract is routing and translation only.

---

## `sentai.registry.StepType` — the catalog

- A `description` field per entry, in the same XData block, following the pattern the existing
  **parameter** entries already use.
- `GetCatalog()` returns it. No new accessor is needed: the corpus builder reads the catalog's
  `type`, `label` and `description` and **never the `class` field of any entry**, so the legacy
  `custom` entry has nothing to leak (FR-018, R-009).
- The legacy `custom` entry gets a `description` like any other, and remains `available: false`. It
  can be suggested when an operator searches for a custom step, and it renders exactly as it does
  today when browsed — listed, un-addable (FR-021).

---

## Request handling, for the implementer

- **Route**: `<Route Url="/catalog/step-types/search" Method="GET" Call="SearchStepTypes"/>`, inside
  the existing `/catalog/` group. Verified that an exact path and a deeper path coexist without
  conflict in this URL map (R-010).
- **Method**: read `q` from `%request.Get("q")`, delegate to `sentai.search.StepSearchService`, and
  write the outcome it is given. No business logic, no provider call, no SQL in the Dispatcher.
- **Corpus currency happens inside the service**, before ranking: compute the catalog version, rebuild
  if it differs, then rank. The client never triggers a build and never knows one happened (FR-016,
  R-005).
- **Empty `q` never reaches the service** — the Dispatcher answers `400` first, so a service call is
  always a real question.
