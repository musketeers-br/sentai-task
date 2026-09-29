/// Spec 011 T025 (D1): an operator the platform refuses the product's tables (SQLCODE -99) gets
/// that refusal from validation and dispatch, never a clean report for an "empty" flow. The
/// refused reads run in a JOB signed in as a temporary operator without SQL privileges.
Class sentai.unittest.validation.ReadRefusalTest Extends sentai.unittest.SentaiTestCase
{

Parameter USER = "sentai_t025";

Parameter ROLE = "SentaiT025NoSql";

/// Runs in the JOB: signs in as the refused operator and validates.
ClassMethod ValidateAs(flowId As %String, password As %String)
{
    Set key = $JOB
    Try {
        Set sc = $SYSTEM.Security.Login(..#USER, password)
        If $$$ISERR(sc) { Set ^IRIS.Temp.sentaiT025("report") = "LOGIN: "_$SYSTEM.Status.GetErrorText(sc) Quit }
        Set ^IRIS.Temp.sentaiT025("user") = $USERNAME
        Set ^IRIS.Temp.sentaiT025("report") = ##class(sentai.validation.FlowValidator).Validate(flowId).%ToJSON()
    } Catch ex {
        Set ^IRIS.Temp.sentaiT025("report") = "ERROR: "_ex.DisplayString()
    }
}

Method TestValidationReportsTheSqlRefusal()
{
    Set id = ..CreateCanonicalFlow("ReadRefusalFixture")
    Set password = "T025-"_$SYSTEM.Util.CreateGUID()
    Do ..CreateOperator(password)
    Try {
        Kill ^IRIS.Temp.sentaiT025
        Job ..ValidateAs(id, password)
        For i = 1:1:100 { Quit:$D(^IRIS.Temp.sentaiT025("report"))  Hang 0.1 }
        Set text = $G(^IRIS.Temp.sentaiT025("report"))
        Do $$$AssertEquals($G(^IRIS.Temp.sentaiT025("user")), ..#USER, "the JOB ran as the refused operator")
        Set report = ##class(%DynamicAbstractObject).%FromJSON(text)
        Do $$$AssertEquals(report.errors.%Size(), 1, text)
        Do $$$AssertEquals(report.errors.%Get(0).code, "PLATFORM_REFUSED")
        Do $$$AssertTrue(report.errors.%Get(0).message [ "-99", "the platform's SQLCODE is kept: "_report.errors.%Get(0).message)
    } Catch ex {
        Do $$$AssertFailure(ex.DisplayString())
    }
    Do ..DeleteOperator()
    Kill ^IRIS.Temp.sentaiT025
}

/// An operator who may read gets the usual report (no PLATFORM_REFUSED).
Method TestReadableFlowHasNoRefusal()
{
    Set id = ..CreateCanonicalFlow("ReadRefusalReadable")
    Do $$$AssertEquals(##class(sentai.validation.FlowValidator).ReadRefusal(id), "")
}

Method CreateOperator(password As %String)
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Do ##class(Security.Users).Delete(..#USER)
    Do:##class(Security.Roles).Exists(..#ROLE) ##class(Security.Roles).Delete(..#ROLE)
    $$$ThrowOnError(##class(Security.Roles).Create(..#ROLE, "spec 011 T025 test: product databases, no SQL privilege", "%DB_IRISAPP_CODE:R,%DB_IRISAPP_DATA:RW"))
    $$$ThrowOnError(##class(Security.Users).Create(..#USER, ..#ROLE, password, "spec 011 T025 test operator"))
}

Method DeleteOperator()
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Do ##class(Security.Users).Delete(..#USER)
    Do:##class(Security.Roles).Exists(..#ROLE) ##class(Security.Roles).Delete(..#ROLE)
}

}
