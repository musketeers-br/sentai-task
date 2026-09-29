/// Spec 015 T022 (FR-003, SC-002): after scheduling, firing and reading, the run-as password is in
/// none of the product's globals (subscripts or values), tables, log entries or answers.
Class sentai.unittest.schedule.SecretHygieneTest Extends sentai.unittest.SentaiTestCase
{

/// Every global of this namespace whose name starts with `sentai` (the product's data and the
/// test double), searched node by node for `text`. Returns the first node holding it, or "".
ClassMethod FindInGlobals(text As %String) As %String
{
    Set name = "^sentai"
    For {
        Set name = $O(^$GLOBAL(name))
        Quit:((name = "") || ($E($P(name, "^", 2), 1, 6) '= "sentai"))
        Set node = name
        If ($D(@node) # 10) && ($G(@node) [ text) Return node
        For {
            Set node = $Q(@node)
            Quit:(node = "")
            If (node [ text) || ($G(@node) [ text) Return node
        }
    }
    Quit ""
}

Method TestPasswordIsNowhere()
{
    Set password = "pw-hyg-"_$SYSTEM.Util.CreateGUID()
    Set id = ..CreateFlowOf("Hygiene", [{"id": "01", "type": "db-size-report"}])
    Do ##class(sentai.unittest.schedule.ScheduleServiceTest).ScriptPlatform(id)
    Set body = ##class(sentai.unittest.schedule.ScheduleServiceTest).Body()
    Set body.password = password
    Set out = ##class(sentai.schedule.ScheduleService).Schedule(id, body, "operator-token", "operator")
    Do $$$AssertEquals(out.httpStatus, 201)
    Do $$$AssertNotTrue(out.%ToJSON() [ password)

    Do ##class(sentai.unittest.schedule.ScheduledStartTest).ScriptLogin()
    Do $$$AssertStatusOK(##class(sentai.schedule.ScheduledStart).Fire(id))
    Set read = ##class(sentai.schedule.ScheduleService).Read(id, "operator-token")
    Do $$$AssertNotTrue(read.%ToJSON() [ password)

    Do $$$AssertEquals(..FindInGlobals(password), "")
    Set s = ##class(sentai.model.Schedule).FlowIndexOpen(id, 0)
    Set row = s.flowGetObjectId()_s.kind_s.runAs_s.targets_s.createdBy
    Do $$$AssertNotTrue(row [ password)
    &sql(SELECT COUNT(*) INTO :n FROM sentai_model.LogEntry WHERE message [ :password)
    Do $$$AssertEquals(+$G(n), 0)
}

}
