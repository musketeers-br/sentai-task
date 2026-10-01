/// Spec 020 US2 (`permissions-inventory`, FR-007): who may do what — every role with the resources
/// and roles it grants, and every resource with what the public (no role at all) may do with it.
/// Fixed rules (research R-6): public write or use on a database (`%DB_…`), administration
/// (`%Admin_…`) or development (`%Development`) resource is *high*, on any other resource *medium*;
/// a role other than `%All` that grants `%All` is *high*. Holders of `%All` are the security
/// posture report's (spec 013).
Class sentai.steps.reports.PermissionsInventory Extends sentai.steps.reports.Report
{

ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status
{
    Set report = ..NewReport("permissions-inventory")
    Set roles = [], resources = [], refused = 0, firstProblem = ""

    Set list = reader.Get("/api/admin/v2/security/roles", .problem)
    If (problem '= "") {
        Set refused = refused + 1, firstProblem = problem
        Do ..AddIncompleteRead(report, "roles", problem)
    } Else {
        Set n = 0
        Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
        While $IsObject(it) && it.%GetNext(.k, .r) {
            Set n = n + 1
            Continue:(n > ..#CAP)
            Do roles.%Push(..Role(reader, report, $S($IsObject(r):r, 1:{"Name": (r)})))
        }
        Do:(n > ..#CAP) ..AddNotAllRead(report, "roles", n - ..#CAP)
    }

    Set list = reader.Get("/api/admin/v2/security/resources", .problem)
    If (problem '= "") {
        Set refused = refused + 1, firstProblem = $S(firstProblem '= "":firstProblem, 1:problem)
        Do ..AddIncompleteRead(report, "resources", problem)
    } Else {
        Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
        While $IsObject(it) && it.%GetNext(.k, .r) {
            Set safe = ..Pick($S($IsObject(r):r, 1:{"Name": (r)}), $LB("Name", "Description", "ResourceType", "PublicPermission"))
            Set name = safe.Name, public = safe.PublicPermission
            Do resources.%Push({"name": (name), "type": (safe.ResourceType), "publicPermission": (public)})
            Continue:'((public [ "W") || (public [ "U"))
            If ..IsSensitive(name) {
                Do ..AddFinding(report, "high", "PUBLIC_WRITE_OR_USE_SENSITIVE", name, "the public (no role) holds "_public_" on this resource")
            } Else {
                Do ..AddFinding(report, "medium", "PUBLIC_WRITE_OR_USE", name, "the public (no role) holds "_public_" on this resource")
            }
        }
    }

    Set report.details = {"roles": (roles), "resources": (resources)}
    // Totals live in the summary, which is never cut when the details do not fit (FitResult).
    Do report.summary.%Set("roles", roles.%Size()), report.summary.%Set("resources", resources.%Size())
    Set report.summary.itemsRead = reader.Reads
    Quit:(refused = 2) $$$ERROR($$$GeneralError, firstProblem)
    Quit:(parameters.failOnFindings && (report.summary.high > 0)) $$$ERROR($$$GeneralError, ..HighFindingsText(report))
    Quit $$$OK
}

/// One role with its resources and granted roles (data-model §2).
ClassMethod Role(reader As sentai.steps.reports.Reader, report As %DynamicObject, entry As %DynamicObject) As %DynamicObject
{
    Set head = ..Pick(entry, $LB("Name", "Description", "EscalationOnly"))
    Set name = head.Name
    Set item = {"name": (name), "description": (head.Description), "resources": [], "grantedRoles": []}
    Do item.%Set("escalationOnly", ''head.EscalationOnly, "boolean")
    Set detail = reader.Get("/api/admin/v2/security/role?name="_$ZCVT(name, "O", "URL"), .problem)
    If (problem '= "") {
        Do ..AddIncompleteRead(report, "role "_name, problem)
        Quit item
    }
    Set d = ..Pick(detail, $LB("Resources", "GrantedRoles"))
    If $IsObject(d.Resources) {
        Set it = d.Resources.%GetIterator()
        While it.%GetNext(.k, .r) {
            Set safe = ..Pick($S($IsObject(r):r, 1:{}), $LB("Name", "Permissions"))
            Do item.resources.%Push({"name": (safe.Name), "permissions": (safe.Permissions)})
        }
    }
    If $IsObject(d.GrantedRoles) {
        Set it = d.GrantedRoles.%GetIterator()
        While it.%GetNext(.k, .g) { Do item.grantedRoles.%Push($S($IsObject(g):g.Name, 1:g)) }
    }
    If (name '= "%All") && ..Includes(item.grantedRoles, "%All") {
        Do ..AddFinding(report, "high", "ROLE_GRANTS_ALL", name, "holders of this role also hold %All")
    }
    Quit item
}

ClassMethod IsSensitive(name As %String) As %Boolean
{
    Quit ($E(name, 1, 4) = "%DB_") || ($E(name, 1, 7) = "%Admin_") || (name = "%Development")
}

}
