/// Spec 020 US1 (FR-006): the certificate expiry check over scripted platform answers.
Class sentai.unittest.steps.ReportCertificateExpiryTest Extends sentai.unittest.SentaiTestCase
{

Parameter P = "/api/admin/v2/security/";

ClassMethod Ok(result) As %String
{
    Quit {"status": {"errors": [], "summary": ""}, "result": (result)}.%ToJSON()
}

ClassMethod Script(path As %String, result, status As %Integer = 200)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script(..#P_path, "GET", status, "", $S(status = 200:..Ok(result), 1:"{""status"":{""errors"":[],""summary"":"""_result_"""}}"))
}

ClassMethod Build(params As %DynamicObject = "", Output report As %DynamicObject) As %Status
{
    Set:(params = "") params = {}
    Quit ##class(sentai.dispatch.ReadExecutor).Build("certificate-expiry-check", params, ##class(sentai.steps.reports.Reader).For("", "tok"), .report)
}

/// A date `days` from today on the instance, as the platform writes validity dates.
ClassMethod In(days As %Integer) As %String
{
    Quit $ZDATE(+$HOROLOG + days, 3)_" 12:00:00"
}

/// Credentials `aliases` ($LB) whose certificates end `days` ($LB) from today ("" = no validity).
ClassMethod ScriptCredentials(aliases As %List, days As %List)
{
    Set list = []
    For i = 1:1:$LL(aliases) {
        Set alias = $LG(aliases, i)
        Set entry = {"Alias": (alias), "OwnerList": ["%SuperServer"], "PeerNames": [], "CAFile": "", "PrivateKeyPassword": "must-not-leak"}
        Do entry.%Set("HasPrivateKey", 0, "boolean")
        Do list.%Push(entry)
        Set d = $LG(days, i)
        Set cert = {"SubjectDN": ("CN="_alias), "IssuerDN": "CN=Test CA", "SerialNumber": "42", "ValidityNotBefore": (..In(-30)), "PrivateKey": "-----BEGIN PRIVATE KEY----- must-not-leak"}
        Do:(d '= "") cert.%Set("ValidityNotAfter", ..In(d))
        Do ..Script("x509-credential/certificate?alias="_alias, cert)
    }
    Do ..Script("x509-credentials", list)
}

ClassMethod NoConfigurations()
{
    Do ..Script("ssl-configurations", [])
}

ClassMethod Rules(report As %DynamicObject) As %String
{
    Set out = ""
    Set it = report.findings.%GetIterator()
    While it.%GetNext(.k, .f) { Set out = out_f.rule_":"_f.item_"," }
    Quit out
}

Method TestExpiredAndExpiringFailTheStep()
{
    Do ..ScriptCredentials($LB("old", "soon", "fine"), $LB(-2, 10, 200))
    Do ..NoConfigurations()
    Set sc = ..Build({"warnDays": 30}, .report)
    Do $$$AssertStatusNotOK(sc)
    Set text = $SYSTEM.Status.GetErrorText(sc)
    Do $$$AssertTrue(text [ "2 certificate(s) expired or expiring within 30 days: old (", text)
    Do $$$AssertTrue(text [ "soon (", text)
    Set rules = ..Rules(report)
    Do $$$AssertTrue(rules [ "CERT_EXPIRED:old,", rules)
    Do $$$AssertTrue(rules [ "CERT_EXPIRING:soon,", rules)
    Do $$$AssertNotTrue(rules [ ":fine,", rules)
    Do $$$AssertEquals(report.summary.high, 1)
    Do $$$AssertEquals(report.summary.medium, 1)
    Set byAlias = {}
    Set it = report.details.credentials.%GetIterator()
    While it.%GetNext(.k, .c) { Do byAlias.%Set(c.alias, c) }
    Do $$$AssertEquals(byAlias.old.status, "expired")
    Do $$$AssertEquals(byAlias.soon.daysLeft, 10)
    Do $$$AssertEquals(byAlias.soon.status, "expiring")
    Do $$$AssertEquals(byAlias.fine.status, "valid")
    Do $$$AssertEquals(byAlias.fine.subject, "CN=fine")
    Do $$$AssertNotTrue(report.%ToJSON() [ "must-not-leak", "no key material or key password is ever copied")
}

Method TestThresholdIsInclusiveAndDefaultIs30()
{
    Do ..ScriptCredentials($LB("edge"), $LB(30))
    Do ..NoConfigurations()
    Do $$$AssertStatusNotOK(..Build(, .report), "30 days left with the default of 30 crosses it")
    Do $$$AssertTrue(..Rules(report) [ "CERT_EXPIRING:edge,")
    Do $$$AssertStatusOK(..Build({"warnDays": 29}, .report))
}

Method TestAllValidCompletes()
{
    Do ..ScriptCredentials($LB("a", "b"), $LB(100, 365))
    Do ..NoConfigurations()
    Do $$$AssertStatusOK(..Build({"warnDays": 30}, .report))
    Do $$$AssertEquals(report.details.credentials.%Size(), 2)
    Do $$$AssertEquals(report.summary.credentials, 2)
    Do $$$AssertEquals(report.findings.%Size(), 0)
}

Method TestUnknownValidityIsInfoAndNotCounted()
{
    Do ..ScriptCredentials($LB("nodate"), $LB(""))
    Do ..NoConfigurations()
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertTrue(..Rules(report) [ "CERT_VALIDITY_UNKNOWN:nodate,")
    Do $$$AssertEquals(report.summary.info, 1)
}

Method TestConfigurationsListedValidityNotReported()
{
    Do ..Script("x509-credentials", [])
    Do ..Script("ssl-configurations", [{"Name": "Web", "Enabled": true, "Type": "Server"}, {"Name": "Client", "Enabled": true, "Type": "Client"}])
    Do ..Script("ssl-configuration?name=Web", {"CertificateFile": "/certs/web.crt", "CAFile": "", "PrivateKeyFile": "/certs/web.key", "PrivateKeyPassword": "must-not-leak", "TLSMinVersion": 16, "TLSMaxVersion": 32, "VerifyPeer": 0, "Enabled": true, "Type": 1})
    Do ..Script("ssl-configuration?name=Client", {"CertificateFile": "", "CAFile": "", "TLSMinVersion": 16, "TLSMaxVersion": 32, "VerifyPeer": 1, "Enabled": true, "Type": 0})
    Do $$$AssertStatusOK(..Build(, .report))
    Set rules = ..Rules(report)
    Do $$$AssertTrue(rules [ "CONFIG_VALIDITY_NOT_REPORTED:Web,", rules)
    Do $$$AssertNotTrue(rules [ ":Client,", "no certificate file, no finding")
    Do $$$AssertEquals(report.details.configurations.%Size(), 2)
    Do $$$AssertEquals(report.details.configurations.%Get(0).certificateFile, "/certs/web.crt")
    Do $$$AssertNotTrue(report.%ToJSON() [ "web.key", "the private key file is never copied")
    Do $$$AssertNotTrue(report.%ToJSON() [ "must-not-leak")
}

Method TestEmptyInstanceCompletes()
{
    Do ..Script("x509-credentials", [])
    Do ..NoConfigurations()
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertEquals(report.findings.%Size(), 0)
    Do $$$AssertEquals(report.details.credentials.%Size(), 0)
}

Method TestPartialAndFullRefusal()
{
    Do ..ScriptCredentials($LB("a"), $LB(100))
    Do ..Script("ssl-configurations", "ERROR #822: Access Denied", 403)
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertTrue(..Rules(report) [ "INCOMPLETE_READ:SSL/TLS configurations,")
    Do $$$AssertTrue(report.%ToJSON() [ "ERROR #822: Access Denied")

    Do ..Script("x509-credentials", "ERROR #822: Access Denied", 403)
    Set sc = ..Build(, .report)
    Do $$$AssertStatusNotOK(sc)
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "returned HTTP 403: ERROR #822: Access Denied")
}

Method TestCertificateReadRefusedIsIncomplete()
{
    Do ..Script("x509-credentials", [{"Alias": "x"}])
    Do ..Script("x509-credential/certificate?alias=x", "ERROR #822: Access Denied", 403)
    Do ..NoConfigurations()
    Do $$$AssertStatusOK(..Build(, .report))
    Do $$$AssertTrue(..Rules(report) [ "INCOMPLETE_READ:certificate x,")
    Do $$$AssertEquals(report.details.credentials.%Get(0).status, "unknown")
}

Method TestCapAt200()
{
    Set list = []
    For i = 1:1:203 { Do list.%Push({"Alias": ("c"_i)}) }
    Do ..Script("x509-credentials", list)
    Do ..NoConfigurations()
    Do ..Build(, .report)
    Do $$$AssertEquals(report.details.credentials.%Size(), 200)
    Do $$$AssertTrue(..Rules(report) [ "NOT_ALL_READ:x509 credentials,")
    Do $$$AssertEquals(report.summary.itemsOmitted, 3)
}

}
