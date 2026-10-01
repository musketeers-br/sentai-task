/// Spec 018 US2/US3 (plan D-3, D-4, D-8): the overview summary and on-demand reports.
/// The summary makes 10 distinct platform reads for its 11 areas (the dashboard read feeds both
/// `activity` and `alerts`), one after the other, and gives each area its own outcome; one area's
/// failure never touches another (FR-007). It runs no report and computes no finding
/// (clarification Q1). Headlines are pure functions of one read (research R-3).
Class sentai.overview.OverviewService Extends %RegisteredObject
{

/// The platform read behind each area's summary entry.
ClassMethod SummaryPath(area As %String) As %String
{
    Quit $CASE(area,
        "processes": "/api/admin/v2/processes",
        "locks": "/api/admin/v2/locks",
        "memory": "/api/admin/v2/monitor/system-usage/shared-memory",
        "activity": "/api/admin/v2/monitor/dashboard/main",
        "devices": "/api/admin/v2/devices",
        "licenses": "/api/admin/v2/monitor/license-usage",
        "web-sessions": "/api/admin/v2/web-sessions",
        "security": "/api/admin/v2/security/users",
        "web-apps": "/api/admin/v2/web-apps",
        "alerts": "/api/admin/v2/monitor/dashboard/main",
        "secrets": "/api/admin/v2/wallet/collections",
        : "")
}

/// `{readAt, areas: [AreaEntry × 11]}` (data-model §3).
ClassMethod Summary(token As %String) As %DynamicObject
{
    Set areas = [], it = ##class(sentai.overview.Areas).All().%GetIterator()
    While it.%GetNext(.k, .a) {
        Set path = ..SummaryPath(a.id)
        // Each distinct path is read once per summary.
        If '$D(reads(path)) {
            Set reads(path) = ##class(sentai.catalog.TaskService).PlatformRead(path, token)
            Set readAt(path) = $ZDATETIME($HOROLOG, 3)
        }
        Do areas.%Push(..Entry(a, reads(path), readAt(path)))
    }
    Quit {"readAt": ($ZDATETIME($HOROLOG, 3)), "areas": (areas)}
}

ClassMethod Entry(area As %DynamicObject, read As %DynamicObject, readAt As %String) As %DynamicObject
{
    Set entry = {"area": (area.id), "group": (area.group), "readAt": (readAt)}
    Do entry.%Set("stepType", area.stepType, $S(area.stepType = "":"null", 1:"string"))
    If ##class(sentai.overview.Readings).IsRefused(read) {
        Set refusal = ##class(sentai.catalog.TaskService).Refusal(read).problem
        // The platform's words verbatim; when it gave none, say so (the spec 009 wording).
        Set detail = $S(refusal.detail '= "":refusal.detail, 1:"HTTP "_(+read.httpStatus)_": no reason given")
        Set problem = {"title": (refusal.title), "detail": (detail)}
        Do problem.%Set("httpStatus", +read.httpStatus, "number")
        Do:$IsObject(read.status) problem.%Set("platformStatus", read.status)
        Do entry.%Set("outcome", $S(+read.httpStatus = 0:"unreachable", 1:"refused"))
        Do entry.%Set("headline", "", "null")
        Do entry.%Set("problem", problem)
        Quit entry
    }
    Do entry.%Set("outcome", "ok")
    Do entry.%Set("headline", ..Headline(area.id, read.result))
    Do entry.%Set("problem", "", "null")
    Quit entry
}

ClassMethod Headline(area As %String, result) As %DynamicObject
{
    Quit $CASE(area,
        "processes": ..HeadlineProcesses(result),
        "memory": ..HeadlineMemory(result),
        "activity": ..HeadlineActivity(result),
        "licenses": ..HeadlineLicenses(result),
        "security": ..HeadlineSecurity(result),
        "alerts": ..HeadlineAlerts(result),
        "secrets": {"collections": (..Count(result))},
        : {"count": (..Count(result))})
}

ClassMethod Count(result) As %Integer
{
    Quit:'$IsObject(result) 0
    Quit:(result.%ClassName(1) '= "%Library.DynamicArray") 0
    Quit result.%Size()
}

ClassMethod HeadlineProcesses(result) As %DynamicObject
{
    Set out = {"count": (..Count(result))}, best = ""
    If ..Count(result) {
        Set it = result.%GetIterator()
        While it.%GetNext(.k, .p) {
            Continue:'$IsObject(p)
            If '$IsObject(best) || (+p.Commands > +best.Commands) Set best = p
        }
    }
    If $IsObject(best) {
        Do out.%Set("busiest", ##class(sentai.overview.Readings).Row(best, "Pid,Routine,Commands"))
    } Else {
        Do out.%Set("busiest", "", "null")
    }
    Quit out
}

ClassMethod HeadlineMemory(result) As %DynamicObject
{
    Set out = {}, most = "", mostPct = -1
    Do out.%Set("usedPercent", "", "null")
    If ..Count(result) {
        Set it = result.%GetIterator()
        While it.%GetNext(.k, .row) {
            Continue:'$IsObject(row)
            If (row.Description = "Total") {
                Do ##class(sentai.overview.Readings).SetPercent(out, "usedPercent", row.SMHUsed, row.SMHAllocated)
                Continue
            }
            Continue:'(+row.SMHAllocated > 0)
            Set pct = row.SMHUsed / row.SMHAllocated
            If (pct > mostPct) Set most = row, mostPct = pct
        }
    }
    If $IsObject(most) {
        Set m = {"description": (most.Description)}
        Do ##class(sentai.overview.Readings).SetPercent(m, "usedPercent", most.SMHUsed, most.SMHAllocated)
        Do out.%Set("mostUsed", m)
    } Else {
        Do out.%Set("mostUsed", "", "null")
    }
    Quit out
}

ClassMethod HeadlineActivity(dash) As %DynamicObject
{
    Set d = $S($IsObject(dash):dash, 1:{})
    Set status = $S($IsObject(d.Status):d.Status, 1:{}), perf = $S($IsObject(d.Performance):d.Performance, 1:{})
    Set busy = 0
    If $IsObject(d.SystemUsage) && $IsObject(d.SystemUsage.BusyProcesses) {
        Set it = d.SystemUsage.BusyProcesses.%GetIterator()
        While it.%GetNext(.k, .p) { Set:($IsObject(p) && (p.Process '= "")) busy = busy + 1 }
    }
    Set out = {"uptime": (status.UpTime), "lastBackup": (status.LastBackup), "busyProcesses": (busy)}
    Do out.%Set("globalRefsPerSecond", perf.GlobalRefsPerSecond, $S(perf.%IsDefined("GlobalRefsPerSecond"):"number", 1:"null"))
    Quit out
}

/// From the Summary rows, by their label with runs of spaces collapsed (research R-3).
ClassMethod HeadlineLicenses(result) As %DynamicObject
{
    Set out = {}
    Do out.%Set("inUse", "", "null"), out.%Set("authorized", "", "null")
    If $IsObject(result) && $IsObject(result.Summary) {
        Set it = result.Summary.%GetIterator()
        While it.%GetNext(.k, .row) {
            Continue:'$IsObject(row)
            Set label = $ZSTRIP(row.LicenseUnitUse, "<>=W")
            Set value = $S($ISVALIDNUM(row.Local):+row.Local, 1:"")
            Continue:(value = "")
            Do:(label = "Current License Units Used") out.%Set("inUse", value, "number")
            Do:(label = "License Units Authorized") out.%Set("authorized", value, "number")
        }
    }
    Quit out
}

ClassMethod HeadlineSecurity(result) As %DynamicObject
{
    Set enabled = 0
    If ..Count(result) {
        Set it = result.%GetIterator()
        While it.%GetNext(.k, .u) { Set:($IsObject(u) && (+u.Enabled = 1)) enabled = enabled + 1 }
    }
    Quit {"accounts": (..Count(result)), "enabledAccounts": (enabled)}
}

ClassMethod HeadlineAlerts(dash) As %DynamicObject
{
    Set alerts = $S($IsObject(dash) && $IsObject(dash.Alerts):dash.Alerts, 1:{})
    Quit {"seriousAlerts": (+alerts.SeriousAlerts), "applicationErrors": (+alerts.ApplicationErrors)}
}

/// Spec 018 US3 (research R-6): a `platform-read` step type's report, built by the step's own
/// code with the operator's token, on the primary. Creates no run, step run or log entry, and is
/// not stored, so it is not fitted to the run record's size. Outcomes: 200 `OnDemandReport`
/// (also when the report failed), 404 unknown type, 422 not a report, 422 parameter findings.
ClassMethod RunReport(type As %String, parameters, token As %String) As %DynamicObject
{
    If '##class(sentai.registry.StepType).IsKnownType(type) {
        Quit ##class(sentai.catalog.TaskService).Problem(404, "UNKNOWN_STEP_TYPE: '"_type_"' is not in the step-type catalog")
    }
    If (##class(sentai.registry.StepType).GetExecutor(type) '= "platform-read") {
        Quit ##class(sentai.catalog.TaskService).Problem(422, "STEP_TYPE_NOT_A_REPORT: '"_type_"' is not a report step type")
    }
    Set findings = ..ParameterFindings(type, parameters)
    If $IsObject(findings) Quit {"httpStatus": 422, "body": (findings)}

    Set report = ""
    Set sc = ##class(sentai.dispatch.ReadExecutor).Build(type, $S($IsObject(parameters):parameters, 1:{}), ##class(sentai.steps.reports.Reader).For("", token), .report)
    Do:$IsObject(report) report.%Set("instance", "local")
    Set out = {"stepType": (type), "state": ($S($$$ISOK(sc):"completed", 1:"failed")), "failureReason": ($S($$$ISOK(sc):"", 1:$SYSTEM.Status.GetErrorText(sc))), "ranAt": ($ZDATETIME($HOROLOG, 3))}
    Do out.%Set("report", $S($IsObject(report):report, 1:""), $S($IsObject(report):"", 1:"null"))
    Quit ##class(sentai.catalog.TaskService).Ok(out)
}

/// The validator's report `{errors, warnings}` when `parameters` break the type's declared schema
/// (the same checks a flow step gets), else "".
ClassMethod ParameterFindings(type As %String, parameters) As %DynamicObject
{
    Set errors = []
    Do ##class(sentai.validation.FlowValidator).DeclaredStepFindings("ondemand", type, ##class(sentai.registry.StepType).GetParameterSchema(type), $S($IsObject(parameters):parameters, 1:""), ##class(sentai.registry.StepType).GetTargetClass(type), errors)
    Quit:(errors.%Size() = 0) ""
    Quit ##class(sentai.validation.FlowValidator).Report(errors, [])
}

}
