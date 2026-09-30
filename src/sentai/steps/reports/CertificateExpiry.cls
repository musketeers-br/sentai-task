/// Spec 020 US1 (`certificate-expiry-check`, FR-006): the instance's x509 credentials with the
/// validity their certificates report, and its SSL/TLS configurations. Validity comes only from the
/// platform's answer (research R-2): configurations name certificate files, whose validity the
/// platform does not report, and the product never opens them. The step fails when a certificate
/// has expired or expires within `warnDays` — so a scheduled flow warns before it happens.
/// Only allow-listed fields are copied: never a private key, key file or key password.
Class sentai.steps.reports.CertificateExpiry Extends sentai.steps.reports.Report
{

ClassMethod Build(reader As sentai.steps.reports.Reader, parameters As %DynamicObject, Output report As %DynamicObject) As %Status
{
    Set report = ..NewReport("certificate-expiry-check")
    Set warn = +parameters.warnDays, asOf = report.summary.asOf, refused = 0, firstProblem = ""
    Set credentials = [], configurations = [], crossing = ""

    Set list = reader.Get("/api/admin/v2/security/x509-credentials", .problem)
    If (problem '= "") {
        Set refused = refused + 1, firstProblem = problem
        Do ..AddIncompleteRead(report, "x509 credentials", problem)
    } Else {
        Set n = 0
        Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
        While $IsObject(it) && it.%GetNext(.k, .c) {
            Set n = n + 1
            Continue:(n > ..#CAP)
            Set item = ..Credential(reader, report, $S($IsObject(c):c, 1:{"Alias": (c)}), asOf, warn)
            Do credentials.%Push(item)
            Set:$LISTFIND($LB("expired", "expiring"), item.status) crossing = crossing_$LB(item.alias_" ("_item.notAfter_")")
        }
        Do:(n > ..#CAP) ..AddNotAllRead(report, "x509 credentials", n - ..#CAP)
    }

    Set list = reader.Get("/api/admin/v2/security/ssl-configurations", .problem)
    If (problem '= "") {
        Set refused = refused + 1, firstProblem = $S(firstProblem '= "":firstProblem, 1:problem)
        Do ..AddIncompleteRead(report, "SSL/TLS configurations", problem)
    } Else {
        Set n = 0
        Set it = $S($IsObject(list):list.%GetIterator(), 1:"")
        While $IsObject(it) && it.%GetNext(.k, .c) {
            Set n = n + 1
            Continue:(n > ..#CAP)
            Do configurations.%Push(..Configuration(reader, report, $S($IsObject(c):c, 1:{"Name": (c)})))
        }
        Do:(n > ..#CAP) ..AddNotAllRead(report, "SSL/TLS configurations", n - ..#CAP)
    }

    Set report.details = {"warnDays": (warn), "credentials": (credentials), "configurations": (configurations)}
    // Totals live in the summary, which is never cut when the details do not fit (FitResult).
    Do report.summary.%Set("credentials", credentials.%Size()), report.summary.%Set("configurations", configurations.%Size())
    Set report.summary.itemsRead = reader.Reads
    Quit:(refused = 2) $$$ERROR($$$GeneralError, firstProblem)
    If (crossing '= "") {
        Set shown = ""
        For i = 1:1:$S($LL(crossing) > 5:5, 1:$LL(crossing)) { Set shown = shown_$S(shown = "":"", 1:"; ")_$LG(crossing, i) }
        Quit $$$ERROR($$$GeneralError, $LL(crossing)_" certificate(s) expired or expiring within "_warn_" days: "_shown)
    }
    Quit $$$OK
}

/// One credential with its certificate's validity and status (data-model §1).
ClassMethod Credential(reader As sentai.steps.reports.Reader, report As %DynamicObject, entry As %DynamicObject, asOf As %String, warn As %Integer) As %DynamicObject
{
    Set safe = ..Pick(entry, $LB("Alias", "OwnerList", "PeerNames", "HasPrivateKey"))
    Set alias = safe.Alias
    Set item = {"alias": (alias), "usedBy": ($S($IsObject(safe.OwnerList):safe.OwnerList, 1:[])), "subject": "", "issuer": "", "serial": "", "notBefore": "", "notAfter": "", "daysLeft": "", "status": "unknown"}
    Do item.%Set("hasPrivateKey", ''safe.HasPrivateKey, "boolean")
    Set cert = reader.Get("/api/admin/v2/security/x509-credential/certificate?alias="_$ZCVT(alias, "O", "URL"), .problem)
    If (problem '= "") {
        Do ..AddIncompleteRead(report, "certificate "_alias, problem)
        Quit item
    }
    Set c = ..Pick(cert, $LB("SubjectDN", "IssuerDN", "SerialNumber", "ValidityNotBefore", "ValidityNotAfter"))
    Set item.subject = c.SubjectDN, item.issuer = c.IssuerDN, item.serial = c.SerialNumber
    Set item.notBefore = c.ValidityNotBefore, item.notAfter = c.ValidityNotAfter
    Set days = $S(c.ValidityNotAfter '= "":..DaysLeft(asOf, c.ValidityNotAfter), 1:"")
    If (days = "") {
        Do ..AddFinding(report, "info", "CERT_VALIDITY_UNKNOWN", alias, "the platform reports no expiry date for this certificate")
        Quit item
    }
    Set item.daysLeft = days
    If (c.ValidityNotAfter ']] asOf) {
        Set item.status = "expired"
        Do ..AddFinding(report, "high", "CERT_EXPIRED", alias, "expired on "_c.ValidityNotAfter_" ("_item.subject_")")
    } ElseIf (days <= warn) {
        Set item.status = "expiring"
        Do ..AddFinding(report, "medium", "CERT_EXPIRING", alias, "expires on "_c.ValidityNotAfter_", in "_days_" day"_$S(days = 1:"", 1:"s")_" ("_item.subject_")")
    } Else {
        Set item.status = "valid"
    }
    Quit item
}

/// One SSL/TLS configuration: where its certificate file is, never its key (data-model §1).
ClassMethod Configuration(reader As sentai.steps.reports.Reader, report As %DynamicObject, entry As %DynamicObject) As %DynamicObject
{
    Set head = ..Pick(entry, $LB("Name", "Description", "Enabled", "Type"))
    Set name = head.Name
    Set item = {"name": (name), "description": (head.Description), "type": (head.Type), "certificateFile": "", "caFile": "", "tlsMin": "", "tlsMax": "", "verifyPeer": "", "validity": "not reported by the platform"}
    Do item.%Set("enabled", ''head.Enabled, "boolean")
    Set detail = reader.Get("/api/admin/v2/security/ssl-configuration?name="_$ZCVT(name, "O", "URL"), .problem)
    If (problem '= "") {
        Do ..AddIncompleteRead(report, "SSL/TLS configuration "_name, problem)
        Quit item
    }
    Set d = ..Pick(detail, $LB("CertificateFile", "CAFile", "TLSMinVersion", "TLSMaxVersion", "VerifyPeer"))
    Set item.certificateFile = d.CertificateFile, item.caFile = d.CAFile
    Set item.tlsMin = d.TLSMinVersion, item.tlsMax = d.TLSMaxVersion, item.verifyPeer = d.VerifyPeer
    If (d.CertificateFile '= "") {
        Do ..AddFinding(report, "info", "CONFIG_VALIDITY_NOT_REPORTED", name, "uses "_d.CertificateFile_"; the platform reports no expiry date for configuration files — register the certificate as an x509 credential to have it checked")
    }
    Quit item
}

}
