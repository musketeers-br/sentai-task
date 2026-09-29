/// Spec 013 US2 (`web-app-inventory`, FR-008): every web application with its namespace, whether it
/// is a REST endpoint, the resource that protects it and its authentication methods. An enabled,
/// non-system application that accepts unauthenticated access with no resource is a finding.
Class sentai.steps.reports.WebAppInventory Extends sentai.steps.reports.Report
{

ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status
{
    Set report = ..NewReport("web-app-inventory")
    Set list = reader.Get("/api/admin/v2/web-apps", .problem)
    Set report.summary.itemsRead = reader.Reads
    Quit:(problem '= "") $$$ERROR($$$GeneralError, problem)

    Set apps = []
    Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
    While $IsObject(it) && it.%GetNext(.k, .a) {
        Set methods = $S($IsObject(a.AuthenticationMethods):a.AuthenticationMethods, 1:[])
        // Research R-1: IsSystemApp was false for /csp/sys*; the Type says "System,CSP".
        Set system = ''a.IsSystemApp || ($ZCVT(a.Type, "U") [ "SYSTEM")
        Set rest = (a.DispatchClass '= "")
        Set app = {"path": (a.Name), "namespace": (a.Namespace), "dispatchClass": (a.DispatchClass), "resource": (a.Resource), "authenticationMethods": (methods)}
        Do app.%Set("enabled", ''a.Enabled, "boolean")
        Do app.%Set("rest", rest, "boolean")
        Do app.%Set("system", system, "boolean")
        Do apps.%Push(app)
        Continue:('a.Enabled || system || (a.Resource '= "") || '..Includes(methods, "Unauthenticated"))
        If rest {
            Do ..AddFinding(report, "high", "ANONYMOUS_REST_ENDPOINT", a.Name, "REST endpoint ("_a.DispatchClass_") accepts unauthenticated access with no resource")
        } Else {
            Do ..AddFinding(report, "medium", "ANONYMOUS_APPLICATION", a.Name, "accepts unauthenticated access with no resource")
        }
    }
    Set report.details = {"applications": (apps)}
    If parameters.failOnFindings && (report.summary.high > 0) Quit $$$ERROR($$$GeneralError, ..HighFindingsText(report))
    Quit $$$OK
}

}
