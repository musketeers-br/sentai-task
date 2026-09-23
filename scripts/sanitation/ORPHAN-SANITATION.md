# Runbook — sanitation of orphaned persistence artifacts (003-backend-objectscript)

Operational follow-up to the reference-assignment bug fixed in 003 (`plan.md` §Data sanitation after
persistence bug fixes, tasks T071/T072). Not a product feature: the tool lives outside the `sentai`
package and is **not** part of the `sentai-task` ZPM module.

## What is an orphan

Pre-fix code assigned raw ids to reference properties (`Set step.flow = flowId`). IRIS stored an
**empty** reference (`$lb("",...)` in the data node, `NULL` in SQL — reported as "`flow = 0`" in
earlier notes, which was a display artifact of the query tool). Such rows belong to no flow/run.

`sentaiops.OrphanSanitation` treats as orphaned:

| Class | Orphan when |
|---|---|
| `sentai.model.Step`, `Edge`, `Join`, `Run` | `flow` is empty or names a `Flow` that does not exist |
| `sentai.model.StepRun`, `LogEntry` | `run` is empty, names a missing `Run`, or names an orphaned `Run` |
| `^sentaiRun(runGuid)` | no `Run` with that guid (or it is orphaned); `%`-prefixed keys are skipped |
| `^sentaiRun("idx", stepRunGuid)` | no `StepRun` with that guid (or it is orphaned) |

Rows attached to an existing flow are never touched — including flows left by test runs.

## Procedure

All commands run in the target namespace (IRISAPP in the dev container). `iris session` is used
because it is the most reliable channel; any terminal on the instance works the same way.

```bash
docker exec -it sentai-task-iris-1 iris session IRIS -U IRISAPP
```

1. **Load the tool** (not part of the module; source is mounted at `/home/irisowner/dev`):

   ```objectscript
   Do $SYSTEM.OBJ.Load("/home/irisowner/dev/scripts/sanitation/sentaiops.OrphanSanitation.cls", "ck")
   ```

2. **Report — read-only.** Prints counts per class, up to 10 sample ids each, and a `fingerprint`.

   ```objectscript
   Do ##class(sentaiops.OrphanSanitation).Report()
   ```

   Record the full JSON in the evidence note (`specs/003-backend-objectscript/sanitation-evidence.md`).
   Cross-check the counts independently before signing off, e.g.:

   ```sql
   SELECT COUNT(*) FROM sentai_model.Step c
    WHERE c.flow IS NULL OR NOT EXISTS (SELECT 1 FROM sentai_model.Flow p WHERE p.%ID = c.flow)
   ```

3. **Review and sign off.** A reviewer confirms the counts and samples are the pre-fix residue and
   nothing else. The sign-off is the `fingerprint` value from step 2.

4. **Apply — destructive, guarded.**

   ```objectscript
   Write $SYSTEM.Status.GetErrorText(##class(sentaiops.OrphanSanitation).Apply("<fingerprint>", "/home/irisowner/dev/scripts/sanitation/backup-<yyyymmdd>.zwr", "<operator>"))
   ```

   `Apply` refuses — changing nothing — when any argument is missing, when the backup file already
   exists, or when the orphan set no longer matches the reviewed fingerprint. Otherwise it:
   1. writes a ZWRITE-format backup of every data node of every orphan row and every orphan
      `^sentaiRun` subtree (`^global(subs)=value`, one node per line, after a two-line header);
   2. deletes the set in one transaction via `%DeleteId` (indices maintained) and `Kill`;
   3. stores an audit entry in `^sentaiOps("sanitation", n)` (operator, time, backup path, before
      and after inventories) and prints it.

   Writing the backup under `/home/irisowner/dev/...` puts it on the host checkout; do not commit it.

5. **Verify.** Run `Report()` again: `total` must be `0`. Record the after JSON and the audit entry
   (`zw ^sentaiOps("sanitation")`) in the evidence note, then rerun the test suite.

## Restore (only if the cleanup must be undone)

Every backup line is `globalRef=ZWRITE-value`. Split on the **first** `=` (subscripts in these
globals are numeric, `"parameters"`, or guids — none contain `=`), then:

```objectscript
Set f=##class(%Stream.FileCharacter).%New(),f.Filename="<backup file>"
While 'f.AtEnd { Set l=f.ReadLine() Continue:$E(l)'="^"  Set ref=$P(l,"=",1),val=$P(l,"=",2,*) X "Set "_ref_"="_val }
For c="sentai.model.Step","sentai.model.Edge","sentai.model.Join","sentai.model.Run","sentai.model.StepRun","sentai.model.LogEntry" { Do $CLASSMETHOD(c,"%BuildIndices") }
```

The same read loop, comparing instead of setting, was used to prove the backup format round-trips
(see the evidence note).
