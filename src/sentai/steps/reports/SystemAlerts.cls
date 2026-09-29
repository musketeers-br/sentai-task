/// Spec 013 US3 (`system-alerts-check`, FR-009): the platform's main monitoring dashboard as a gate.
/// Fails when serious alerts or application errors exceed their thresholds, or (by default) when a
/// system resource status is not "Normal". The platform's counters are reported as it gives them
/// (research R-4 records what "serious alerts" counts).
Class sentai.steps.reports.SystemAlerts Extends sentai.steps.reports.Report
{

ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status
{
    Set report = ..NewReport("system-alerts-check")
    Set dash = reader.Get("/api/admin/v2/monitor/dashboard/main", .problem)
    Set report.summary.itemsRead = reader.Reads
    Quit:(problem '= "") $$$ERROR($$$GeneralError, problem)

    Set maxSerious = +parameters.maxSeriousAlerts, maxErrors = +parameters.maxApplicationErrors
    Set requireNormal = ''parameters.requireNormalStatus
    Set alerts = $S($IsObject(dash.Alerts):dash.Alerts, 1:{})
    Set serious = +alerts.SeriousAlerts, appErrors = +alerts.ApplicationErrors

    Set usage = {}, it = $S($IsObject(dash.SystemUsage):dash.SystemUsage.%GetIterator(), 1:"")
    While $IsObject(it) && it.%GetNext(.name, .value) {
        // Only the named statuses; counters and the busy-process list are not statuses.
        Continue:($IsObject(value) || (dash.SystemUsage.%GetTypeOf(name) '= "string"))
        Do usage.%Set(name, value)
    }
    Set lic = $S($IsObject(dash.Licensing):dash.Licensing, 1:{})
    Set report.details = {
        "alerts": {"serious": (serious), "applicationErrors": (appErrors)},
        "systemUsage": (usage),
        "license": {"use": (lic.LicenseUse), "limit": (lic.LicenseLimit), "high": (lic.LicenseUseHigh)},
        "uptime": ($S($IsObject(dash.Status):dash.Status.UpTime, 1:"")),
        "thresholds": {"maxSeriousAlerts": (maxSerious), "maxApplicationErrors": (maxErrors)}
    }
    Do report.details.thresholds.%Set("requireNormalStatus", requireNormal, "boolean")

    Set reasons = ""
    If (serious > maxSerious) {
        Do ..AddFinding(report, "high", "SERIOUS_ALERTS_OVER", "alerts", serious_" serious alerts (maximum "_maxSerious_")")
        Set reasons = reasons_$LB(serious_" serious alerts (maximum "_maxSerious_")")
    }
    If (appErrors > maxErrors) {
        Do ..AddFinding(report, "high", "APPLICATION_ERRORS_OVER", "alerts", appErrors_" application errors (maximum "_maxErrors_")")
        Set reasons = reasons_$LB(appErrors_" application errors (maximum "_maxErrors_")")
    }
    If requireNormal {
        Set it = usage.%GetIterator()
        While it.%GetNext(.name, .value) {
            Continue:(value = "Normal")
            // An unknown status is not normal (spec edge case).
            Do ..AddFinding(report, "high", "STATUS_NOT_NORMAL", name, value)
            Set reasons = reasons_$LB(name_" is "_value)
        }
    }
    Quit:(reasons = "") $$$OK
    Quit $$$ERROR($$$GeneralError, "System alerts check: "_$LTS(reasons, "; "))
}

}
