/// Spec 005 T004: the in-process executor — outcomes as values (Constitution IV), the namespace
/// frame (R-5), result truncation (data-model §Result size) and the recorded runner (ID-4).
/// Fake task objects are driven through RunTask; the class a real step runs comes from the
/// catalog only (Constitution II).
Class sentai.unittest.dispatch.InProcessExecutorTest Extends sentai.unittest.SentaiTestCase
{

Method TestOkOutcome()
{
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(##class(sentai.unittest.fixtures.FakeOk).%New(), .outcome)
    Do $$$AssertEquals(outcome("ok"), 1)
    Do $$$AssertEquals(outcome("reason"), "")
    Do $$$AssertEquals(outcome("result"), "{""ok"":true}")
    Do $$$AssertEquals(outcome("user"), $USERNAME)
}

Method TestErrorStatusIsVerbatim()
{
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(##class(sentai.unittest.fixtures.FakeFails).%New(), .outcome)
    Do $$$AssertEquals(outcome("ok"), 0)
    Do $$$AssertEquals(outcome("reason"), $SYSTEM.Status.GetErrorText($$$ERROR($$$GeneralError, "fake failure reason")))
    Do $$$AssertEquals(outcome("result"), "", "the class declares no Result")
}

Method TestExceptionBecomesAValue()
{
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(##class(sentai.unittest.fixtures.FakeThrows).%New(), .outcome)
    Do $$$AssertEquals(outcome("ok"), 0)
    Do $$$AssertTrue(outcome("reason") [ "<DIVIDE>", outcome("reason"))
}

Method TestNamespaceIsRestored()
{
    Set ns = $NAMESPACE
    Set before = $D(^|"%SYS"|sentaiRun)
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(##class(sentai.unittest.fixtures.FakeSwitchesNamespace).%New(), .outcome)
    Do $$$AssertEquals(outcome("ok"), 1)
    Do $$$AssertEquals($NAMESPACE, ns)
    Do $$$AssertEquals($D(^|"%SYS"|sentaiRun), before)
}

Method TestBigResultIsTruncatedToValidJson()
{
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(##class(sentai.unittest.fixtures.FakeBigResult).%New(), .outcome)
    Do $$$AssertTrue($L(outcome("result")) > 8000, "fixture is over the limit")
    Set stored = ##class(sentai.dispatch.InProcessExecutor).FitResult(outcome("result"))
    Do $$$AssertTrue($L(stored) <= 8000, "length "_$L(stored))
    Set obj = {}.%FromJSON(stored)
    Do $$$AssertEquals(obj.truncated, 1)
    Do $$$AssertEquals(obj.%GetTypeOf("truncated"), "boolean")
    Do $$$AssertEquals(obj.omitted + obj.items.%Size(), 2000)
    Do $$$AssertTrue(obj.omitted > 0)
    Do $$$AssertEquals(obj.items.%Get(0), "item-   1-abcdefghi", "elements are dropped from the end")
}

Method TestOversizedWithoutArrayKeepsOnlyTheLength()
{
    Set big = {"text": ($TR($J("", 9000), " ", "x"))}.%ToJSON()
    Set stored = ##class(sentai.dispatch.InProcessExecutor).FitResult(big)
    Set obj = {}.%FromJSON(stored)
    Do $$$AssertEquals(obj.truncated, 1)
    Do $$$AssertEquals(obj.originalLength, $L(big))
    Do $$$AssertEquals(##class(sentai.dispatch.InProcessExecutor).FitResult("{""a"":1}"), "{""a"":1}", "small results unchanged")
    Do $$$AssertEquals(##class(sentai.dispatch.InProcessExecutor).FitResult(""), "")
}

/// Properties come from iterating the declared schema: defaults apply, unknown keys are never set.
Method TestParametersAreSetFromTheSchemaOnly()
{
    Set schema = [
        {"name": "threshold", "property": "Threshold", "type": "number", "required": false, "default": 7},
        {"name": "label", "property": "Label", "type": "string", "required": false}
    ]
    Set task = ##class(sentai.unittest.fixtures.FakeWithParams).%New()
    Do ##class(sentai.dispatch.InProcessExecutor).ApplyParameters(task, schema, {"label": "L1", "Result": "injected"})
    Do $$$AssertEquals(task.Threshold, 7, "default applied")
    Do $$$AssertEquals(task.Label, "L1")
    Do $$$AssertEquals(task.Result, "", "a key outside the schema is never forwarded")

    Set task = ##class(sentai.unittest.fixtures.FakeWithParams).%New()
    Do ##class(sentai.dispatch.InProcessExecutor).ApplyParameters(task, schema, {"threshold": 42})
    Do ##class(sentai.dispatch.InProcessExecutor).RunTask(task, .outcome)
    Set echoed = ##class(%DynamicObject).%FromJSON(outcome("result"))
    Do $$$AssertEquals(echoed.threshold, 42)
}

/// The worker entry on a real catalog type: runs db-size-report, records who ran it and the
/// result, and ends the StepRun in this namespace.
Method TestRunRecordsExecutedAsAndResult()
{
    Set ns = $NAMESPACE
    Set flowId = ..CreateFlowOf("InProcRun", [{"id": "01", "type": "db-size-report"}])
    Set run = ..DispatchUngated(flowId)
    Set guid = ^sentaiRun(run.guid, "01")
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(guid, "running"))

    Do $$$AssertStatusOK(##class(sentai.dispatch.InProcessExecutor).Run(guid))
    Do $$$AssertEquals($NAMESPACE, ns)

    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid, 0)
    Do sr.%Reload()
    Do $$$AssertEquals(sr.state, "completed", sr.failureReason)
    Do $$$AssertEquals(sr.executedAs, $USERNAME)
    Set result = ##class(%DynamicObject).%FromJSON(sr.result)
    Do $$$AssertTrue(result.databases.%Size() > 0)
}

/// A step whose type is not in-process (or has no class) is never executed by the worker.
Method TestRunRefusesAPlatformApiType()
{
    Set run = ..DispatchUngated(..CreateSupportedFlow("InProcRefuse"))
    Set guid = ^sentaiRun(run.guid, "01")
    Do $$$AssertStatusOK(##class(sentai.model.StepRun).TransitionLocked(guid, "running"))
    Do ##class(sentai.dispatch.InProcessExecutor).Run(guid)
    Set sr = ##class(sentai.model.StepRun).GuidIndexOpen(guid, 0)
    Do sr.%Reload()
    Do $$$AssertEquals(sr.state, "failed")
    Do $$$AssertTrue(sr.failureReason [ "integrity-check", sr.failureReason)
}

}
