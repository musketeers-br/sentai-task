# Vector search — applications considered and deferred

Findings from an analysis of SentaiTask's own data against IRIS 2026.2's native vector
capability. One of these is being built (see `specs/011-*`); the rest are recorded here so they
are not re-derived from scratch, with the friction each one carries.

**Nothing on this page is a commitment.** These are candidates, sized honestly.

## Platform facts (verified on the running instance, `IRISAPP`, 2026-09-27)

- SQL types `%Library.Vector` and `%Library.Embedding`.
- Functions `VECTOR_COSINE`, `VECTOR_DOT_PRODUCT`, `TO_VECTOR`, `EMBEDDING()`.
- Embedding configurations live in the `%Embedding.Config` table; providers ship as
  `%Embedding.OpenAI`, `%Embedding.SentenceTransformers` and `%Embedding.TextSplitter`.
- HNSW indexes: `%SQL.VectorIndex.HNSWIndexerV2`,
  `CREATE INDEX ... AS HNSW(Distance='Cosine')`, served by the ACORN-1 planner.
- HNSW preconditions, all hard: a fixed-length `double` or `decimal` field, bitmap-supported
  ids, and default storage only. A sharded or partitioned class therefore needs a dedicated
  side table rather than a new column.
- An exact `VECTOR_COSINE` scan needs no ANN index. HNSW is only worth its overhead in the
  thousands of rows. State the row count that justifies it.
- No embedding provider is configured on the dev stack. The host's `ollama` container carries
  only chat models (`gemma3:1b`, `qwen3.5:0.8b`, `qwen3:0.6b`); an embedding model must be
  pulled, and the `iris` container must be able to reach it.

## Search over run and step failures by meaning — not built

**Solves.** An operator with hundreds of runs and a vague memory — "the one that was about disk
pressure" — has no way in today. The `RunScreen` shows a single run, the flows list orders by
`savedAt`, and there is no search over run history at all.

**Substrate.** `sentai.model.StepRun.failureReason` (2000), `result` (8000, fitted JSON), and
`LogEntry.message` (4000). The catalog already surfaces the platform's own `status.summary`
verbatim.

**Shape.** A side table over failed `StepRun`s, queried with
`WHERE state = 'failed' ORDER BY VECTOR_COSINE(doc, EMBEDDING(?)) DESC`.

**Friction.** Write cost per run, not per read. Every run writes a vector, so this changes the
hot path of the dispatch loop — a much heavier change than any read-time index.

**Bonus.** "Has this happened before?" is a `WHERE` clause on the same table, not a second
index. It is arguably the more useful of the two questions.

**Would need to be true.** That the dispatch loop can afford a write, and that the platform's
error text is worth embedding verbatim.

## Semantic search over saved flows — not built

**Solves.** `filterByName` in `frontend/src/lib/flows/list.ts` is a substring match on the flow
name only. With nine step types and a few dozen flows this is the weakest search in the product:
"which flow purges audit on APP at night" has no answer.

**Shape.** A derived one-line document per flow — name, step types, task names, namespaces,
database directories, WQM categories.

**Friction.** Low. This is the most shippable item on this page, and the most purely additive:
one read endpoint and one search box, with no change to dispatch, validation or scheduling.

**Constraint.** The derived document may carry only `Step.type` resolved through
`sentai.registry.StepType`. A legacy `custom` entry's `customClass` is never read, here or
anywhere (Constitution II).

**Would need to be true.** That a flow's identity is its content, not only its name — an
assumption worth putting to the operator rather than deciding here.

## Semantic search in the task catalog — not built, and the hardest

**Solves.** `sentai.catalog.TaskFilter.Matches` is `[`-containment on the lowercased name and
class. Platform task names are class-shaped identifiers, not prose, so an operator searching
for "the nightly thing that compacts globals" gets nothing.

**Friction — the reason it is last.** The catalog is a transient mirror of
`/api/admin/v2/tasks`, explicitly never a source of truth (spec 006). Indexing it means
persisting a local index of someone else's data, and raises a question the product has
deliberately avoided so far: how much of the platform's words do we store? It also introduces a
failure mode that is not a platform refusal — the embedding provider being unavailable — and the
`unavailable` / `refused` machinery has no honest place to put that without distorting what
those words already mean.

**Would need to be true.** A decision on persisting a rebuildable local index of a mirror, and
on whether a new non-platform failure mode is acceptable in that screen.

## Retrieval over validation findings — expected to lose

**Solves.** Attaching a knowledge-base passage to each `FlowValidator` finding.

**Friction.** `sentai.validation.FlowValidator` emits a closed set of roughly twelve finding
codes (`CYCLE_DETECTED`, `CATEGORY_NOT_FOUND`, `WQM_INVARIANT_VIOLATED`, `TARGET_REFUSED` …). A
lookup table is exact, instant, reviewable and testable. A vector index over twelve strings
would be strictly worse and less predictable.

This is also the one item that drifts toward the product narrating a fix, which collides with
"the platform decides, SentaiTask passes its refusal through" (Constitution III).

**Would need to be true.** That the corpus outgrows what a table can hold. Nothing suggests it
will.

---

See also [known limitations](limitations.md) for what v1 as a whole does not do.
