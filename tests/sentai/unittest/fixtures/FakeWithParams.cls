/// Test fixture (spec 005 T001): echoes the two properties the executor sets from a schema.
Class sentai.unittest.fixtures.FakeWithParams Extends %SYS.Task.Definition
{

Property Threshold As %Numeric;

Property Label As %String;

Property Result As %String(MAXLEN = "");

Method OnTask() As %Status
{
    Set ..Result = {"threshold": (+..Threshold), "label": (..Label)}.%ToJSON()
    Quit $$$OK
}

}
