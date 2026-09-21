# Research: validate-async-job-contract

**Feature**: 001-validate-async-job-contract
**Phase**: 0 (Outline & Research)
**Date**: 2026-09-20

## Purpose

Resolve every `NEEDS CLARIFICATION` from the specification and record the
technical decisions the plan depends on. Each entry names what was chosen,
why, and what was considered instead.

---

## R1. Target data platform identity

**Decision**: InterSystems IRIS, Community Edition, run as a container from
the official `intersystemsdc/iris-community` image (or an equivalent
container distribution of the Community edition), reached from the host at
the container's published HTTP port. The compatibility statement records
the exact version reported by the running instance (from a `/api/*` reply
carrying it, or from `%SYSTEM.Version.GetVersion()` observable via the
platform's own API) and the image's SHA256 digest.

**Rationale**: The endpoint paths supplied by the plan
(`/api/admin/login`, `/api/admin/v2/tasks`,
`/api/admin/v2/database-dir/integrity-check`,
`/api/admin/v2/async-result`, `/api/admin/v2/wqm-categories`) match the
InterSystems IRIS v2 management API surface. The `.iris-agentic-dev.toml`
in the repository root corroborates this. The Community edition is the
freely available edition the specification requires.

**Alternatives considered**:
- **A different data platform**: No other data platform exposes this
  combination of endpoint paths and terminology (WQM = Work Queue Manager,
  an IRIS-specific concept). Rejected on evidence.
- **A licensed edition**: The spec requires the freely available edition;
  a licensed edition may probe differently and any deviation is a separate
  spike per the assumptions in [spec.md](spec.md).

---

## R2. Evidence layout on disk

**Decision**: Under `specs/001-validate-async-job-contract/`:

```text
compatibility.md               # Compatibility statement (the answers)
decision.md                    # Execution-model decision (the consequence)
evidence/
  01-login.json                # POST /api/admin/login
  02-refresh.json              # POST /api/admin/refresh
  03-tasks-list.json           # GET  /api/admin/v2/tasks
  04-task-single.json          # GET  /api/admin/v2/task?id={id}
  05-task-info.json            # GET  /api/admin/v2/task/info?id={id}
  06-integrity-check-start.json  # POST /api/admin/v2/database-dir/integrity-check
  07a-async-result-first.json    # First status poll
  07b-async-result-midflight.json  # Mid-flight poll
  07c-async-result-settled.json    # Final poll
  08a-async-result-pause.json    # POST /api/admin/v2/async-result/pause
  08b-async-result-resume.json   # POST /api/admin/v2/async-result/resume
  08c-async-result-cancel.json   # POST /api/admin/v2/async-result/cancel
  09-wqm-categories.json       # GET  /api/admin/v2/wqm-categories
  10a-wqm-category-write.json  # PUT  /api/admin/v2/wqm-category
  10b-wqm-categories-verify.json  # GET  /api/admin/v2/wqm-categories (readback)
  11-chaining-probe.json       # Not a call — an analysis over 03/04/05
  .archive/                    # Prior runs archived here on rerun
    YYYYMMDD-HHMMSSZ/
      compatibility.md
      decision.md
      evidence/<files-from-prior-run>
```

**Rationale**:
- One file per interaction (per user instruction: "one evidence file each").
- Numeric prefixes preserve call ordering, so a reader can traverse the
  spike's chronology by directory listing.
- The compatibility statement and decision live at the feature root, not
  under `evidence/`, so they are trivially discoverable and cannot be
  confused with captured platform output.
- Prior runs are archived under `.archive/<UTC-timestamp>/` before a
  fresh run overwrites; the compatibility statement of the new run records
  the archive path. This satisfies the "second run must not silently
  overwrite prior evidence" constraint.

**Alternatives considered**:
- **One folder per interaction** (with `request.txt`, `response.json`,
  `meta.json`): rejected as heavier than the "one evidence file each"
  constraint asks for; the same information fits in one JSON envelope.
- **A single HAR file per run**: rejected because a reader would need a
  HAR viewer to inspect the answers, and downstream features would then
  parse a HAR to consume the contract — a heavier dependency than
  necessary.

---

## R3. Evidence envelope format

**Decision**: Each `NN-*.json` evidence file is a single JSON object with
the following top-level keys:

```json
{
  "call_id": "01-login",
  "captured_at": "2026-09-20T14:03:11Z",
  "platform": {
    "version": "IRIS for UNIX (…) 2025.1 (…)",
    "image_digest": "sha256:…"
  },
  "request": {
    "method": "POST",
    "url_path": "/api/admin/login",
    "query": {},
    "headers": { "Content-Type": "application/json", "Authorization": "<REDACTED>" },
    "body": { "…request body as sent, credential fields REDACTED…" }
  },
  "response": {
    "status": 200,
    "headers": { "Content-Type": "application/json", "Set-Cookie": "<REDACTED>" },
    "body": { "…response body verbatim, session tokens REDACTED…" }
  },
  "notes": []
}
```

**Rationale**: JSON is `jq`-parseable, human-readable, and self-describing.
The envelope carries enough context (call id, timestamp, platform version,
image digest) that any single file stands alone as evidence, which the
spec's SC-003 requires.

**Alternatives considered**:
- **Two files per call** (`request.txt` + `response.json`): rejected as
  heavier than needed; the JSON envelope is one file and covers both.
- **Raw curl `-v` transcript**: rejected because parsing free-form curl
  verbose output is fragile, and the redaction pass cannot inspect it
  structurally.

---

## R4. Redaction policy

**Decision**: Redaction is applied **before** any file is written to disk.
The capture path is:

1. `curl` writes response body and headers to file descriptors 3/4 (or an
   ephemeral file inside `$XDG_RUNTIME_DIR`/`mktemp` on a `tmpfs`).
2. A `jq` pass reads request body, request headers, response body, and
   response headers, and produces the envelope with the following values
   replaced literally by the string `<REDACTED>`:
   - Every request header named `Authorization` (any casing).
   - Every request body field whose path ends in `password`, `token`,
     `secret`, or `credential` (case-insensitive).
   - Every response header named `Set-Cookie` or matching
     `X-*-Token` / `Authorization`.
   - Every response body field whose path ends in `token`, `refreshToken`,
     `accessToken`, `sessionId`, or `csrf`.
3. The envelope is written to its final path with `install -m 0644`.

An unredacted body never touches a persistent path. The temp file used
between (1) and (2) lives on tmpfs and is unlinked before (3) returns.

**Rationale**: The repository is public. A cleanup pass would leave a
window during which an unredacted file exists on disk; the constraint
forbids that.

**Alternatives considered**:
- **Post-hoc redaction**: rejected; violates the "unredacted file must
  never exist on disk" constraint.
- **Redaction by regex over the raw response body**: rejected as
  brittle — JSON escaping, key ordering, and nested structure will
  eventually break a regex. `jq` operates on parsed structure.

---

## R5. Session lifecycle and rerun safety

**Decision**:

- **Login**: `POST /api/admin/login`. The captured evidence is
  `01-login.json`. The session token is extracted into a Bash variable
  (`$SESSION_TOKEN`) and never printed, echoed, or written to disk.
- **Refresh**: `POST /api/admin/refresh` is called once between (2) and
  (3) to capture the refresh envelope shape; the resulting token replaces
  `$SESSION_TOKEN`.
- **Job cleanup**: any accepted-for-processing job identifier the script
  holds is cancelled via `POST /api/admin/v2/async-result/cancel` in a
  trap on `EXIT`, unless it is already observed to have settled.
- **Prior evidence**: on entry, if `evidence/` is non-empty, the script
  moves it to `evidence/.archive/<UTC-timestamp>/` and writes a
  compatibility-statement entry naming the archive path.

**Rationale**: The constraints demand "not leave a job running" and "not
silently overwrite prior evidence". Both are wired into the script's
lifecycle rather than relying on operator discipline.

**Alternatives considered**:
- **Refuse to overwrite prior evidence**: rejected because an operator
  running a second sanity check should not be forced to hand-manage the
  filesystem; archiving preserves both prior and new evidence.
- **Best-effort cleanup only**: rejected; the constraint is absolute.

---

## R6. Async polling

**Decision**: `GET /api/admin/v2/async-result` is polled at a **1 s**
interval with a **120 s** bounded timeout. Three responses are captured:

- **First**: the very first poll (`07a-async-result-first.json`).
- **Mid-flight**: the first response after the first that reports the job
  as not yet settled and differs from the first (`07b-async-result-midflight.json`);
  if every response is identical until settle, this file records the last
  non-settled response.
- **Settled**: the first response reporting a terminal state, or the last
  response captured before the timeout, whichever comes first
  (`07c-async-result-settled.json`).

Both the interval and the timeout are recorded in `compatibility.md` under
question 4.

**Rationale**: Fixed values (not adaptive backoff) keep the evidence
reproducible. A 120 s ceiling is long enough for `integrity-check` on a
freshly created Community instance's databases and short enough that a
stalled probe fails fast.

**Alternatives considered**:
- **Exponential backoff**: rejected — the goal is contract capture, not
  production polling ergonomics; a variable cadence makes evidence harder
  to interpret.
- **No timeout**: rejected — a stalled job would hang the run.

---

## R7. Chaining-identifier probe (call 11)

**Decision**: Call 11 is not a network call but a `jq` analysis over the
already-captured `03-tasks-list.json`, `04-task-single.json`, and
`05-task-info.json`. The probe searches every leaf field for a value that:

- looks like a globally unique identifier (UUID, GUID, or IRIS
  `%Library.ObjectIdentity`), **and**
- is unique to a single task within `03-tasks-list.json` (i.e. not a
  category name, not a type slug, not a static enum).

If a field is found, `11-chaining-probe.json` records the field name and
JSON path (dot-notation) in each of the three source files, plus one
example value (redacted if it looks credential-shaped). If no such field
is found, `11-chaining-probe.json` records `"found": false`, the list of
every field inspected, and the reason each was rejected.

**Rationale**: The published contract omits response schemas, so this
question can only be answered by inspecting what was actually returned.
Doing the analysis in `jq` over already-captured evidence, rather than
running a new probe, means the answer is reproducible from the committed
files alone (SC-003).

**Alternatives considered**:
- **A separate `/api/admin/v2/task/dependencies` probe**: rejected —
  no such endpoint is documented, and inventing endpoint names would
  violate Constitution Principle II (closed capability set).

---

## R8. Prerequisite handling and preflight

**Decision**: The script preflights, in order:

1. `command -v curl` and `command -v jq`; missing either aborts with a
   one-line message naming what to install and stops before touching
   the network.
2. `${IRIS_BASE_URL}` is set (defaults to `http://localhost:52773` when
   unset, matching the container image's default published port).
3. `${IRIS_USER}` and `${IRIS_PASSWORD}` are set in the environment (never
   read from files or command-line arguments — the repository is public).
4. A `curl` HEAD against `${IRIS_BASE_URL}/api/` returns a routable
   response (any HTTP status, including 401); a connection error aborts
   the run.
5. Any pre-existing `evidence/` is moved to `evidence/.archive/<UTC>/`.

**Rationale**: Preflight failures cost nothing; a run that gets halfway
before it discovers a missing dependency has wasted operator time and
produced ambiguous partial evidence.

**Alternatives considered**:
- **Prompt for credentials at runtime**: rejected — even a prompt reads
  into shell state that can be captured by traces; environment variables
  are equally safe and cleaner to redact.

---

## Summary of resolved NEEDS CLARIFICATION

| Marker (from spec)                              | Resolved by | Section |
|-------------------------------------------------|-------------|---------|
| Target data platform, edition, version constraint | R1        | above   |
| Evidence layout under the feature directory     | R2, R3      | above   |

Both spec-level clarifications are closed. The spec's Assumptions section
has been updated in place to record the resolutions.
