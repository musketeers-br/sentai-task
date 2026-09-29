# Feature Specification: Semantic Step-Type Search over the Closed Catalog

**Feature Branch**: `011-semantic-step-search`

**Created**: 2026-09-27

**Status**: Merged

**Status note**: PR #17, 2026-09-28. 34/34 tasks; evidence in evidence/.

**Input**: User description: "Semantic step-type search over the closed catalog. In the palette's
existing search box, an operator should be able to type what they mean — *free up disk space*,
*check my globals are sound*, *get rid of old audit records*, *rotate the journal* — and be offered
the catalog entries closest to that sentence, ranked. Insertion stays an explicit operator action:
the operator still drags or clicks exactly as today. A search result can never be a capability that
is not already in the closed catalog. The searchable corpus is the catalog and nothing else. The
similarity service is configuration, local and free by default. When it is absent, unreachable, slow
or incompatible, the palette behaves exactly as it does today, and that degradation crosses layers
as a value (Constitution IV), not an exception and not a behaviour change. Explicitly out of scope:
any language model, any generated text, any flow or step constructed from the query, any change to
validation, dispatch, scheduling or confirmations, and any vectorizing of the task catalog, run
history or flow documents."

## Context and Problem

1. **The palette search box requires the operator to already know the vocabulary.** It matches a
   case-insensitive substring against an entry's identifier, label and implementation class name. An
   operator who needs disk space has to guess that the entry is called *Storage headroom check*; one
   who needs space freed has to know it is *Compact globals*. The gap is not the capability set — it
   is the operator's memory of the names already in the catalog.
2. **The miss is silent and looks like absence.** Typing an intent the catalog does satisfy yields
   *No step type matches "…"* — indistinguishable from a capability that genuinely does not exist.
   The operator concludes the product cannot do the thing, when in fact it can.
3. **The catalog is already the single source of capability, and already carries reviewed prose.**
   Every step type is a hand-written, reviewable entry. Nothing needs to be invented to describe
   them; the description of what each entry does is the missing text, not a missing capability.
4. **The search surface is the risk.** Ranking introduces a new way for the product to *name* things
   to the operator. A ranking that can suggest something outside the closed catalog, or read a
   legacy entry's implementation class, would turn a convenience into a way of reaching an
   undeclared capability (Constitution II). The guard is that the corpus is the catalog and the
   result is only ever a re-ordering of it.
5. **A similarity service is an external, optional dependency.** It may be unconfigured,
   unreachable, slow, or return a different shape from what the corpus was built with. Each of those
   is a predictable failure and must cross every layer as a value with the palette's existing
   behaviour intact behind it (Constitution IV).

## Objective

An operator searching the palette by intent sees the relevant catalog entries ranked above the rest,
finds the right step type without knowing its name, and adds it with the same drag or click used
today — with the guarantee that a search can only ever re-order capabilities that already exist, and
that when the similarity service is not usable, the palette does exactly what it does today.

## Open Questions Answered Here

These are the five questions this specification was asked to answer rather than assume. They are
this specification's positions, recorded so they can be revisited deliberately through
`/speckit.clarify` instead of being discovered during implementation.

### Session 2026-09-27

**Q: Does a suggestion only re-order the palette, or may it insert a step?**
→ A: Re-order only. A suggestion changes what the operator sees first; it never adds a step, never
selects a step, and never changes the canvas. Insertion stays an explicit operator action — the same
drag or click, on a step the operator has chosen. This is what makes the feature safe to try: a
misread sentence cannot put a capability on the operator's canvas.

**Q: What exact text goes into each corpus document, and who writes it?**
→ A: One hand-written prose description per catalog entry, held in the entry itself, written by
whoever adds the entry and reviewed in the same pull request as the entry. Prose is never derived
from a class name, a file name, a parameter, or anything else derivable — the point of the corpus is
a human statement of what the capability is for, and derived text is how a label leaks an
implementation detail into a user-facing ranking. The existing prose on a catalog entry's
parameters is the same pattern, extended from parameters to entries.

**Q: When is the corpus built, and when is it rebuilt after a catalog change?**
→ A: A catalog change must be reflected with no manual step, no separate registration, no index
build, and no configuration — otherwise the corpus becomes a second list of capabilities that can
drift from the first, which is exactly the failure Constitution II exists to prevent. The Plan
resolves *how* the corpus is produced and kept current (derived when it is needed, or refreshed when
the catalog changes); this specification fixes only the observable consequence: an entry added or
reworded is searchable correctly without anyone remembering to do anything.

**Q: What is the latency budget for a keystroke, and is there a minimum similarity below which the
answer is "no good match" rather than a ranked list of everything?**
→ A: Two separate answers. *Latency* — the operator sees the ranked list within one second of the
last keystroke; a result that arrives after a newer keystroke must not re-order the palette behind
the operator's back. *Minimum similarity* — yes, there is a floor. Below it, similarity contributes
nothing and the palette falls back to exactly today's behaviour, including today's no-match message.
A ranked list of all nine entries in arbitrary similarity order is not a result; it is noise, and it
is indistinguishable from a search that did not work.

**Q: Does the operator's query text ever leave the instance?**
→ A: Not in the shipped default configuration, where the similarity service runs on the same host
and no query text crosses a network. The query text is sent only to whichever service is configured,
so an operator who points the setting at a hosted service should know that their sentence leaves
the machine; that trade-off is documented where the setting is described, and the default is the one
that does not require the trade-off. The query text is never retained as a searchable record of
operator intent.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find the right step type by describing the job (Priority: P1)

An operator who needs space freed, or who needs to know their globals are sound, or who needs old
audit records gone, opens the palette and types the sentence they would say out loud rather than the
identifier they happen to remember. The palette puts the catalog entries closest to that sentence at
the top, ahead of the entries it already showed, while keeping everything it already showed
reachable. The operator recognises the capability, drags or clicks it exactly as they do today, and
is never asked to learn a new interaction.

**Why this priority**: This is the whole value of the feature. Every other story protects this one
from going wrong; without it there is no reason for the feature to exist.

**Independent Test**: With the similarity service usable, type the four intent sentences named
above and observe that the intended entry is among the first entries shown, that nothing is inserted
into the canvas without an explicit action, and that the rest of the palette is unchanged. Every
other behaviour in this specification exists to keep this one safe.

**Acceptance Scenarios**:

1. **Given** the palette is open and the similarity service is usable, **When** the operator types
   "free up disk space", **Then** the storage-related catalog entries are shown ahead of the entries
   unrelated to space, and the compaction entry appears among the first three shown.
2. **Given** the palette is open, **When** the operator types "check my globals are sound", **Then**
   the verification and integrity entries are shown first, and the integrity check is among them.
3. **Given** the palette is open, **When** the operator types "get rid of old audit records", **Then**
   the purge entry for audit records is among the first entries shown.
4. **Given** the palette is open, **When** the operator types "rotate the journal", **Then** the
   switch journal entry is among the first entries shown.
5. **Given** a ranked result is showing, **When** the operator does nothing but read, **Then** the
   canvas is unchanged and no step has been added, selected or highlighted as chosen.
6. **Given** a ranked result is showing, **When** the operator drags or clicks a suggested entry,
   **Then** the step is added exactly as it would be if the entry had been found by typing its
   identifier.
7. **Given** the search box is empty, **When** the palette is displayed, **Then** the entries appear
   in today's order and today's grouping, with no suggestion group and no re-ordering.
8. **Given** the operator has typed a sentence, **When** the operator then narrows the same sentence
   with more characters that turn it into an exact identifier or label, **Then** the exact match is
   shown first, and the existing substring behaviour is preserved.

---

### User Story 2 - The search box keeps working when the similarity service is not usable
(Priority: P2)

The similarity service is someone else's component: it may not be configured on this deployment, may
be down, may answer too slowly to be useful, or may return something the product cannot compare with
what it stored. The operator does not care which. They type in the palette search box and get
today's behaviour: narrowing by the text of the entry itself, the familiar category grouping, and
the familiar no-match message. Nothing is disabled, no error replaces the list, and no keystroke is
lost — the reason is recorded where it can be diagnosed instead of being pushed in front of the
person trying to work.

**Why this priority**: A search that can be broken by a dependency the operator did not choose is
worse than no semantic search at all, and the constitution requires the failure to be a value that
crosses the layers rather than an exception. This story is what makes shipping the feature safe on
a deployment that has no service configured.

**Independent Test**: Stop the similarity service, or run with no service configured at all, then
type a known identifier and an intent sentence. The palette must narrow by entry text exactly as it
does today, show today's no-match message for text that matches nothing, and show no new error.

**Acceptance Scenarios**:

1. **Given** no similarity service is configured, **When** the operator types "compact" in the
   palette search box, **Then** the compaction entry is shown and the palette behaves exactly as it
   does today.
2. **Given** no similarity service is configured, **When** the operator types "free up disk space",
   **Then** the palette shows today's behaviour for that text — entries matching the entry text
   itself, and today's no-match message when nothing matches — and the operator sees no error and no
   warning in place of the list.
3. **Given** the similarity service is configured but unreachable, **When** the operator types in the
   palette search box, **Then** the palette narrows by entry text as it does today and the reason
   the ranking was unavailable is available for diagnosis without interrupting the operator.
4. **Given** the similarity service is configured but answers too slowly to be useful, **When** the
   operator keeps typing, **Then** the palette stays responsive on every keystroke, and a ranking
   that arrives after a newer keystroke does not re-order the list the operator is looking at.
5. **Given** the similarity service answers with a different shape from the stored corpus, **When**
   the operator types in the palette search box, **Then** the palette behaves as it does today and
   no entry is ranked against something it cannot be compared to.
6. **Given** the similarity service is answering normally, **When** nothing about the configuration
   changes, **Then** the operator's search results are the same as on the previous attempt —
   degraded and working runs are not distinguishable from the palette's own behaviour.

---

### User Story 3 - Search can only ever offer what the catalog already declares
(Priority: P3)

A reviewer asks the uncomfortable question: if the product now ranks what the operator typed against
a list of capabilities, what stops that list from being a way to reach something the product never
declared? The answer is that the corpus is the catalog, the answer is a re-ordering of the catalog,
and nothing else can enter it. The legacy entry that carries a class name in its data is the sharpest
test of that, because it is the one entry whose stored text could point somewhere the product does
not currently execute.

**Why this priority**: This is the constitutional floor under Stories 1 and 2. A semantic search that
could surface an undeclared capability would trade a convenience for a remote-execution surface on
production systems, which is not a trade this product makes.

**Independent Test**: Run searches whose text is a capability that does not exist, a class name from
inside the product, and a legacy class name. Nothing outside the declared catalog appears, no
undeclared capability is inserted into a canvas, and the legacy entry is treated as the unavailable
legacy entry it already is.

**Acceptance Scenarios**:

1. **Given** the operator types a sentence describing a capability the product does not declare,
   **When** the palette answers, **Then** every entry shown is an entry in the declared catalog and
   the operator sees today's no-match message when nothing in the catalog is close.
2. **Given** the operator types the name of an implementation class from inside the product, **When**
   the palette answers, **Then** the result contains no entry that is not in the declared catalog.
3. **Given** the declared catalog contains the legacy custom entry, **When** the legacy entry's
   stored class name is read by any part of the search, **Then** the search behaves as it does
   without semantic search, and the legacy entry remains unavailable and unexecutable.
4. **Given** a similarity service returns text or a suggestion of its own, **When** the palette
   renders the ranking, **Then** the operator sees only the reviewed text of catalog entries, and no
   text, name, class or capability generated outside the catalog.
5. **Given** the operator searches and then adds a step, **When** the added step is compared with the
   catalog, **Then** it corresponds to a declared catalog entry, chosen by the operator rather than
   derived from the query.

---

### User Story 4 - A capability's description is written and reviewed with the capability
(Priority: P4)

An engineer adds a capability the way they always do: the entry in the closed catalog plus the thing
it names, reviewed in a pull request. Because the entry now carries a sentence describing what it is
for, the new capability is findable by intent with nothing else to do — no second list, no
registration call, no index to build, no setting to flip, and no documentation page to keep in step.
The sentence is written by the same person in the same review as the entry, and if it is wrong or
missing, the change does not go in.

**Why this priority**: Without this the feature rots. A corpus built by a separate process from a
separate list would drift from the catalog, and a catalog entry with no reviewed description would be
a capability the operator can never find by intent. It is lower priority only because it becomes
visible when the catalog changes, not on day one of the existing nine entries.

**Independent Test**: Change the description of an existing catalog entry and reword a second one;
both must be findable by their new wording with no other action. Then add a new entry with a
description and confirm it is findable by intent. Then add an entry with an empty description and
confirm the change is rejected.

**Acceptance Scenarios**:

1. **Given** an engineer has added a catalog entry with a reviewed description, **When** the
   operator searches the palette using a sentence describing the capability's purpose, **Then** the
   new entry is among the entries shown, with no registration, build or configuration step having
   been performed for it.
2. **Given** a catalog entry's description has been reworded, **When** the operator searches using
   the new wording, **Then** the entry is ranked accordingly, with no manual step in between.
3. **Given** a proposed catalog entry has no description, **When** the change is reviewed, **Then** it
   is rejected, and adding the capability is not possible by any route that skips the description.
4. **Given** the catalog is the only list of capabilities, **When** a new capability is added, **Then**
   the addition is a catalog entry plus the capability it names, and no second place records it.

---

### Edge Cases

- **Whitespace-only query** — treated as an empty query: today's grouped list, no suggestion group,
  no request made.
- **A query that matches an entry's identifier, label or class name exactly** — the exact match is
  shown first and today's substring behaviour is unchanged; the semantic ranking never hides or
  reorders a match the operator could already find.
- **Similarity below the relevance floor** — similarity contributes nothing and the palette shows
  today's behaviour, including today's no-match message; the operator is not shown a ranked list of
  every entry in arbitrary order.
- **Two entries that are equally relevant** — shown in a stable, deterministic order so the palette
  does not reshuffle between two keystrokes that both qualify.
- **A ranking that arrives after the operator has typed again** — discarded; the palette never
  re-orders behind the operator's back.
- **A very long, punctuated or non-English query** — treated as ordinary text; a query that is empty
  after trimming is the empty-query case, and no query text is interpreted as a command, a
  capability name or anything other than text to be compared.
- **A catalog entry whose description is missing at run time** — the entry is still listed and still
  filterable by its own text; it is simply not ranked, and no text is invented for it on the fly.
- **A catalog entry that is unavailable on this deployment** — unavailable entries stay unavailable
  and un-addable whether they were found by intent, by identifier, or by browsing.
- **Two operators searching the same deployment with the same sentence** — same answer, because
  nothing about an operator's session changes the corpus.
- **The similarity service configured but answering with an empty result for a sentence it clearly
  should have matched** — the palette shows today's behaviour and today's no-match message; it never
  falls back to showing entries in an order the product cannot justify.

## Requirements *(mandatory)*

### Functional Requirements

**Searching by intent**

- **FR-001**: The palette's existing search box MUST accept an operator's plain-language sentence
  about a maintenance job and MUST offer the declared catalog entries closest to that sentence.
- **FR-002**: When the palette offers entries for a query, the entries closest to the query MUST be
  shown before the entries that are further from it, and the order MUST be stable for the same
  query — the palette MUST NOT reshuffle between two queries that produce the same ranking.
- **FR-003**: The palette MUST present the entries closest to the query as a distinguishable leading
  group, and MUST present the remaining entries in today's order and today's category grouping
  beneath it, omitting from that lower part any entry already shown as a suggestion.
- **FR-004**: A search MUST only re-order what the palette already shows. It MUST NOT insert a step,
  select a step, place a step on the canvas, or modify the flow in any way.
- **FR-005**: An empty or whitespace-only query MUST produce today's palette exactly — no suggestion
  group, no re-ordering, and no request to the similarity service.
- **FR-006**: Today's substring behaviour MUST be preserved: an entry whose identifier, label or
  implementation class name contains the typed text MUST be shown, and today's no-match message MUST
  be shown when no entry matches that text.
- **FR-007**: When the typed text also matches an entry's identifier, label or class name, that entry
  MUST be shown ahead of entries that match only by similarity, and today's narrowing MUST remain
  available to the operator for the same query.
- **FR-008**: The system MUST apply a minimum relevance below which similarity contributes nothing, and
  MUST fall back to today's behaviour in that case rather than showing a ranked list of every entry.
- **FR-009**: The system MUST show the operator the re-ordered palette within one second of the last
  keystroke, and MUST discard any ranking that arrives after a keystroke typed more recently.
- **FR-010**: The text the operator typed MUST be sent only to the configured similarity service, MUST
  NOT be retained as a searchable record of operator intent, and — in the shipped default
  configuration — MUST NOT leave the host.
- **FR-011**: The setting that identifies the similarity service MUST be configuration, and the
  shipped default configuration MUST be a service that runs on the same host, so that the feature
  costs nothing to run.
- **FR-012**: Documentation MUST state how to point the setting at a different similarity service,
  and MUST state that a hosted service means the operator's query text leaves the machine.

**The closed catalog as the only corpus**

- **FR-013**: The searchable corpus MUST be the declared catalog and nothing else. The system MUST
  NOT introduce a second list, table or source of searchable capabilities.
- **FR-014**: Every entry in the declared catalog MUST carry a hand-written prose description of what
  the capability is for, held in the entry itself, and the description MUST NOT be derived from a
  class name, a file name, a parameter, or any other source outside the entry's own reviewed text.
- **FR-015**: A catalog entry with an empty description MUST be rejected by the change process; a
  capability MUST NOT be addable by any route that skips the description.
- **FR-016**: Adding a capability MUST remain a catalog entry plus the capability it names, reviewed
  in a pull request. No registration call, index build, migration, setting or second list may be
  required for a new entry to become searchable.
- **FR-017**: A change to a catalog entry — added, removed or reworded — MUST be reflected in search
  results with no manual step.
- **FR-018**: Search MUST NOT read the implementation class name recorded against a legacy custom
  entry on any path, including the path that builds the corpus or the path that ranks results.
- **FR-019**: Search MUST NOT generate, paraphrase, summarise or complete any text. The operator sees
  only the reviewed text of declared catalog entries, and every entry shown MUST correspond to a
  declared catalog entry.
- **FR-020**: Search MUST NOT construct a step, a flow, or any executable content from the operator's
  query. The query is text to be compared, never an instruction.
- **FR-021**: Entries that are unavailable on this deployment MUST remain unavailable and un-addable
  when they are found by intent rather than by browsing.

**Degrading as a value**

- **FR-022**: The similarity service being unconfigured, unreachable, slow, or incompatible with the
  stored corpus MUST produce a typed outcome that crosses layers as a value, and MUST NOT produce an
  exception, an unhandled failure, or a change in what the palette shows the operator.
- **FR-023**: When search is unavailable, the palette MUST behave exactly as it does today: entries
  narrowed by the operator's own text, today's grouping, today's no-match message, and no error text
  in place of the list.
- **FR-024**: The reason search was unavailable MUST be recorded so that it can be diagnosed by an
  operator or engineer, and MUST NOT interrupt the operator's typing or replace the palette contents.
- **FR-025**: No search result may ever be ranked against something it cannot be meaningfully
  compared to; a comparison that cannot be made MUST be treated as search being unavailable
  (FR-023), not as a poor match.
- **FR-026**: A working search and a degraded search MUST be indistinguishable from the palette's own
  behaviour, so that the operator's workflow is identical in both cases.

**Out of scope for this feature**

- **FR-027**: No approximate-nearest-neighbour index over the catalog corpus is created in this
  feature. The Plan MUST record it as a later optimization together with the corpus size at which it
  would be justified, and MUST state that an exact comparison over the current corpus needs no such
  index.
- **FR-028**: This feature MUST NOT change validation, dispatch, scheduling, or confirmations, and
  MUST NOT change the behaviour of any step, the platform's own refusals, or the authorization
  decisions delegated to the platform (Constitution III).
- **FR-029**: This feature MUST NOT vectorize the task catalog, run history, or flow documents. The
  other vector-search applications considered and not built remain recorded, with their friction, in
  `docs/vector-search-proposals.md` as candidates for their own specifications.
- **FR-030**: No language model and no generated text may be used anywhere in this feature.

### Key Entities

- **Catalog entry** — one declared capability in the closed catalog: its identifier, label, category,
  whether it is available, and whether it is destructive or pausable. The only thing a search may
  ever return, and reached only through the catalog's own accessor.
- **Catalog description** — a new, hand-written prose sentence per entry, held in the entry itself,
  stating what the capability is for. The searchable text. Never derived, never generated, never
  cached separately from the entry.
- **Searchable corpus** — the set of every catalog entry's description, used for comparison. Derived
  from the catalog at the moment it is needed, never maintained as a second list.
- **Similarity service** — the configurable external capability that turns text into a comparable
  form. Reached only through configuration; its identity is never hardcoded into the product's core,
  and the product's core names no platform or vendor.
- **Search outcome** — the value that crosses every layer in place of a failure: either a ranked set
  of catalog entries, or a typed reason search is unavailable (not configured, unreachable, too slow,
  incompatible). Carries no exception and no partially ranked set.
- **Palette suggestion group** — the leading, ordered group of entries closest to the operator's
  query, plus the untouched remainder of today's palette beneath it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a fixed set of 10 operator intent phrases — including "free up disk space", "check
  my globals are sound", "get rid of old audit records" and "rotate the journal" — the intended
  catalog entry appears within the first three entries shown in at least 9 of 10 attempts, with the
  operator doing nothing but reading the palette.
- **SC-002**: In a usability run with 5 operators who do not know the entry names, at least 90% find
  the step type they need on their first search attempt, and none of them need to learn a new
  interaction to add it.
- **SC-003**: In 20 consecutive search attempts on the development stack, the operator sees the
  ranked palette within one second of the last keystroke in at least 19 of 20, and in 20 consecutive
  attempts the palette never re-orders in response to a keystroke that is no longer the operator's
  latest.
- **SC-004**: With the similarity service unconfigured, unreachable, slow, or incompatible, 20 out of
  20 attempts show the palette narrowing by entry text exactly as today, with zero error states, zero
  disabled entries, zero lost keystrokes, and today's no-match message where today shows it.
- **SC-005**: Across 100 search attempts — including nonsense sentences, sentences naming an
  implementation class, and sentences describing a capability that does not exist — 100% of entries
  shown are declared catalog entries, and zero undeclared capabilities are reachable.
- **SC-006**: With the similarity service usable, 0% of strings presented to the operator as a step
  type come from any source other than the reviewed text of a declared catalog entry.
- **SC-007**: Adding a capability requires a catalog entry plus the capability it names, and nothing
  else: in a run of 3 new capabilities, each becomes findable by intent with 0 registration steps, 0
  index builds, 0 configuration changes, and 0 second lists of capabilities created.
- **SC-008**: In the shipped default configuration, 100% of searches are answered without any query
  text leaving the host, verified by observing traffic on the host's only external interface.
- **SC-009**: A catalog entry whose description is removed is rejected before merge — 0 entries
  without a reviewed description exist in the catalog, and the legacy custom entry's implementation
  class name is read on 0 search paths.
- **SC-010**: An operator who types an exact identifier today finds exactly the same entries as
  before this feature, in 20 of 20 attempts, including the case where the same text also matches
  semantically.

## Assumptions

- The declared catalog remains the single, enumerable set of capabilities, and this feature adds no
  way to extend it at run time (Constitution II). A search result is a re-ordering of that set and
  nothing else.
- Every existing catalog entry gains a reviewed prose description as part of this feature, written
  by the engineer adding or owning the entry, in the same review as the entry.
- The similarity service is reached only through configuration, and the shipped default runs on the
  same host as the product and costs nothing to run. A deployment that configures a different
  service accepts the trade-off that query text leaves the machine, and the documentation says so.
- The corpus is small — the catalog has nine entries today, and the exact comparison over a corpus
  of that size needs no approximate-nearest-neighbour index. Creating one is out of scope; the Plan
  records it as a later optimization above a stated row count.
- The corpus is derived from the catalog whenever it is needed, so it cannot drift from the catalog.
  The Plan resolves the mechanism; the observable consequence — a catalog change reflected with no
  manual step — is fixed here.
- The platform this product runs on already offers vector types, a cosine comparison, an embedding
  configuration table and HNSW indexing. These are verified platform facts the Plan builds on; they
  are not requirements of this specification and no particular one of them is mandated here.
- The similarity service may be absent, slow, or incompatible in normal operation, so the degraded
  path is a supported state, not an error case to be reported and forgotten.
- Search never changes an authorization decision. The platform's refusal of any operation passes
  through unmodified, and this feature neither caches nor infers permission outcomes
  (Constitution III).
- The other vector-search applications considered and not built are recorded with their friction in
  `docs/vector-search-proposals.md`. They are candidates for their own specifications, not part of
  this one.
- No language model, no generated text, no step or flow constructed from a sentence, and no change to
  validation, dispatch, scheduling or confirmations is in scope. Vectorizing the task catalog, run
  history or flow documents is out of scope. All user-facing text is in English.
