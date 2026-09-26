/// Test fixture (spec 005 T001): a task that succeeds and reports a JSON result.
Class sentai.unittest.fixtures.FakeOk Extends %SYS.Task.Definition
{

Property Result As %String(MAXLEN = "");

Method OnTask() As %Status
{
    Set ..Result = {"ok": true}.%ToJSON()
    Quit $$$OK
}

}
