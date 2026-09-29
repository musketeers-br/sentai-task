# Feature Specification: In-Process Embeddings for Step-Type Search

**Feature Branch**: `017-in-process-embeddings`

**Created**: 2026-09-29

**Status**: Implemented

**Status note**: 2026-09-29. 47/49 tasks; backend 395/395, frontend 216/216, `scripts/check-search-image.sh` 6/6, evidence in evidence/README.md. Open, both [external]: T043 (deploy on the demo VM) and T048 §7 (quickstart through a real `scripts/demo/up.sh`, done on the VM with T043).

**Input**: User description: "In-process embeddings for step-type search: replace the `ollama`
sidecar with sentence-transformers running inside the IRIS container. The operator-visible feature
of spec 011 (ranked palette within one second; degrade to today's palette otherwise) must stay
exactly as it is — only where the vectors come from changes. The corpus stays the catalog, the
provider stays a row in `%Embedding.Config` named `sentai-steps`, failures stay typed values, and
`git clone && docker compose up -d` still gives working semantic search with no manual step.
Explicitly out of scope: any change to the search API, the palette, the ranking, the catalog
descriptions or the degradation contract; GPU support; new vector applications; an ANN index."

## Context and Problem

1. **The default similarity service costs far more than the model it serves.** Spec 011 made the
   dev stack's default provider a separate `ollama` service holding `all-minilm`. The model is
   43.8 MB; the service image is 9.28 GB on disk (about 3.7 GB to download) because it carries GPU
   runtimes this stack never uses. A first `docker compose up -d` spends minutes on it, and every
   stack has a third container to keep healthy.
2. **The public demo does not run it.** `scripts/demo/up.sh` starts only the two instances and the
   proxy, while the image still installs a provider row that names the `ollama` host. On the demo,
   semantic search can only ever answer "not available" — the showcase for the feature is the one
   place it is guaranteed not to work.
3. **The same model can run inside the instance, and does it faster.** Measured on 2026-09-29 in the
   project's own image: the equivalent model (`all-MiniLM-L6-v2`, 384 dimensions) encodes a query in
   about 17 ms once loaded, against about 75 ms per call to the sidecar (spec 011 research R-004).
   Installed CPU-only it adds about 1.3 GB of packages and 88 MB of model to the image.
4. **Two traps sit on the obvious path.** (a) A plain package install pulls the GPU build of the
   numeric library: 5.4 GB measured, worse than the problem being solved. (b) The platform's own
   in-process provider class loads the model on *every* call; loading takes about 3.4 s in a fresh
   process, more than three times the one-second budget spec 011 promised the operator.
5. **Changing the provider is a silent correctness risk today.** The stored corpus is versioned by
   the catalog text alone. Two providers with the same vector length produce vectors from different
   models; after a switch, the stored vectors of the old model would be ranked against queries
   embedded by the new one, and nothing would say so.

## Objective

A developer or a demo visitor gets semantic step-type search from the stack as it comes up, with no
similarity sidecar to download or keep healthy, and the operator sees exactly the behaviour spec 011
defined — the same rankings for the same intents, within the same budget, degrading the same way —
with the guarantee that no ranking ever compares vectors produced by two different providers.

## Open Questions Answered Here

These are the questions the input asked this specification to answer rather than assume. They are
this specification's positions, recorded so they can be revisited through `/speckit.clarify`.

### Session 2026-09-29

**Q: (a) The platform's in-process provider class, or the product's own?**
→ A: The specification fixes the observable requirement, not the class: the in-instance provider
must meet spec 011's one-second budget (FR-004), including the first search a fresh server process
handles. The platform class reloads the model on every call (about 3.4 s measured), so the Plan
must either show it meeting FR-004 in the real instance, with numbers, or use a small provider of
the product's own that keeps the loaded model for the life of the process — selected, like every
provider, by the `sentai-steps` row and configured only through that row.

**Q: (b) Who pays the model load?**
→ A: Never the operator's keystroke beyond the budget. The provider is warmed when the instance
starts, so in the normal case the first search is already ranked (confirmed in Clarifications). A
search that still finds the provider not ready degrades as a value (`reason: "warming"`, the palette
behaves as today for that request) and a later search ranks normally. The Plan decides how the warm
state reaches every server process that answers searches. "Slow first search" is not an accepted
outcome.

**Q: (c) Corpus invalidation across providers?**
→ A: The stored corpus is valid only for the provider that produced it. Its version covers the
provider's identity (the configuration's name, its provider class and its model) as well as the
catalog text, so any change to either rebuilds the corpus before the next ranking (FR-007).

**Q: (d) Is the 0.20 relevance floor still right?**
→ A: It is re-measured, not assumed: the spec 011 intent queries are run against the new provider
and the floor is kept only if it still separates a good match from no match (SC-004). A changed
floor is recorded with its measurement.

**Q: (e) Build time or run time?**
→ A: Build time. Packages and model are part of the image; bringing the stack up and searching need
no network access. The image growth is stated against the removed sidecar (SC-001).

**Q: (f) What happens to the sidecar and to existing installs?**
→ A: The sidecar leaves the compose file entirely, with its model volume — no opt-in profile
(confirmed in Clarifications). The HTTP provider stays in the product and documented, so anyone who
wants a separate model server runs their own and points the row at it. An
existing install whose `sentai-steps` row is exactly the one the dev build wrote is moved to the
in-instance provider on the next build; any other row is the operator's choice and is never touched
(FR-010, FR-011).

**Q: (g) Does the target instance need any of this?**
→ A: No. Search runs on the primary instance only; the target image does not grow.

**Q: (h) Does the public demo get semantic search?**
→ A: Yes — that is a goal, not a side effect (User Story 4). The demo's image grows by the same
amount as the dev image; its bring-up no longer depends on a service it never started.

## Clarifications

### Session 2026-09-29

- Q: After this feature, should the `ollama` service leave `docker-compose.yml`, or stay behind an opt-in compose profile? → A: Remove it — the `ollama` service and the `ollama-models` volume leave the compose file; the README shows how to point the row at an `ollama` the operator runs themself.
- Q: On the first search after the instance starts, while the model is still loading, may the palette show unranked results, or must the first search always be ranked? → A: Warm the provider when the instance starts, before any operator searches; if it is still not ready when a search arrives, that search degrades as a typed value (`reason: "warming"`) and the palette behaves as today.
- Q: Should an IPM install (`zpm "install sentai-task"`) on an operator's own instance also set up the in-instance provider automatically, or only the dev and demo images? → A: Only the dev and demo images. The IPM install is unchanged: it installs no Python packages, downloads no model and writes no `sentai-steps` row; the README shows the packages and the one row that enable the in-instance provider.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Semantic search works from a plain bring-up, with no sidecar (Priority: P1)

A developer clones the repository and runs `docker compose up -d`. The stack that comes up has no
similarity service container, downloads no model at start-up, and the palette's intent search works
on the first try.

**Why this priority**: This is the reason for the change. Everything else protects what spec 011
already delivers.

**Independent Test**: From a machine with no project images, build and bring the stack up, list the
running services, then type the spec 011 intent sentences into the palette.

**Acceptance Scenarios**:

1. **Given** a fresh clone and no project images, **When** the developer runs
   `docker compose up -d`, **Then** no similarity-service container or image is pulled or started,
   and the running services are the two instances only.
2. **Given** the stack just came up with no outbound network access, **When** the operator types
   *free up disk space*, **Then** the palette ranks the catalog exactly as User Story 2 requires.
3. **Given** the stack is up, **When** the provider configuration is read, **Then** the row named
   `sentai-steps` names the in-instance provider and holds its model and cache location in its
   configuration, and nothing about the provider is written in code.

---

### User Story 2 - The operator sees exactly spec 011's search (Priority: P1)

The operator uses the palette's search box as before. The same intents bring the same step types to
the top, within the same budget, including the first search after the instance starts; when the
provider cannot answer in time, the palette behaves exactly as it does without semantic search.

**Why this priority**: Spec 011's contract is the product. A provider swap that changes what the
operator sees is a regression, however much faster the stack starts.

**Independent Test**: Run the spec 011 acceptance queries against the new provider on a freshly
started instance and again after warm-up; compare the top result of each with spec 011's evidence,
and time each from last keystroke to re-ordered palette.

**Acceptance Scenarios**:

1. **Given** an instance that has just finished starting, **When** the operator's first search is
   *free up disk space*, **Then** the ranked palette appears within one second of the last
   keystroke, because the provider was warmed at start-up.
2. **Given** a search that arrives while the provider is still warming, **When** it is answered,
   **Then** the answer is the typed "not available" value with reason `warming`, the palette behaves
   exactly as today for that search, and the next search after warm-up ranks normally.
3. **Given** a warm instance, **When** the operator types each of *free up disk space*, *check my
   globals are sound*, *get rid of old audit records* and *rotate the journal*, **Then** the top
   result for each is the step type spec 011's evidence records for it.
4. **Given** a query that matches nothing in the catalog, **When** it is searched, **Then** the
   palette shows today's no-match behaviour, as in spec 011.
5. **Given** the in-instance provider fails, **When** the operator searches, **Then** the answer is
   the typed "not available" value with a reason and the palette behaves exactly as today.

---

### User Story 3 - A provider change never mixes two models' vectors (Priority: P2)

An operator (or a build) changes the `sentai-steps` row to another provider or another model with
the same vector length. The next search rebuilds the stored corpus with the new provider before it
ranks anything.

**Why this priority**: Without this, the migration in User Story 5 — and any future provider change
— silently produces meaningless rankings that still look like results.

**Independent Test**: Build a corpus with one provider configuration, switch the row to a second
configuration of the same length, search, and inspect which provider produced the stored vectors.

**Acceptance Scenarios**:

1. **Given** a corpus built by provider A, **When** the row is changed to provider B with the same
   vector length and the operator searches, **Then** the corpus is rebuilt with B before ranking,
   and no ranking compares a B query to an A vector.
2. **Given** a corpus built by a model, **When** only the model named in the row changes, **Then**
   the corpus is rebuilt, as in scenario 1.
3. **Given** neither the catalog text nor the provider identity changed, **When** the operator
   searches, **Then** the corpus is not rebuilt.

---

### User Story 4 - The public demo offers semantic search (Priority: P2)

A visitor to the public demo types an intent into the palette and gets the same ranking a developer
gets locally.

**Why this priority**: The demo is where the feature is shown; today it is the one place the feature
cannot work.

**Independent Test**: Bring the demo up with `scripts/demo/up.sh` and search as a demo user.

**Acceptance Scenarios**:

1. **Given** the demo brought up by its own script, **When** a demo user types *rotate the
   journal*, **Then** the palette ranks the catalog as in User Story 2.
2. **Given** the demo, **When** its running services are listed, **Then** there is no
   similarity-service container.

---

### User Story 5 - Existing installs move over without losing an operator's choice (Priority: P3)

A developer with a stack built before this feature rebuilds it. If their provider row is the one
the old dev build wrote, it moves to the in-instance provider; if they configured their own row, it
stays exactly as they left it.

**Why this priority**: It only affects stacks that predate the feature, but getting it wrong either
leaves them pointing at a service that no longer exists, or overwrites a deliberate choice.

**Independent Test**: Seed the old dev-build row, rebuild, inspect; seed a custom row, rebuild,
inspect.

**Acceptance Scenarios**:

1. **Given** the `sentai-steps` row the previous dev build installed (the HTTP provider pointing at
   the `ollama` service), **When** the image is rebuilt and the stack comes up, **Then** the row
   names the in-instance provider and semantic search works.
2. **Given** a `sentai-steps` row the operator wrote themself, **When** the image is rebuilt,
   **Then** the row is unchanged.
3. **Given** a stack whose row still points at a similarity service that is not running, **When**
   the operator searches, **Then** the answer is the typed "not available" value and the palette
   behaves as today, as in spec 011.

### Edge Cases

- The model cache location is not writable, or sits on the read-only source mount: the provider
  reports a typed failure naming the cause; the palette behaves as today.
- Many server processes each handle their first search at once: each is either within the budget
  or degrades for that request; none blocks the others' searches beyond the budget.
- A catalog entry is added while the stack runs (a module load): the corpus is rebuilt with the
  current provider on the next search, as in spec 011.
- The image is built on a machine with no route to the package index or the model hub: the build
  fails loudly; it never produces an image whose search silently cannot work.
- The in-instance provider returns a vector of a different length from the row's declared length:
  the typed "wrong dimension" outcome of spec 011 applies.
- The module is installed through IPM into an instance without the provider's Python packages:
  nothing is installed or configured; search answers "not available" (`not-configured`) and the
  palette behaves as today, as in spec 011.
- The operator points the row at a hosted service: their query text leaves the machine, as spec 011
  documents; the default does not.

## Requirements *(mandatory)*

### Functional Requirements

**The in-instance provider**

- **FR-001**: The default similarity provider MUST run inside the primary instance; the compose
  file MUST NOT declare a similarity-service container or its model volume, in any profile.
- **FR-002**: The provider MUST be selected and configured only through the `sentai-steps` row of
  the platform's embedding configuration; model name, cache location and every other setting live in
  that row, never in code.
- **FR-003**: The packages and model the default provider needs MUST be part of the built image;
  bringing the stack up and searching MUST need no network access.
- **FR-003a**: Only the project's dev and demo images install the provider's packages and model and
  write the default row. Installing the module through IPM into an operator's own instance MUST NOT
  install Python packages, download a model or write a `sentai-steps` row; there, semantic search
  stays off until the operator adds the row, exactly as today.
- **FR-004**: Every search MUST re-order the palette within one second of the last keystroke, or
  degrade as a value so the palette behaves exactly as today; this includes the first search a
  freshly started server process handles.
- **FR-004a**: The provider MUST be warmed when the instance starts, before any operator search, so
  that the first search after start-up is ranked in the normal case. A search that finds the
  provider still warming MUST degrade with the typed reason `warming`.
- **FR-005**: The default provider MUST use the same model family and vector length (384) as spec
  011's default, so the spec 011 acceptance intents keep their top results (SC-003).
- **FR-006**: The image MUST NOT carry GPU runtimes for the provider.

**Corpus correctness**

- **FR-007**: The stored corpus MUST be valid only for the provider identity that produced it
  (configuration name, provider class and model) and the catalog text; a change to either MUST
  cause a rebuild before the next ranking.
- **FR-008**: The relevance floor MUST be re-measured against the new provider and kept or changed
  with its measurement recorded.

**Unchanged from spec 011 (restated as requirements of this feature)**

- **FR-009**: The corpus MUST remain the catalog, read only through its single reader; a result MUST
  never be a capability outside it (Constitution II).
- **FR-010**: An operator-written `sentai-steps` row MUST never be overwritten by a build or a load.
- **FR-011**: A `sentai-steps` row that is exactly the one a previous dev build installed MUST be
  moved to the in-instance provider on the next build.
- **FR-012**: Unconfigured, failing, slow, warming or wrong-dimension providers MUST produce a
  typed outcome with a reason, never an exception across layers (Constitution IV).
- **FR-013**: The HTTP provider (OpenAI-compatible) MUST remain available, and the README MUST show
  the one row that points it at a separate model server the operator runs, such as their own
  `ollama`.

**Documentation**

- **FR-014**: The README, `dev.md` and `AGENTS.md` MUST describe the in-instance default, how to
  switch provider with one row, the migration for existing stacks, that the target instance needs
  none of it, and — for IPM installs — the CPU-only package install and the row that enable the
  in-instance provider.

**Out of scope for this feature**

- **FR-015**: This feature MUST NOT change the search API, the palette, the ranking query, the
  catalog descriptions or the degradation contract.
- **FR-016**: This feature MUST NOT add GPU support, an approximate-nearest-neighbour index, or any
  new use of vectors.

### Key Entities

- **Provider configuration (`sentai-steps`)**: the one row that says which provider ranks step
  types — its class, model, cache location and vector length. Owned by the operator once they
  change it; the dev build only ever writes it when it is absent or is exactly the dev build's own.
- **Provider identity**: the part of the configuration that determines what a vector means —
  configuration name, provider class, model. Changing it invalidates the stored corpus.
- **Stored corpus**: one vector per catalog entry, valid for one catalog text and one provider
  identity, rebuilt on demand when either changes (spec 011).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first `docker compose up -d` from a clean machine downloads no similarity-service
  image; the images the stack needs total at least 5 GB less on disk than before this feature
  (today: 9.28 GB sidecar image removed, about 1.4 GB added to the primary image), and the
  measured numbers are recorded in `evidence/`.
- **SC-002**: The running dev stack has two containers, and the public demo has no
  similarity-service container.
- **SC-003**: The four spec 011 intents return the same top step type as spec 011's evidence, on a
  fresh and on a warm instance.
- **SC-004**: 19 of 20 searches re-order the palette within one second of the last keystroke or
  degrade to today's palette; none takes longer and still re-orders. The first search made once the
  instance reports started is ranked (not degraded) within one second in 5 of 5 fresh starts.
- **SC-005**: After switching the provider row between two configurations of equal vector length,
  zero rankings are computed from vectors of the previous configuration (verified by test).
- **SC-006**: The image carries zero GPU runtime packages for the provider.
- **SC-007**: The backend suite passes, including the new tests, which are written first.

## Assumptions

- The primary image's Embedded Python can install the provider's packages; this was measured on
  2026-09-29 (Ubuntu 24.04, Python 3.12.3, pip 24.0) and must be re-verified by the Plan.
- The model `all-MiniLM-L6-v2` is the one the previous default served as `all-minilm`, so rankings
  are expected to be close; SC-003 verifies rather than assumes it.
- Image size grows by roughly 1.4 GB; build time grows by roughly two to three minutes. Both are
  accepted in exchange for removing a 9.28 GB image and a container; the demo VM's disk is assumed to
  have room (to confirm in the Plan).
- The relevance floor 0.20 may need to change; FR-008 covers it.
