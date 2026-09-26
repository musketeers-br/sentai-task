/// Test fixture (spec 005 T001): a task that raises an ObjectScript error.
Class sentai.unittest.fixtures.FakeThrows Extends %SYS.Task.Definition
{

Method OnTask() As %Status
{
    Set x = 1/0
    Quit $$$OK
}

}
