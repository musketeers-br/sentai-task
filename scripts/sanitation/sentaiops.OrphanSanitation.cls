/// Controlled sanitation of orphaned persistence artifacts written by pre-fix builds of
/// 003-backend-objectscript (plan.md §Data sanitation after persistence bug fixes, T071/T072).
/// 
/// Pre-fix code assigned raw ids to reference properties (e.g. `Set step.flow = flowId`), which
/// persisted the reference as 0 — rows attached to no flow/run at all. This class finds every
/// row whose reference does not resolve to an existing parent, plus ^sentaiRun registry entries
/// pointing at runs/step-runs that do not exist.
/// 
/// Operational tool only: lives outside the `sentai` package, is NOT part of the sentai-task
/// module, and is loaded by hand (see runbook ORPHAN-SANITATION.md next to this file).
/// 
///   Report()  read-only; prints counts, sample ids, and the fingerprint Apply() requires.
///   Apply()   deletes exactly the reviewed set: refuses unless the fingerprint still matches,
///             writes a ZWRITE-format backup of every row/node first, deletes in one
///             transaction, records an audit entry, and prints the after-counts.
Class sentaiops.OrphanSanitation Extends %RegisteredObject
{

/// Row-level rules, in deletion order (children before parents). Each piece is
/// class:reference property:parent class. A row is orphaned when its reference is empty or
/// names a parent row that does not exist — including a parent that is itself orphaned, since
/// that parent is deleted in the same pass.
Parameter RULES = "sentai.model.LogEntry:run:sentai.model.Run,sentai.model.StepRun:run:sentai.model.Run,sentai.model.Run:flow:sentai.model.Flow,sentai.model.Edge:flow:sentai.model.Flow,sentai.model.Join:flow:sentai.model.Flow,sentai.model.Step:flow:sentai.model.Flow";

Parameter SAMPLESIZE = 10;

/// Read-only. Prints the orphan inventory as JSON and returns it.
ClassMethod Report() As %DynamicObject
{
    Set report = ..Inventory(.ids)
    Write report.%ToJSON(), !
    Quit report
}

/// Deletes the orphan set whose fingerprint was reviewed from Report().
///   expectedFingerprint  the "fingerprint" value printed by Report() — the operator's sign-off
///   backupFile           server-side path for the ZWRITE-format backup (must not exist yet)
///   operator             who is running the cleanup (recorded in the audit entry)
ClassMethod Apply(expectedFingerprint As %String, backupFile As %String, operator As %String) As %Status
{
    If (expectedFingerprint = "") || (backupFile = "") || (operator = "") {
        Quit $$$ERROR($$$GeneralError, "expectedFingerprint, backupFile and operator are all required")
    }
    If ##class(%File).Exists(backupFile) {
        Quit $$$ERROR($$$GeneralError, "backup file already exists, refusing to overwrite: "_backupFile)
    }

    Set before = ..Inventory(.ids)
    If (before.fingerprint '= expectedFingerprint) {
        Quit $$$ERROR($$$GeneralError, "orphan set changed since it was reviewed (expected "_expectedFingerprint_", found "_before.fingerprint_"); run Report() again")
    }
    If (before.total = 0) {
        Write "Nothing to delete.", !
        Quit $$$OK
    }

    // 1. Backup: every storage node of every orphan row, plus every orphan registry node.
    Set sc = ..WriteBackup(.ids, before, backupFile, operator)
    If $$$ISERR(sc) Quit sc

    // 2. Delete the reviewed set, all or nothing.
    TSTART
    Try {
        For i = 1:1:$LENGTH(..#RULES, ",") {
            Set className = $PIECE($PIECE(..#RULES, ",", i), ":", 1)
            Set id = ""
            For {
                Set id = $ORDER(ids("row", className, id))
                Quit:(id = "")
                $$$ThrowOnError($CLASSMETHOD(className, "%DeleteId", id))
            }
        }
        Set ref = ""
        For {
            Set ref = $ORDER(ids("registry", ref))
            Quit:(ref = "")
            Kill @ref
        }
        TCOMMIT
    }
    Catch ex {
        TROLLBACK
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) Quit sc

    // 3. Evidence: after-counts and a durable audit entry.
    Set after = ..Inventory(.idsAfter)
    Set audit = {}
    Do audit.%Set("at", $ZDATETIME($HOROLOG, 3))
    Do audit.%Set("operator", operator)
    Do audit.%Set("namespace", $NAMESPACE)
    Do audit.%Set("backupFile", backupFile)
    Do audit.%Set("before", before)
    Do audit.%Set("after", after)
    Set ^sentaiOps("sanitation", $INCREMENT(^sentaiOps("sanitation"))) = audit.%ToJSON()
    Write audit.%ToJSON(), !
    Quit $$$OK
}

/// Computes the orphan set. `ids("row", className, id)` and `ids("registry", globalRef)` hold
/// the members; the returned object carries counts, samples, and the fingerprint.
ClassMethod Inventory(Output ids) As %DynamicObject
{
    Kill ids
    Set out = {}, counts = {}, samples = {}, total = 0, fingerprint = ""

    // Parents that are themselves orphaned are removed in the same pass, so children
    // must be judged against the surviving parents: evaluate parents first.
    For i = $LENGTH(..#RULES, ","):-1:1 {
        Set piece = $PIECE(..#RULES, ",", i)
        Set className = $PIECE(piece, ":", 1), refProp = $PIECE(piece, ":", 2), parentClass = $PIECE(piece, ":", 3)
        Set table = ..TableOf(className), parentTable = ..TableOf(parentClass)

        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID AS rowId, "_refProp_" AS ref FROM "_table_" c WHERE c."_refProp_" IS NULL OR NOT EXISTS (SELECT 1 FROM "_parentTable_" p WHERE p.%ID = c."_refProp_")")
        Set n = 0, sample = []
        While rs.%Next() {
            Set n = n + 1
            Set ids("row", className, rs.%Get("rowId")) = rs.%Get("ref")
            Do:(sample.%Size() < ..#SAMPLESIZE) sample.%Push({"id": (rs.%Get("rowId")), "ref": (rs.%Get("ref"))})
        }
        // Rows whose parent is valid today but orphaned itself (and so about to go).
        Set pid = ""
        For {
            Set pid = $ORDER(ids("row", parentClass, pid))
            Quit:(pid = "")
            Set rs2 = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID AS rowId FROM "_table_" WHERE "_refProp_" = ?", pid)
            While rs2.%Next() {
                Continue:$DATA(ids("row", className, rs2.%Get("rowId")))
                Set n = n + 1
                Set ids("row", className, rs2.%Get("rowId")) = pid
                Do:(sample.%Size() < ..#SAMPLESIZE) sample.%Push({"id": (rs2.%Get("rowId")), "ref": (pid), "via": "orphaned parent"})
            }
        }
        Do counts.%Set(className, n)
        Do samples.%Set(className, sample)
        Set total = total + n
        Set fingerprint = fingerprint_className_"="_n_"@"_$ORDER(ids("row", className, ""), -1)_";"
    }

    // ^sentaiRun registry: run entries and step-run index entries with no backing row.
    Set n = 0, sample = []
    Set key = ""
    For {
        Set key = $ORDER(^sentaiRun(key))
        Quit:(key = "")
        If (key = "idx") {
            Set srGuid = ""
            For {
                Set srGuid = $ORDER(^sentaiRun("idx", srGuid))
                Quit:(srGuid = "")
                Continue:(##class(sentai.model.StepRun).GuidIndexExists(srGuid, .srId) && '$DATA(ids("row", "sentai.model.StepRun", srId)))
                Set ref = $NAME(^sentaiRun("idx", srGuid)), ids("registry", ref) = "", n = n + 1
                Do:(sample.%Size() < ..#SAMPLESIZE) sample.%Push(ref)
            }
            Continue
        }
        Continue:($EXTRACT(key) = "%")
        Continue:(##class(sentai.model.Run).GuidIndexExists(key, .runId) && '$DATA(ids("row", "sentai.model.Run", runId)))
        Set ref = $NAME(^sentaiRun(key)), ids("registry", ref) = "", n = n + 1
        Do:(sample.%Size() < ..#SAMPLESIZE) sample.%Push(ref)
    }
    Do counts.%Set("^sentaiRun", n)
    Do samples.%Set("^sentaiRun", sample)
    Set total = total + n
    Set fingerprint = fingerprint_"^sentaiRun="_n_";"

    Do out.%Set("namespace", $NAMESPACE)
    Do out.%Set("at", $ZDATETIME($HOROLOG, 3))
    Do out.%Set("total", total)
    Do out.%Set("counts", counts)
    Do out.%Set("samples", samples)
    Do out.%Set("fingerprint", $ZCRC(fingerprint, 7)_"-"_total)
    Quit out
}

/// ZWRITE-format dump (one `^global(subs)=value` line per node) of every orphan row's data
/// nodes and every orphan registry subtree. Restorable line by line — see the runbook.
ClassMethod WriteBackup(ByRef ids, before As %DynamicObject, backupFile As %String, operator As %String) As %Status
{
    Set file = ##class(%Stream.FileCharacter).%New()
    Set sc = file.LinkToFile(backupFile)
    If $$$ISERR(sc) Quit sc
    Do file.WriteLine("; sentaiops.OrphanSanitation backup — "_$ZDATETIME($HOROLOG, 3)_" — "_operator_" — "_$NAMESPACE)
    Do file.WriteLine("; inventory: "_before.%ToJSON())

    Set className = ""
    For {
        Set className = $ORDER(ids("row", className))
        Quit:(className = "")
        Set dataLocation = ..DataLocationOf(className)
        Set id = ""
        For {
            Set id = $ORDER(ids("row", className, id))
            Quit:(id = "")
            Do ..DumpSubtree($NAME(@dataLocation@(id)), file)
        }
    }
    Set ref = ""
    For {
        Set ref = $ORDER(ids("registry", ref))
        Quit:(ref = "")
        Do ..DumpSubtree(ref, file)
    }
    Quit file.%Save()
}

ClassMethod DumpSubtree(root As %String, file As %Stream.FileCharacter)
{
    If ($DATA(@root) # 2) Do file.WriteLine(root_"="_##class(%Utility).FormatString(@root))
    Set ref = root
    For {
        Set ref = $QUERY(@ref)
        Quit:(ref = "")
        Quit:'..IsUnder(ref, root)
        Do file.WriteLine(ref_"="_##class(%Utility).FormatString(@ref))
    }
}

/// True if global reference `ref` is `root` itself or a descendant of it.
ClassMethod IsUnder(ref As %String, root As %String) As %Boolean
{
    If ($QSUBSCRIPT(ref, 0) '= $QSUBSCRIPT(root, 0)) Quit 0
    If ($QLENGTH(ref) < $QLENGTH(root)) Quit 0
    For i = 1:1:$QLENGTH(root) {
        If ($QSUBSCRIPT(ref, i) '= $QSUBSCRIPT(root, i)) Return 0
    }
    Quit 1
}

ClassMethod TableOf(className As %String) As %String
{
    Set def = ##class(%Dictionary.CompiledClass).%OpenId(className, 0)
    Quit def.SqlSchemaName_"."""_def.SqlTableName_""""
}

ClassMethod DataLocationOf(className As %String) As %String
{
    Set storage = ##class(%Dictionary.CompiledStorage).%OpenId(className_"||Default", 0)
    Quit storage.DataLocation
}

}
