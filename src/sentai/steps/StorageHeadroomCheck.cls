/// Declared step type `storage-headroom-check` (spec 005 FR-008a): read-only. Fails when any
/// location the instance writes to — every database directory the platform lists (R-9) and the
/// primary journal directory — has less free disk space than MinFreePercent. Free space is read
/// with Python's shutil.disk_usage inside the worker (R-3), under the operator's authority.
Class sentai.steps.StorageHeadroomCheck Extends %SYS.Task.Definition
{

Parameter TaskName = "Sentai storage headroom check";

/// Declared parameter `minFreePercent` (0–100, default 10).
Property MinFreePercent As %Numeric [ InitialExpression = 10 ];

/// JSON text: {"minFreePercent", "locations":[{"path","freePercent","ok"}]}.
Property Result As %String(MAXLEN = "");

Method OnTask() As %Status
{
    Set sc = ##class(sentai.steps.DatabaseSizeReport).Databases(.databases)
    Quit:$$$ISERR(sc) sc

    // Locations, de-duplicated, in the order the platform lists them; the journal last.
    Kill seen
    Set paths = []
    Set iter = databases.%GetIterator()
    While iter.%GetNext(.k, .db) {
        Continue:(db.directory = "")||$D(seen(db.directory))
        Set seen(db.directory) = ""
        Do paths.%Push(db.directory)
    }
    Set journal = ##class(%SYS.Journal.System).GetPrimaryDirectory()
    If (journal '= "") && '$D(seen(journal)) Do paths.%Push(journal)

    Set threshold = +..MinFreePercent, locations = [], problems = ""
    Set iter = paths.%GetIterator()
    While iter.%GetNext(.k, .path) {
        Set answer = ..DiskFree(path)
        If ($P(answer, " ") = "ok") {
            Set free = +$P(answer, " ", 2), ok = (free >= threshold)
            Do locations.%Push({"path": (path), "freePercent": (free), "ok": (ok)})
            Set:'ok problems = problems_$S(problems = "":"", 1:"; ")_"'"_path_"' has "_free_"% free, below the "_threshold_"% threshold"
        } Else {
            Do locations.%Push({"path": (path), "ok": false, "error": ($P(answer, " ", 2, *))})
            Set problems = problems_$S(problems = "":"", 1:"; ")_"'"_path_"' could not be read: "_$P(answer, " ", 2, *)
        }
    }
    // Make the booleans JSON booleans.
    Set iter = locations.%GetIterator()
    While iter.%GetNext(.k, .loc) {
        Do loc.%Set("ok", loc.ok, "boolean")
    }
    Set ..Result = {"minFreePercent": (threshold), "locations": (locations)}.%ToJSON()
    Quit:(problems '= "") $$$ERROR($$$GeneralError, "Storage headroom below "_threshold_"%: "_problems)
    Quit $$$OK
}

/// "ok <free%>" for a readable path, "error <Type>: <message>" otherwise — never raises.
ClassMethod DiskFree(path As %String) As %String [ Language = python ]
{
    import shutil
    try:
        usage = shutil.disk_usage(path)
        return "ok %.1f" % (usage.free * 100.0 / usage.total)
    except Exception as e:
        return "error %s: %s" % (type(e).__name__, e)
}

}
