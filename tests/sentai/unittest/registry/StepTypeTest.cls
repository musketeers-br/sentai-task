Class sentai.unittest.registry.StepTypeTest Extends sentai.unittest.SentaiTestCase
{

/// The seven spec 003 types are all still present; spec 005 adds the two shipped declared types.
Method TestAllSevenTypesPresent()
{
    Set catalog = ##class(sentai.registry.StepType).GetCatalog()
    For type = "integrity-check", "compact-globals", "defragment-globals", "switch-journal", "purge-audit-records", "purge-task-history", "custom" {
        Do $$$AssertTrue(##class(sentai.registry.StepType).IsKnownType(type), type)
    }
    Do $$$AssertEquals(catalog.%Size(), 9)
}

/// Spec 004 D-1 (amended): integrity-check was the only type proven end to end on IRIS 2026.2.
/// Spec 005 FR-007: each declared type becomes available once its real-instance evidence is
/// recorded (db-size-report: evidence/a-db-size-report.json; storage-headroom-check:
/// evidence/ab-headroom.json; switch-journal: evidence/e-native-types.json).
Method TestAvailabilityIsIntegrityCheckOnly()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsAvailable("integrity-check"), 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsAvailable("db-size-report"), 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsAvailable("storage-headroom-check"), 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsAvailable("switch-journal"), 1)
    // purge-task-history: proven (evidence/e-native-types.json) but held until spec 007 T009 ships
    // the typed-confirmation dialog (spec 005 T016).
    For type = "compact-globals", "defragment-globals", "purge-audit-records", "purge-task-history", "custom" {
        Do $$$AssertEquals(##class(sentai.registry.StepType).IsAvailable(type), 0, type_" is not available in v1")
    }
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsAvailable("bogus"), 0)
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
    // Spec 005: purge-task-history runs in-process, where there is nothing to pause.
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsPausable("purge-task-history"), 0)
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

/// Spec 006 T002: destructiveness by a platform task class, from the catalog's `class` only.
Method TestDestructiveByClass()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).DestructiveByClass("%SYS.Task.PurgeTaskHistory", .k), 1)
    Do $$$AssertEquals(k, 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).DestructiveByClass("%SYS.Task.IntegrityCheck", .k), 0)
    Do $$$AssertEquals(k, 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).DestructiveByClass("%SYS.Task.SecurityScan", .k), 0)
    Do $$$AssertEquals(k, 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).DestructiveByClass("", .k), 0)
    Do $$$AssertEquals(k, 0, "the custom entry's empty class never matches")
    Do ##class(sentai.registry.StepType).DestructiveByClass("%sys.task.purgetaskhistory", .k)
    Do $$$AssertEquals(k, 0, "exact, case-sensitive")
    Do ##class(sentai.registry.StepType).DestructiveByClass("purge-task-history", .k)
    Do $$$AssertEquals(k, 0, "matches the class, never the type")
}

/// Spec 006 D-4: the audit purge's platform class is %SYS.Task.PurgeAudit (research R-5); the
/// type stays unavailable.
Method TestPurgeAuditClassIsThePlatformsAndStillUnavailable()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetTargetClass("purge-audit-records"), "%SYS.Task.PurgeAudit")
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsAvailable("purge-audit-records"), 0)
}

/// Spec 005 T002: every entry names itself for the palette and says how it executes.
Method TestEveryEntryHasLabelAndExecutor()
{
    Set iter = ##class(sentai.registry.StepType).GetCatalog().%GetIterator()
    While iter.%GetNext(.k, .entry) {
        Do $$$AssertTrue(entry.label '= "", entry.type_" has a label")
        Do $$$AssertTrue($LISTFIND($LB("platform-api", "in-process"), entry.executor), entry.type_" executor = "_entry.executor)
    }
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetExecutor("integrity-check"), "platform-api")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetExecutor("db-size-report"), "in-process")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetExecutor("storage-headroom-check"), "in-process")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetExecutor("bogus"), "")
}

/// Spec 005 T002 (data-model.md §Entries): the two shipped declared types and their schemas.
Method TestShippedDeclaredTypes()
{
    Set headroom = ##class(sentai.registry.StepType).Lookup("storage-headroom-check")
    Do $$$AssertTrue($IsObject(headroom))
    Do $$$AssertEquals(headroom.class, "sentai.steps.StorageHeadroomCheck")
    Do $$$AssertEquals(headroom.category, "storage")
    Do $$$AssertEquals(+headroom.destructive, 0)
    Do $$$AssertEquals(+headroom.pausable, 0)
    Set schema = ##class(sentai.registry.StepType).GetParameterSchema("storage-headroom-check")
    Do $$$AssertEquals(schema.%Size(), 1)
    Set def = schema.%Get(0)
    Do $$$AssertEquals(def.name, "minFreePercent")
    Do $$$AssertEquals(def.property, "MinFreePercent")
    Do $$$AssertEquals(def.type, "number")
    Do $$$AssertEquals(+def.required, 0)
    Do $$$AssertEquals(def.default, 10)
    Do $$$AssertEquals(def.min, 0)
    Do $$$AssertEquals(def.max, 100)
    Do $$$AssertTrue(def.description '= "")
    Do $$$AssertTrue(##class(sentai.registry.StepType).DeclaresParameters("storage-headroom-check"))

    Set report = ##class(sentai.registry.StepType).Lookup("db-size-report")
    Do $$$AssertTrue($IsObject(report))
    Do $$$AssertEquals(report.class, "sentai.steps.DatabaseSizeReport")
    Do $$$AssertEquals(report.category, "verification")
    Do $$$AssertEquals(+report.destructive, 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetParameterSchema("db-size-report").%Size(), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).DeclaresParameters("db-size-report"), 1, "an empty schema is declared: any key is unknown")
    Do $$$AssertEquals(##class(sentai.registry.StepType).DeclaresParameters("integrity-check"), 0)

    // Types that declare no schema get an empty array, never "".
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetParameterSchema("integrity-check").%Size(), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetParameterSchema("bogus").%Size(), 0)
}

/// Spec 007 BD-2: purge-audit-records declares its daysToKeep for the canvas; it stays
/// platform-api and unavailable.
Method TestPurgeAuditDeclaresDaysToKeep()
{
    Set schema = ##class(sentai.registry.StepType).GetParameterSchema("purge-audit-records")
    Do $$$AssertEquals(schema.%Size(), 1)
    Set def = schema.%Get(0)
    Do $$$AssertEquals(def.name, "daysToKeep")
    Do $$$AssertEquals(def.property, "KeepDays")
    Do $$$AssertEquals(def.type, "integer")
    Do $$$AssertEquals(+def.required, 1)
    Do $$$AssertEquals(def.min, 1)
    Do $$$AssertTrue('def.%IsDefined("default"), "no default: the operator must choose")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetExecutor("purge-audit-records"), "platform-api")
}

/// Spec 005 T002 / R-6: a declared class counts as installed only when compiled and a task
/// definition; IsInstalled reads the catalog's class, never anything else.
Method TestClassIsInstalled()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).ClassIsInstalled("sentai.steps.DoesNotExist"), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).ClassIsInstalled("sentai.unittest.fixtures.FakeOk"), 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).ClassIsInstalled("sentai.unittest.SentaiTestCase"), 0, "compiled but not a task")
    Do $$$AssertEquals(##class(sentai.registry.StepType).ClassIsInstalled(""), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsInstalled("custom"), 0, "empty class")
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsInstalled("switch-journal"), 1)
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsInstalled("bogus"), 0)
}

/// Spec 005 T013 (US5): the journal switch and the task-history purge run in-process with their
/// declared schemas; the purge stays destructive.
Method TestNativeTypesRunInProcess()
{
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetExecutor("switch-journal"), "in-process")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetTargetClass("switch-journal"), "%SYS.Task.SwitchJournal")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetParameterSchema("switch-journal").%Size(), 0)
    Do $$$AssertEquals(##class(sentai.registry.StepType).DeclaresParameters("switch-journal"), 1)

    Do $$$AssertEquals(##class(sentai.registry.StepType).GetExecutor("purge-task-history"), "in-process")
    Do $$$AssertEquals(##class(sentai.registry.StepType).GetTargetClass("purge-task-history"), "%SYS.Task.PurgeTaskHistory")
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsDestructive("purge-task-history"), 1)
    Set schema = ##class(sentai.registry.StepType).GetParameterSchema("purge-task-history")
    Do $$$AssertEquals(schema.%Size(), 1)
    Set def = schema.%Get(0)
    Do $$$AssertEquals(def.name, "keepDays")
    Do $$$AssertEquals(def.property, "KeepDays")
    Do $$$AssertEquals(def.type, "integer")
    Do $$$AssertEquals(+def.required, 0)
    Do $$$AssertEquals(def.default, 30)
    Do $$$AssertEquals(def.min, 0)
    Do $$$AssertTrue(def.description '= "")
    Do $$$AssertEquals(##class(sentai.registry.StepType).IsInstalled("purge-task-history"), 1)
}

}
