# Sanitation evidence — orphaned persistence artifacts (T071)

Procedure and tool: [`scripts/sanitation/ORPHAN-SANITATION.md`](../../scripts/sanitation/ORPHAN-SANITATION.md),
[`sentaiops.OrphanSanitation`](../../scripts/sanitation/sentaiops.OrphanSanitation.cls).

## Instance

- IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.2 (Build 221U), container
  `sentai-task-iris-1`, namespace `IRISAPP` (local dev instance)

## Pre-cleanup inventory — 2026-09-23 03:14:51 (read-only `Report()`)

Fingerprint for sign-off: **`137624262-527`**

| Class | Orphans | Rows in table | Attached to an existing flow | Orphan id range | Sample ids |
|---|---:|---:|---:|---|---|
| `sentai.model.Step` | 266 | 2609 | 2343 | 1–271 | 1, 2, 3, 4 … |
| `sentai.model.Edge` | 209 | 2053 | 1844 | 1–209 | 1, 2, 3, 4 … |
| `sentai.model.Join` | 52 | 511 | 459 | 1–52 | 1, 2, 3, 4 … |
| `sentai.model.Run` | 0 | | | | |
| `sentai.model.StepRun` | 0 | | | | |
| `sentai.model.LogEntry` | 0 | | | | |
| `^sentaiRun` registry | 0 | | | | |
| **Total** | **527** | | | | |

Independent cross-check (plain SQL, not the tool): orphans + attached = total rows for each of
Step (266 + 2343 = 2609), Edge (209 + 1844 = 2053) and Join (52 + 459 = 511).

Raw storage of a sample orphan — the reference slot is **empty**, not `0` (the "`flow = 0`" in earlier
notes came from how the query tool rendered it):

```
^sentai.model.StepD(1)=$lb("","","01","integrity-check","IC USER","USER","/opt/iris/mgr/user/","irisadm",90,"SENTAI.NIGHT","")
^sentai.model.StepD(1,"parameters")="{}"
^sentai.model.EdgeD(1)=$lb("","01","04","")
```

Profile of every orphan row, grouped by content — all of it matches what the unit-test suite wrote
before the reference-assignment fix (52 copies of the canonical fixture, the pre-fix
`SAMPLES`/`DOCBOOK` variant, plus the extra rows individual tests add); no operator data:

| Class | Content | Rows | Written by |
|---|---|---:|---|
| Step | `IC USER`, `IC SAMPLES`, `IC DOCBOOK` (integrity-check), `Purge audit`, `Switch journal` | 5 × 52 | `SentaiTestCase.CanonicalFlowPayload` |
| Step | `custom` steps `Custom` (4) / `Custom step` (2) | 6 | custom-step / schedule / dispatch / validate tests |
| Edge | 01→04, 02→04, 03→04, 04→05 | 4 × 52 | canonical fixture |
| Edge | 05→01 | 1 | `AcyclicityRuleTest` (injected cycle) |
| Join | target 04, `ALL_MUST_SUCCEED` | 52 | canonical fixture (fan-in join) |

## Dry run of the destructive path (no data changed)

- Backup writer on the real orphan set → `/tmp/sentai-orphans-dryrun.zwr` inside the container (removed afterwards): 795
  lines = 2 header + 532 Step nodes (266 rows × data + `parameters`) + 209 Edge + 52 Join.
- Round trip: all 793 node lines evaluate to exactly the live value (793 match, 0 mismatch).
- `Apply` guards, each refused with nothing written or deleted:
  - wrong fingerprint → "orphan set changed since it was reviewed …"
  - missing operator → "expectedFingerprint, backupFile and operator are all required"
  - existing backup file → "backup file already exists, refusing to overwrite …"
- Inventory after the dry run: unchanged (`137624262-527`, total 527).

## Cleanup (T072) — executed 2026-09-23 03:31:02

- sign-off: henryhamon approved fingerprint `137624262-527` (2026-09-23)
- command (runbook step 4, via `iris session` in `IRISAPP`):
  `Do ##class(sentaiops.OrphanSanitation).Apply("137624262-527", "/home/irisowner/dev/scripts/sanitation/backup-20260923.zwr", "henryhamon (approved 2026-09-23)")`
- result: `$$$OK`; fingerprint re-checked at apply time and matched (total 527)
- backup: `scripts/sanitation/backup-20260923.zwr` on the host checkout (git-ignored), 795 lines —
  same shape as the dry run (2 header + 532 Step + 209 Edge + 52 Join nodes)
- audit entry: `^sentaiOps("sanitation", 1)` (operator, time, backup path, before/after inventories)
- post-cleanup `Report()`: `total: 0` for every class and for `^sentaiRun` (fingerprint `3031748604-0`)
- independent SQL cross-check: `flow IS NULL` rows — Step 0, Edge 0, Join 0
- test suite rerun: 81/81 passed
