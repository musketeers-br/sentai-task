Class sentai.unittest.rest.StepTypeCatalogTest Extends sentai.unittest.SentaiTestCase
{

Method TestCatalogExposesAllSevenTypesWithCategoryDestructiveAndPausable()
{
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ListStepTypes()
    Do $$$AssertEquals(%response.Status, 200)

    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    // The seven spec 003 types plus the two shipped declared types (spec 005).
    Do $$$AssertEquals(catalog.%Size(), 9)

    // Spec 004 FR-001: every entry the endpoint serves carries `available`.
    Set iter = catalog.%GetIterator()
    While iter.%GetNext(.k, .entry) {
        Do $$$AssertTrue(entry.%IsDefined("available"), entry.type_" declares available")
        Do $$$AssertEquals(entry.%GetTypeOf("available"), "boolean")
        Do $$$AssertEquals(+entry.available, ##class(sentai.unittest.rest.StepTypeCatalogTest).AvailableTypes()[(","_entry.type_","), entry.type)
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

/// Spec 005 T007: the catalog read carries label and executor for every entry, and the declared
/// schema for in-process types (the canvas renders the parameter form from it, spec 007).
/// ListStepTypes serves GetCatalog() as is.
Method TestCatalogCarriesLabelExecutorAndParameters()
{
    Set %request = ##class(%CSP.Request).%New()
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ListStepTypes()
    Do $$$AssertEquals(%response.Status, 200)

    Set iter = ##class(sentai.registry.StepType).GetCatalog().%GetIterator(), inProcess = 0
    While iter.%GetNext(.k, .entry) {
        Do $$$AssertTrue(entry.label '= "", entry.type_" label")
        Do $$$AssertTrue(entry.executor '= "", entry.type_" executor")
        If (entry.executor = "in-process") {
            Set inProcess = inProcess + 1
            Do $$$AssertEquals(entry.%GetTypeOf("parameters"), "array", entry.type_" parameters")
        }
    }
    Do $$$AssertTrue(inProcess >= 2)
}

/// The types proven on the real instance (spec 004 D-1, spec 005 FR-007), comma-delimited.
ClassMethod AvailableTypes() As %String
{
    Quit ",integrity-check,switch-journal,storage-headroom-check,db-size-report,"
}

}
