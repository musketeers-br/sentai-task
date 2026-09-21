# Data Model: validate-async-job-contract

**Feature**: 001-validate-async-job-contract
**Phase**: 1 (Design & Contracts)
**Date**: 2026-09-20

## Note on scope

This spike produces evidence, not product state. The entities below
describe the artifacts the spike commits to disk and the internal
structure of the evidence envelope. There is no product database, no
ORM, and no runtime domain model here. Downstream features will model
platform tasks, jobs, and worker categories against this spike's
evidence; that modeling belongs to those features' plans.

---

## Entity: Evidence File

**Purpose**: One captured platform interaction, self-contained.

**Location**: `specs/001-validate-async-job-contract/evidence/NN-<slug>.json`

**Fields**:

| Field                | Type    | Required | Description                                                                                       |
|----------------------|---------|----------|---------------------------------------------------------------------------------------------------|
| `call_id`            | string  | yes      | Matches the file's `NN-<slug>` name.                                                              |
| `captured_at`        | string  | yes      | ISO-8601 UTC timestamp, precision seconds, suffix `Z`.                                            |
| `platform.version`   | string  | yes      | Platform version string, exactly as reported by the platform's own reply.                         |
| `platform.image_digest` | string | no    | The image's SHA256 digest (`sha256:…`), read from the container runtime, not from operator memory. |
| `request.method`     | string  | yes      | Upper-case HTTP verb.                                                                              |
| `request.url_path`   | string  | yes      | Path only, starting with `/`. No scheme, no host, no query.                                       |
| `request.query`      | object  | yes      | Query parameters as a flat map (empty `{}` if none). Values with credential-shaped keys are `<REDACTED>`. |
| `request.headers`    | object  | yes      | Request headers as sent. `Authorization` is always `<REDACTED>`.                                  |
| `request.body`       | any     | when applicable | Request body as sent. Fields with credential-shaped names are `<REDACTED>`. Absent for GET.  |
| `response.status`    | integer | yes      | HTTP status code from the platform.                                                                |
| `response.headers`   | object  | yes      | Response headers verbatim. `Set-Cookie` and token-shaped headers are `<REDACTED>`.                |
| `response.body`      | any     | yes      | Response body verbatim, credential-shaped fields `<REDACTED>`. `null` if empty.                   |
| `notes`              | array   | yes      | Free-text strings the script emits when a deviation from the published contract is observed. Never contains a session token, credential, or other secret. |

**Validation rules**:
- Every field marked required MUST be present and non-null.
- `call_id` MUST match `^[0-9]{2}[a-z]?-[a-z0-9-]+$`.
- `captured_at` MUST parse as ISO-8601 UTC.
- `<REDACTED>` MUST appear verbatim, as an exact string sentinel, wherever
  a value has been redacted. Any other placeholder is a bug.
- The file MUST parse as JSON (`jq empty file.json` returns 0).
- The file MUST NOT contain the operator's actual credentials or session
  tokens (see acceptance criterion SC-006).

**State**: An Evidence File is written once and not modified in place. On
rerun, the prior file is moved into `.archive/`, not overwritten.

---

## Entity: Compatibility Statement

**Purpose**: The prose document that answers each of the six spec-level
questions, cites the evidence supporting each answer, and records the
exact platform version and image digest exercised.

**Location**: `specs/001-validate-async-job-contract/compatibility.md`

**Required sections** (headings, in order):

1. `# Compatibility Statement`
2. `## Environment` — platform version, image digest, run timestamp, base URL.
3. `## Q1 — Reachability and authentication` — answer, evidence pointers, deviations.
4. `## Q2 — Response shapes` — answer per read (list, single, info), evidence pointers, absent-vs-present identifier fields.
5. `## Q3 — Long-running operations` — answer, evidence pointer to `06-…`.
6. `## Q4 — Job observation and control` — answer per subquestion (state, failure reason, timings, pause, resume, cancel), evidence pointers per supported transition, explicit "not supported" entries otherwise.
7. `## Q5 — Resource ceilings` — read, write, read-back answers with evidence pointers.
8. `## Q6 — Task chaining identifier` — outcome (`found: true` with field/path, or `found: false` with fields inspected).
9. `## Deviations from the published contract` — every observed deviation, grouped by endpoint.
10. `## Open risks` — every question that could not be closed, with the dependent feature(s) it blocks.
11. `## Prior-run archive` — if a prior run was archived, the archive path.

**Validation rules**:
- Every one of Q1–Q6 MUST be present.
- Every answer MUST cite at least one evidence file by relative path.
- The Environment section MUST name the version and digest as strings the
  platform itself provided (see Evidence File `platform.*`), not as
  operator recollection.

---

## Entity: Execution-Model Decision

**Purpose**: One committed statement of which gate branch was taken and
what it means for downstream scope.

**Location**: `specs/001-validate-async-job-contract/decision.md`

**Required content**:

- **Decision**: exactly one of `delegate parallel execution to the platform`
  or `build execution engine inside the product`.
- **Rationale**: two to five sentences citing the evidence from Q3 and Q4
  by file path.
- **Consequence**: what the decision means for the planned scope of
  dependent features. If the decision is "build inside the product", the
  consequence MUST name that the planned scope is to be reduced and MUST
  list a follow-up action so the negative outcome produces a decision
  rather than a retry.

**Validation rules**:
- Exactly one decision string appears verbatim.
- At least one evidence path from `evidence/06-*` and one from
  `evidence/07*-*` is cited.

---

## Entity: Open Risk

**Purpose**: Records a question the spike could not close and names what
it blocks. Not a separate file — an entry under
`## Open risks` in the Compatibility Statement.

**Fields per entry**:

| Field                  | Type   | Required | Description                                                                 |
|------------------------|--------|----------|-----------------------------------------------------------------------------|
| Question number        | string | yes      | Q1..Q6.                                                                     |
| Reason not closed      | string | yes      | Concrete cause (e.g. "endpoint returned 501").                              |
| Evidence pointer       | string | yes      | The evidence file capturing the attempt, if any; otherwise `none captured`. |
| Dependent features     | list   | yes      | Named downstream features blocked by the open risk.                         |

---

## Entity: Prior-Run Archive

**Purpose**: Preserves prior evidence when the spike is rerun.

**Location**: `specs/001-validate-async-job-contract/evidence/.archive/<UTC-timestamp>/`

**Contents**: A verbatim copy of the prior run's `evidence/*.json` files,
plus `compatibility.md` and `decision.md` from that prior run.

**Timestamp format**: `YYYYMMDD-HHMMSSZ` — UTC, no separators, `Z`-suffixed.

**Validation rules**:
- The archive directory MUST be created before any file in `evidence/`
  is overwritten.
- The new run's `compatibility.md` MUST cite the archive path under
  `## Prior-run archive` when an archive was created.

---

## Relationships

```text
Compatibility Statement  ── cites ──▶  Evidence File (one-to-many)
Execution-Model Decision ── cites ──▶  Evidence File (one-to-many; at least
                                                      one from Q3 and one from Q4)
Compatibility Statement  ── lists ──▶  Open Risk (zero-to-many)
Prior-Run Archive        ── mirrors ▶  Evidence File + Compatibility + Decision (from a prior run)
```

No entity references anything outside this feature's directory.
