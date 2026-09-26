/// Test fixture (spec 005 T001): switches to %SYS and deliberately does not restore it, as the
/// native %SYS.Task.* classes do (research.md R-5).
Class sentai.unittest.fixtures.FakeSwitchesNamespace Extends %SYS.Task.Definition
{

Method OnTask() As %Status
{
    Set $NAMESPACE = "%SYS"
    Quit $$$OK
}

}
