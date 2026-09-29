# Data Model — Semantic Step-Type Search over the Closed Catalog

**Feature**: `specs/011-semantic-step-search` · **Plan**: [plan.md](plan.md) · **Research**:
[research.md](research.md)

Five things are described here. Only the first is stored by this feature. The corpus is derived from
the closed catalog and never becomes a second record of capabilities; the provider configuration
belongs to the platform's own table; everything else is a value that crosses the layers.

---

## 1. `sentai_search.StepCorpus` — the stored corpus (persistent, 9 rows)

One row per catalog entry. This is a **cache of the catalog's reviewed prose**, not a list of
capabilities: every row is produced from `sentai.registry.StepType.GetCatalog()`, and the catalog
remains the only place a capability is declared (FR-013, FR-016, Constitution II).

| Field | Type | Rules |
|---|---|---|
| `type` | `%String(100)` | **IdKey.** Copied from the catalog entry's `type`. Never invented; a value not in the catalog is never written. |
| `description` | `%String(MAXLEN)` | The entry's reviewed prose, copied verbatim from the catalog's `description`. **Required, non-empty** — an entry with empty prose cannot reach the corpus (FR-014, FR-015). |
| `vector` | `%Library.Vector` | The embedded `description`. Declared with **no length**: `VECTOR_COSINE` rejects a lengthless column, and `TO_VECTOR(vector)` in the query satisfies it (R-001). This is deliberate — see [Storage notes](#storage-notes). |
| `corpusVersion` | `%String(64)` | The catalog version this row was built from (§2). |
| `embeddedAt` | `%TimeStamp` | When the row was last embedded. Diagnostic only; never used to decide currency. |

**Index**: the id key only. A corpus of 9 rows is an exact scan; an index here would be a lie about
the workload (R-006, FR-027).

**Storage notes.** No hand-written `Storage` block beyond the default the compiler generates, and
per the repo guardrails, no hand-editing of it. The `%Library.Embedding` type was rejected: it
resolves its length through a named row in the platform's configuration table, which a persistent
class cannot name, and the resulting compile-order cycle is documented in R-001a. The
`%Library.Vector` form compiles with no external row present, so the class loads in any environment
— including one with no provider configured at all, which is the state the feature must survive.

### Storage

| Global | Contents |
|---|---|
| `^sentai.search.StepCorpusD` | the rows (id and data) |
| `^sentai.search.StepCorpusI` | the id index |

---

## 2. Catalog version — computed, never stored on its own

**Definition.** A hash over the catalog's `(type, description)` pairs, in the catalog's own order:
each pair is rendered as `type` + a separator + `description`, the pieces are concatenated, and the
result is hashed. Label, category, executor, availability and destructiveness are **excluded** — none
of them affect what an entry is *for*, so rewording a label must not invalidate the corpus.

**Why it exists.** FR-017 requires a catalog change to be reflected with no manual step. Comparing
this hash against the rows' `corpusVersion` is what makes that true without a build step (R-005).

**Why it is cheap.** The catalog is read from compiled XData, so it can only change when the
application is loaded. A rebuild is 9 embed calls, once, after a deploy that changed the catalog.

**Currency rule.** A search computes the current version; if any row's `corpusVersion` differs, or
the row count differs from the catalog's entry count, the corpus is rebuilt before ranking. The
rebuild is an idempotent upsert per entry plus a delete of types no longer in the catalog, so two
concurrent rebuilds converge on the same state and no lock is required (R-005, YAGNI).

---

## 3. `sentai.search.SearchOutcome` — the value that crosses every layer (not stored)

The single typed result of a search. This is Constitution IV made concrete: the search service
returns one of these, the Dispatcher writes it, `client.ts` maps it, and the palette renders it. There
is no path on which a failure is reported as a ranking.

```
SearchOutcome
├── matches      { matches: [CorpusMatch] }
└── unavailable  { reason: UnavailableReason }
```

| `UnavailableReason` | Meaning | Operator-visible effect |
|---|---|---|
| `not-configured` | no provider row is configured on this deployment | palette behaves exactly as today |
| `unreachable` | the provider did not answer (refused, DNS, reset) | as above |
| `slow` | the provider exceeded the request's timeout (R-013) | as above |
| `incompatible` | the provider answered with a different vector width than the stored corpus | as above |
| `error` | anything else, with the detail carried alongside for diagnosis | as above |

**Invariant.** `unavailable` carries **no matches**. A partially ranked set is never returned, and no
match is ever ranked against a vector it could not be compared with (FR-025).

**Transport.** Every variant is HTTP `200` (R-007). `unavailable` is not an error status because the
product's answer when search is unavailable is *today's working palette*; an error status would
manufacture the error state SC-004 forbids. The reason is still carried in the response so it is
diagnosable (FR-024) without being shown to the operator.

---

## 4. `CorpusMatch` — one ranked entry (not stored)

| Field | Type | Rules |
|---|---|---|
| `type` | `%String(100)` | A catalog entry's `type`. The **only** thing the palette uses it for. |
| `score` | `%Double` | Cosine similarity, `0.20`–`1.0`. Present for the frontend's benefit and for tests; **the floor has already been applied by the time a match exists**. |

**Ordering.** Descending by `score`. Ties break on catalog order, so the palette does not reshuffle
between two keystrokes that produce the same ranking (FR-002).

**Validation.** A `CorpusMatch` exists only if the row it came from is a catalog entry that was
present when the corpus was built. A score below **0.20** never becomes a `CorpusMatch` (FR-008);
below the floor the outcome is `matches` with an empty list, which the palette renders as today's
behaviour.

**The floor is absolute, not relative** — measured, with the reasoning and the rejected alternative,
in R-008. For "order me a pizza" the best match in the whole corpus scores 0.053, and it is the
unavailable legacy `custom` entry.

---

## 5. Provider configuration — a row in the platform's own `%Embedding.Config`

Not ours to design; the platform's table, with a validating trigger that checks the named class
extends `%Embedding.Interface` and passes its own `IsValidConfig` (R-002). The feature adds one class
that can be named there.

| Column | Value in the default configuration |
|---|---|
| `Name` | the name the search passes to `EMBEDDING()`; the feature reads it from its own configuration, not hardcoded per row |
| `EmbeddingClass` | `sentai.search.EmbeddingService` — the class this feature adds |
| `Configuration` | `{"host":"ollama","port":11434,"https":0,"path":"/v1/embeddings","model":"all-minilm"}` |
| `VectorLength` | `384` — informational for this class; the column carries no length (R-001). **It must be supplied in the `INSERT`**: it is `SqlComputed`, and its compute method throws on an empty value for any class other than `%Embedding.SentenceTransformers`. The table is `%EMBEDDING.Config`, and the row is created with a plain `INSERT` — this class has no `%Create`. |

**What the configuration may carry.** `host`, `port`, `https`, `path`, `model`, and an optional
`apiKey` sent as a bearer token. Nothing else is read. `IsValidConfig` rejects a row missing `host`,
`model` or `path`, so a malformed row fails at insert time with the platform's own message rather than
at the first keystroke.

**Swapping providers is a row, not a code change** (FR-012): point `EmbeddingClass` at
`%Embedding.SentenceTransformers` or `%Embedding.OpenAI` and adjust `Configuration`. The search code
does not change. Note the trade-off a hosted service brings, which the documentation must state
(FR-010): the operator's query text then leaves the machine.

---

## 6. Frontend view model — `PaletteSearchResult` (not stored)

The product of `frontend/src/lib/palette/search.ts`, and the structural place where Constitution II
holds: it receives ranked **identifiers** and maps them onto entries `registry` already holds.

```
PaletteSearchResult
├── suggestions  { suggestions: StepTypeInfo[] }   // leading group, best first
└── none         { }                                 // render today's palette unchanged
```

**Invariants.**

- Every element of `suggestions` is an element of the `registry` array that was passed in. An
  identifier with no matching entry is **dropped**, not rendered — so the view model is not
  structurally able to introduce a capability (R-011).
- `none` is returned for an empty query, for a below-floor result, for an `unavailable` outcome, and
  for any ranking the model cannot make sense of. The palette then renders exactly today's list
  (FR-005, FR-008, FR-023).
- Unavailable entries keep `available: false` and stay un-addable wherever they appear (FR-021); the
  view model does not change availability, it only orders.
- The remainder of the palette comes from the existing `paletteGroups()`, unchanged (FR-003), with
  suggested entries omitted from it so no entry is listed twice.

---

## What is never stored

- **The operator's query text.** Sent to the configured provider and discarded; never written to the
  corpus, never logged as a searchable record of operator intent (FR-010).
- **A second list of capabilities.** The corpus is derived from the catalog and carries no capability
  the catalog does not (FR-013). Removing a catalog entry removes its corpus row on the next rebuild.
- **A permission outcome.** Nothing here authorises anything, and nothing here is a cache of a
  platform's answer to anything (Constitution III).
- **An approximate-nearest-neighbour index.** Deliberately absent at 9 rows; the row count that would
  justify one is 10,000, recorded in R-006.
