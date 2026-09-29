# Data Model: In-Process Embeddings for Step-Type Search

Only what this feature adds or changes. Everything else is spec 011's data model
(`specs/011-semantic-step-search/data-model.md`).

## 1. Provider configuration — the `sentai-steps` row (platform table `%Embedding.Config`)

Unchanged table, new default value, written by `iris-provider.script` only when no row of that name
exists (R-6):

| Column | Default value (dev and demo images) |
|---|---|
| `Name` | `sentai-steps` |
| `EmbeddingClass` | `sentai.search.LocalEmbedding` |
| `Configuration` | `{"modelName":"sentence-transformers/all-MiniLM-L6-v2","cachePath":"/usr/irissys/mgr/sentai-models"}` |
| `VectorLength` | `384` |
| `Description` | `Step-type search, in-process (installed by the dev build)` |

`LocalEmbedding.IsValidConfig` (called by the table's validating trigger) requires `modelName` and
`cachePath`, and fails with a message when the Python packages cannot be imported or the model is not
present in `cachePath`. It never downloads: the model is placed at build time (R-3), or by the
operator for an IPM install (R-7). Optional key: `pythonPath` (extra import path).

## 2. Provider identity (new, derived — not stored in the platform table)

`<Name>|<EmbeddingClass>|<model>|<VectorLength>` where `<model>` is `Configuration.model`, else
`Configuration.modelName`, else empty.

- Derived from the row on every search; the one value that says what a stored vector means.
- Excludes every other `Configuration` key, so a secret such as `apiKey` is never copied
  (Constitution III).
- Example today: `sentai-steps|sentai.search.EmbeddingService|all-minilm|384`; after this feature:
  `sentai-steps|sentai.search.LocalEmbedding|sentence-transformers/all-MiniLM-L6-v2|384`.

## 3. Stored corpus — `sentai.search.StepCorpus` (changed)

Adds one property; the storage map is extended by the compiler, never by hand.

| Property | Type | Rule |
|---|---|---|
| `providerIdentity` | `%String(MAXLEN = 512)` | The provider identity (§2) of the provider that embedded this row. |

**Currency rule (changes `StepSearchService.CorpusIsCurrent`).** The corpus is current when, as in
spec 011, the stored `(type, description)` pairs equal the catalog's, **and** every stored row's
`providerIdentity` equals the current one. Otherwise `EnsureCorpus` rebuilds it with the current
provider before any ranking (FR-007). Rows written by spec 011 have no identity, so the first search
after the upgrade rebuilds once.

`corpusVersion` becomes `v2-…` and includes the identity; it stays informational.

## 4. Embedding worker registration (new, temporary)

Global `^IRIS.Temp.sentai.embed` (IRISTEMP: cleared on restart, never journalled):

| Node | Value |
|---|---|
| `("pid")` | `$JOB` of the worker |
| `("state")` | `warming` \| `ready` |
| `("identity")` | the identity (§2) the worker loaded |
| `("readyAt")` | `$ZTIMESTAMP` when the model finished loading |

Named event resource: `sentaiEmbed` + the namespace with punctuation stripped, e.g. `sentaiEmbedIRISAPP`
(created by the worker, deleted when it stops). IRIS resource names take letters and digits only
(`-`, `_` or `.` fail with `<FUNCTION>`) and at most 32 characters, so the name is cut to 32.

**State transitions.**

```text
(none) --Start()/lazy JOB--> warming --model loaded--> ready --stop / process gone--> (none)
                                 \--load failed--> (none), failure recorded as `error`
```

A caller trusts `state` only when the pid in `("pid")` is alive; otherwise the worker is treated as
absent and started again (lazy path, R-2). A worker whose identity differs from the row's (the row
was changed) is asked to stop and a new one is started: the caller answers `warming` meanwhile.

## 5. Search outcome — `sentai.search.SearchOutcome` (changed)

`REASONS` becomes `not-configured,unreachable,slow,incompatible,warming,error`.

| Reason | When (new provider) |
|---|---|
| `warming` | No ready worker yet: the worker is loading, or was just started by this call. |
| `slow` | A ready worker did not answer within 0.8 s. |
| `error` | The worker failed to load, or any other failure. |
| `not-configured` | No `sentai-steps` row (unchanged). |
| `incompatible` | Vector width differs from the stored corpus (unchanged). |
| `unreachable` | Only the HTTP provider produces it (unchanged). |
