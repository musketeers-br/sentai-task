/// Spec 018 (plan D-1, data-model §1): the closed list of overview areas. An area id is the only
/// thing an overview request may name; it selects fixed platform reads written in code, never a
/// path taken from input (Constitution II). `stepType` is the catalog type an area becomes when it
/// is turned into a flow ("" = none; clarification Q4: the catalog is not changed).
Class sentai.overview.Areas Extends %RegisteredObject
{

XData Table [ MimeType = application/json ]
{
[
  { "id": "processes",    "group": "instance", "reading": true,  "stepType": "" },
  { "id": "locks",        "group": "instance", "reading": true,  "stepType": "" },
  { "id": "memory",       "group": "instance", "reading": true,  "stepType": "" },
  { "id": "activity",     "group": "instance", "reading": true,  "stepType": "" },
  { "id": "devices",      "group": "instance", "reading": true,  "stepType": "" },
  { "id": "licenses",     "group": "instance", "reading": true,  "stepType": "" },
  { "id": "web-sessions", "group": "instance", "reading": true,  "stepType": "" },
  { "id": "security",     "group": "report",   "reading": false, "stepType": "security-posture-report" },
  { "id": "web-apps",     "group": "report",   "reading": false, "stepType": "web-app-inventory" },
  { "id": "alerts",       "group": "report",   "reading": false, "stepType": "system-alerts-check" },
  { "id": "secrets",      "group": "report",   "reading": false, "stepType": "secrets-inventory" }
]
}

/// The 11 areas in display order — the sole reader of the XData block.
ClassMethod All() As %DynamicArray
{
    Set stream = ##class(%Dictionary.CompiledXData).%OpenId(..%ClassName(1)_"||Table").Data
    Quit ##class(%DynamicAbstractObject).%FromJSON(stream)
}

/// The entry for `id`, or "" when `id` is not an area (exact, case-sensitive match).
ClassMethod Lookup(id As %String) As %DynamicObject
{
    Quit:(id = "") ""
    Set it = ..All().%GetIterator()
    While it.%GetNext(.k, .entry) { Return:(entry.id = id) entry }
    Quit ""
}

ClassMethod IsReading(id As %String) As %Boolean
{
    Set entry = ..Lookup(id)
    Quit $IsObject(entry) && entry.reading
}

/// The catalog type `id` becomes as a flow, or "".
ClassMethod StepTypeOf(id As %String) As %String
{
    Set entry = ..Lookup(id)
    Quit $S($IsObject(entry):entry.stepType, 1:"")
}

}
