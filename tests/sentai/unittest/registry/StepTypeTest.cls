Class sentai.unittest.registry.StepTypeTest Extends sentai.unittest.SentaiTestCase
{

Method TestAllSevenTypesPresent()
{
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    Do $$$AssertEquals(catalog.%Size(), 7)
}

Method TestNonDestructiveTypes()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsDestructive("integrity-check"), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsDestructive("compact-globals"), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsDestructive("defragment-globals"), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsDestructive("switch-journal"), 0)
}

Method TestPurgeFamilyIsDestructiveAndPausable()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsDestructive("purge-audit-records"), 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsDestructive("purge-task-history"), 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsPausable("purge-audit-records"), 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsPausable("purge-task-history"), 1)
}

Method TestOnlyPurgeFamilyIsPausable()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsPausable("integrity-check"), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsPausable("compact-globals"), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsPausable("defragment-globals"), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsPausable("switch-journal"), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsPausable("custom"), 0)
}

Method TestCategories()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetCategory("integrity-check"), "verification")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetCategory("compact-globals"), "storage")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetCategory("defragment-globals"), "storage")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetCategory("switch-journal"), "journal")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetCategory("purge-audit-records"), "purge")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetCategory("purge-task-history"), "purge")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetCategory("custom"), "custom")
}

Method TestUnknownTypeIsNotInCatalog()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsKnownType("not-a-real-type"), 0)
}

}
