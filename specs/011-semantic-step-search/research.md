# Phase 0 Research — Semantic Step-Type Search over the Closed Catalog

**Feature**: `specs/011-semantic-step-search`
**Date**: 2026-09-27
**Instance**: IRIS 2026.2, namespace `IRISAPP`, confirmed live

Every decision below was verified against the running instance or the running dev stack before
being written down. Where a claim is a measurement rather than an assumption, the measurement is
reproduced so a reviewer can re-run it. Spike artefacts (`sentai.devprobe.*`, a
`%Embedding.Config` row named `devprobe`) were created for this research and **deleted afterwards**;
`INFORMATION_SCHEMA.TABLES` and `%Embedding.Config` were both re-queried to confirm zero residue.

---

## R-001 — Cosine similarity runs in SQL, over a class-projected side table, with the column
wrapped in `TO_VECTOR()`

**Decision.** The corpus is a dedicated persistent class with a native `VECTOR` column. The ranking
is a single SQL statement:

```sql
SELECT Type, VECTOR_COSINE(EMBEDDING(?, :configName), TO_VECTOR(Vector)) AS score
  FROM sentai_search.StepCorpus
 ORDER BY score DESC
```

**Rationale.** Three findings, in order, each of which eliminated the previous option.

1. *Cosine cannot be computed in ObjectScript.* `$VOP` exposes only structural operators — `type`,
   `length`, `count`, `tostring`, `fromstring`, `convert` are the ones IRIS itself uses. Arithmetic
   operators are not in the set: `$vop("dot",v,w)` and `$vop("multiply",v,w)` both fail at
   **compile** time with `<SYNTAX>`, not at runtime. There is no in-process cosine, so SQL is the only
   path.
2. *`VECTOR_COSINE` refuses a column with no declared length.* Ranking directly against
   `Property Vector As %Library.Vector` fails at cursor-compile time with a repeated
   `SQLCODE=-260: Cannot perform vector operation on sentai_devprobe.Corpus.Vector because it does not
   have a specified length`.
3. *Wrapping the column in `TO_VECTOR()` satisfies it.* The same query with `TO_VECTOR(Vector)`
   compiled and returned all 9 rows correctly. No length is declared anywhere.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| Compute cosine in ObjectScript with `$VOP` | `dot` / `multiply` / `scale` are not valid operators — compile-time `<SYNTAX>`. Verified. |
| `Property Vector As %Library.Embedding` (the embedding-aware type) | Will not compile: `ERROR #5002 <SUBSCRIPT>compileoneproperty+74^%occProperty ^rINDEXSQL("Embedding","")`. It resolves its length by looking up a named config row, and a persistent class cannot name one — `Default = "devprobe"` does not parse, and inline type parameters (`As %Library.Embedding(384)`) do not parse either. Creates a bootstrap cycle, see R-001a. |
| DDL table: `CREATE TABLE … vector VECTOR(384)` | Works, and declares the length. Rejected because it needs a DDL execution step outside the class load, duplicating the schema in a second place — against the Reproducibility standard ("a stranger with a clean checkout MUST be able to run the system from a single documented command"). |
| Add a sized column to an existing sharded class | Also defeats the purpose: the input records that HNSW needs default storage, and a vector column on a sharded class is neither. |

**R-001a — the bootstrap cycle, stated so nobody re-treads it.** A class using
`%Library.Embedding` cannot compile until a `%Embedding.Config` row exists; that row's validating
trigger cannot be satisfied until the provider class compiles; and the class cannot name the row.
`%Library.Vector` with no length breaks the cycle and is sufficient, because `TO_VECTOR()` satisfies
`VECTOR_COSINE`.

---

## R-002 — The provider is a `%Embedding.Interface` subclass, chosen by a row in
`%Embedding.Config`

**Decision.** `sentai.search.EmbeddingService` implements the two abstract class methods
(`Embedding(input, configuration)`, `IsValidConfig(config, ByRef errorMsg)`). Its host, port, path,
model and optional API key are read from the configuration JSON. An operator points the product at a
service by inserting a row into the platform's `%Embedding.Config` table; the product's core names no
vendor and no endpoint (FR-011, FR-012, Principle VI).

**Rationale.** The platform already owns this mechanism, and using it is what keeps the choice
configurable: `%Embedding.Config` has a `ValidateConfig` trigger that checks the named class extends
`%Embedding.Interface` and that its own `IsValidConfig` passes, and `EMBEDDING()` then resolves the
row in SQL. Verified working end to end: the trigger accepted the row, `EMBEDDING('free up disk
space', 'devprobe')` produced a vector, and it wrote into a `VECTOR` column.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| Reuse `%Embedding.OpenAI` against the local OpenAI-compatible endpoint | **Verified not viable.** The class hardcodes `req.Server = "api.openai.com"` and `req.Https = 1`, and `IsValidConfig` *requires* both a non-empty `apiKey` and the name of an SSL configuration that exists in the portal. The only override is `httpConfig`, applied afterwards by `set $PROPERTY(req,key) = value` — an undocumented side effect that would still need a fake key and a real SSL configuration name. Fragile, and it names a vendor in the core. |
| Hardcode the endpoint in the search package | Violates FR-011 and Principle VI. |
| Call the provider from the frontend | Puts a network hop and a model dependency in the browser, and makes the corpus a client-side concern. |

**A note on "the core does not name IRIS" (Principle VI).** The codebase is already ObjectScript on
this platform, so the reading applied here is the useful one: the *search domain* does not name a
platform, vendor, model or endpoint. `sentai.search` depends on a two-method abstraction it owns
(`%Embedding.Interface`) and on configuration. Swapping the provider is a row in a table, not a code
change.

---

## R-003 — The default provider is a local embedding model on the compose network

**Decision.** The dev stack gains an `ollama` service holding `all-minilm` (43.8 MB, BERT, 23M
parameters, **embedding length 384** — read from `ollama show all-minilm`). The product talks to it
over an OpenAI-compatible `POST /v1/embeddings`.

**Rationale, all verified from inside the running `iris` container.**

- `iris` **cannot** currently resolve `ollama` by name: `ollama` is on `triageaide_fhir-net`
  (172.18.0.3), `iris` is on `sentai-task_default` (172.20.0.3). Another project's container.
- `iris` **can** reach the host-published ollama at the network gateway:
  `wget http://172.20.0.1:11434/api/tags` from inside `iris` returns the model list.
- Both endpoints answer identically from inside `iris`, 384 dimensions, same values:
  `/v1/embeddings` → `data[0].embedding`, `/api/embed` → `embeddings[0]`,
  first three components `[-0.0493, 0.05775, -0.01603]` for "free up disk space".
- `all-minilm` is 43.8 MB across its manifest layers.

`/v1/embeddings` is chosen over `/api/embed` because it is the shape `%Embedding.OpenAI` already
speaks, so the same provider class serves a local service and a hosted one.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| `/api/embed` (the vendor-native shape) | Ties the core to one vendor's response shape. `/v1/embeddings` is the interoperable one. |
| `%Embedding.SentenceTransformers` | Needs a Python environment and a model download inside the IRIS container. The input asks only that this be *documented* as an alternative, which R-002 makes a one-row change. |
| Point the dev stack at the existing host `ollama` via the gateway IP | Works today, but the gateway address is not a stable name, and that container belongs to another project and holds unrelated chat models. A service in this project's compose file is reproducible. |

**Documented, per FR-012**: `README.md` gains the provider section — how to point the setting at
`%Embedding.SentenceTransformers` or `%Embedding.OpenAI` instead (change the `EmbeddingClass` and
`Configuration` on the row), and that a hosted service means the operator's query text leaves the
machine (FR-010).

---

## R-004 — The corpus is stored, not recomputed per request

**Decision.** Each entry's description is embedded once and stored. A keystroke costs **one** embed
call.

**Rationale, measured.** Five sequential embed calls issued from inside the `iris` container:
**71, 87, 79, 75, 74 ms** — about 75 ms each. Recomputing per request would mean 10 calls per
keystroke (9 descriptions + the query), roughly 750 ms before any HTTP or SQL, which puts FR-009's
one-second budget at risk for no benefit. Against a warm corpus the whole request is one 75 ms call
plus a round trip — on the order of 100 ms, leaving roughly ten times headroom under the one-second
budget that SC-003 measures.

**Alternative considered.** Embedding on every request (≈750 ms/keystroke) — rejected on the
measured budget.

---

## R-005 — The corpus is rebuilt lazily, keyed by a version derived from the catalog

**Decision.** The corpus version is a hash over the catalog's `(type, description)` pairs. On a
search, the current version is computed from `StepType.GetCatalog()`; if it differs from the stored
one, the corpus is rebuilt before ranking. The rebuild is an idempotent upsert per entry plus a
delete of types no longer in the catalog, so a concurrent duplicate rebuild produces the same state
and needs no lock (YAGNI).

**Rationale.** This is the mechanism that discharges FR-017 and FR-016: a catalog entry that is
added or reworded becomes searchable with no registration call, no index build, no migration and no
setting, because the corpus is derived from the catalog rather than maintained beside it. Rebuild
cost is 9 embed calls, once, only after the catalog actually changes. Note that the catalog is read
from compiled XData, so it can only change when the application is loaded — a rebuild is rare by
construction.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| A corpus build step in the load sequence | That is a manual step, and it fails silently whenever the provider is down — the exact failure mode FR-017 forbids. |
| Rebuild on every request | 10 embed calls per keystroke; see R-004. |
| Rebuild on catalog change via a class trigger | Not available for XData, and would still need the provider up at load time. |
| A lock around the rebuild | Not needed: the rebuild is idempotent. Adding one would be speculative concurrency management. |

---

## R-006 — No approximate-nearest-neighbour index, and the row count that would justify one

**Decision.** No ANN/HNSW index is created (FR-027). The corpus is 9 entries; the exact scan in
R-001 returns the complete ranking in the same single round trip, so an index would add a schema
object, a rebuild obligation and an invalidation problem to buy nothing.

**Row count at which it would be justified.** HNSW starts to earn its keep in the **thousands** of
rows — take **10,000** as the threshold to re-evaluate at, and re-measure well before that. The exact
scan is linear in corpus size; at 10,000 rows of 384 float32 values the comparison itself is still
trivial, so the threshold is deliberately conservative and should be revisited against a measurement
rather than treated as a trigger.

**A second reason the index is not merely premature but inapplicable.** HNSW requires a
fixed-length `double` or `decimal` field, bitmap-supported ids and default storage. The
`%Library.Vector` column chosen in R-001 declares no length — which is exactly what
`VECTOR_COSINE` rejects (SQLCODE=-260) and exactly what HNSW would reject too. Moving to the sized
form means the DDL table of R-001, which is a separate decision to be taken *with* the index, not
before it.

---

## R-007 — Unavailable search is a 200 with a typed reason, not an error status

**Decision.** `GET /catalog/step-types/search?q=…` answers `200 {"available": false, "reason":
"…"}` for every degradation: not configured, unreachable, slow, incompatible, unexpected. Only a
missing or empty `q` is a 400.

**Rationale.** The product's answer when search is unavailable is *today's palette* — a successful
experience, not an error. SC-004 requires 0 error states across 20 degraded attempts. Returning 503
would be correct HTTP and wrong product behaviour: it would push a failure path into the frontend
that the specification forbids, and tempt a toast the operator does not need. `available: false` with
a reason is the honest description of what the search surface produced, and it keeps the reason
available for diagnosis (FR-024) without interrupting the operator.

This is Constitution IV, not a workaround: the predictable failure crosses every layer as a value,
and nothing partially ranked ever escapes as a success.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| `503` + a problem document | Correct HTTP semantics, wrong product behaviour; produces the error state SC-004 forbids. |
| `200` with an empty match list | Indistinguishable from a genuine no-match. A misconfiguration would be invisible, violating FR-024. |
| `200` with a best-effort ranking from a stale corpus | Ranks the operator's question against vectors from a different model. Violates FR-025. |

---

## R-008 — The relevance floor is absolute, at 0.20

**Decision.** Entries scoring below **0.20** contribute nothing; the palette then behaves exactly as
today (FR-008). Above the floor, entries are ordered by score.

**Rationale, measured on the real 9-entry corpus** with the descriptions the plan will ship
(cosine against the query, highest first):

| Query | Top entry | Top score | 2nd | 3rd |
|---|---|---|---|---|
| rotate the journal | `switch-journal` | **0.795** | 0.333 | 0.298 |
| get rid of old audit records | `purge-audit-records` | **0.743** | 0.501 | 0.308 |
| free up disk space | `compact-globals` | **0.529** | 0.497 | 0.457 |
| check my globals are sound | `integrity-check` | **0.501** | 0.158 | 0.148 |
| **order me a pizza** (no such capability) | `custom` | **0.053** | 0.002 | −0.007 |

The intended entry ranks first for all four intent phrases. The best score any nonsense query
reaches is 0.053 — a factor of ~4 below the floor, and the floor is a further ~2.5× below the
lowest true match (0.501). The margin is wide on both sides, which is what makes a fixed constant
honest here.

The last row is also the sharpest argument in the whole plan: **the best match for "order me a pizza"
is the unavailable legacy `custom` entry.** A ranking without a floor would confidently offer the
operator a legacy placeholder for a pizza. FR-008 exists for that row.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| Relative-to-best floor (e.g. 0.6 × best) | **Demonstrated to fail on the measured data.** For "order me a pizza" the top score *is* the best score, so the relative ratio is 1.0 and nonsense passes. |
| Always return the top N | Violates FR-008 directly; a ranked list of all nine is noise, and it produces the `custom`-for-pizza outcome above. |
| No floor, let the palette show everything ranked | Same violation, and it destroys the distinction between "found it" and "matched everything". |

The floor is a named constant with the measurement above beside it, so a future corpus or model
change can re-derive it instead of guessing.

---

## R-009 — The corpus is the catalog, reached only through its accessor; no class name is read

**Decision.** The corpus builder reads `type`, `label` and `description` from
`sentai.registry.StepType.GetCatalog()` and nothing else. It never reads the `class` field of any
entry, so there is nothing for the legacy `custom` entry to leak (FR-013, FR-018, Constitution II).

**Rationale.** Verified: the `custom` entry's `class` field is the empty string, and the catalog has
no `customClass` field at all. Excluding the class field from the corpus build is therefore not a
filter — it is the absence of any read. The only place a class name is shown to the operator is the
palette's existing substring match on `t.className` (`Palette.svelte:16`), which is pre-existing
display behaviour that FR-006 requires preserving; the search path neither reads nor adds to it.

**Consequence for the completeness test.** `StepTypeTest.cls:101` (`TestEveryEntryHasLabelAndExecutor`)
already asserts every entry has a non-empty label and a legal executor. It gains a sibling assertion
that every entry has a non-empty `description` (FR-015, SC-009) — the check already has a home, and
an entry without prose cannot reach the corpus.

---

## R-010 — One new route, `GET /catalog/step-types/search?q=`

**Decision.** A single route under the existing `/catalog/` group, delegating to
`sentai.search.StepSearchService`. `ListStepTypes` is untouched, so the palette's existing load is
unchanged.

**Rationale.** Verified in the URL map: exact and parameterised paths sit side by side without
conflict today (`/catalog/step-types` alongside `/catalog/tasks/:taskId`), so
`/catalog/step-types/search` is a distinct route. GET with a query parameter matches the existing
`/catalog/tasks?q=` precedent (`Dispatcher.cls:618`) and keeps the operator's sentence out of a
request body. A missing or empty `q` is a 400, which matches FR-005's rule that the client never
asks.

**Alternatives considered.**

| Alternative | Why rejected |
|---|---|
| `POST /catalog/step-types/search` | It is a read. |
| An optional `q` on the existing `GET /catalog/step-types` | One URL with two meanings, and it would change the response shape of a route the palette already depends on. |
| A `q` on `/catalog/tasks` | Wrong resource: this searches the closed step-type catalog, not the platform's task catalog. The two are different lists and conflating them is how a second source of capabilities appears. |

---

## R-011 — The description rides along on the catalog endpoint; the palette does not display it

**Decision.** The new `description` field is part of the catalog entry, so `GET /catalog/step-types`
returns it, and `frontend`'s `StepTypeInfo` does **not** gain a `description` field — `wire.ts`
ignores it. The search response carries only ranked type identifiers and scores.

**Rationale.** Two small things are better than one clever thing. Stripping the field in the
Dispatcher would put a projection in the class whose contract is explicitly "routing, authentication,
JSON (de)serialization, and error-to-HTTP status translation only — no business logic lives here".
And because `StepTypeInfo` does not declare the field, the re-ordering view model can only ever
re-order entries it already holds — Constitution II is enforced structurally in the view model,
not by a filter someone might forget.

**Considered and not built.** Showing each entry's description in the palette (as a tooltip or a
second line) would help an operator judge a suggestion. No requirement in the spec asks for it, and
YAGNI is a stated engineering standard. It is a one-line change to `StepTypeInfo` and the entry
markup when someone wants it, in its own specification.

---

## R-012 — Frontend: a pure view model, a debounce, and the existing latest-request-wins helper

**Decision.** `frontend/src/lib/palette/search.ts` — pure, no Svelte, no I/O — takes the registry and
the ranked identifiers and returns the leading suggestion group plus the untouched remainder.
`Palette.svelte` owns a small tagged search state, debounces at **150 ms**, and calls the API through
`client.ts`. Staleness is handled by reusing the existing `createSequence()` helper.

**Rationale.** `createSequence()` already exists at `lib/catalog/catalog.ts:268` and is already used
by `CatalogScreen` for exactly this — "latest-request-wins: a slower, older answer never overwrites a
newer one". FR-009 needs precisely that, and reusing the helper keeps one mechanism in the codebase
rather than two. `paletteGroups()` (`lib/flow/document.ts:110`) is already pure and already encodes
the spec 007 grouping, so the remainder of the palette is produced by calling it unchanged (FR-003).
The 150 ms debounce keeps one request per word rather than one per character; with a ~100 ms
request, FR-009's one-second budget is met with the palette landing roughly 250 ms after the last
keystroke.

**Layering.** components → `lib/palette/*.ts` → `lib/api/client.ts` / `wire.ts`, no `fetch` in a
component (Principle I). The view model is where the ranking becomes a palette, and it is covered by
vitest in the same style as `lib/flows/list.ts`.

---

## R-013 — Provider timeouts, because "slow" is a specified state

**Decision.** The provider request sets an explicit connect and read timeout, and a timeout is
reported as the `slow` reason, not as a hang.

**Rationale.** FR-024 and SC-004 both treat slowness as a state the product must have an answer for.
A request with no timeout can hold a CSP worker for the platform's default, which is the difference
between "the palette keeps working" and "the palette stops responding". This is also the only place
in the feature where a wall-clock bound appears, so it is worth stating plainly rather than relying
on a library default nobody has read.

---

## R-014 — The transport contract of `%Net.HttpRequest` on this build, and the dialect traps around it

**Decision.** A request is judged by `HttpResponse.StatusCode`, never by `Post()`'s return value, and
the response object is only touched after `$IsObject()` has confirmed it exists. Elapsed time is
measured with `$ZTIMESTAMP` differences. The reason travels as a leading token on the error text
(`unreachable: …`, `slow: …`, `error: …`), which `StepSearchService` parses.

**Rationale.** Measured, not assumed, on IRIS 2026.2 in the dev stack:

| Outcome | `Post()` returns | `HttpResponse` | `StatusCode` |
|---|---|---|---|
| provider answered 200 | `1` | present | `200` |
| connection refused / host unresolvable | `0` | **absent** | — |

So `sc` alone cannot mean success, and reading `req.HttpResponse.StatusCode` without a guard is a
`<SYNTAX>` on the failure path. `slow` is then separated from `unreachable` by how long the attempt
took: at least the open-timeout budget means the connection was made and the provider went quiet
(`slow`), anything faster means it refused or could not be named (`unreachable`).

**The dialect traps found alongside it**, each of which cost a real debugging cycle and each of which
is a silent wrong answer rather than a compile error unless noted:

- `$ZCONVERT(x, "N")` and `$ZCONVERT(x, "N", 20)` return `<FUNCTION>`. `$TRANSLATE` and
  `$Library.Vector.DisplayToLogical()` do the work instead.
- **A two-argument `FOR` whose stop is a bare expression does not terminate.** `For i = 1:3` and
  `For i = 1:$LENGTH(word)` and `For i = 2:..#Dimensions` all run forever; `For i = 1:(3)` and the
  three-argument `For i = 1:1:3` are correct. The bare-stop form shows up as a hang from SQL
  (`<MAXSTRING>` once the loop has concatenated long enough) and as a silent hang from a terminal.
  *Every* loop bound in this feature is parenthesized or three-argument.
- `$PPIECE(string, delim, piece, value)` raises `<SYNTAX>` at runtime in a class method, with a
  variable as well as an expression in the fourth argument. A `%DynamicArray` with `%Push`/`%Set`/
  `%Get` is used instead, and `%ToJSON()` on it yields exactly the bracketed, comma-separated text
  `%Library.Vector.DisplayToLogical()` wants.
- `ch ? [A-Z0-9]` raises `<SYNTAX>`; `$ASCII` range comparisons are used.
- `%String(MAXLEN)` with no value is a **parse** error, not a long-string declaration: the compiler
  wants `MAXLEN = 32000`.
- A property parameter keyword `IdKey` is not accepted by this parser. The id key is declared the
  way the rest of this codebase declares one — as the **first** property, implicitly.
- **`&sql(... INTO :local)` does not bind when the SQL names a host variable**, and there is no
  `$SQLCODE` special variable to notice: a failed `&sql` is completely silent. `SELECT COUNT(*)
  INTO :stale FROM … WHERE corpusVersion <> version` left `stale` undefined, and the assertion then
  failed as a *wrong number* rather than as a wrong statement. Every statement whose **result
  matters** uses `##class(%SQL.Statement).%ExecDirect(, sql, …)` with bound parameters and reads
  `%SQLCODE`/`%Message`; `&sql` is kept only for the unconditional `DELETE`s that need no value.
- Two consequences of the above that are worth stating on their own, because both produce a
  **confident wrong answer**: a `DELETE … WHERE Name = ?` written with `&sql` does not delete
  anything, and a reserved word used as a column alias (`SELECT COUNT(*) AS found`) fails the
  statement, which a `Quit 0` on `%SQLCODE` then reports as *absent*. `ProviderIsConfigured`
  therefore answers `1`/`0`/`-1`, and `-1` (the lookup itself failed) is surfaced as `error`, never
  as `not-configured`.
- **`$LEFT`, `$SELECT` and `$SQLCODE` do not exist.** `$EXTRACT(x, 1, n)` and an `If` do the work.
- `$$$AssertFail` is not defined, and `$$$AssertTrue` and friends are **instance** methods, so a
  `ClassMethod` helper cannot assert. Helpers return `""` or the SQL message and the instance
  `OnBeforeOneTest`/`OnAfterOneTest` (or the test method) make the assertion.
- A `Quit` carrying a value inside a `{ }` block is rejected (`#1043`); a bare `Quit` is accepted.
  Early exits inside a block are written as a flag in the loop's own condition.
- A subscripted **local** array may not use `[]`: `Set stored[label] = …` is `#1027`, `Set
  stored(label) = …` compiles. `()` everywhere, as the rest of the module already writes it.
- An object literal (`{"type": x}`) requires literal values; a variable in one is `#1033`. Objects
  are built with `##class(%DynamicObject).%New()` and property assignment.
- `%SQL.ResultSet` has no `%GetIterator()`; iterate it with `%Next()`/`%Get()`. A `.` prefix is for
  `ByRef` arguments only — in an expression the local is written plain, so `entry.type`, never
  `.entry.type`.
- `%DynamicArray` is indexed from **zero**, and an array cannot be created by `New` inside a class
  method ("private variable not allowed") — assign it where it is used, with `()`.
- `iris session` in a terminal is **not** a valid place to check embedded SQL: `&sql … INTO
  :local` does not bind there either. Behavioural claims are verified through
  `iris_execute`/the suite, and a `##class()` call in a terminal prints a caret for the offending
  line, which is the fastest way to see *which* line a runtime `<SYNTAX>` belongs to.
- **`$TRIM`, `$ZTRIM` and `$TAB` do not exist either**, and neither does `##class(%String).Trim()`.
  Blankness is decided with `$TRANSLATE(q, " "_$CHAR(9,10,13)) = ""`, which is the only one of the
  candidates that survives. `$CHAR` and `$TRANSLATE` are both available.
- **`ROWS` is a reserved word**, like `FOUND`. `SELECT COUNT(*) AS rows` fails the statement, so a
  `CorpusRowCount()` written that way reads `0` forever and would make "the corpus did not grow"
  pass for the wrong reason. The alias is `n`.
- **`%CSP.Request` has no `Parameters` list** on this build: the property does not exist. Query
  parameters live in the public multidimensional `Data` property, so a test writes
  `Set %request.Data("q",1) = text` and `%request.Get("q")` reads it back.
- **`%EMBEDDING.Config` validates its `Configuration` column on INSERT** and rejects anything that
  is not strict JSON, with `SQLCODE -415` and `Not a valid JSON format` in `%Message`. A single-quoted
  pseudo-JSON literal therefore fails at insert time rather than at read time. Test fixtures build the
  configuration with `##class(%DynamicObject).%New()`/`%ToJSON()` rather than a hand-written literal.
  Worth knowing for the same reason it matters in the product: a malformed row is refused where it is
  written, not at the operator's first keystroke.

**Consequence for review.** These are properties of the platform build this repository is developed
and tested against, not of ObjectScript in general. A reader who copies a loop from elsewhere in
ObjectScript documentation will get a hang, not an error, so the convention is stated here rather
than left to be rediscovered.

---

## Resolved: no `NEEDS CLARIFICATION` remains

| Question in Technical Context | Resolved by |
|---|---|
| How is the corpus stored and compared? | R-001 |
| How is the provider chosen and configured? | R-002, R-003 |
| Build on every request, or store? | R-004 |
| How does a catalog change reach the corpus? | R-005 |
| Index now or later? | R-006 |
| How does unavailability cross the wire? | R-007 |
| What is the relevance floor, and why absolute? | R-008 |
| How is the closed set enforced at the corpus? | R-009 |
| Which route, and what about a bad request? | R-010 |
| What crosses the wire? | R-011 |
| How does the palette avoid a stale re-order? | R-012 |
| What bounds a slow provider? | R-013 |
| How is a transport failure told from a slow one, and what does this build accept? | R-014 |
