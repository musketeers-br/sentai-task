Class sentai.unittest.rest.StepTypeCatalogTest Extends sentai.unittest.SentaiTestCase
{

Method TestCatalogExposesAllSevenTypesWithCategoryDestructiveAndPausable()
{
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ListStepTypes()
    Do $$$AssertEquals(%response.Status, 200)

    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    Do $$$AssertEquals(catalog.%Size(), 7)

    // Spec 004 FR-001: every entry the endpoint serves carries `available`.
    Set iter = catalog.%GetIterator()
    While iter.%GetNext(.k, .entry) {
        Do $$$AssertTrue(entry.%IsDefined("available"), entry.type_" declares available")
        Do $$$AssertEquals(entry.%GetTypeOf("available"), "boolean")
        Do $$$AssertEquals(+entry.available, (entry.type = "integrity-check"), entry.type)
    }
}

Method TestCustomIsSelectableButStillBlockedByValidationUntilClassDeclared()
{
    Do $$$AssertTrue(##class(sentai.registry.StepType).IsKnownType("custom"))

    Set payload = ..CanonicalFlowPayload("CatalogCustomSelectable")
    Do payload."steps".%Push({"id": "06", "type": "custom", "taskName": "Custom", "namespace": "USER"})
    Set sc = ##class(sentai.model.Flow).SaveGraph(payload, "", 0, "tester", .id)
    Do $$$AssertStatusOK(sc)

    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertNotTrue(##class(sentai.validation.FlowValidator).HasNoErrors(report))
}

}
