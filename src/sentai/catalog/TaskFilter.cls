/// In-memory filters over the corrected catalog task (spec 006 FR-007, data-model §Filters).
/// Parameters are data, validated against closed value sets and compared with values; nothing is
/// built from them (Constitution II). A value that is unavailable or unknown never satisfies a
/// filter about it.
Class sentai.catalog.TaskFilter Extends %RegisteredObject
{

ClassMethod Validate(q As %String, namespace As %String, filter As %String, destructiveOnly As %String, Output problem As %String) As %Boolean
{
    Set problem = ""
    If '$LISTFIND($LB("all", "scheduled", "suspended"), filter) {
        Set problem = "INVALID_FILTER: filter must be one of all, scheduled, suspended"
        Quit 0
    }
    If '$LISTFIND($LB("0", "1", "true", "false"), destructiveOnly) {
        Set problem = "INVALID_FILTER: destructiveOnly must be one of 0, 1, true, false"
        Quit 0
    }
    Quit 1
}

ClassMethod Matches(task As %DynamicObject, q As %String, namespace As %String, filter As %String, destructiveOnly As %String) As %Boolean
{
    If (q '= "") {
        Set needle = $ZCONVERT(q, "L")
        Set inName = ($ZCONVERT(task.name, "L") [ needle)
        Set inClass = task.%IsDefined("class") && ($ZCONVERT(task.class, "L") [ needle)
        If 'inName && 'inClass Quit 0
    }
    If (namespace '= "") && ($ZCONVERT(task.namespace, "U") '= $ZCONVERT(namespace, "U")) Quit 0
    If (filter = "scheduled") && '(task.%IsDefined("suspended") && 'task.suspended) Quit 0
    If (filter = "suspended") && '(task.%IsDefined("suspended") && task.suspended) Quit 0
    If ((destructiveOnly = "1") || (destructiveOnly = "true")) && 'task.destructive Quit 0
    Quit 1
}

}
