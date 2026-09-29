/// Spec 013: base of the declared report step types (executor `platform-read`). A report class is
/// chosen only from the step-type registry by `type` (Constitution II); it reads fixed paths
/// through a `Reader` and applies fixed rules. It never writes anything to the platform.
///
/// The report (plan D-4):
///   {"type", "instance", "summary": {"high", "medium", "info", "itemsRead", "itemsOmitted"},
///    "findings": [{"severity", "rule", "item", "detail"}], "details": {…}}
/// `Build` returns $$$OK, or an error whose text is the step's failure reason; the report is kept
/// in both cases (it may be partial).
Class sentai.steps.reports.Report Extends %RegisteredObject [ Abstract ]
{

/// Subclasses implement the reads and rules. `parameters` holds the declared parameters with their
/// defaults applied (ReadExecutor.Parameters).
ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status [ Abstract ]
{
}

/// A new, empty report of `type`.
ClassMethod NewReport(type As %String) As %DynamicObject
{
    Quit {"type": (type), "summary": {"high": 0, "medium": 0, "info": 0, "itemsRead": 0, "itemsOmitted": 0}, "findings": [], "details": {}}
}

ClassMethod AddFinding(report As %DynamicObject, severity As %String, rule As %String, item As %String, detail As %String = "")
{
    Do report.findings.%Push({"severity": (severity), "rule": (rule), "item": (item), "detail": (detail)})
    Do report.summary.%Set(severity, report.summary.%Get(severity) + 1)
}

/// A copy of `source` with only the `fields` listed ($LB of names), under the same names. Nothing
/// else in a platform answer is ever read, so a password or secret value cannot leak (FR-005).
ClassMethod Pick(source As %DynamicObject, fields As %List) As %DynamicObject
{
    Set out = {}
    Quit:'$IsObject(source) out
    For i = 1:1:$LL(fields) {
        Set f = $LG(fields, i)
        Continue:'source.%IsDefined(f)
        Set type = source.%GetTypeOf(f)
        If (type = "boolean") { Do out.%Set(f, source.%Get(f), "boolean") } Else { Do out.%Set(f, source.%Get(f)) }
    }
    Quit out
}

/// Whether the JSON array `list` contains `value` (case-sensitive, as the platform spells it).
ClassMethod Includes(list, value As %String) As %Boolean
{
    Quit:'$IsObject(list) 0
    Set it = list.%GetIterator()
    While it.%GetNext(.k, .v) { Return:(v = value) 1 }
    Quit 0
}

/// "<n> high finding(s): <rule> <item>; …" (first five), the failure reason of a report that fails
/// on findings (plan D-6).
ClassMethod HighFindingsText(report As %DynamicObject) As %String
{
    Set n = report.summary.high, text = "", shown = 0
    Set it = report.findings.%GetIterator()
    While it.%GetNext(.k, .f) {
        Continue:(f.severity '= "high")
        Set shown = shown + 1
        Quit:(shown > 5)
        Set text = text_$S(text = "":"", 1:"; ")_f.rule_" "_f.item
    }
    Quit n_" high finding"_$S(n = 1:"", 1:"s")_": "_text
}

}
