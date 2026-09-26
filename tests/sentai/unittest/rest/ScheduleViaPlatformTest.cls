/// POST /flows/{id}/schedule creates each native task through the platform's management API
/// (`POST /api/admin/v2/task`) with the operator's own token, so the platform decides who may
/// create tasks (%Admin_Task or %Admin_Operate) and its refusal reaches the operator verbatim
/// (Constitution III). The in-process %SYS.Task path skipped that privilege (spec 006 research
/// R-1) and is gone. Nothing here creates a real task: the platform is the test double.
Class sentai.unittest.rest.ScheduleViaPlatformTest Extends sentai.unittest.SentaiTestCase
{

Method NewRequest(bodyObj As %DynamicObject) As %Status
{
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write(bodyObj.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
    Quit $$$OK
}

/// The platform's list after the creates: one task per step of `flowId`, Ids 900 + step number,
/// plus an older task with the same name as step 01 (a previous schedule), which must not be
/// taken for the new one.
ClassMethod ScriptPlatformList(flowId As %String, stepIds As %List)
{
    Set rows = []
    Do rows.%Push({"Id": 17, "Name": ("SentaiTask: "_flowId_"#01"), "Namespace": "IRISAPP"})
    For i = 1:1:$LISTLENGTH(stepIds) {
        Set stepId = $LIST(stepIds, i)
        Do rows.%Push({"Id": (900 + stepId), "Name": ("SentaiTask: "_flowId_"#"_stepId), "Namespace": "IRISAPP"})
    }
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "", {"result": (rows)}.%ToJSON())
}

ClassMethod StepIdsOf(flowId As %String) As %List
{
    Set ids = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT id FROM sentai_model.Step WHERE flow = ? ORDER BY id", flowId)
    While rs.%Next() { Set ids = ids_$LB(rs.%Get("id")) }
    Quit ids
}

Method TestEachTaskIsCreatedByThePlatformWithTheOperatorsToken()
{
    Set id = ..CreateSupportedFlow("SchedulePlatform")
    Set stepIds = ..StepIdsOf(id)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "POST", 201, "", "{""result"":{}}")
    Do ..ScriptPlatformList(id, stepIds)

    Set out = ##class(sentai.dispatch.NativeScheduler).Schedule(id, "operator-token")
    Do $$$AssertEquals(out.httpStatus, 200)

    // One platform create per step, in step order, each with the product's own name and class.
    Do $$$AssertEquals(+$G(^sentaiTestDouble("postlog")), $LISTLENGTH(stepIds))
    For i = 1:1:$LISTLENGTH(stepIds) {
        Set entry = ^sentaiTestDouble("postlog", i)
        Do $$$AssertEquals($LIST(entry, 1), "/api/admin/v2/task")
        Do $$$AssertEquals($LIST(entry, 3), "operator-token")
        Set body = {}.%FromJSON($LIST(entry, 2))
        Do $$$AssertEquals(body.Name, "SentaiTask: "_id_"#"_$LIST(stepIds, i))
        Do $$$AssertEquals(body.TaskClass, "sentai.dispatch.ScheduledFlowTask")
        Do $$$AssertEquals(body.NameSpace, $NAMESPACE)
        Do $$$AssertEquals(body.Settings.FlowId, id)
        Do $$$AssertEquals(body.Settings.StepId, $LIST(stepIds, i))
        // Run as the operator: the platform stores the caller when RunAsUser is empty.
        Do $$$AssertEquals(body.RunAsUser, "")
    }

    // Task ids are the platform's, the newest task of each name (not the older #01).
    Do $$$AssertEquals(out.body.taskIds.%Size(), $LISTLENGTH(stepIds))
    Do $$$AssertEquals(out.body.taskIds.%Get(0), 900 + $LIST(stepIds, 1))
    Do $$$AssertEquals(^sentaiTestDouble("gets", "/api/admin/v2/tasks"), "operator-token")

    // Nothing was created in-process.
    Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
}

Method TestRootFlagFollowsIncomingEdges()
{
    Set id = ..CreateSupportedFlow("ScheduleRoot")
    Set stepIds = ..StepIdsOf(id)
    Set body = ##class(sentai.dispatch.NativeScheduler).TaskBody(id, $LIST(stepIds, 1))
    Do $$$AssertEquals(body.Settings.IsRoot, '##class(sentai.rest.Dispatcher).StepHasIncomingEdge(id, $LIST(stepIds, 1)))
}

Method TestPlatformRefusalIsVerbatimAndNothingIsCreated()
{
    Set id = ..CreateSupportedFlow("ScheduleRefused")
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "POST", 403, "", "{""status"":{""errors"":[],""summary"":""""}}")

    Set out = ##class(sentai.dispatch.NativeScheduler).Schedule(id, "unprivileged-token")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.status, 403)
    Do $$$AssertEquals(out.problem.platformStatus.%ToJSON(), "{""errors"":[],""summary"":""""}")
    // Refused at the first create: no further call, nothing to roll back.
    Do $$$AssertEquals(+$G(^sentaiTestDouble("postlog")), 1)
    Do $$$AssertEquals($D(^sentaiTestDouble("deleted")), 0)
    Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
}

Method TestRefusedScheduleIsNotRecordedOnTheFlow()
{
    Set id = ..CreateSupportedFlow("ScheduleRefusedEndpoint")
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "POST", 403, "", "{""status"":{""errors"":[],""summary"":""""}}")

    Do ..NewRequest({"scheduleSpec": "WEEKLY SAT 03:00"})
    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 403)
    Do $$$AssertEquals(##class(sentai.model.Flow).%OpenId(id, 0).scheduleSpec, "")
}

/// The steps are read with the operator's SQL privileges. A refused read is the answer, with the
/// platform's own message — never "0 steps, scheduled" (seen on the instance for an operator
/// without SQL privilege on the product's tables).
Method TestRefusedStepReadIsTheAnswerNotAnEmptySchedule()
{
    Set out = ##class(sentai.dispatch.NativeScheduler).SqlProblem(-99, "User q006user is not privileged for the operation")
    Do $$$AssertEquals(out.httpStatus, 403)
    Do $$$AssertEquals(out.problem.detail, "SQLCODE -99: User q006user is not privileged for the operation")
    Set out = ##class(sentai.dispatch.NativeScheduler).SqlProblem(-400, "Fatal error occurred")
    Do $$$AssertEquals(out.httpStatus, 500)
}

Method TestStepsAreReadInOrder()
{
    Set id = ..CreateSupportedFlow("ScheduleSteps")
    Set steps = ##class(sentai.dispatch.NativeScheduler).StepsOf(id, .problem)
    Do $$$AssertEquals(problem, "")
    Do $$$AssertEquals(steps, ..StepIdsOf(id))
}

/// The platform accepted a create but its own list has no task of that name: the schedule is not
/// confirmed. Tasks already created for this request are deleted, with the operator's token, so a
/// half-scheduled flow is never reported as scheduled (Constitution IV).
Method TestUnconfirmedCreateRollsBackAndIsNotSuccess()
{
    Set id = ..CreateSupportedFlow("ScheduleUnconfirmed")
    Set stepIds = ..StepIdsOf(id)
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "POST", 201, "", "{""result"":{}}")
    // Only the first step's task shows up in the platform's list.
    Set rows = [{"Id": 901, "Name": ("SentaiTask: "_id_"#"_$LIST(stepIds, 1))}]
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "", {"result": (rows)}.%ToJSON())

    Set out = ##class(sentai.dispatch.NativeScheduler).Schedule(id, "operator-token")
    Do $$$AssertEquals(out.httpStatus, 502)
    Do $$$AssertTrue(out.problem.detail [ "SCHEDULE_NOT_CONFIRMED")
    Do $$$AssertEquals($G(^sentaiTestDouble("deleted", "/api/admin/v2/task?id=901")), "operator-token")
}

}
