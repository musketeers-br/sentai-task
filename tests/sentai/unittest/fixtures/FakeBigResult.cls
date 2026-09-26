/// Test fixture (spec 005 T001): a result larger than StepRun.result can hold (> 8000 chars).
Class sentai.unittest.fixtures.FakeBigResult Extends %SYS.Task.Definition
{

Property Result As %String(MAXLEN = "");

Method OnTask() As %Status
{
    Set items = []
    For i = 1:1:2000 {
        Do items.%Push("item-"_$JUSTIFY(i, 4)_"-abcdefghi")
    }
    Set ..Result = {"items": (items)}.%ToJSON()
    Quit $$$OK
}

}
