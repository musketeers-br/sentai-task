/// Spec 013 US1 (`security-posture-report`, FR-007): enabled accounts and their roles, accounts
/// holding %All, enabled services accepting unauthenticated connections, and whether auditing is
/// on. Reads only through the management API with the run's credential; the platform decides.
Class sentai.steps.reports.SecurityPosture Extends sentai.steps.reports.Report
{

/// Per-account role reads are capped (research R-3).
Parameter ROLECAP = 200;

ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status
{
    Set report = ..NewReport("security-posture-report")
    Set users = reader.Get("/api/admin/v2/security/users", .problem)
    If (problem '= "") { Set report.summary.itemsRead = reader.Reads  Quit $$$ERROR($$$GeneralError, problem) }

    // Enabled accounts in name order, then their roles, one read each up to the cap.
    Kill names
    Set it = $S($IsObject(users):users.%GetIterator(), 1:"")
    While $IsObject(it) && it.%GetNext(.k, .u) {
        Set:(u.Enabled) names(u.Name) = u
    }
    Set accounts = [], read = 0, refused = 0, firstRefusal = "", name = ""
    For {
        Set name = $O(names(name))
        Quit:(name = "")
        If (read >= ..#ROLECAP) { Set report.summary.itemsOmitted = report.summary.itemsOmitted + 1  Continue }
        Set read = read + 1
        Set detail = reader.Get("/api/admin/v2/security/user?name="_$ZCVT(name, "O", "URL"), .problem)
        If (problem '= "") {
            Set refused = refused + 1
            Set:(firstRefusal = "") firstRefusal = problem
            Do ..AddFinding(report, "medium", "ROLES_NOT_READABLE", name, problem)
            Do accounts.%Push({"name": (name), "fullName": (names(name).FullName), "roles": null})
            Continue
        }
        Set account = ..Pick(detail, $LB("FullName", "Roles", "AccountNeverExpires", "PasswordNeverExpires"))
        Set entry = {"name": (name), "fullName": (account.FullName), "roles": ($S($IsObject(account.Roles):account.Roles, 1:[]))}
        Do entry.%Set("accountNeverExpires", ''account.AccountNeverExpires, "boolean")
        Do entry.%Set("passwordNeverExpires", ''account.PasswordNeverExpires, "boolean")
        Do accounts.%Push(entry)
        Do:..Includes(account.Roles, "%All") ..AddFinding(report, "high", "ALL_ROLE_HOLDER", name, "holds %All")
    }
    If (read > 0) && (refused = read) {
        Set report.summary.itemsRead = reader.Reads
        Quit $$$ERROR($$$GeneralError, firstRefusal)
    }
    Do:(report.summary.itemsOmitted > 0) ..AddFinding(report, "info", "ROLES_CAP_REACHED", "accounts", "roles of "_report.summary.itemsOmitted_" accounts not read (cap "_..#ROLECAP_")")

    Set services = [], list = reader.Get("/api/admin/v2/security/services", .problem)
    If (problem '= "") { Set report.summary.itemsRead = reader.Reads  Quit $$$ERROR($$$GeneralError, problem) }
    Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
    While $IsObject(it) && it.%GetNext(.k, .svc) {
        Continue:'svc.Enabled
        Set methods = $S($IsObject(svc.AuthenticationMethods):svc.AuthenticationMethods, 1:[])
        Do services.%Push({"name": (svc.Name), "authenticationMethods": (methods)})
        Do:..Includes(methods, "Unauthenticated") ..AddFinding(report, "medium", "UNAUTHENTICATED_SERVICE", svc.Name, "enabled and accepts unauthenticated connections")
    }

    Set audit = reader.Get("/api/admin/v2/security/audit/enabled", .problem)
    If (problem '= "") { Set report.summary.itemsRead = reader.Reads  Quit $$$ERROR($$$GeneralError, problem) }
    Set auditOn = $IsObject(audit) && audit.Enabled
    Do:'auditOn ..AddFinding(report, "high", "AUDIT_DISABLED", "audit", "auditing is off")

    Set report.details = {"accounts": (accounts), "services": (services)}
    Do report.details.%Set("auditEnabled", auditOn, "boolean")
    Set report.summary.itemsRead = reader.Reads
    If parameters.failOnFindings && (report.summary.high > 0) Quit $$$ERROR($$$GeneralError, ..HighFindingsText(report))
    Quit $$$OK
}

}
