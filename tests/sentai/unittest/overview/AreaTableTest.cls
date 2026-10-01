/// Spec 018 T003: the compiled area table, proved against the step-type catalog.
Class sentai.unittest.overview.AreaTableTest Extends sentai.unittest.SentaiTestCase
{

Method TestElevenAreasInOrder()
{
    Set ids = ""
    Set it = ##class(sentai.overview.Areas).All().%GetIterator()
    While it.%GetNext(.k, .a) { Set ids = ids_$LB(a.id_":"_a.group) }
    Do $$$AssertEquals($LTS(ids, ","), "processes:instance,locks:instance,memory:instance,activity:instance,devices:instance,licenses:instance,web-sessions:instance,security:report,web-apps:report,alerts:report,secrets:report")
}

Method TestReadingsAreTheSevenInstanceAreas()
{
    For id = "processes", "locks", "memory", "activity", "devices", "licenses", "web-sessions" {
        Do $$$AssertTrue(##class(sentai.overview.Areas).IsReading(id), id_" is a reading")
    }
    For id = "security", "web-apps", "alerts", "secrets", "nope", "" {
        Do $$$AssertNotTrue(##class(sentai.overview.Areas).IsReading(id), id_" is not a reading")
    }
}

Method TestStepTypesAreInstalledReportTypes()
{
    Set it = ##class(sentai.overview.Areas).All().%GetIterator()
    While it.%GetNext(.k, .a) {
        If (a.group = "instance") {
            Do $$$AssertEquals(a.stepType, "", a.id_" has no step type (Q4)")
            Continue
        }
        Do $$$AssertEquals(##class(sentai.registry.StepType).GetExecutor(a.stepType), "platform-read", a.id_" maps to a report type")
        Do $$$AssertTrue(##class(sentai.registry.StepType).IsInstalled(a.stepType), a.stepType_" is installed")
    }
    Do $$$AssertEquals(##class(sentai.overview.Areas).StepTypeOf("secrets"), "secrets-inventory")
    Do $$$AssertEquals(##class(sentai.overview.Areas).StepTypeOf("processes"), "")
}

Method TestUnknownIdsAreNotAreas()
{
    For id = "../api/admin/info", "", "Processes", "processes/", "/api/admin/v2/processes" {
        Do $$$AssertEquals(##class(sentai.overview.Areas).Lookup(id), "", "'"_id_"' is unknown")
    }
}

}
