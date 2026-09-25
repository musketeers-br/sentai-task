/// Spec 004 FR-006 (F-3): validation refuses a step whose effective WQM category — its own
/// wqmCategory, else the flow's defaultCategory — is not in the platform's category list, read
/// with the operator's credential. Fail closed when the list cannot be read; skipped when there is
/// no credential at all (scheduled fire time, D-2).
Class sentai.unittest.validation.CategoryExistenceRuleTest Extends sentai.unittest.SentaiTestCase
{

Parameter CODE = "CATEGORY_NOT_FOUND";

Parameter TOKEN = "test-token";

/// The supported flow with every step's category replaced by `category` ("" removes it, so the
/// flow's defaultCategory applies); `defaultCategory` "" leaves the product default in place.
Method FlowWithCategory(category As %String, defaultCategory As %String = "Default", namePrefix As %String = "CatExists") As %String
{
    Set payload = ..SupportedGraphPayload(namePrefix)
    If (defaultCategory = "") { Do payload.%Remove("defaultCategory") } Else { Do payload.%Set("defaultCategory", defaultCategory) }
    Set iter = payload."steps".%GetIterator()
    While iter.%GetNext(.k, .s) {
        If (category = "") { Do s.%Remove("wqmCategory") } Else { Do s.%Set("wqmCategory", category) }
    }
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)
    Quit id
}

ClassMethod Findings(report As %DynamicObject, ByRef stepIds As %String, ByRef messages As %String) As %Integer
{
    Set n = 0, stepIds = "", messages = ""
    Set iter = report."errors".%GetIterator()
    While iter.%GetNext(.k, .e) {
        Continue:(e.code '= ..#CODE)
        Set n = n + 1, stepIds = stepIds_$S(stepIds = "":"", 1:",")_e.stepId, messages = messages_e.message_$C(10)
    }
    Quit n
}

Method TestUnknownStepCategoryIsReportedPerStep()
{
    Set id = ..FlowWithCategory("NONEXISTENT")
    Set report = ##class(sentai.validation.FlowValidator).Validate(id, ..#TOKEN)
    Do $$$AssertEquals(..Findings(report, .ids, .msgs), 3)
    Do $$$AssertEquals(ids, "01,02,03")
    Do $$$AssertTrue(msgs [ "'NONEXISTENT'")
}

Method TestMissingFlowDefaultIsReportedForStepsWithoutCategory()
{
    // No step names a category and the flow keeps the product default SENTAI.DEFAULT, which the
    // platform does not have (spec 004 Clarifications Q1).
    Set id = ..FlowWithCategory("", "")
    Set flow = ##class(sentai.model.Flow).%OpenId(id, 0)
    Do $$$AssertEquals(flow.defaultCategory, "SENTAI.DEFAULT")

    Set report = ##class(sentai.validation.FlowValidator).Validate(id, ..#TOKEN)
    Do $$$AssertEquals(..Findings(report, .ids, .msgs), 3)
    Do $$$AssertTrue(msgs [ "'SENTAI.DEFAULT'")
}

Method TestExistingCategoriesPass()
{
    Set report = ##class(sentai.validation.FlowValidator).Validate(..CreateSupportedFlow("CatExistsOk"), ..#TOKEN)
    Do $$$AssertEquals(report."errors".%Size(), 0)

    // Built-in names from the platform list and the flow default resolve too.
    Set report2 = ##class(sentai.validation.FlowValidator).Validate(..FlowWithCategory("", "Utility"), ..#TOKEN)
    Do $$$AssertEquals(..Findings(report2), 0)
}

Method TestUnreadableCategoryListFailsClosed()
{
    Do ##class(sentai.unittest.AdminApiDouble).Script("/api/admin/v2/wqm-categories", "GET", 401, "", "")
    Set report = ##class(sentai.validation.FlowValidator).Validate(..CreateSupportedFlow("CatExistsDown"), ..#TOKEN)
    Do $$$AssertEquals(..Findings(report), 3)
}

Method TestNoCredentialSkipsTheRule()
{
    // Scheduled fire time carries no credential (D-2): the run is still created and its steps
    // fail with the platform's 401, as documented — validation does not pre-empt that.
    Set report = ##class(sentai.validation.FlowValidator).Validate(..FlowWithCategory("NONEXISTENT"))
    Do $$$AssertEquals(..Findings(report), 0)
}

Method TestDispatchAndScheduleAreRefused()
{
    Set id = ..FlowWithCategory("NONEXISTENT")

    Set errorCode = "", errorDetail = "", vr = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [], "tester", .errorCode, .errorDetail, .vr, ..#TOKEN)
    Do $$$AssertEquals(errorCode, "VALIDATION_FAILED")
    Do $$$AssertEquals(..Findings(vr), 3)
    &sql(SELECT COUNT(*) INTO :runs FROM sentai_model.Run WHERE flow = :id)
    Do $$$AssertEquals(runs, 0)

    Do $$$AssertEquals(..Findings(##class(sentai.validation.FlowValidator).ValidateForSchedule(id, ..#TOKEN)), 3)
}

}
