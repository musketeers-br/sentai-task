# Contract: `run-spike.sh` — Operator CLI

**Feature**: 001-validate-async-job-contract
**Artifact**: `scripts/validate-async-job-contract/run-spike.sh`

This document is the contract between the operator and the probe script.
It is deliberately narrow: the script's only external surface is its
environment, its exit code, and the files it writes.

## Invocation

```bash
scripts/validate-async-job-contract/run-spike.sh
```

The script takes **no command-line arguments**. Every operator-supplied
value comes from the environment.

## Required environment

| Variable          | Purpose                                                                                 | Default                     |
|-------------------|-----------------------------------------------------------------------------------------|-----------------------------|
| `IRIS_BASE_URL`   | Base URL of the running IRIS Community container's management port.                     | `http://localhost:52773`    |
| `IRIS_USER`       | Username for `POST /api/admin/login`. Never read from a file or CLI argument.           | *(required — no default)*   |
| `IRIS_PASSWORD`   | Password for `POST /api/admin/login`. Never read from a file or CLI argument.           | *(required — no default)*   |

**Never** committed to the repository. The script refuses to start if
`IRIS_USER` or `IRIS_PASSWORD` are unset.

## Prerequisites

The script preflights, in order. Any failure aborts before the network
is touched:

1. `curl` is on `$PATH`.
2. `jq` is on `$PATH`.
3. `IRIS_USER` and `IRIS_PASSWORD` are set and non-empty.
4. `${IRIS_BASE_URL}/api/` returns any HTTP response (i.e. is routable);
   a connection error aborts.

Missing prerequisite messages name exactly what is missing and how to
install it. No other diagnostic text is emitted to stdout by default.

## Filesystem effects

The script writes only under
`specs/001-validate-async-job-contract/`:

- **Evidence files** — `evidence/NN-<slug>.json`, one per captured
  interaction, per the layout in [research.md](../research.md#r2-evidence-layout-on-disk).
- **Compatibility statement** — `compatibility.md` at the feature root.
- **Execution-model decision** — `decision.md` at the feature root.
- **Prior-run archive** — on rerun, prior `evidence/*.json`,
  `compatibility.md`, and `decision.md` are moved into
  `evidence/.archive/<UTC-timestamp>/` before any new file is written.

The script writes nowhere else on disk.

## Exit codes

| Code | Meaning                                                                                                   |
|------|-----------------------------------------------------------------------------------------------------------|
| 0    | Every one of the eleven calls captured a file, and `compatibility.md` and `decision.md` were written.     |
| 2    | Preflight failure (missing tool, missing env, unreachable base URL). No file was written.                 |
| 3    | Login (call 1) failed. `01-login.json` captured the failure; no other file was written.                   |
| 4    | A subsequent capture failed. The compatibility statement records the failure as an open risk; a job that was accepted is cancelled before exit. |
| 5    | Rerun-safety failure — prior evidence could not be archived. Nothing was written for the new run.         |
| 130  | Interrupted by SIGINT. Any accepted job is cancelled in the trap before exit.                             |

Exit codes 4 and 130 are the two paths where the script exits non-zero
but still leaves useful evidence on disk. In those cases the compatibility
statement's `## Open risks` section records what did not close.

## Standard streams

- **stdout**: One line per call, of the form
  `NN-<slug> <HTTP-status> <captured-path>`. Nothing else.
- **stderr**: Preflight messages, redaction warnings if the platform
  returns an unfamiliar credential-shaped field, and one summary line at
  exit.

No secrets are printed to either stream at any point. In particular, the
session token is stored only in a Bash variable and is passed to `curl`
via `--header @-` reading a here-string, not via a command-line argument
that would appear in `ps`.

## Signals

- **SIGINT / SIGTERM**: the `EXIT` trap runs. If the script holds an
  accepted job identifier, it issues one `POST
  /api/admin/v2/async-result/cancel` before exiting with code 130.
- Ignored: all other signals default.

## Reruns

A rerun is idempotent in outcome: given the same environment, it produces
a fresh set of evidence files at the same paths. Prior evidence is
preserved under `evidence/.archive/<UTC-timestamp>/`, and the new run's
`compatibility.md` cites the archive path.

## What the script does not do

- It does not read from stdin.
- It does not open a network port.
- It does not write to `/tmp`, `~/`, `/var/`, or any location outside
  this feature's directory.
- It does not launch a background process that survives the invocation.
- It does not install anything.
