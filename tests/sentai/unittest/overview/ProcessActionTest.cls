/// Spec 018 T030: process actions with the contract of evidence/01–04 — `POST …/process/<action>
/// ?id=<pid>` with no body; terminate needs the pid typed again; every call that reached the
/// platform is recorded, accepted or refused; the product never refuses a pid on its own.
Class sentai.unittest.overview.ProcessActionTest Extends sentai.unittest.SentaiTestCase
{

Property ActionIdBefore As %Integer [ InitialExpression = 0 ];

Method OnBeforeOneTest() As %Status
{
    Set max = 0
    &sql(SELECT MAX(%ID) INTO :max FROM sentai_model.ProcessAction)
    Set ..ActionIdBefore = +$G(max)
    Quit ##super()
}

Method OnAfterOneTest() As %Status
{
    Set floor = ..ActionIdBefore
    &sql(DELETE FROM sentai_model.ProcessAction WHERE %ID > :floor)
    Quit ##super()
}

Method NewRecords() As %Integer
{
    Set n = 0, floor = ..ActionIdBefore
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.ProcessAction WHERE %ID > :floor)
    Quit +n
}

Method Act(pid, action, confirmation = "") As %DynamicObject
{
    Quit ##class(sentai.overview.ProcessActions).Act(pid, action, confirmation, "tester", "fake-token")
}

Method ScriptOk(action As %String)
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/process/"_action, "POST", 200, "", "{""status"":{""errors"":[],""summary"":""""},""console"":[],""result"":{}}")
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/process?id=4100", {"Pid": 4100, "State": "SUSP", "Routine": "shell", "CSPSessionID": (##class(sentai.unittest.overview.OverviewFixtures).#Leak), "CanBeTerminated": true})
}

Method TestTerminateNeedsTheTypedPid()
{
    For confirmation = "", "4101", "x" {
        Set out = ..Act("4100", "terminate", confirmation)
        Do $$$AssertEquals(out.httpStatus, 428, "confirmation '"_confirmation_"'")
    }
    Do $$$AssertNotTrue($D(^sentaiTestDouble("postlog")), "no platform call")
    Do $$$AssertEquals(..NewRecords(), 0, "no record")
}

Method TestAcceptedActionIsRecordedAndReRead()
{
    Do ..ScriptOk("terminate")
    Set out = ..Act("4100", "terminate", "4100")
    Do $$$AssertEquals(out.httpStatus, 200)
    Do $$$AssertEquals(out.body.platform.httpStatus, 200)
    Do $$$AssertEquals(out.body.process.State, "SUSP")
    Do $$$AssertNotTrue(out.%ToJSON() [ ##class(sentai.unittest.overview.OverviewFixtures).#Leak, "no CSPSessionID")
    // The spike's contract: the pid in the query string, no body.
    Set posted = ^sentaiTestDouble("posted", "/api/admin/v2/process/terminate")
    Do $$$AssertEquals($LG(posted, 1), "/api/admin/v2/process/terminate?id=4100")
    Do $$$AssertEquals($LG(posted, 2), "")
    Set list = ##class(sentai.overview.ProcessActions).List(50)
    Do $$$AssertEquals(list.%Get(0).pid, 4100)
    Do $$$AssertEquals(list.%Get(0).action, "terminate")
    Do $$$AssertEquals(list.%Get(0).operator, "tester")
    Do $$$AssertTrue(list.%Get(0).accepted)
}

Method TestSuspendAndResumeNeedNoConfirmation()
{
    Do ..ScriptOk("suspend"), ..ScriptOk("resume")
    Do $$$AssertEquals(..Act("4100", "suspend").httpStatus, 200)
    Do $$$AssertEquals(..Act("4100", "resume").httpStatus, 200)
    Set list = ##class(sentai.overview.ProcessActions).List(50)
    Do $$$AssertEquals(list.%Get(0).action, "resume", "newest first")
    Do $$$AssertEquals(list.%Get(1).action, "suspend")
}

Method TestRefusalIsVerbatimAndRecorded()
{
    // evidence/04: 403 with an empty status object.
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/process/terminate", "POST", 403, "", "{""status"":{""errors"":[],""summary"":""""},""console"":[],""result"":{}}")
    Set out = ..Act("4100", "terminate", "4100")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.detail, "HTTP 403: no reason given")
    Do $$$AssertTrue($IsObject(out.problem.platformStatus))
    Set rec = ##class(sentai.overview.ProcessActions).List(1).%Get(0)
    Do $$$AssertNotTrue(rec.accepted)
    Do $$$AssertEquals(rec.httpStatus, 403)
    Do $$$AssertEquals(..NewRecords(), 1)
}

Method TestTheProductNeverRefusesAPidOnItsOwn()
{
    Do ..ScriptOk("terminate")
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/process?id=839", {"Pid": 839, "CanBeTerminated": false})
    Set out = ..Act("839", "terminate", "839")
    Do $$$AssertEquals(out.httpStatus, 200, "the platform, not the product, decides")
}

Method TestUnknownActionAndBadPid()
{
    Do $$$AssertEquals(..Act("4100", "kill").httpStatus, 404)
    Do $$$AssertEquals(..Act("abc", "suspend").httpStatus, 400)
    Do $$$AssertEquals(..Act("0", "suspend").httpStatus, 400)
    Do $$$AssertNotTrue($D(^sentaiTestDouble("postlog")), "no platform call")
    Do $$$AssertEquals(..NewRecords(), 0)
}

}
