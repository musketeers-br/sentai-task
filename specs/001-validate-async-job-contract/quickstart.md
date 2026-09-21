# Quickstart: validate-async-job-contract

**Feature**: 001-validate-async-job-contract
**Purpose**: Get a stranger from a clean checkout to a set of committed
evidence artifacts in one documented flow.

This document is the runbook a reader who has never touched the repo
follows. It is not a script.

## Prerequisites

Install these two tools on the host that will run the spike. They are
the only runtime dependencies the script has.

- `curl` (any recent version).
- `jq` (1.6 or later).

Verify:

```bash
curl --version
jq --version
```

The script refuses to start if either is missing.

You also need a running InterSystems IRIS Community instance reachable
from the host. The simplest path is a container:

```bash
docker run --rm -d \
  --name iris-spike \
  -p 52773:52773 \
  intersystemsdc/iris-community:latest
```

Wait for the container to finish initializing (typically 20–60 s on a
fresh pull). The management API is at `http://localhost:52773/api/`.

Capture the image's SHA256 digest — the spike will record it, but you
also want to know it out-of-band:

```bash
docker inspect --format='{{index .RepoDigests 0}}' iris-spike
```

## Set the operator environment

The script reads credentials from the environment. Do not commit these
values, and do not pass them on the command line.

```bash
export IRIS_BASE_URL="http://localhost:52773"
export IRIS_USER="<your operator username>"
export IRIS_PASSWORD="<your operator password>"
```

The `IRIS_BASE_URL` default matches the container command above; unset
it or export a different value if your instance is elsewhere.

## Run the spike

```bash
scripts/validate-async-job-contract/run-spike.sh
```

The script prints one line per captured interaction to stdout and one
summary line to stderr at exit. Nothing else. Total wall-clock is
typically well under two minutes on a freshly booted Community instance.

## Validation scenarios

After the run, every one of these MUST hold. Any failure is a bug in the
spike, not a discovery about the platform.

### V1 — All eleven files are present

```bash
ls specs/001-validate-async-job-contract/evidence/*.json | wc -l
```

Expected: at least the 14 files listed in
[research.md](research.md#r2-evidence-layout-on-disk) (calls 7 and 8 each
produce three; calls 10 produces two). The exact count depends on
whether the platform reported a distinct mid-flight state for call 7b.

### V2 — Every file parses as JSON and matches the envelope schema

```bash
for f in specs/001-validate-async-job-contract/evidence/*.json; do
  jq empty "$f" || echo "BROKEN: $f"
done
```

Expected: no `BROKEN:` lines.

The envelope shape itself is documented in
[contracts/evidence-envelope.md](contracts/evidence-envelope.md); a
downstream feature that wants strict validation can pass a JSON Schema
validator; the quickstart uses `jq empty` only as a fast smoke check.

### V3 — No unredacted secrets are on disk

```bash
grep -REn --include='*.json' \
  -e '"Authorization": *"[^<]' \
  -e '"password":' \
  -e '"token": *"[^<]' \
  -e '"refreshToken": *"[^<]' \
  -e '"accessToken": *"[^<]' \
  -e '"Set-Cookie": *"[^<]' \
  specs/001-validate-async-job-contract/evidence/ || echo "OK: no unredacted secrets found"
```

Expected: `OK: no unredacted secrets found`. Any match is a redaction
bug; do not commit the files. Also grep for the actual value of
`$IRIS_PASSWORD` — never as a printed argument on the command line —
to catch a mistake this heuristic list would miss.

### V4 — The compatibility statement answers all six questions

```bash
grep -Ec '^## Q[1-6] ' specs/001-validate-async-job-contract/compatibility.md
```

Expected: `6`.

### V5 — The decision cites evidence from Q3 and Q4

Open [decision.md](decision.md) after the run:

- It names exactly one of `delegate parallel execution to the platform`
  or `build execution engine inside the product`.
- It cites at least one path under `evidence/06-*` and one under
  `evidence/07*-*`.
- If the decision is "build inside the product", it names the follow-up
  action to reduce the planned scope of dependent features.

### V6 — A reader who did not run the spike can reconstruct each answer

This is the SC-003 acceptance criterion, and it is human-verified. Give
the committed artifacts to a colleague who was not in the room during
the run. Ask them to answer each of the six spec-level questions from
the committed files alone. If they can, the spike closes. If they
cannot, the compatibility statement is incomplete and must be updated
before the spike is marked done.

## Reruns

Simply re-run the script:

```bash
scripts/validate-async-job-contract/run-spike.sh
```

The script archives the prior run under
`evidence/.archive/<UTC-timestamp>/` and starts fresh. The new
`compatibility.md` records the archive path under
`## Prior-run archive`.

## Tearing down

```bash
docker stop iris-spike
unset IRIS_BASE_URL IRIS_USER IRIS_PASSWORD
```

The evidence files and the compatibility statement remain in the
working tree; commit them to close the spike.

## What this quickstart does not cover

- How the script is implemented internally — see [plan.md](plan.md) and
  [research.md](research.md).
- The exact JSON returned by the platform — that is the discovery the
  spike commits; read the resulting `evidence/*.json` files.
- Downstream feature design — out of scope. This spike answers what is
  possible; subsequent `/speckit-specify` invocations design against
  what it committed.
