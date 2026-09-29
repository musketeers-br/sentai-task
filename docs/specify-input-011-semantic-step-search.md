Semantic step-type search over the closed catalog.

WHAT AN OPERATOR SHOULD BE ABLE TO DO. In the palette's existing search box
(frontend/src/lib/palette/Palette.svelte:31 — today a case-insensitive substring match on
`type`, `typeLabel` and `className`), type what they mean rather than what the identifier
happens to be: "free up disk space", "check my globals are sound", "get rid of old audit
records", "rotate the journal". The palette ranks the step types of the closed catalog by
semantic similarity to that sentence and offers the best matches. The operator still drags or
clicks exactly as today. Nothing is inserted automatically, and a search result can never be a
capability that is not already in the catalog.

THE CORPUS IS THE CATALOG AND NOTHING ELSE. The searchable text is the `sentai.registry.StepType`
XData `Catalog` block — 9 entries today, reached only through `StepType.GetCatalog()`. Each entry
gets a reviewed, hand-written prose `description` in the XData, the same pattern the existing
parameter entries already use. Do not derive prose from class names, do not add a second source
of capability, and do not let a legacy `custom` entry's `customClass` be read on any path
including this one (Constitution II). Adding a new searchable capability stays "a compiled class
plus one catalog entry, reviewed in a pull request".

EMBEDDING PROVIDER: CONFIGURABLE, LOCAL BY DEFAULT. The provider is configuration, never a
hardcoded endpoint, and the product's core does not name IRIS (Constitution VI). For this
implementation the default provider is a local embedding model served by Ollama, pulled into the
dev stack so that it costs nothing: the running `ollama` container currently holds only chat
models (gemma3:1b, qwen3.5:0.8b, qwen3:0.6b) and must gain a small embedding model (for example
`all-minilm`, 384 dimensions), reachable from the `iris` container as part of the compose stack.
Document how to point the same setting at `%Embedding.SentenceTransformers` or
`%Embedding.OpenAI` instead, and what the product does when no provider is configured.

VERIFIED PLATFORM FACTS TO BUILD ON (IRIS 2026.2, confirmed on the running instance in IRISAPP):
SQL types `%Library.Vector` and `%Library.Embedding`; the functions `VECTOR_COSINE`,
`VECTOR_DOT_PRODUCT`, `TO_VECTOR` and `EMBEDDING()`; embedding configurations held in the
`%Embedding.Config` table, with `%Embedding.OpenAI`, `%Embedding.SentenceTransformers` and
`%Embedding.TextSplitter`; and HNSW indexes (`%SQL.VectorIndex.HNSWIndexerV2`,
`CREATE INDEX ... AS HNSW(Distance='Cosine')`, ACORN-1 planner). HNSW also has hard preconditions
— a fixed-length `double` or `decimal` field, bitmap-supported ids, and default storage only —
which is why the vectors belong in a dedicated side table rather than a new column on an existing
sharded class.

SIZE THE INDEX HONESTLY. The corpus is 9 rows. An exact `VECTOR_COSINE` scan over 9 rows is
exact, instant and needs no approximate-nearest-neighbour index. State in the plan whether HNSW is
created now or documented as a later optimization above some row count; do not add an ANN index
for 9 rows as a matter of form.

DEGRADE AS A VALUE, NEVER AS A FAILURE (Constitution IV). The embedding provider being
unconfigured, unreachable, slow, or returning a different dimensionality than the stored vectors
must produce a typed outcome that crosses layers — not an exception, and not a behaviour change.
When search is unavailable the palette behaves exactly as it does today. State this as a
user-observable acceptance scenario, because "the operator's search box keeps working" is a real
requirement and not an implementation detail.

WHERE IT PLUGS IN. One new route under the existing `/catalog/` group of `sentai.rest.Dispatcher`,
which stays free of business logic; a small search package beside `sentai.registry`; a pure view
model in `frontend/src/lib/<domain>/*.ts` covered by vitest; and the palette itself, which keeps
its existing substring behaviour for exact identifier hits. Follow the layering the constitution
holds: components -> `lib/<domain>/*.ts` -> `lib/api/client.ts` / `wire.ts`, and no `fetch` in a
component.

QUESTIONS THIS SPECIFICATION SHOULD ANSWER RATHER THAN ASSUME. (a) Does a suggestion only
re-order or highlight the palette, or may it insert a step? Default to re-order only — insertion
stays an explicit operator action. (b) What exact text goes into each corpus document, and who
writes it? (c) When is the corpus built, and when is it rebuilt after a catalog change? (d) What
is the latency budget for a keystroke, and is there a minimum similarity below which the answer is
"no good match" rather than a ranked list of everything? (e) Does the operator's query text ever
leave the instance?

EXPLICITLY OUT OF SCOPE. No language model and no generated text anywhere. No natural language
producing an executable flow. No step constructed from the query. No change to validation,
dispatch, scheduling or confirmations. No vectorizing the task catalog, run history or flow
documents in this feature. The other vector-search applications considered and not built are
recorded, with their friction, in `docs/vector-search-proposals.md` — they are candidates for
their own specifications, not for this one.
