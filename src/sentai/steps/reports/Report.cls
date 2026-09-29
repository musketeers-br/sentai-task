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
/// Spec 020: the most items a report reads one by one (roles, credentials, configurations…).
Parameter CAP = 200;

ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status [ Abstract ]
{
}

/// A new, empty report of `type`.
ClassMethod NewReport(type As %String) As %DynamicObject
{
    // Spec 020: `asOf` is the instance's date and time the report was built at.
    Quit {"type": (type), "summary": {"high": 0, "medium": 0, "info": 0, "itemsRead": 0, "itemsOmitted": 0, "asOf": ($ZDATETIME($HOROLOG, 3))}, "findings": [], "details": {}}
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

/// Spec 020: whole days from `asOf` to `notAfter` (both "YYYY-MM-DD hh:mm:ss"); negative when the
/// date is past. "" when `notAfter` is not a date.
ClassMethod DaysLeft(asOf As %String, notAfter As %String) As %String
{
    Set to = $ZDATEH($P(notAfter, " "), 3, , , , , , , "")
    Quit:(to = "") ""
    Quit to - $ZDATEH($P(asOf, " "), 3)
}

/// Spec 020: one of a report's reads was refused while others succeeded: kept as a finding with the
/// platform's words (FR-011).
ClassMethod AddIncompleteRead(report As %DynamicObject, part As %String, text As %String)
{
    Do ..AddFinding(report, "medium", "INCOMPLETE_READ", part, text)
}

/// Spec 020: items beyond the per-report cap were not read.
ClassMethod AddNotAllRead(report As %DynamicObject, part As %String, omitted As %Integer)
{
    Do ..AddFinding(report, "info", "NOT_ALL_READ", part, omitted_" item"_$S(omitted = 1:"", 1:"s")_" not read (limit "_..#CAP_")")
    Set report.summary.itemsOmitted = report.summary.itemsOmitted + omitted
}

/// Spec 020: an address that is not https, loopback excepted (http://localhost, 127.0.0.1, [::1]).
ClassMethod IsInsecureAddress(url As %String) As %Boolean
{
    Quit:(url = "") 0
    Set lower = $ZCVT(url, "L")
    Quit:($E(lower, 1, 8) = "https://") 0
    Set host = $P($P($P(lower, "://", 2), "/", 1), "@", *)
    Set host = $S($E(host) = "[":$P(host, "]", 1)_"]", 1:$P(host, ":", 1))
    Quit '$LISTFIND($LB("localhost", "127.0.0.1", "[::1]"), host)
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
