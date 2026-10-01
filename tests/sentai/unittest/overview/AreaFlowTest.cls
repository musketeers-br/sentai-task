/// Spec 018 T024: an area as an ordinary one-step flow; the application class never calls the
/// REST layer (Constitution I).
Class sentai.unittest.overview.AreaFlowTest Extends sentai.unittest.SentaiTestCase
{

Property FlowIdBefore As %Integer [ InitialExpression = 0 ];

Method OnBeforeOneTest() As %Status
{
    Set max = 0
    &sql(SELECT MAX(%ID) INTO :max FROM sentai_model.Flow)
    Set ..FlowIdBefore = +$G(max)
    Quit ##super()
}

Method OnAfterOneTest() As %Status
{
    Set floor = ..FlowIdBefore
    &sql(DELETE FROM sentai_model.Edge WHERE flow > :floor)
    &sql(DELETE FROM sentai_model."Join" WHERE flow > :floor)
    &sql(DELETE FROM sentai_model.Step WHERE flow > :floor)
    &sql(DELETE FROM sentai_model.Flow WHERE %ID > :floor)
    Quit ##super()
}

Method TestSecretsBecomesAOneStepFlow()
{
    Set out = ##class(sentai.overview.AreaFlow).Definition("secrets", {}, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 200)
    Set def = out.body
    Do $$$AssertTrue($E(def.name, 1, 24) = "Check: Secrets inventory")
    Do $$$AssertEquals(def.defaultCategory, "Default")
    Do $$$AssertEquals(def.steps.%Size(), 1)
    Set step = def.steps.%Get(0)
    Do $$$AssertEquals(step.id, "01")
    Do $$$AssertEquals(step.type, "secrets-inventory")
    Do $$$AssertEquals(step.taskName, "Secrets inventory")
    Do $$$AssertEquals(step.namespace, "%SYS")
    Do $$$AssertEquals(def.canvasGeometry.nodes."01".x, 40)

    Do $$$AssertStatusOK(##class(sentai.overview.AreaFlow).Save(def, "tester", "fake-token", .flowId))
    Set v = ##class(sentai.overview.AreaFlow).Validation(flowId, "fake-token")
    Do $$$AssertTrue(##class(sentai.validation.FlowValidator).HasNoErrors(v), v.%ToJSON())
}

Method TestSecondFlowGetsASuffix()
{
    Set def = ##class(sentai.overview.AreaFlow).Definition("web-apps", {}, "fake-token").body
    Do $$$AssertStatusOK(##class(sentai.overview.AreaFlow).Save(def, "tester", "fake-token", .id1))
    Set again = ##class(sentai.overview.AreaFlow).Definition("web-apps", {}, "fake-token").body
    Do $$$AssertTrue(again.name '= def.name)
    Do $$$AssertTrue(again.name [ "(")
}

Method TestCategoryFallback()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/wqm-categories", [{"Name": "SQL", "DefaultWorkers": 1, "MaxActiveWorkers": 2, "MaxWorkers": 0, "MaxTotalWorkers": 0, "AlwaysQueue": true}])
    Do $$$AssertEquals(##class(sentai.overview.AreaFlow).Definition("secrets", {}, "fake-token").body.defaultCategory, "SQL")
    Do ##class(sentai.unittest.overview.OverviewFixtures).Refuse("/api/admin/v2/wqm-categories")
    Do $$$AssertEquals(##class(sentai.overview.AreaFlow).Definition("secrets", {}, "fake-token").body.defaultCategory, "Default")
}

Method TestAreasWithoutStepTypeAndUnknown()
{
    Set out = ##class(sentai.overview.AreaFlow).Definition("processes", {}, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 409)
    Do $$$AssertTrue(out.problem.detail [ "AREA_HAS_NO_STEP_TYPE")
    Set out = ##class(sentai.overview.AreaFlow).Definition("nope", {}, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 404)
    Set out = ##class(sentai.overview.AreaFlow).Definition("alerts", {"maxSeriousAlerts": -1}, "fake-token")
    Do $$$AssertEquals(out.httpStatus, 422)
}

Method TestNoDependencyOnTheRestLayer()
{
    Set cls = ##class(%Dictionary.ClassDefinition).%OpenId("sentai.overview.AreaFlow")
    Do $$$AssertTrue($IsObject(cls))
    For i = 1:1:cls.Methods.Count() {
        Set m = cls.Methods.GetAt(i)
        Do m.Implementation.Rewind()
        Set text = m.Implementation.Read(32000)
        Do $$$AssertNotTrue(text [ "sentai.rest.", m.Name_" makes no call to sentai.rest.*")
    }
}

}
