/// Test fixture (spec 005 T001): a task that returns an error %Status.
Class sentai.unittest.fixtures.FakeFails Extends %SYS.Task.Definition
{

Method OnTask() As %Status
{
    Quit $$$ERROR($$$GeneralError, "fake failure reason")
}

}
