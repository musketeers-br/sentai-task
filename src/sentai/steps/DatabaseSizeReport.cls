/// Declared step type `db-size-report` (spec 005 FR-008b): read-only report of every database
/// the platform lists, with its size and the free space inside it (MB). Listed through the
/// platform's own query (%SYS.DatabaseQuery:FreeSpace, research.md R-9) under the authority of
/// the operator the worker runs as; a platform error is returned verbatim as the %Status.
Class sentai.steps.DatabaseSizeReport Extends %SYS.Task.Definition
{

Parameter TaskName = "Sentai database size report";

/// JSON text: {"databases":[{"name","directory","sizeMB","freeMB"}]}.
Property Result As %String(MAXLEN = "");

Method OnTask() As %Status
{
    Set sc = ..Databases(.databases)
    Quit:$$$ISERR(sc) sc
    Set ..Result = {"databases": (databases)}.%ToJSON()
    Quit $$$OK
}

/// Every database the platform reports, as [{"name","directory","sizeMB","freeMB"}].
/// Shared with sentai.steps.StorageHeadroomCheck.
ClassMethod Databases(Output databases As %DynamicArray) As %Status
{
    Set databases = []
    Set statement = ##class(%SQL.Statement).%New()
    Set sc = statement.%PrepareClassQuery("%SYS.DatabaseQuery", "FreeSpace")
    Quit:$$$ISERR(sc) sc
    Set rs = statement.%Execute("*")
    If (rs.%SQLCODE < 0) Quit $$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message)
    While rs.%Next(.sc) {
        Do databases.%Push({
            "name": (rs.%Get("DatabaseName")),
            "directory": (rs.%Get("Directory")),
            "sizeMB": (+rs.%Get("SizeInt")),
            "freeMB": (+rs.%Get("AvailableNum"))
        })
    }
    Quit sc
}

}
