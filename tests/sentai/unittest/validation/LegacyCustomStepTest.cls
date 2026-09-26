/// Spec 005 T009 (FR-002, SC-002, Constitution II): nothing an operator types selects code. A
/// legacy `custom` step naming a real platform class is refused on every path that could run it,
/// still loads unchanged, and no execution path reads Step.customClass.
Class sentai.unittest.validation.LegacyCustomStepTest Extends sentai.unittest.SentaiTestCase
{

Method CustomFlow(prefix As %String) As %String
{
    Quit ..CreateFlowOf(prefix, [{"id": "01", "type": "custom", "customClass": "%SYS.Task.SwitchJournal", "namespace": "%SYS"}])
}

ClassMethod HasCode(errors As %DynamicArray, code As %String) As %Boolean
{
    Set iter = errors.%GetIterator()
    While iter.%GetNext(.k, .e) {
        Quit:(e.code = code)
    }
    Quit ($G(e) '= "") && (e.code = code)
}

Method TestRefusedOnEveryPathAndTheJournalIsUntouched()
{
    Set journal = ##class(%SYS.Journal.System).GetCurrentFileName()
    Set id = ..CustomFlow("LegacyCustom")

    // validate
    Set report = ##class(sentai.validation.FlowValidator).Validate(id)
    Do $$$AssertTrue(..HasCode(report.errors, "STEP_TYPE_NOT_SUPPORTED_ON_TARGET"))

    // dispatch
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(id, [], "tester", .ec, .ed, .rep)
    Do $$$AssertEquals(ec, "VALIDATION_FAILED")
    &sql(SELECT COUNT(*) INTO :runs FROM sentai_model.Run WHERE flow = :id)
    Do $$$AssertEquals(runs, 0)

    // schedule
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do %request.Content.Write({"scheduleSpec": "WEEKLY SAT 03:00"}.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
    Do ##class(sentai.rest.Dispatcher).ScheduleFlow(id)
    Do $$$AssertEquals(%response.Status, 422)
    Do $$$AssertEquals(..NativeTaskCountFor(id), 0)
    Do $$$AssertEquals(+$G(^sentaiTestDouble("postlog")), 0, "nothing sent to the platform")

    // rerun of a failed custom StepRun (the run created without the gates)
    Set run = ..DispatchUngated(id)
    Set guid = ^sentaiRun(run.guid, "01")
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(guid, "failed", "fixture"))
    Set sc = ##class(sentai.dispatch.WaveDispatcher).RerunStep(run.guid, guid, .newGuid)
    Do $$$AssertTrue($$$ISERR(sc))
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "STEP_TYPE_NOT_SUPPORTED_ON_TARGET")

    // even a direct worker call never runs it
    Set other = ..DispatchUngated(id)
    Set g2 = ^sentaiRun(other.guid, "01")
    Do ##class(sentai.model.StepRun).TransitionLocked(g2, "running")
    Do ##class(sentai.dispatch.InProcessExecutor).Run(g2)
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(g2, 0)
    Do sr.%Reload()
    Do $$$AssertEquals(sr.state, "failed")
    Do $$$AssertEquals(sr.executedAs, "", "not executed")

    Do $$$AssertEquals(##class(%SYS.Journal.System).GetCurrentFileName(), journal, "journal not switched")
}

Method TestOldFlowLoadsUnchanged()
{
    Set id = ..CustomFlow("LegacyCustomLoad")
    Set shaped = ##class(sentai.rest.Dispatcher).ShapeFlow(##class(sentai.model.Flow).%OpenId(id, 0), 1)
    Set step = shaped.steps.%Get(0)
    Do $$$AssertEquals(step.type, "custom")
    Do $$$AssertEquals(step.customClass, "%SYS.Task.SwitchJournal")
}

/// Static guard: the executor and the dispatcher never mention customClass.
Method TestNoExecutionPathReadsCustomClass()
{
    For class = "sentai.dispatch.InProcessExecutor", "sentai.dispatch.WaveDispatcher" {
        Set def = ##class(%Dictionary.ClassDefinition).%OpenId(class, 0)
        Do $$$AssertTrue($IsObject(def), class)
        For i = 1:1:def.Methods.Count() {
            Set method = def.Methods.GetAt(i)
            Set code = method.Implementation.Read(3000000)
            Do $$$AssertNotTrue($ZCVT(code, "L") [ "customclass", class_":"_method.Name_" reads no customClass")
        }
    }
}

}
