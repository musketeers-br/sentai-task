/// Spec 013 US4 (`secrets-inventory`, FR-010): the platform wallet's collections, the resources that
/// protect them, and the names and types of their secrets — never a value. Only allow-listed
/// fields are copied from the platform's answers (plan D-5), so a value field cannot leak even if
/// the platform returned one.
Class sentai.steps.reports.SecretsInventory Extends sentai.steps.reports.Report
{

ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status
{
    Set report = ..NewReport("secrets-inventory")
    Set list = reader.Get("/api/admin/v2/wallet/collections", .problem)
    If (problem '= "") { Set report.summary.itemsRead = reader.Reads  Quit $$$ERROR($$$GeneralError, problem) }

    Set collections = []
    Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
    While $IsObject(it) && it.%GetNext(.k, .c) {
        Set name = $S($IsObject(c):c.Name, 1:c)
        Set col = ..Pick($S($IsObject(c):c, 1:{}), $LB("UseResource", "EditResource"))
        Set entry = {"name": (name), "useResource": (col.UseResource), "editResource": (col.EditResource), "secrets": []}
        Set secrets = reader.Get("/api/admin/v2/wallet/secrets?collection="_$ZCVT(name, "O", "URL"), .problem)
        If (problem '= "") {
            Do ..AddFinding(report, "medium", "SECRETS_NOT_READABLE", name, problem)
        } Else {
            Set sit = $S($IsObject(secrets):secrets.%GetIterator(), 1:"")
            While $IsObject(sit) && sit.%GetNext(.j, .s) {
                Set safe = ..Pick($S($IsObject(s):s, 1:{"Name": (s)}), $LB("Name", "Type"))
                Do entry.secrets.%Push({"name": (safe.Name), "type": (safe.Type)})
            }
        }
        Do collections.%Push(entry)
        Do:(col.UseResource = "") ..AddFinding(report, "medium", "UNPROTECTED_COLLECTION", name, "no use resource protects this collection")
    }
    Set report.details = {"collections": (collections)}
    Set report.summary.itemsRead = reader.Reads
    Quit $$$OK
}

}
