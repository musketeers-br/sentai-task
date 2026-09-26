Class sentai.unittest.rest.ScheduleEndpointTest Extends sentai.unittest.SentaiTestCase
{

Method NewRequest(bodyObj As %DynamicObject) As %Status
{
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write(bodyObj.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
    Quit $$$OK
}

/// Removes the native tasks a successful /schedule created, so the suite never leaves real
/// scheduled tasks behind on the instance. Returns how many were removed.
Method DeleteNativeTasksFor(flowId As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT ID AS taskId FROM %SYS.Task WHERE Name %STARTSWITH ?")
    Set result = rs.%Execute("SentaiTask: "_flowId_"#")
    Set count = 0
    While result.%Next() {
        Set count = count + 1
        Do ##class(%SYS.Task).%DeleteId(result.%Get("taskId"))
    }
    Quit count
}

Method TestScheduleValidatedNonDestructiveFlowReturns201WithOneTaskIdPerStep()
{
    Set id = ..CreateSupportedFlow("ScheduleOk")
    // Adjusted at spec 005 close-out: the tasks are created by the platform's management API
    // (ScheduleViaPlatformTest), so the platform is scripted here instead of counting real tasks.
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/task", "POST", 201, "", "{""result"":{}}")
    Set rows = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT id FROM sentai_model.Step WHERE flow = ?", id)
    While rs.%Next() { Do rows.%Push({"Id": ($I(n) + 500), "Name": ("SentaiTask: "_id_"#"_rs.%Get("id"))}) }
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/tasks", "GET", 200, "", {"result": (rows)}.%ToJSON())

    Do ..NewRequest({"scheduleSpec": "WEEKLY SAT 03:00", "category": "Default"})
    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 201)

    // One native task per step (FR-031), created by the platform, none in-process.
    Do $$$AssertEquals(+$G(^sentaiTestDouble("postlog")), 3)
    Do $$$AssertEquals(..DeleteNativeTasksFor(id), 0)
    Do $$$AssertEquals(##class(sentai.model.Flow).%OpenId(id, 0).scheduleSpec, "WEEKLY SAT 03:00")
}

Method TestSchedulingFlowWithValidationErrorIsRefused()
{
    Set payload = ..NonDestructiveFlowPayload("ScheduleBad")
    Do payload."steps".%Push({"id": "06", "type": "custom", "taskName": "Custom", "namespace": "USER"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Do ..NewRequest({"scheduleSpec": "WEEKLY SAT 03:00"})
    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 422)
    Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
}

/// Scheduling of any flow containing a destructive step is out of scope in v1 (spec.md
/// Change Log 2026-09-22, TD-06): /schedule refuses it with an explicit blocking error and
/// creates no native %SYS.Task entry at all.
Method TestSchedulingFlowWithDestructiveStepIsRefusedAndCreatesNoNativeTask()
{
    // The canonical flow's step 04 (purge-audit-records) is destructive (and, since spec 004,
    // also unavailable — both errors are reported; this test is about the destructive one).
    Set id = ..CreateCanonicalFlow("ScheduleDestructive")
    Set tasksBefore = ..NativeTaskCount()

    Do ..NewRequest({"scheduleSpec": "WEEKLY SAT 03:00", "category": "SENTAI.NIGHT"})
    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)

    // Explicit blocking error: 422 ValidationReport (contracts/rest-mapping.md §Errors),
    // whose body is exactly the schedule-scoped report below.
    Do $$$AssertEquals(%response.Status, 422)
    Set report = ##class(sentai.validation.FlowValidator).ValidateForSchedule(id)
    Set found = 0
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        If (e.code = "DESTRUCTIVE_NOT_SCHEDULABLE") && (e.stepId = "04") Set found = 1
    }
    Do $$$AssertTrue(found)

    // Zero native tasks: none for this flow, none anywhere on the instance.
    Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
    Do $$$AssertEquals(..NativeTaskCount(), tasksBefore)

    // The refused schedule is not recorded on the flow either.
    Set flow = ##class(sentai.model.Flow).%OpenId(id, 0)
    Do $$$AssertEquals(flow.scheduleSpec, "")
}

}
